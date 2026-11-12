// ignore_for_file: prefer_const_constructors
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pomodoro_app/main.dart';
import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/widgets.dart';

/// 2026-11-07 需求：
/// 1. 自动休息只触发**短休**（不再按 70 分钟分档）；
/// 2. 新增「吃饭」按钮，一键开始吃饭计时（默认 40 分钟，设置页可改）；
/// 3. 新增「休息」按钮 = 今日收工（结束计时 + 标记今日休息，今天不再自动提醒）。
AppData _base() => AppData(
      settings: const TimerSettings(focus: 50, short: 10, meal: 40),
      tasks: [PineTask(name: '高数')],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('只自动触发短休', () {
    test('一轮 120 分钟专注结束 → 短休（旧规则会进长休息/吃饭）', () {
      final t0 = DateTime(2026, 11, 7, 9);
      var data = TimerEngine.start(_base(), SessionMode.focus, t0);
      final doneAt = t0.add(const Duration(minutes: 120));
      data = TimerEngine.advance(data, doneAt);
      data = TimerEngine.complete(data, doneAt);
      expect(data.activeSession!.mode, SessionMode.shortBreak);
      expect(data.activeSession!.running, isTrue);
    });
  });

  group('手动休息入口', () {
    test('吃饭 = longBreak 槽位，时长取 settings.meal（默认 40）', () {
      final t0 = DateTime(2026, 11, 7, 12);
      var data = TimerEngine.startBreak(_base(), SessionMode.longBreak, t0);
      expect(data.activeSession!.mode, SessionMode.longBreak);
      expect(data.activeSession!.running, isTrue);
      final view = SessionView.of(data, t0)!;
      expect(view.plannedSeconds, 40 * 60);
    });

    test('专注进行中按「短休」：本轮时长先落记录，再进短休', () {
      final t0 = DateTime(2026, 11, 7, 9);
      var data = TimerEngine.start(_base(), SessionMode.focus, t0);
      data = TimerEngine.advance(data, t0.add(const Duration(minutes: 37)));
      data = TimerEngine.startBreak(data, SessionMode.shortBreak,
          t0.add(const Duration(minutes: 37)));

      final record = data.records.firstWhere((r) => r.taskName == '高数');
      expect(record.status, RecordStatus.completed);
      expect(record.minutes, closeTo(37, 0.05));
      expect(data.activeSession!.mode, SessionMode.shortBreak);
    });

    test('休息进行中按「吃饭」：不写记录，直接换成吃饭', () {
      final t0 = DateTime(2026, 11, 7, 9);
      var data = TimerEngine.start(_base(), SessionMode.shortBreak, t0);
      final before = data.records.length;
      data = TimerEngine.startBreak(data, SessionMode.longBreak, t0);
      expect(data.records.length, before);
      expect(data.activeSession!.mode, SessionMode.longBreak);
    });
  });

  group('今日休息', () {
    test('收工：标记当日 + 结束会话，进行中的专注不算白学', () {
      final t0 = DateTime(2026, 11, 7, 21);
      var data = TimerEngine.start(_base(), SessionMode.focus, t0);
      data = TimerEngine.advance(data, t0.add(const Duration(minutes: 25)));
      data = TimerEngine.restForToday(data, t0.add(const Duration(minutes: 25)));

      expect(data.restDate, ymdOf(dayStart(t0)));
      expect(data.isRestDay(t0), isTrue);
      expect(data.activeSession, isNull);
      expect(data.records.first.minutes, closeTo(25, 0.05));
    });

    test('「继续今日」清掉标记；换一天自然不再命中', () {
      final t0 = DateTime(2026, 11, 7, 21);
      var data = TimerEngine.restForToday(_base(), t0);
      expect(data.isRestDay(t0), isTrue);
      // 第二天：标记还在，但不再算「今天休息」
      expect(data.isRestDay(t0.add(const Duration(days: 1))), isFalse);
      data = TimerEngine.resumeToday(data);
      expect(data.restDate, isNull);
      expect(data.isRestDay(t0), isFalse);
    });

    test('restDate 只存本机：不进云端净荷', () {
      final data = TimerEngine.restForToday(_base(), DateTime(2026, 11, 7, 21));
      expect(data.toCloudMap().containsKey('restDate'), isFalse);
      expect(data.toMap()['restDate'], isNotNull);
      // 序列化往返仍在
      final round =
          AppData.fromMap(jsonDecode(jsonEncode(data.toMap())) as Map);
      expect(round.restDate, data.restDate);
    });
  });

  group('首屏：阶段条 + 收工入口', () {
    Future<void> pump(WidgetTester tester, AppData data) async {
      tester.view.physicalSize = const Size(1120, 1520); // 560×760
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.pine-pomodoro': jsonEncode(data.toMap()),
      });
      await tester.pumpWidget(const PomodoroApp());
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    testWidgets('三段阶段条（专注/短休/吃饭）都在，且带各自的分钟数', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(tester, _base());
        expect(find.text('专注'), findsOneWidget);
        expect(find.text('短休'), findsOneWidget);
        expect(find.text('吃饭'), findsOneWidget);
        expect(find.text('50'), findsOneWidget); // 专注时长
        expect(find.text('10'), findsOneWidget); // 短休时长
        expect(find.text('40'), findsOneWidget); // 吃饭时长
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('点「吃饭」→ 环内切成吃饭', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(tester, _base());
        await tester.tap(find.text('吃饭'));
        await tester.pumpAndSettle();
        expect(find.text('吃饭，慢慢来'), findsOneWidget);
        // 时钟按真实时间倒数，精确值会飘（39:59…），只验"起了 40 分钟的一轮"。
        expect(find.textContaining(RegExp(r'^(40:00|39:\d\d)$')), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('短休中点「专注」一步回到主计时（不必先按 ✓ 结束休息）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(tester, _base());
        await tester.tap(find.text('短休'));
        await tester.pumpAndSettle();
        expect(find.text('起身活动一下'), findsOneWidget);

        await tester.tap(find.text('专注'));
        await tester.pumpAndSettle();
        expect(find.text('起身活动一下'), findsNothing);
        expect(find.text('专注中'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('点当前阶段不会把剩余时间重置成满格（幂等）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(tester, _base());
        await tester.tap(find.text('短休'));
        await tester.pumpAndSettle();
        // 让 10 分钟真的走掉 90 秒
        await tester.pump(const Duration(seconds: 90));
        final before = tester.widget<Text>(find.textContaining('09:')).data;
        expect(before, isNotNull);

        await tester.tap(find.text('短休'), warnIfMissed: false);
        await tester.pump(const Duration(seconds: 1));
        // 仍是从 09:xx 继续倒数，不是回到 10:00
        expect(find.textContaining('10:00'), findsNothing);
        expect(find.textContaining('09:'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('收工入口 → 仪式浮层 →「再学一会儿」退出且今天不算收工', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(tester, _base());
        expect(find.text('收工'), findsOneWidget);

        await tester.tap(find.text('收工'));
        await tester.pumpAndSettle();
        expect(find.text('今天收工了'), findsOneWidget);
        // 仪式里报今日总账
        expect(find.text('今日专注'), findsOneWidget);
        expect(find.text('连续'), findsOneWidget);

        await tester.tap(find.text('再学一会儿'));
        await tester.pumpAndSettle();
        expect(find.text('今天收工了'), findsNothing);
        expect(find.text('准备开始'), findsOneWidget);
        expect(find.text('继续今日'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('仪式里按「收工」→ 盖章 → 1.2 秒收起 → 环内变「收工」+ 入口转「继续今日」',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(tester, _base());
        await tester.tap(find.text('收工'));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(BrickButton, '收工'));
        await tester.pump();
        // 第二幕：数据已落，标题换成「今日已收工」
        expect(find.text('今日已收工'), findsOneWidget);
        expect(find.text('准备开始'), findsNothing);

        // 盖章停留 1.2 秒后自动收起
        await tester.pump(const Duration(milliseconds: 1400));
        await tester.pumpAndSettle();
        expect(find.text('今日已收工'), findsNothing);
        expect(find.text('继续今日'), findsOneWidget);
        // 环内文案带总账（今天 0 分钟 → 就是「今日休息」）
        expect(find.text('今日休息'), findsOneWidget);
        expect(find.text('准备开始'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('收工态点「继续今日」→ 回到可开始', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(tester, TimerEngine.restForToday(_base(), DateTime.now()));
        expect(find.text('今日休息'), findsOneWidget);
        expect(find.text('继续今日'), findsOneWidget);

        await tester.tap(find.text('继续今日'));
        await tester.pumpAndSettle();
        expect(find.text('准备开始'), findsOneWidget);
        expect(find.text('收工'), findsOneWidget); // 胶囊回到"可点收工"
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('今日休息时直接按「开始」也回到工作（标记自动作废）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(tester,
            TimerEngine.restForToday(_base(), DateTime.now()));
        expect(find.text('今日休息'), findsOneWidget);

        await tester.tap(find.text('开始'));
        await tester.pumpAndSettle();
        expect(find.text('收工'), findsOneWidget); // 胶囊回到"可点收工"
        expect(find.text('准备开始'), findsNothing);
        expect(find.text('专注中'), findsOneWidget); // 专注已开始
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
