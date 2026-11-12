// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';

/// 阶段条的口径（2026-11-11）：**点谁进谁**，三条硬规则各有单测。
///
/// 1. 幂等——点当前所在的阶段不改任何东西（旧实现会重置成满格）；
/// 2. 不丢时长——离开专注按完成收口，离开休息直接丢弃；
/// 3. 顺路收口不写 0 分钟记录（旧实现留下一条"0 分"的噪音条目）。
AppData _base() => AppData(
      settings: const TimerSettings(focus: 50, short: 10, meal: 40),
      tasks: [PineTask(name: '高数')],
    );

void main() {
  group('幂等：点当前阶段不动剩余时间', () {
    test('专注进行中点「专注」→ 原样返回同一实例', () {
      final t0 = DateTime(2026, 11, 8, 9);
      var data = TimerEngine.start(_base(), SessionMode.focus, t0);
      data = TimerEngine.advance(data, t0.add(const Duration(minutes: 12)));
      final next = TimerEngine.switchPhase(
          data, SessionMode.focus, t0.add(const Duration(minutes: 12)));
      expect(identical(next, data), isTrue, reason: '不该重建对象，调用方靠这个跳过写盘');
    });

    test('短休只剩 6 分钟时点「短休」→ 剩余仍是 6 分钟，不重置成 10', () {
      final t0 = DateTime(2026, 11, 8, 9);
      var data = TimerEngine.start(_base(), SessionMode.shortBreak, t0);
      final at = t0.add(const Duration(minutes: 4));
      data = TimerEngine.advance(data, at);
      final next = TimerEngine.switchPhase(data, SessionMode.shortBreak, at);
      final view = SessionView.of(next, at)!;
      expect(view.remainingSeconds, 6 * 60);
    });

    test('空闲态点「专注」不启动会话（起不停交给主按钮）', () {
      final t0 = DateTime(2026, 11, 8, 9);
      final next = TimerEngine.switchPhase(_base(), SessionMode.focus, t0);
      expect(next.activeSession, isNull);
      expect(next.records, isEmpty);
    });
  });

  group('不丢时长', () {
    test('专注 37 分钟点「短休」→ 先落 37 分钟记录，再进短休', () {
      final t0 = DateTime(2026, 11, 8, 9);
      var data = TimerEngine.start(_base(), SessionMode.focus, t0);
      final at = t0.add(const Duration(minutes: 37));
      data = TimerEngine.advance(data, at);
      data = TimerEngine.switchPhase(data, SessionMode.shortBreak, at);

      final record = data.records.firstWhere((r) => r.taskName == '高数');
      expect(record.status, RecordStatus.completed);
      expect(record.minutes, closeTo(37, 0.05));
      expect(data.activeSession!.mode, SessionMode.shortBreak);
      expect(data.activeSession!.running, isTrue);
    });

    test('短休中点「吃饭」→ 不写记录，直接换段', () {
      final t0 = DateTime(2026, 11, 8, 9);
      var data = TimerEngine.start(_base(), SessionMode.shortBreak, t0);
      final before = data.records.length;
      data = TimerEngine.switchPhase(
          data, SessionMode.longBreak, t0.add(const Duration(minutes: 3)));
      expect(data.records.length, before);
      expect(data.activeSession!.mode, SessionMode.longBreak);
    });

    test('短休中点「专注」→ 结束休息，直接起一轮专注（本次新增的一步切换）', () {
      final t0 = DateTime(2026, 11, 8, 9);
      var data = TimerEngine.start(_base(), SessionMode.shortBreak, t0);
      final at = t0.add(const Duration(minutes: 2));
      data = TimerEngine.switchPhase(data, SessionMode.focus, at);
      expect(data.activeSession!.mode, SessionMode.focus);
      expect(data.activeSession!.running, isTrue);
      // 休息不计入统计，也不该留下记录
      expect(data.records.where((r) => r.counted), isEmpty);
    });
  });

  group('顺路收口：不足 1 分钟不留空记录', () {
    test('专注 40 秒点「短休」→ 不留 0 分钟记录', () {
      final t0 = DateTime(2026, 11, 8, 9);
      var data = TimerEngine.start(_base(), SessionMode.focus, t0);
      final at = t0.add(const Duration(seconds: 40));
      data = TimerEngine.advance(data, at);
      data = TimerEngine.switchPhase(data, SessionMode.shortBreak, at);

      expect(data.records.where((r) => r.counted), isEmpty,
          reason: '切阶段是"顺路收口"，40 秒写一条 0 分记录只会在最近记录里留噪音');
      expect(data.activeSession!.mode, SessionMode.shortBreak);
    });

    test('专注 61 秒点「短休」→ 仍然照记（只挡 0 分钟档）', () {
      final t0 = DateTime(2026, 11, 8, 9);
      var data = TimerEngine.start(_base(), SessionMode.focus, t0);
      final at = t0.add(const Duration(seconds: 61));
      data = TimerEngine.advance(data, at);
      data = TimerEngine.switchPhase(data, SessionMode.shortBreak, at);
      expect(data.records.where((r) => r.counted).length, 1);
    });

    test('收工同样不留 0 分钟记录', () {
      final t0 = DateTime(2026, 11, 8, 21);
      var data = TimerEngine.start(_base(), SessionMode.focus, t0);
      final at = t0.add(const Duration(seconds: 30));
      data = TimerEngine.restForToday(data, at);
      expect(data.records.where((r) => r.counted), isEmpty);
      expect(data.isRestDay(at), isTrue);
    });
  });

  group('收工标记与阶段条的一致性', () {
    test('收工态点「吃饭」→ 标记作废（不能出现"正在吃饭但今天已收工"）', () {
      final t0 = DateTime(2026, 11, 8, 21);
      var data = TimerEngine.restForToday(_base(), t0);
      expect(data.isRestDay(t0), isTrue);
      data = TimerEngine.switchPhase(data, SessionMode.longBreak, t0);
      expect(data.isRestDay(t0), isFalse);
      expect(data.activeSession!.mode, SessionMode.longBreak);
    });

    test('收工态点「专注」（空闲）→ 只清标记，不凭空起一轮', () {
      final t0 = DateTime(2026, 11, 8, 21);
      var data = TimerEngine.restForToday(_base(), t0);
      data = TimerEngine.switchPhase(data, SessionMode.focus, t0);
      expect(data.isRestDay(t0), isFalse);
      expect(data.activeSession, isNull);
    });

    test('未收工时点「专注」（空闲）→ 连对象都不换', () {
      final t0 = DateTime(2026, 11, 8, 9);
      final data = _base();
      expect(identical(TimerEngine.switchPhase(data, SessionMode.focus, t0), data),
          isTrue);
    });
  });
}
