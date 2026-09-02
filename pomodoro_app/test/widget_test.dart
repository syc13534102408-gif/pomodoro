import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pomodoro_app/main.dart';
import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';

AppData _base({int focus = 1}) => AppData(
      settings: TimerSettings(focus: focus, short: 5, long: 15),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('主界面渲染出计时器与今日目标', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const PomodoroApp());
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(find.text('准备开始'), findsOneWidget);
    expect(find.text('今日目标'), findsOneWidget);
    expect(find.text('专注'), findsWidgets);
  });

  test('旧版今日目标（次）自动迁移为专注分钟', () {
    // 旧数据只有 goalTarget（次），按 次数 × 专注时长 换算。
    final legacy = AppData.fromMap(<String, dynamic>{
      'goalTarget': 8,
      'settings': {'focus': 25, 'short': 5, 'long': 15},
    });
    expect(legacy.goalMinutes, 200);

    // 新数据优先，旧字段被忽略。
    final modern = AppData.fromMap(<String, dynamic>{
      'goalMinutes': 150,
      'goalTarget': 8,
      'settings': {'focus': 25},
    });
    expect(modern.goalMinutes, 150);
  });

  test('计划时长到点后继续累计，不自动结束', () {
    final start = DateTime(2026, 8, 29, 9, 0);
    var data = TimerEngine.start(_base(), SessionMode.focus, start);
    expect(data.activeSession, isNotNull);
    expect(data.activeSession!.running, isTrue);

    // 尚未到点。
    final midway = TimerEngine.advance(data, start.add(const Duration(seconds: 30)));
    expect(midway.activeSession!.targetReached, isFalse);
    expect(SessionView.of(midway, start.add(const Duration(seconds: 30)))!.clockText,
        '00:30');

    // 到点：进入超时但会话仍在运行。
    final atTarget = TimerEngine.advance(data, start.add(const Duration(seconds: 61)));
    expect(atTarget.activeSession!.targetReached, isTrue);
    expect(atTarget.activeSession!.running, isTrue);

    // 超时继续累计。
    final overtime = TimerEngine.advance(
        atTarget, start.add(const Duration(seconds: 61 + 90)));
    final view = SessionView.of(overtime, start.add(const Duration(seconds: 151)))!;
    expect(view.targetReached, isTrue);
    expect(view.clockText, '+01:31');
    expect(view.elapsedMinutes, closeTo(2.5, 0.05));
  });

  test('确认完成后记录完整时长并自动进入短休息', () {
    final start = DateTime(2026, 8, 29, 9, 0);
    var data = TimerEngine.start(_base(focus: 50), SessionMode.focus, start);
    final later = start.add(const Duration(minutes: 72));
    data = TimerEngine.advance(data, later);
    data = TimerEngine.syncMinutes(data, later);

    final view = SessionView.of(data, later)!;
    expect(view.elapsedMinutes, closeTo(72.0, 0.05));

    data = TimerEngine.complete(data, later);
    final record = data.records.firstWhere(
      (item) => item.taskName == '数学真题',
      orElse: () => data.records.first,
    );
    expect(record.status, RecordStatus.completed);
    expect(record.minutes, closeTo(72.0, 0.05));

    // 自动开始休息，且第 1 次是短休息。
    expect(data.activeSession, isNotNull);
    expect(data.activeSession!.mode, SessionMode.shortBreak);
    expect(data.activeSession!.running, isTrue);
  });

  test('第 4 次专注完成后进入长休息', () {
    final now = DateTime(2026, 8, 29, 12, 0);
    var data = _base(focus: 25);
    // 先补 3 条已完成记录，使本次成为第 4 次。
    for (var i = 0; i < 3; i++) {
      data = TimerEngine.addManual(
        data,
        taskName: '数学真题',
        minutes: 25,
        at: now.subtract(Duration(hours: 3 - i)),
      );
    }
    expect(StatsView.of(data, now).todayCount, 3);

    data = TimerEngine.start(data, SessionMode.focus, now);
    data = TimerEngine.complete(data, now.add(const Duration(minutes: 25)));
    expect(StatsView.of(data, now).todayCount, 4);
    expect(data.activeSession!.mode, SessionMode.longBreak);
  });

  test('重置会丢弃未完成会话，不写入统计', () {
    final start = DateTime(2026, 8, 29, 9, 0);
    var data = TimerEngine.start(_base(focus: 25), SessionMode.focus, start);
    final mid = start.add(const Duration(minutes: 7));
    data = TimerEngine.syncMinutes(data, mid);
    expect(data.records.length, 1);

    data = TimerEngine.discard(data);
    expect(data.activeSession, isNull);
    expect(data.records, isEmpty);
    expect(StatsView.of(data, mid).todayCount, 0);
  });

  test('暂停冻结剩余时间，继续后从同一剩余值恢复', () {
    final start = DateTime(2026, 8, 29, 9, 0);
    var data = TimerEngine.start(_base(focus: 25), SessionMode.focus, start);
    data = TimerEngine.pause(data, start.add(const Duration(minutes: 10)));
    expect(SessionView.of(data, start.add(const Duration(minutes: 40)))!.remainingSeconds,
        15 * 60);

    data = TimerEngine.resume(data, start.add(const Duration(minutes: 40)));
    expect(SessionView.of(data, start.add(const Duration(minutes: 45)))!.clockText,
        '10:00');
  });

  test('本周统计按周一到周日聚合，且按任务分色堆叠', () {
    // 2026-08-29 是周六，本周一为 2026-08-24。
    final monday = DateTime(2026, 8, 24, 9, 0);
    var data = _base();
    data = TimerEngine.addManual(data, taskName: '数学真题', minutes: 50, at: monday);
    data = TimerEngine.addManual(
        data,
        taskName: '错题整理',
        minutes: 30,
        at: monday.add(const Duration(hours: 2)),
    );
    data = TimerEngine.addManual(
        data,
        taskName: '数学真题',
        minutes: 20,
        at: monday.add(const Duration(days: 2)),
    );

    final stats = StatsView.of(data, DateTime(2026, 8, 29, 20, 0));
    expect(stats.weekMinutes, closeTo(100, 0.001));
    expect(stats.totalForDay(0), closeTo(80, 0.001)); // 周一
    expect(stats.totalForDay(2), closeTo(20, 0.001)); // 周三
    expect(stats.totalForDay(5), closeTo(0, 0.001)); // 周六
    expect(stats.tasksInWeek().first, '数学真题');
  });
}
