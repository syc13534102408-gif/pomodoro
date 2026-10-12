import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/cloud_auto.dart';
import 'package:pomodoro_app/src/cloud_sync.dart';
import 'package:pomodoro_app/src/models.dart';

const _code = 'DEVICE_CODE_1234567890';

/// 内存版同步后端：不发真实 HTTP，可自由设置云端内容与冲突。
class FakeCloudSync extends CloudSync {
  FakeCloudSync() : super(baseUrl: 'http://fake-sync');

  /// null 表示云端还没有这份同步码的备份（对应 404）。
  DateTime? updatedAt;
  Map<String, dynamic>? payload;

  String? lastUploadedCode;
  Map<String, dynamic>? lastUploadedPayload;

  /// 上传次数：验证「占用期间不并发上传 / 补传恰好一次」。
  int uploadCount = 0;

  /// true 时上传直接抛网络错误（模拟离线）。
  bool offline = false;

  /// 非空时上传挂起直到 completer 完成（模拟"同步进行中"的竞争窗口）。
  Completer<void>? gate;

  @override
  Future<DateTime> upload({
    required String deviceCode,
    required Map<String, dynamic> payload,
    DateTime? baseUpdatedAt,
  }) async {
    uploadCount++;
    if (gate != null) await gate!.future;
    if (offline) throw CloudSyncException('网络不可用');
    lastUploadedCode = deviceCode;
    lastUploadedPayload = payload;
    if (baseUpdatedAt != null &&
        updatedAt != null &&
        !baseUpdatedAt.isAtSameMomentAs(updatedAt!)) {
      throw CloudSyncException('云端数据已在另一台设备更新', conflict: true);
    }
    updatedAt = DateTime.utc(2026, 8, 31, 10, 5);
    this.payload = payload;
    return updatedAt!;
  }

  @override
  Future<CloudBackup> download(String deviceCode) async {
    if (updatedAt == null || payload == null) {
      throw CloudSyncException('没有找到云端备份，请先在原设备上传一次');
    }
    return CloudBackup(payload: payload!, updatedAt: updatedAt!);
  }
}

AppData _linked({
  String code = _code,
  DateTime? lastSyncedAt,
  String lastSyncedHash = '',
}) =>
    AppData(
      sync: SyncState(
        deviceCode: code,
        lastSyncedAt: lastSyncedAt,
        lastSyncedHash: lastSyncedHash,
      ),
    );

FocusRecord _record(String name) => FocusRecord(
      taskName: name,
      minutes: 25,
      dayKey: '2026-08-31',
      status: RecordStatus.completed,
      at: DateTime(2026, 8, 31, 10),
    );

Map<String, dynamic> _webPayload() => {
      'tasks': [
        {'name': '数学真题', 'count': 3},
        {'name': '错题整理', 'count': 1},
      ],
      'records': [
        {
          'name': '数学真题',
          'minutes': 50,
          'date': '2026-08-31',
          'status': 'completed',
        }
      ],
      'selected': 0,
      'goalMinutes': 200,
      'weekGoal': 12,
      'settings': {'focus': 25, 'short': 5, 'long': 15},
    };

