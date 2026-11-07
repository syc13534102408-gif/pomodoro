import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pomodoro_app/main.dart';
import 'package:pomodoro_app/pages/stats_page.dart';
import 'package:pomodoro_app/src/models.dart';

/// 2026-11-06 反馈：「多个事件进展的切换问题」。
///
/// 复现到的真问题：`TimerEngine.resumeEvent` 只被 `showEventActionSheet` 调用，
/// 而打开那个面板的唯一入口（任务行的事件徽标）只认 `isRunning`。
/// 于是事件一旦暂停 → 操作面板再也进不去 → 「继续累计 / 完成 / 删除」全部失联，
/// 多事件并存时表现就是「切不回上一条事件」。
///
/// 顺带发现：那个入口只画在桌面舱的任务行里，手机任务卡没有任何事件入口，
/// 安卓端等于「事件只能看不能动」。本次把入口抽成 `_eventChip()` 给两个布局共用。
AppData _data({required bool paused}) {
  final now = DateTime.now();
  return AppData(
    tasks: [PineTask(name: '现控'), PineTask(name: '高数')],
    events: [
      FocusEvent(
        id: 'e-zk',
        name: '现控 ch5',
        taskName: '现控',
        startedAt: now.subtract(const Duration(hours: 2)),
        pausedAt: paused ? now.subtract(const Duration(minutes: 30)) : null,
      ),
      FocusEvent(
        id: 'e-gs',
        name: '高数 ch6',
        taskName: '高数',
        startedAt: now.subtract(const Duration(hours: 1)),
      ),
    ],
    settings: const TimerSettings(focus: 50, short: 5, long: 15),
  );
}

Future<void> _pumpApp(WidgetTester tester, AppData data) async {
  tester.view.physicalSize = const Size(1000, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{
    'flutter.pine-pomodoro': jsonEncode(data.toMap()),
  });
  await tester.pumpWidget(const PomodoroApp());
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('桌面舱：已暂停的事件仍可点开，且能「继续累计」', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _pumpApp(tester, _data(paused: true));

      // 修前：徽标消失、退回「＋事件」——那条暂停的事件就再也点不到了。
      expect(find.text('＋事件'), findsNothing);
      expect(find.textContaining('现控 ch5'), findsOneWidget);
      // 徽标必须写出「已暂停」，否则看着像还在累计。
      expect(find.textContaining('已暂停'), findsOneWidget);

      await tester.tap(find.textContaining('现控 ch5'));
      await tester.pumpAndSettle();
      expect(find.text('继续累计'), findsOneWidget);

      await tester.tap(find.text('继续累计'));
      await tester.pumpAndSettle();

      // 继续后回到进行中：徽标还在，但不再带「已暂停」。
      expect(find.textContaining('现控 ch5'), findsOneWidget);
      expect(find.textContaining('已暂停'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('手机任务卡也有事件入口（修前只在桌面舱里）', (tester) async {
    await _pumpApp(tester, _data(paused: true));

    expect(find.textContaining('现控 ch5'), findsOneWidget);
    await tester.tap(find.textContaining('现控 ch5'));
    await tester.pumpAndSettle();
    expect(find.text('继续累计'), findsOneWidget);
  });

  testWidgets('统计页「事件进展」右侧 ⋯ 能打开操作面板（暂停的事件给「继续累计」）', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 只留一条（已暂停）：卡片里 live 的顺序是「进行中在前、已暂停在后」，
    // 放两条的话 ⋯.first 落在进行中那条上，验不到「继续累计」。
    final now = DateTime.now();
    final data = AppData(
      tasks: [PineTask(name: '现控')],
      events: [
        FocusEvent(
          id: 'e-zk',
          name: '现控 ch5',
          taskName: '现控',
          startedAt: now.subtract(const Duration(hours: 2)),
          pausedAt: now.subtract(const Duration(minutes: 30)),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: StatsPage(data: data, onChanged: (_) {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('事件进展'), findsOneWidget);
    // 行本身仍进明细；动作走右侧 ⋯（修前这一行只能看，不能动）。
    final more = find.byTooltip('暂停 / 继续 / 完成 / 编辑');
    expect(more, findsOneWidget);
    await tester.tap(more);
    await tester.pumpAndSettle();

    expect(find.text('继续累计'), findsOneWidget);
    expect(find.text('完成此事件（归档保留）'), findsOneWidget);
  });

  testWidgets('操作面板里能直接「切换到其他事件」（暂停旧 + 恢复新 + 换任务）', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    AppData? applied;
    final now = DateTime.now();
    final data = AppData(
      tasks: [PineTask(name: '自控'), PineTask(name: '高数')],
      events: [
        FocusEvent(
            id: 'e1',
            name: '刷真题',
            taskName: '自控',
            startedAt: now.subtract(const Duration(hours: 3))),
        FocusEvent(
            id: 'e2',
            name: '背单词',
            taskName: '高数',
            startedAt: now.subtract(const Duration(hours: 2)),
            pausedAt: now.subtract(const Duration(hours: 1))),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: StatsPage(data: data, onChanged: (next) => applied = next),
    ));
    await tester.pumpAndSettle();

    // 事件进展里 live 顺序是「进行中在前」→ 第一个 ⋯ 就是「刷真题」。
    await tester.tap(find.byTooltip('暂停 / 继续 / 完成 / 编辑').first);
    await tester.pumpAndSettle();

    // 2026-11-07 前的面板只有 编辑/暂停/完成/新建/删除，没有切换入口。
    expect(find.textContaining('切换到其他事件'), findsOneWidget);
    await tester.tap(find.textContaining('切换到其他事件'));
    await tester.pumpAndSettle();
    expect(find.text('切换到哪个事件？'), findsOneWidget);

    await tester.tap(find.text('背单词').last);
    await tester.pumpAndSettle();

    expect(applied, isNotNull);
    expect(applied!.selectedTask.name, '高数');
    expect(applied!.events.firstWhere((e) => e.id == 'e1').isPaused, isTrue);
    expect(applied!.events.firstWhere((e) => e.id == 'e2').isRunning, isTrue);
  });
}
