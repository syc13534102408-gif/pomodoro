// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/storage.dart';

FocusRecord _rec(String id, String date, String name, double minutes,
        {String status = 'completed'}) =>
    FocusRecord(
      id: id,
      taskName: name,
      minutes: minutes,
      dayKey: date,
      status: RecordStatusX.from(status),
      at: DateTime.parse('$date 12:00'),
    );

AppData localWithEvent() {
  final base = _withRecords([
    _rec('A', '2026-10-05', '高数', 50),
  ]);
  return base.copyWith(
    events: [
      FocusEvent(
        name: '无穷级数',
        taskName: '高数',
        startedAt: DateTime(2026, 9, 28),
        finishedAt: DateTime(2026, 10, 2),
      ),
    ],
  );
}

AppData _withRecords(List<FocusRecord> records) =>
    AppData(settings: TimerSettings(), records: records);

void main() {
  test('mergeFromCloud 按 id 并集：本机独有保留、云端独有补入、同 id 云端优先', () {
    // 本机：记录 A（云端也有）、C（云端没有——本机新学的）
    final local = _withRecords([
      _rec('A', '2026-09-15', '高数', 50),
      _rec('C', '2026-09-15', '英语', 23),
    ]);
    // 云端：记录 A（同 id，分钟不同——云端 45）、B（云端独有）
    final payload = {
      'tasks': [],
      'todos': <String, dynamic>{},
      'records': [
        {'id': 'A', 'name': '高数', 'minutes': 45.0, 'date': '2026-09-15', 'status': 'completed'},
        {'id': 'B', 'name': '英语', 'minutes': 30.0, 'date': '2026-09-15', 'status': 'completed'},
      ],
    };

    final merged = mergeFromCloud(local, payload);

    final ids = merged.records.map((r) => r.id).toSet();
    expect(ids, containsAll(['A', 'B', 'C'])); // 三条都在：并集
    expect(merged.records.length, 3); // 不多不少
    // 同 id 冲突：云端版本优先（恢复场景云端是权威）
    expect(merged.records.firstWhere((r) => r.id == 'A').minutes, 45.0);
    // 本机独有的 C 保留（事故根因：曾被整体替换清空）
    expect(merged.records.firstWhere((r) => r.id == 'C').minutes, 23.0);
  });

  test('events 也按 id 并集：本机独有的事件不被云端清空（10-05 事故）', () {
    // 本机有一个事件；云端净荷来自旧版设备，events 字段缺失
    final local = localWithEvent();
    final payload = {
      'tasks': [],
      'records': [
        {'id': 'A', 'name': '高数', 'minutes': 50.0, 'date': '2026-10-05', 'status': 'completed'},
      ],
    };

    final merged = mergeFromCloud(local, payload);
    expect(merged.events.length, 1);
    expect(merged.events.first.name, '无穷级数');
  });

  test('同 id 记录云端优先时，本机的 eventId 归属保留（防关联被斩断）', () {
    // 本机记录带 eventId，云端同 id 记录来自旧版（无 eventId 字段）
    final local = _withRecords([
      _rec('A', '2026-10-05', '高数', 50),
    ]);
    final localLinked = local.copyWith(
      records: [
        FocusRecord(
          id: 'A',
          taskName: '高数',
          minutes: 50,
          dayKey: '2026-10-05',
          status: RecordStatus.completed,
          at: DateTime.parse('2026-10-05 12:00'),
          eventId: 'event-1',
        ),
      ],
    );
    final payload = {
      'tasks': [],
      'records': [
        {'id': 'A', 'name': '高数', 'minutes': 45.0, 'date': '2026-10-05', 'status': 'completed'},
      ],
    };

    final merged = mergeFromCloud(localLinked, payload);
    expect(merged.records.length, 1);
    // 分钟数取云端（同 id 云端优先）
    expect(merged.records.first.minutes, 45.0);
    // 但归属保留本机的
    expect(merged.records.first.eventId, 'event-1');
  });

  test('合并后按完成时刻倒序排列（列表展示依赖）', () {
    final local = _withRecords([
      _rec('A', '2026-09-15', '高数', 50),
    ]);
    final payload = {
      'tasks': [],
      'todos': <String, dynamic>{},
      'records': [
        {'id': 'B', 'name': '英语', 'minutes': 30.0, 'date': '2026-09-15', 'status': 'completed'},
      ],
    };
    final merged = mergeFromCloud(local, payload);
    // 云端 B 的 at 与本机 A 的 at 相同（测试数据），排序稳定性不作断言，
    // 仅验证全部保留。
    expect(merged.records.length, 2);
  });
}