void main() {
  test('云指纹对业务数据敏感、对本机信息不敏感', () {
    final base = _linked();
    expect(cloudFingerprint(base), cloudFingerprint(base));

    final withRecord = base.copyWith(records: [_record('数学真题')]);
    expect(cloudFingerprint(withRecord), isNot(cloudFingerprint(base)));

    // 进行中的会话不进入云端指纹（云端净荷不含 activeSession）。
    final withSession = base.copyWith(
      activeSession: const ActiveSession(
        recordId: 'r1',
        mode: SessionMode.focus,
        running: true,
      ),
    );
    expect(cloudFingerprint(withSession), cloudFingerprint(base));

    // 同步状态本身也不进入指纹。
    final withSync = base.copyWith(
      sync: base.sync.copyWith(lastUploadedAt: DateTime(2026, 8, 31, 9)),
    );
    expect(cloudFingerprint(withSync), cloudFingerprint(base));
  });

  test('id 重新生成（如从网页端恢复）不产生假冲突', () {
    final base = _linked().copyWith(records: [_record('数学真题')]);
    final before = cloudFingerprint(base);

    // 模拟网页端载荷：剥掉任务/记录的 id，恢复时它们会重新生成。
    final raw = base.toMap();
    List<dynamic> stripIds(List<dynamic> list) => [
          for (final entry in list)
            () {
              final map = Map<String, dynamic>.from(entry as Map);
              map.remove('id');
              return map;
            }(),
        ];
    raw['tasks'] = stripIds(raw['tasks'] as List);
    raw['records'] = stripIds(raw['records'] as List);
    final restored = AppData.fromMap(raw);

    expect(cloudFingerprint(restored), before);
  });

  test('hasLocalChanges 依据上次同步指纹判断本机改动', () {
    final synced = _linked(lastSyncedHash: cloudFingerprint(_linked()));
    expect(hasLocalChanges(synced), isFalse);
    expect(
      hasLocalChanges(synced.copyWith(records: [_record('数学真题')])),
      isTrue,
    );
  });

  test('未绑定同步码时不自动上传', () async {
    final sync = FakeCloudSync();
    AppData? applied;
    final auto = AutoCloudSync(
      sync: sync,
      apply: (data) async => applied = data,
      minInterval: Duration.zero,
    );
    final data = _linked(code: '').copyWith(records: [_record('数学真题')]);
    await auto.afterFocus(null, data);
    expect(sync.lastUploadedCode, isNull);
    expect(applied, isNull);
  });

  test('完成专注后自动上传并记录新的同步指纹', () async {
    final sync = FakeCloudSync();
    AppData? applied;
    final auto = AutoCloudSync(
      sync: sync,
      apply: (data) async => applied = data,
      minInterval: Duration.zero,
    );
    final changed = _linked().copyWith(records: [_record('数学真题')]);
    await auto.afterFocus(null, changed);

    expect(sync.lastUploadedCode, _code);
    expect(sync.lastUploadedPayload!['records'], isNotEmpty);
    expect(applied!.sync.lastSyncedHash, cloudFingerprint(changed));
    expect(applied!.sync.lastSyncedAt, sync.updatedAt);
  });

  test('本机没有新改动时完成专注不会重复上传', () async {
    final sync = FakeCloudSync();
    final base = _linked();
    final auto = AutoCloudSync(
      sync: sync,
      apply: (_) async {},
      minInterval: Duration.zero,
    );
    await auto.afterFocus(
      null,
      base.copyWith(sync: base.sync.copyWith(lastSyncedHash: cloudFingerprint(base))),
    );
    expect(sync.lastUploadedCode, isNull);
  });

  test('云端无备份时回到前台不打扰（404 静默跳过）', () async {
    final sync = FakeCloudSync(); // updatedAt == null → 404
    AppData? applied;
    final auto = AutoCloudSync(
      sync: sync,
      apply: (data) async => applied = data,
      minInterval: Duration.zero,
    );
    await auto.onResume(null, _linked());
    expect(applied, isNull);
  });

  test('云端更新且本机无改动：回到前台静默采用云端版本', () async {
    final sync = FakeCloudSync()
      ..updatedAt = DateTime.utc(2026, 8, 31, 10, 5)
      ..payload = _webPayload();
    final base = _linked();
    AppData? applied;
    final auto = AutoCloudSync(
      sync: sync,
      apply: (data) async => applied = data,
      minInterval: Duration.zero,
    );
    // 本机自上次同步后没有改动，但云端比上次同步新。
    final local = base.copyWith(
      sync: base.sync.copyWith(
        lastSyncedAt: DateTime.utc(2026, 8, 31, 10, 0),
        lastSyncedHash: cloudFingerprint(base),
      ),
    );
    await auto.onResume(null, local);

    expect(applied, isNotNull);
    // 云端记录已进入本机。
    expect(applied!.records.map((r) => r.taskName), contains('数学真题'));
    expect(applied!.sync.lastSyncedAt, sync.updatedAt);
  });

  testWidgets('云端更新且本机有改动：弹窗询问，选择恢复后采用云端', (tester) async {
    final sync = FakeCloudSync()
      ..updatedAt = DateTime.utc(2026, 8, 31, 10, 5)
      ..payload = _webPayload();
    final base = _linked();
    AppData? applied;
    final auto = AutoCloudSync(
      sync: sync,
      apply: (data) async => applied = data,
      minInterval: Duration.zero,
    );
    // 本机有未同步的新记录，云端同时被网页端更新。
    final local = base
        .copyWith(records: [_record('本机新记录')])
        .copyWith(
      sync: base.sync.copyWith(
        lastSyncedAt: DateTime.utc(2026, 8, 31, 10, 0),
        lastSyncedHash: cloudFingerprint(base),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(
        builder: (context) {
          return Center(
            child: TextButton(
              onPressed: () => auto.onResume(context, local),
              child: const Text('trigger'),
            ),
          );
        },
      )),
    ));
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('云端有更新'), findsOneWidget);
    await tester.tap(find.text('恢复云端'));
    await tester.pumpAndSettle();

    expect(applied, isNotNull);
    expect(applied!.records.map((r) => r.taskName), contains('数学真题'));
    expect(applied!.sync.lastSyncedAt, sync.updatedAt);
  });

  test('上传遇 409（云端已被网页端更新）时本机数据不被覆盖', () async {
    final sync = FakeCloudSync()
      ..updatedAt = DateTime.utc(2026, 8, 31, 10, 5)
      ..payload = _webPayload();
    final base = _linked();
    AppData? applied;
    final auto = AutoCloudSync(
      sync: sync,
      apply: (data) async => applied = data,
      minInterval: Duration.zero,
    );
    // 本机自上次同步（10:00）后新增记录，但云端在 10:05 被网页端更新 → 上传会 409。
    final local = base
        .copyWith(records: [_record('本机新记录')])
        .copyWith(
      sync: base.sync.copyWith(
        lastSyncedAt: DateTime.utc(2026, 8, 31, 10, 0),
        lastSyncedHash: cloudFingerprint(base),
      ),
    );
    // 无 context 且本机有改动：不弹窗、不覆盖，原样保留。
    await auto.afterFocus(null, local);
    expect(applied, isNull);
    expect(local.records.map((r) => r.taskName), contains('本机新记录'));
  });

  // ── 「本地改动即上传」（2026-10-12 新增，替代"只在完成专注时上传"）──

  test('本地改动即上传：补记/改设置等不再等到下次完成专注', () async {
    final sync = FakeCloudSync();
    AppData? applied;
    final auto = AutoCloudSync(
      sync: sync,
      apply: (data) async => applied = data,
      minInterval: Duration.zero,
      pushInterval: Duration.zero,
    );
    final changed = _linked().copyWith(records: [_record('补记的记录')]);
    await auto.afterLocalChange(changed);

    expect(sync.lastUploadedCode, _code);
    expect(sync.lastUploadedPayload!['records'], isNotEmpty);
    expect(applied!.sync.lastSyncedHash, cloudFingerprint(changed));
  });

  test('未绑定同步码时，本地改动不上传（不创建孤立备份）', () async {
    final sync = FakeCloudSync();
    final auto = AutoCloudSync(
      sync: sync,
      apply: (_) async {},
      minInterval: Duration.zero,
      pushInterval: Duration.zero,
    );
    await auto.afterLocalChange(
      _linked(code: '').copyWith(records: [_record('数学真题')]),
    );
    expect(sync.lastUploadedCode, isNull);
  });

  test('本机无改动时不上传', () async {
    final sync = FakeCloudSync();
    final base = _linked();
    final auto = AutoCloudSync(
      sync: sync,
      apply: (_) async {},
      minInterval: Duration.zero,
      pushInterval: Duration.zero,
    );
    await auto.afterLocalChange(
      base.copyWith(
        sync: base.sync.copyWith(lastSyncedHash: cloudFingerprint(base)),
      ),
    );
    expect(sync.lastUploadedCode, isNull);
  });

  test('会话进行中不上传（避免把 in-progress 记录写进云端）', () async {
    final sync = FakeCloudSync();
    final auto = AutoCloudSync(
      sync: sync,
      apply: (_) async {},
      minInterval: Duration.zero,
      pushInterval: Duration.zero,
    );
    // 有进行中会话，即便数据与上次同步不同也不上传。
    final running = _linked().copyWith(
      records: [_record('数学真题')],
      activeSession: const ActiveSession(
        recordId: 'r1',
        mode: SessionMode.focus,
        running: true,
      ),
    );
    await auto.afterLocalChange(running);
    expect(sync.lastUploadedCode, isNull);
  });

  test('节流：pushInterval 内第二次本地改动不上传', () async {
    var now = DateTime(2026, 8, 31, 12);
    final sync = FakeCloudSync();
    AppData? lastApplied;
    final auto = AutoCloudSync(
      sync: sync,
      apply: (data) async => lastApplied = data,
      minInterval: Duration.zero,
      pushInterval: const Duration(seconds: 20),
      clock: () => now,
    );
    final first = _linked().copyWith(records: [_record('第一条')]);
    await auto.afterLocalChange(first);
    expect(sync.lastUploadedCode, _code, reason: '首轮应上传');

    sync.lastUploadedPayload = null;
    now = now.add(const Duration(seconds: 5)); // 仍在节流窗口内
    final second = lastApplied!.copyWith(records: [
      ...lastApplied!.records,
      _record('第二条'),
    ]);
    await auto.afterLocalChange(second);
    expect(sync.lastUploadedPayload, isNull, reason: '节流窗口内不应上传');

    now = now.add(const Duration(seconds: 20)); // 超出窗口
    await auto.afterLocalChange(second);
    expect(sync.lastUploadedPayload, isNotNull, reason: '超出窗口后应补传');
  });

  test('本地改动上传遇 409：静默跳过，不弹窗不覆盖本机', () async {
    final sync = FakeCloudSync()
      ..updatedAt = DateTime.utc(2026, 8, 31, 10, 5)
      ..payload = _webPayload();
    AppData? applied;
    final auto = AutoCloudSync(
      sync: sync,
      apply: (data) async => applied = data,
      minInterval: Duration.zero,
      pushInterval: Duration.zero,
    );
    final local = _linked()
        .copyWith(records: [_record('本机新记录')])
        .copyWith(
      sync: _linked().sync.copyWith(
        lastSyncedAt: DateTime.utc(2026, 8, 31, 10, 0),
        lastSyncedHash: cloudFingerprint(_linked()),
      ),
    );
    await auto.afterLocalChange(local);
    expect(applied, isNull, reason: '冲突时不应 apply 任何数据');
    expect(local.records.map((r) => r.taskName), contains('本机新记录'));
  });

  // ── 「完成专注必达」（2026-10-12：修"点了完成却没上传"）──

  test('节流窗口内完成专注照常上传（不再被 minInterval 吞掉）', () async {
    var now = DateTime(2026, 8, 31, 12);
    final sync = FakeCloudSync();
    final auto = AutoCloudSync(
      sync: sync,
      apply: (_) async {},
      minInterval: const Duration(hours: 1), // 极端节流：完成专注也应穿过去
      pushInterval: const Duration(hours: 1),
      clock: () => now,
    );
    // 回前台拉取先跑一次（云端无备份 → 404 静默），刷新了节流时钟。
    await auto.onResume(null, _linked());
    now = now.add(const Duration(seconds: 2)); // 仍在节流窗口内

    final changed = _linked().copyWith(records: [_record('刚完成的专注')]);
    await auto.afterFocus(null, changed);

    expect(sync.lastUploadedCode, _code, reason: '完成专注不受节流约束');
    expect(sync.lastUploadedPayload!['records'], isNotEmpty);
  });

  test('同步进行中完成专注：排队而非丢弃，下一次机会补传', () async {
    final sync = FakeCloudSync();
    final auto = AutoCloudSync(
      sync: sync,
      apply: (_) async {},
      minInterval: Duration.zero,
      pushInterval: Duration.zero,
    );
    // 占住通道：模拟回前台拉取/另一次上传正在进行。
    sync.gate = Completer<void>();
    final first = auto.afterFocus(
      null,
      _linked().copyWith(records: [_record('第一条')]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(sync.uploadCount, 1);

    // 此时用户点了「完成」：应排队，不能并发上传也不能丢。
    final second = _linked().copyWith(records: [_record('第二条')]);
    await auto.afterFocus(null, second);
    expect(sync.uploadCount, 1, reason: '占用期间不应并发上传');

    sync.gate!.complete();
    await first;

    // 下一次同步机会（回前台/巡检/启动）用最新数据补传。
    await auto.flushPending(null, second);
    expect(sync.uploadCount, 2, reason: '应恰好补传一次');
    expect(sync.lastUploadedPayload!['records'], isNotEmpty);
  });

  test('上传失败留待补传：下一次同步机会补上', () async {
    final sync = FakeCloudSync()..offline = true;
    AppData? applied;
    final auto = AutoCloudSync(
      sync: sync,
      apply: (data) async => applied = data,
      minInterval: Duration.zero,
      pushInterval: Duration.zero,
    );
    final done = _linked().copyWith(records: [_record('离线完成的专注')]);
    await auto.afterFocus(null, done);
    expect(applied, isNull, reason: '离线时不上传也不 apply');

    sync.offline = false;
    await auto.flushPending(null, done);
    expect(applied, isNotNull);
    expect(sync.lastUploadedPayload!['records'], isNotEmpty);
  });

  test('已同步成功后不再重复补传', () async {
    final sync = FakeCloudSync();
    final auto = AutoCloudSync(
      sync: sync,
      apply: (_) async {},
      minInterval: Duration.zero,
      pushInterval: Duration.zero,
    );
    final done = _linked().copyWith(records: [_record('完成的专注')]);
    await auto.afterFocus(null, done); // 一次成功上传，pending 清空
    await auto.flushPending(null, done);
    expect(sync.uploadCount, 1, reason: '不应重复上传');
  });

  testWidgets('完成专注遇 409：释放通道后拉取并弹窗询问（修 _busy 顺序）',
      (tester) async {
    final sync = FakeCloudSync()
      ..updatedAt = DateTime.utc(2026, 8, 31, 10, 5)
      ..payload = _webPayload();
    final base = _linked();
    final auto = AutoCloudSync(
      sync: sync,
      apply: (_) async {},
      minInterval: Duration.zero,
      pushInterval: Duration.zero,
    );
    // 本机自 10:00 后新增记录，云端 10:05 被另一端更新 → 上传必 409。
    final local = base.copyWith(records: [_record('本机新记录')]).copyWith(
          sync: base.sync.copyWith(
            lastSyncedAt: DateTime.utc(2026, 8, 31, 10, 0),
            lastSyncedHash: cloudFingerprint(base),
          ),
        );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(
        builder: (context) {
          return Center(
            child: TextButton(
              onPressed: () => auto.afterFocus(context, local),
              child: const Text('trigger'),
            ),
          );
        },
      )),
    ));
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    // 修复前 _pull 在 _busy 未释放时被静默 return，这个弹窗根本不会出现。
    expect(find.text('云端有更新'), findsOneWidget);
  });
}
