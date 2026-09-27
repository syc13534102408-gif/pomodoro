// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';

AppData _base() => AppData(
      settings: TimerSettings(focus: 50),
      tasks: [PineTask(name: '高数'), PineTask(name: '英语')],
      selectedIndex: 0,
    );

void main() {
  group('事件生命周期', () {
    test('开启事件 → 完成 → 状态派生正确', () {
      final t0 = DateTime(2026, 9, 27, 10);
      var data = TimerEngine.startEvent(_base(),
          name: '高数第六章', taskName: '高数', now: t0);
      expect(data.events.length, 1);
      expect(data.events.first.isRunning, isTrue);

      data = TimerEngine.pauseEvent(data, data.events.first.id, t0.add(const Duration(hours: 1)));
      expect(data.events.first.isPaused, isTrue);

      data = TimerEngine.resumeEvent(data, data.events.first.id, t0.add(const Duration(hours: 2)));
      expect(data.events.first.isRunning, isTrue);

      data = TimerEngine.finishEvent(data, data.events.first.id, t0.add(const Duration(days: 1)));
      expect(data.events.first.isFinished, isTrue);
      expect(data.events.first.isPaused, isFalse);
    });

    test('同任务开启新事件 → 旧的自动暂停（同时只有一个进行中）', () {
      final t0 = DateTime(2026, 9, 27, 10);
      var data = TimerEngine.startEvent(_base(),
          name: '第六章', taskName: '高数', now: t0);
      data = TimerEngine.startEvent(data,
          name: '第七章', taskName: '高数', now: t0.add(const Duration(days: 1)));
      final running = data.events.where((e) => e.isRunning).toList();
      expect(running.length, 1);
      expect(running.first.name, '第七章');
      expect(data.events.firstWhere((e) => e.name == '第六章').isPaused, isTrue);
    });

    test('不同任务的事件互不影响', () {
      final t0 = DateTime(2026, 9, 27, 10);
      var data = TimerEngine.startEvent(_base(),
          name: '高数第六章', taskName: '高数', now: t0);
      data = TimerEngine.startEvent(data,
          name: '英语阅读', taskName: '英语', now: t0);
      expect(data.events.where((e) => e.isRunning).length, 2);
    });
  });

  group('记录归属', () {
    test('进行中事件期间：专注与补记都自动归入', () {
      final t0 = DateTime(2026, 9, 27, 10);
      var data = TimerEngine.startEvent(_base(),
          name: '高数第六章', taskName: '高数', now: t0);
      final eventId = data.events.first.id;

      // 开始一轮专注（in_progress 记录）
      data = TimerEngine.start(data, SessionMode.focus, t0);
      expect(data.records.first.eventId, eventId);

      // 补记
      data = TimerEngine.addManual(data,
          taskName: '高数', minutes: 30, at: t0.add(const Duration(hours: 1)));
      expect(data.records.first.eventId, eventId);
    });

    test('暂停期间与完成之后的记录不归入', () {
      final t0 = DateTime(2026, 9, 27, 10);
      var data = TimerEngine.startEvent(_base(),
          name: '高数第六章', taskName: '高数', now: t0);
      final eventId = data.events.first.id;
      data = TimerEngine.finishEvent(data, eventId, t0.add(const Duration(hours: 1)));

      data = TimerEngine.addManual(data,
          taskName: '高数', minutes: 30, at: t0.add(const Duration(hours: 2)));
      expect(data.records.first.eventId, isNull);
    });

    test('未开事件的任务：记录 eventId 为空', () {
      final data = TimerEngine.addManual(_base(),
          taskName: '高数', minutes: 30, at: DateTime(2026, 9, 27, 10));
      expect(data.records.first.eventId, isNull);
    });

    test('删除事件：记录保留、仅解除关联', () {
      final t0 = DateTime(2026, 9, 27, 10);
      var data = TimerEngine.startEvent(_base(),
          name: '高数第六章', taskName: '高数', now: t0);
      final eventId = data.events.first.id;
      data = TimerEngine.addManual(data,
          taskName: '高数', minutes: 50, at: t0);
      expect(data.records.length, 1);

      data = TimerEngine.deleteEvent(data, eventId);
      expect(data.events, isEmpty);
      expect(data.records.length, 1); // 记录仍在
      expect(data.records.first.eventId, isNull); // 关联已解除
      expect(data.records.first.minutes, 50);
    });
  });

  group('事件聚合', () {
    test('累计时长 / 番茄 / 天数', () {
      final t0 = DateTime(2026, 9, 27, 10);
      var data = TimerEngine.startEvent(_base(),
          name: '高数第六章', taskName: '高数', now: t0);
      final eventId = data.events.first.id;

      data = TimerEngine.addManual(data,
          taskName: '高数', minutes: 50, at: t0);
      data = TimerEngine.addManual(data,
          taskName: '高数', minutes: 52, at: t0.add(const Duration(days: 1)));
      // 未归入的记录（英语）不计
      data = TimerEngine.addManual(data,
          taskName: '英语', minutes: 100, at: t0);

      final stats = eventStatsOf(data, eventId);
      expect(stats.minutes, 102);
      expect(stats.days, 2);
      expect(stats.tomatoCount, 2); // (102+15)~/50 = 2
      expect(stats.records.length, 2);
    });
  });
}
