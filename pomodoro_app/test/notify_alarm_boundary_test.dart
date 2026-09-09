import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';

/// QA 补的边界用例：围绕 A1/A2 加固所依赖的「超时锚点」语义做纯引擎层验证。
///
/// home_page._compensateRestoredAlarm 用 `recordId@overtimeStartedAt(或 deadline)`
/// 作为「同一段超时」的去重键（A2）。这里验证引擎在 暂停/恢复/restore/advance
/// 下对 overtimeStartedAt 的处理是否符合该键的稳定/变化预期：
/// - 同一段超时（进程多次冷启动、未操作）→ 锚点不变，去重键稳定；
/// - 用户暂停后继续（开启新一段超时）→ 锚点变化，视为新事件，允许再补一次。
AppData _base() => AppData(settings: const TimerSettings(focus: 25));

void main() {
  test('A2 锚点：advance 以原计划结束时刻为超时锚点，且幂等不重置', () {
    final start = DateTime(2026, 9, 8, 9, 0);
    var data = TimerEngine.start(_base(), SessionMode.focus, start);
    expect(data.activeSession!.deadline, DateTime(2026, 9, 8, 9, 25));

    final overtime =
        TimerEngine.advance(data, DateTime(2026, 9, 8, 9, 26));
    expect(overtime.activeSession!.targetReached, isTrue);
    expect(overtime.activeSession!.overtimeStartedAt, DateTime(2026, 9, 8, 9, 25));
    expect(overtime.activeSession!.overtimeElapsed, 0);

    // 再次 advance / syncMinutes 不改变锚点。
    final again =
        TimerEngine.advance(overtime, DateTime(2026, 9, 8, 9, 40));
    expect(again.activeSession!.overtimeStartedAt, DateTime(2026, 9, 8, 9, 25));
    final synced = TimerEngine.syncMinutes(again, DateTime(2026, 9, 8, 9, 45));
    expect(synced.activeSession!.overtimeStartedAt, DateTime(2026, 9, 8, 9, 25));
  });

  test('A2 锚点：restore（冷启动恢复）不重置超时锚点，多次冷启动去重键稳定', () {
    final start = DateTime(2026, 9, 8, 9, 0);
    final persisted = TimerEngine.start(_base(), SessionMode.focus, start);
    // 进程在 09:25 前被杀，09:40 冷启动：restore 应翻转到 targetReached 且锚点=deadline。
    final restored =
        TimerEngine.restore(persisted, DateTime(2026, 9, 8, 9, 40));
    expect(restored.activeSession!.running, isTrue);
    expect(restored.activeSession!.targetReached, isTrue);
    expect(restored.activeSession!.overtimeStartedAt, DateTime(2026, 9, 8, 9, 25));

    // 用户未操作再次冷启动（10:00）：锚点仍不变 → 同一去重键 → 不重复补弹 910。
    final again =
        TimerEngine.restore(restored, DateTime(2026, 9, 8, 10, 0));
    expect(again.activeSession!.overtimeStartedAt, DateTime(2026, 9, 8, 9, 25));
  });

  test('A2 锚点：暂停清空 overtimeStartedAt，继续后换新锚点（视为新一段超时）', () {
    final start = DateTime(2026, 9, 8, 9, 0);
    var data = TimerEngine.start(_base(), SessionMode.focus, start);
    final overtime =
        TimerEngine.advance(data, DateTime(2026, 9, 8, 9, 26));

    final paused = TimerEngine.pause(overtime, DateTime(2026, 9, 8, 9, 27));
    expect(paused.activeSession!.running, isFalse);
    expect(paused.activeSession!.targetReached, isTrue);
    expect(paused.activeSession!.overtimeStartedAt, isNull);
    expect(paused.activeSession!.overtimeElapsed, 2 * 60); // 09:25→09:27

    final resumed = TimerEngine.resume(paused, DateTime(2026, 9, 8, 9, 30));
    expect(resumed.activeSession!.running, isTrue);
    expect(resumed.activeSession!.overtimeStartedAt, DateTime(2026, 9, 8, 9, 30));
  });
}
