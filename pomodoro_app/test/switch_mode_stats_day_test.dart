import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';

const _settings = TimerSettings(focus: 25, short: 5, long: 15);

AppData _base() => AppData(settings: _settings);

void main() {
  group('switchMode：切换不打断会话', () {
    test('运行中切到休息：专注暂停挂起，剩余冻结，模式切到休息', () {
      final start = DateTime(2026, 9, 9, 9, 0);
      var data = TimerEngine.start(_base(), SessionMode.focus, start);
      data = TimerEngine.advance(data, start.add(const Duration(minutes: 10)));

      data = TimerEngine.switchMode(data, SessionMode.shortBreak,
          start.add(const Duration(minutes: 12)));

      // 会话保留且暂停：已专注 12 分钟冻结，剩余 13:00。
      expect(data.activeSession, isNotNull);
      expect(data.activeSession!.mode, SessionMode.focus);
      expect(data.activeSession!.running, isFalse);
      expect(data.idleMode, SessionMode.shortBreak);
      expect(
        SessionView.of(data, start.add(const Duration(minutes: 30)))!
            .remainingSeconds,
        13 * 60,
      );
    });

    test('切回专注：时间从冻结点继续', () {
      final start = DateTime(2026, 9, 9, 9, 0);
      var data = TimerEngine.start(_base(), SessionMode.focus, start);
      data = TimerEngine.advance(data, start.add(const Duration(minutes: 10)));
      data = TimerEngine.switchMode(data, SessionMode.shortBreak,
          start.add(const Duration(minutes: 12)));

      // 休息界面停留 20 分钟后再切回：剩余 13:00 继续走，40 分钟时剩 5:00。
      final backAt = start.add(const Duration(minutes: 32));
      data = TimerEngine.switchMode(data, SessionMode.focus, backAt);
      expect(data.activeSession!.running, isTrue);
      expect(
        SessionView.of(data, start.add(const Duration(minutes: 40)))!
            .clockText,
        '05:00',
      );
    });

    test('已暂停的会话切走再切回：直接恢复', () {
      final start = DateTime(2026, 9, 9, 9, 0);
      var data = TimerEngine.start(_base(), SessionMode.focus, start);
      data = TimerEngine.pause(data, start.add(const Duration(minutes: 5)));
      data = TimerEngine.switchMode(data, SessionMode.longBreak, start.add(const Duration(minutes: 6)));
      data = TimerEngine.switchMode(data, SessionMode.focus, start.add(const Duration(minutes: 7)));
      expect(data.activeSession!.running, isTrue);
      expect(data.idleMode, SessionMode.focus);
    });

    test('无会话时切换：仅改变待开始模式', () {
      final data = TimerEngine.switchMode(
          _base(), SessionMode.longBreak, DateTime(2026, 9, 9, 9));
      expect(data.activeSession, isNull);
      expect(data.idleMode, SessionMode.longBreak);
    });

    test('挂起专注后 complete：按已专注时长落记录，不丢数据', () {
      final start = DateTime(2026, 9, 9, 9, 0);
      var data = TimerEngine.start(_base(), SessionMode.focus, start);
      data = TimerEngine.advance(data, start.add(const Duration(minutes: 10)));
      data = TimerEngine.switchMode(data, SessionMode.shortBreak,
          start.add(const Duration(minutes: 12)));

      // 用户在休息模式点「完成」→ 完成挂起中的专注（12 分钟）并自动休息。
      data = TimerEngine.complete(data, start.add(const Duration(minutes: 15)));

      final record = data.records.first;
      expect(record.minutes, 12.0);
      expect(record.status, RecordStatus.completed);
      // 自动进入休息（1 次完成 → 短休息）。
      expect(data.activeSession, isNotNull);
      expect(data.activeSession!.mode, SessionMode.shortBreak);
    });
  });

  group('pomodoroEquiv：满 50 分钟 1 个，缺口不足 15 分钟补齐', () {
    test('边界表', () {
      expect(pomodoroEquiv(0), 0);
      expect(pomodoroEquiv(14), 0);
      expect(pomodoroEquiv(34), 0); // 差 16，不补
      expect(pomodoroEquiv(35), 1); // 差 15，补齐
      expect(pomodoroEquiv(49), 1); // 差 1，补齐
      expect(pomodoroEquiv(50), 1);
      expect(pomodoroEquiv(74), 1); // 差 26，不补
      expect(pomodoroEquiv(85), 2); // 差 15，补齐
      expect(pomodoroEquiv(100), 2);
      expect(pomodoroEquiv(134), 2);
      expect(pomodoroEquiv(135), 3);
    });
  });

  group('统计日：凌晨 3 点为两天的分界', () {
    test('dateKey：0:00–2:59 归前一天，3:00 起归当天', () {
      expect(dateKey(DateTime(2026, 9, 9, 2, 59)), '2026-09-08');
      expect(dateKey(DateTime(2026, 9, 9, 3, 0)), '2026-09-09');
      expect(dateKey(DateTime(2026, 9, 9, 12, 0)), '2026-09-09');
    });

    test('前一天深夜与次日凌晨的记录同属一个统计日', () {
      final now = DateTime(2026, 9, 9, 1, 0); // 统计日 = 09-08
      var data = _base();
      data = data.copyWith(
        records: [
          FocusRecord(
            taskName: '数学',
            minutes: 25,
            dayKey: dateKey(DateTime(2026, 9, 8, 23, 0)),
            status: RecordStatus.completed,
            at: DateTime(2026, 9, 8, 23, 0),
          ),
          FocusRecord(
            taskName: '数学',
            minutes: 25,
            dayKey: dateKey(DateTime(2026, 9, 9, 0, 30)),
            status: RecordStatus.completed,
            at: DateTime(2026, 9, 9, 0, 30),
          ),
        ],
      );
      // 两条（23:00 与次日 00:30）同属统计日 09-08 → 50 分钟 → 1 个番茄。
      expect(StatsView.of(data, now).todayMinutes, 50.0);
      expect(StatsView.of(data, now).todayCount, 1);
    });

    test('addManual 的 dayKey 按统计日归属', () {
      final at = DateTime(2026, 9, 9, 1, 30); // 统计日 = 09-08
      final data = TimerEngine.addManual(
        _base(),
        taskName: '数学',
        minutes: 50,
        at: at,
      );
      expect(data.records.first.dayKey, '2026-09-08');
    });
  });
}
