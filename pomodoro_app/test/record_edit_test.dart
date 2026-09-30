// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/sheets.dart';
import 'package:pomodoro_app/src/theme.dart';

const String kEventId = 'ev-gaoshu';

AppData _data() => AppData(
      settings: TimerSettings(focus: 50),
      tasks: [PineTask(name: '高数'), PineTask(name: '英语')],
      selectedIndex: 0,
      events: [
        FocusEvent(
          id: kEventId,
          name: '第六章',
          taskName: '高数',
          startedAt: DateTime(2026, 9, 26, 9),
        ),
      ],
      records: [
        FocusRecord(
          taskName: '高数',
          minutes: 41.5,
          dayKey: '2026-09-27',
          status: RecordStatus.completed,
          at: DateTime(2026, 9, 27, 20, 36),
        ),
        FocusRecord(
          taskName: '英语',
          minutes: 30,
          dayKey: '2026-09-27',
          status: RecordStatus.completed,
          at: DateTime(2026, 9, 27, 9, 5),
        ),
      ],
    );

void main() {
  group('updateRecord（引擎）', () {
    test('改时长：只动这一条', () {
      final data = _data();
      final next =
          TimerEngine.updateRecord(data, data.records.first.id, minutes: 60);
      expect(next.records.first.minutes, 60);
      expect(next.records.last.minutes, 30, reason: '不该影响其它记录');
      expect(next.records.first.dayKey, '2026-09-27');
    });

    test('改完成时刻：归属日必须跟着重算（统计按归属日聚合）', () {
      final data = _data();
      // 9/27 20:36 → 9/28 20:36
      final next = TimerEngine.updateRecord(data, data.records.first.id,
          at: DateTime(2026, 9, 28, 20, 36));
      expect(next.records.first.dayKey, '2026-09-28',
          reason: '只改 at 不改 dayKey，这条记录会留在错误的一天');
      expect(next.records.first.at, DateTime(2026, 9, 28, 20, 36));
    });

    test('设归属：把漏归的记录接回事件', () {
      final data = _data();
      expect(data.records.first.eventId, isNull);
      final next =
          TimerEngine.setRecordEvent(data, data.records.first.id, kEventId);
      expect(next.records.first.eventId, kEventId);
      expect(eventStatsOf(next, kEventId).minutes, 41.5);
    });

    test('解归属：传 null 只解除关联，记录本身不动', () {
      final linked = TimerEngine.setRecordEvent(
          _data(), _data().records.first.id, kEventId);
      final id = linked.records.first.id;
      final unlinked = TimerEngine.setRecordEvent(linked, id, null);
      expect(unlinked.records.first.eventId, isNull);
      expect(unlinked.records.first.minutes, 41.5, reason: '记录内容不受影响');
      expect(unlinked.records.length, 2);
    });

    test('护栏：拒绝写入不存在的事件 id（那正是悬空引用的来源）', () {
      final data = _data();
      final same =
          TimerEngine.setRecordEvent(data, data.records.first.id, '不存在的id');
      expect(same.records.first.eventId, isNull, reason: '应原样返回，不写入非法 id');
    });

    test('跨凌晨 3 点分界：2:59 仍算前一天，3:00 才算当天', () {
      final data = _data();
      final early = TimerEngine.updateRecord(data, data.records.first.id,
          at: DateTime(2026, 9, 28, 2, 59));
      expect(early.records.first.dayKey, '2026-09-27');
      final after = TimerEngine.updateRecord(data, data.records.first.id,
          at: DateTime(2026, 9, 28, 3, 0));
      expect(after.records.first.dayKey, '2026-09-28');
    });
  });

  testWidgets('全部记录面板 → 记录详情 → 修改时长 → 保存', (tester) async {
    var data = _data();
    final originalId = data.records.first.id; // 每次 _data() 都会生成新 id，先存下来
    await tester.pumpWidget(MaterialApp(
      theme: buildPineTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showAllRecordsSheet(
                context,
                data: data,
                colorFor: (_) => PineColors.pine,
                onChanged: (next) => data = next,
              ),
              child: const Text('打开全部记录'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开全部记录'));
    await tester.pumpAndSettle();

    // 面板出现，且两条记录都在（首页只列 3 条，这里是全部）
    expect(find.text('全部记录'), findsOneWidget);
    expect(find.textContaining('2 条 · 合计'), findsOneWidget);
    expect(find.textContaining('9/27'), findsWidgets, reason: '按统计日分组的小标题');
    expect(find.text('高数'), findsOneWidget);
    expect(find.text('英语'), findsOneWidget);

    // 进详情
    await tester.tap(find.text('高数'));
    await tester.pumpAndSettle();
    expect(find.text('记录详情'), findsOneWidget);
    expect(find.text('修改这条记录'), findsOneWidget);
    expect(find.text('删除这条记录'), findsOneWidget);

    // 修改 → 改时长 → 保存
    await tester.tap(find.text('修改这条记录'));
    await tester.pumpAndSettle();
    expect(find.text('专注时长'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '60');

    // 一并把这条记录归入事件：点开下拉 → 选事件
    expect(find.text('归入专注事件'), findsOneWidget, reason: '对话框应有归属选择');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('第六章').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(data.records.first.minutes, 60, reason: '保存后数据应已更新');
    expect(data.records.first.eventId, kEventId, reason: '归属也应一并写入');
    expect(data.records.first.id, originalId, reason: '改的是同一条记录，不是新增');
    expect(data.records.length, 2, reason: '不应新增记录');
  });
}
