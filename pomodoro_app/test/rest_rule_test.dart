// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';

AppData _base() => AppData(
      settings: const TimerSettings(focus: 100, short: 5, meal: 15),
      tasks: [PineTask(name: '高数')],
    );

/// 跑一轮「开始 → 到点完成」，返回完成后的数据。
AppData _runFocus(Duration planned) {
  final t0 = DateTime(2026, 10, 9, 10);
  var data = TimerEngine.start(_base(), SessionMode.focus, t0);
  // 把计划时长改成本次实际要学的时长：用 settings 控制不便，直接推进到目标时刻。
  final doneAt = t0.add(planned);
  data = TimerEngine.advance(data, doneAt);
  return TimerEngine.complete(data, doneAt);
}

void main() {
  group('自动休息固定短休（2026-11-07 规则）', () {
    test('50 分钟（含 70 以内）→ 短休息', () {
      final data = _runFocus(const Duration(minutes: 50));
      expect(data.activeSession!.mode, SessionMode.shortBreak);
    });

    test('恰好 70 分钟 → 短休息（边界含于「以内」）', () {
      final data = _runFocus(const Duration(minutes: 70));
      expect(data.activeSession!.mode, SessionMode.shortBreak);
    });

    test('超过 70 分钟也只进短休（旧规则的 70 分档已取消）', () {
      final data = _runFocus(const Duration(minutes: 75));
      expect(data.activeSession!.mode, SessionMode.shortBreak);
    });

    test('长专注（100 分钟）→ 短休', () {
      final data = _runFocus(const Duration(minutes: 100));
      expect(data.activeSession!.mode, SessionMode.shortBreak);
    });
  });
}
