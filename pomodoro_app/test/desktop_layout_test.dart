import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pomodoro_app/main.dart';
import 'package:pomodoro_app/pages/stats_page.dart';
import 'package:pomodoro_app/src/models.dart';

/// 桌面「专注舱」的布局回归。
///
/// 2026-10-25 评审 P0-1：500×640 时内容超出视口，信息卡底缘被硬切。
/// 舱是 `SingleChildScrollView`——**内容超长不会抛 overflow 异常，只会被裁掉**，
/// 所以判据必须是「可滚动距离 = 0」，只看异常会假通过。
///
/// 同日改版：主窗去掉「最近完成」（搬进统计抽屉），换成 3 行可勾的今日日程。
AppData _data({int records = 3, int todos = 5}) {
  final now = DateTime.now();
  final today = ymdOf(dayStart(now));
  return AppData(
    records: [
      for (var i = 0; i < records; i++)
        FocusRecord(
          taskName: ['自控', '英语', '数学'][i % 3],
          minutes: 50.0 + i,
          dayKey: today,
          status: RecordStatus.completed,
          at: now.subtract(Duration(minutes: 30 * (i + 1))),
        ),
    ],
    todos: {
      today: [
        for (var i = 0; i < todos; i++) TodoItem(text: '日程条目 ${i + 1}'),
      ],
    },
    settings: const TimerSettings(focus: 60, short: 10, long: 20),
  );
}

Future<void> _pumpDesktop(
  WidgetTester tester, {
  required double width,
  required double height,
  AppData? data,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = Size(width * 2, height * 2);

  SharedPreferences.setMockInitialValues(<String, Object>{
    'flutter.pine-pomodoro': jsonEncode((data ?? _data()).toMap()),
  });
  await tester.pumpWidget(const PomodoroApp());
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void _restore(WidgetTester tester) {
  debugDefaultTargetPlatformOverride = null;
  tester.view.reset();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in const <Size>[
    Size(440, 600), // 最小窗
    Size(500, 640), // 旧默认窗（3 条档）
    Size(560, 760), // 默认窗（4 条档）
    Size(600, 820), // 拉大（5 条档）
  ]) {
    testWidgets('桌面舱 ${size.width.toInt()}×${size.height.toInt()} 不需要滚动',
        (tester) async {
      try {
        await _pumpDesktop(tester, width: size.width, height: size.height);
        expect(find.text('今日日程'), findsOneWidget);
        // 「最近完成」已搬进统计抽屉，主窗不该再出现。
        expect(find.text('最近完成'), findsNothing);
        expect(tester.takeException(), isNull);

        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          ),
        );
        expect(scrollable.position.maxScrollExtent, lessThanOrEqualTo(0.5),
            reason: '${size.width.toInt()}×${size.height.toInt()} 需要滚动才能看全，'
                '说明信息卡又被裁了（评审 P0-1 回归）');
      } finally {
        _restore(tester);
      }
    });
  }

  testWidgets('旧默认窗 500×640 日程显示 3 条，其余折叠成「还有 N 条」', (tester) async {
    try {
      await _pumpDesktop(tester, width: 500, height: 640);
      expect(find.text('日程条目 1'), findsOneWidget);
      expect(find.text('日程条目 3'), findsOneWidget);
      expect(find.text('日程条目 4'), findsNothing);
      expect(find.text('还有 2 条 ›'), findsOneWidget);
    } finally {
      _restore(tester);
    }
  });

  testWidgets('默认窗 560×760 日程显示 4 条，第 5 条折叠', (tester) async {
    try {
      await _pumpDesktop(tester, width: 560, height: 760, data: _data(todos: 6));
      expect(find.text('日程条目 4'), findsOneWidget);
      expect(find.text('日程条目 5'), findsNothing);
      expect(find.text('还有 2 条 ›'), findsOneWidget);
    } finally {
      _restore(tester);
    }
  });

  testWidgets('最小窗日程只显示 2 条', (tester) async {
    try {
      await _pumpDesktop(tester, width: 440, height: 600);
      expect(find.text('日程条目 2'), findsOneWidget);
      expect(find.text('日程条目 3'), findsNothing);
      expect(find.text('还有 3 条 ›'), findsOneWidget);
    } finally {
      _restore(tester);
    }
  });

  testWidgets('统计抽屉里能看到最近完成（主窗搬过来的）', (tester) async {
    // 统计页是长列表，新卡在最后；把视口拉高，免得它还没被构建就断言。
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(1000, 6000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: StatsPage(data: _data(records: 2), onChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    expect(find.text('最近完成'), findsOneWidget);
    expect(find.text('自控'), findsWidgets);

    // 补记入口跟着「最近完成」一起搬进抽屉（2026-10-28 反馈：桌面端一度没有补记）。
    expect(find.text('＋ 补记'), findsOneWidget);
    await tester.tap(find.text('＋ 补记'));
    await tester.pumpAndSettle();
    expect(find.text('补记已完成事件'), findsOneWidget);
  });
}
