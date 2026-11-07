import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/sheets.dart';
import 'package:pomodoro_app/src/theme.dart';

/// 2026-11-02 需求：把一条记录从「高数」改到「自控」。
/// 之前只能改时长/完成时刻，改事件只动 eventId，`taskName` 不动 → 统计的「任务构成」仍算旧任务。
AppData _data() {
  final now = DateTime.now();
  return AppData(
    tasks: [
      PineTask(name: '高数'),
      PineTask(name: '自控'),
    ],
    records: [
      FocusRecord(
        id: 'r1',
        taskName: '高数',
        minutes: 50,
        dayKey: ymdOf(dayStart(now)),
        status: RecordStatus.completed,
        at: now,
      ),
    ],
    events: [
      FocusEvent(
          id: 'e-gs',
          name: '高数第六章',
          taskName: '高数',
          startedAt: now,
        ),
      FocusEvent(
          id: 'e-zk',
          name: '自控 ch5',
          taskName: '自控',
          startedAt: now,
        ),
    ],
    settings: const TimerSettings(focus: 50, short: 5, meal: 15),
  );
}

void main() {
  group('TimerEngine.updateRecord 改任务', () {
    test('只改 taskName，其它字段原样保留', () {
      final data = _data();
      final next =
          TimerEngine.updateRecord(data, 'r1', taskName: '自控');
      final record = next.records.single;
      expect(record.taskName, '自控');
      expect(record.minutes, 50);
      expect(record.dayKey, data.records.single.dayKey);
      expect(record.at, data.records.single.at);
      expect(record.status, RecordStatus.completed);
    });

    test('改任务不会自动清空 eventId（是否清空由界面决定）', () {
      final data = _data();
      final withEvent = TimerEngine.setRecordEvent(data, 'r1', 'e-gs');
      final next = TimerEngine.updateRecord(withEvent, 'r1', taskName: '自控');
      expect(next.records.single.eventId, 'e-gs');
    });

    test('任务名与时长可同时改', () {
      final next = TimerEngine.updateRecord(_data(), 'r1',
          taskName: '自控', minutes: 42.5);
      expect(next.records.single.taskName, '自控');
      expect(next.records.single.minutes, 42.5);
    });
  });

  testWidgets('记录面板里能把任务从高数改成自控，并归入自控的事件', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(900, 1800);
    addTearDown(tester.view.reset);

    var data = _data();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRecordDetailSheet(
              context,
              data: data,
              record: data.records.single,
              color: PineColors.sub,
              onChanged: (next) => data = next,
            ),
            child: const Text('打开记录'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开记录'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('修改这条记录'));
    await tester.pumpAndSettle();

    // 任务下拉：选「自控」
    await tester.tap(find.text('所属任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自控').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(data.records.single.taskName, '自控');
  });
}
