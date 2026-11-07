// ignore_for_file: prefer_const_constructors
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pomodoro_app/main.dart';
import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';

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

  group('首屏三个休息入口', () {
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

    testWidgets('「短休」「吃饭」「今日休息」都在，且带分钟数', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(tester, _base());
        expect(find.text('短休'), findsOneWidget);
        expect(find.text('吃饭'), findsOneWidget);
        expect(find.text('今日休息'), findsOneWidget);
        expect(find.text('10 分'), findsOneWidget); // 短休时长
        expect(find.text('40 分'), findsOneWidget); // 吃饭时长
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('点「吃饭」→ 环内切成吃饭；点「今日休息」→ 状态与按钮同时变', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(tester, _base());

        await tester.tap(find.text('吃饭'));
        await tester.pumpAndSettle();
        expect(find.text('吃饭，慢慢来'), findsOneWidget);
        // 时钟按真实时间倒数，精确值会飘（39:59…），只验"起了 40 分钟的一轮"。
        expect(find.textContaining('40 分'), findsOneWidget);

        // 收工：结束吃饭、标记今日休息
        await tester.tap(find.text('今日休息'));
        await tester.pumpAndSettle();
        expect(find.text('今日休息'), findsOneWidget); // 环内文案
        expect(find.text('继续今日'), findsOneWidget); // 同一格变成撤销入口
        expect(find.text('准备开始'), findsNothing);

        await tester.tap(find.text('继续今日'));
        await tester.pumpAndSettle();
        expect(find.text('准备开始'), findsOneWidget);
        expect(find.text('今日休息'), findsOneWidget); // 变回可点的收工入口
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
        expect(find.text('今日休息'), findsOneWidget); // 胶囊回到"可点收工"
        expect(find.text('准备开始'), findsNothing);
        expect(find.textContaining('个番茄'), findsOneWidget); // 专注已开始
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
