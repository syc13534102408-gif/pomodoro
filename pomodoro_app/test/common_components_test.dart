import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/theme.dart';
import 'package:pomodoro_app/src/widgets.dart';

SessionView session(
        {SessionMode mode = SessionMode.focus,
        bool running = true,
        bool overtime = false}) =>
    SessionView(
        mode: mode,
        running: running,
        targetReached: overtime,
        plannedSeconds: 1500,
        remainingSeconds: 900,
        overtimeSeconds: overtime ? 120 : 0,
        elapsedSeconds: 600);

Future<void> show(WidgetTester tester, Widget child,
    {double width = 360}) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
      theme: buildPineTheme(),
      home:
          Scaffold(body: Align(alignment: Alignment.topCenter, child: child))));
}

void main() {
  testWidgets('单浅色表面与任务标识使用令牌', (tester) async {
    await show(
      tester,
      const Column(mainAxisSize: MainAxisSize.min, children: [
        ActiveVariantSurface(child: Text('会话')),
        SettledVariantSurface(child: Text('事实')),
        TaskIdentityBadge(taskName: '阅读', color: Color(0xFFE89AA6)),
      ]),
    );
    const palette = PinePalette.light;
    final active = tester.widget<AnimatedContainer>(find.descendant(
        of: find.byType(ActiveVariantSurface),
        matching: find.byType(AnimatedContainer)));
    final settled = tester.widget<AnimatedContainer>(find.descendant(
        of: find.byType(SettledVariantSurface),
        matching: find.byType(AnimatedContainer)));
    final activeBox = active.decoration! as BoxDecoration;
    final settledBox = settled.decoration! as BoxDecoration;
    expect(activeBox.color, palette.presence);
    expect(activeBox.borderRadius, BorderRadius.circular(24));
    expect((activeBox.border! as Border).right.style, BorderStyle.none);
    expect(settledBox.color, palette.surface);
    expect(settledBox.borderRadius, BorderRadius.circular(16));
    final badge = tester.widget<Container>(find.descendant(
        of: find.byType(TaskIdentityBadge), matching: find.byType(Container)));
    expect(
        (badge.decoration! as BoxDecoration).color, palette.taskColors.first);
    expect(find.bySemanticsLabel('阅读，标识色玫瑰'), findsOneWidget);
  });

  testWidgets('手机与桌面共用组件正常态符合高度预算', (tester) async {
    try {
      for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
        debugDefaultTargetPlatformOverride = platform;
        final desktop = platform == TargetPlatform.macOS;
        await show(
            tester,
            Column(mainAxisSize: MainAxisSize.min, children: [
              SessionPresenceBar(
                  view: session(),
                  belongingDateText: '11月16日',
                  onComplete: () {},
                  onReturnToPresent: () {}),
              const CompletionAttributionReceipt(belongingDateText: '11月16日'),
              ExternalSessionPresenceCard(
                  view: session(),
                  belongingDateText: '11月16日',
                  onComplete: () {}),
            ]),
            width: desktop ? 500 : 360);
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(SessionPresenceBar)).height,
            desktop ? 64 : 72);
        expect(tester.getSize(find.byType(CompletionAttributionReceipt)).height,
            desktop ? 36 : 40);
        expect(tester.getSize(find.byType(ExternalSessionPresenceCard)).height,
            desktop ? 130 : 134);
        expect(tester.takeException(), isNull);
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('时态重选为空操作、切换即时生效、裁决阻断切换', (tester) async {
    final changes = <PineTense>[];
    await show(tester,
        TenseSwitcher(current: PineTense.present, onChanged: changes.add));
    await tester.tap(find.text('当下'));
    expect(changes, isEmpty);
    await tester.tap(find.text('台账'));
    expect(changes, [PineTense.ledger]);
    await show(
        tester,
        TenseSwitcher(
            current: PineTense.present,
            blockedByAdjudication: true,
            onChanged: changes.add));
    await tester.tap(find.text('台账'));
    expect(changes, [PineTense.ledger]);
  });

  testWidgets('五个台账分段始终按契约顺序全显，选择不等待动画', (tester) async {
    PineLedgerSegment? selected;
    await show(
        tester,
        LedgerSegmentSelector(
            current: PineLedgerSegment.records,
            onChanged: (value) => selected = value));
    double previous = -1;
    for (final segment in PineLedgerSegment.values) {
      final text = find.text(segment.label);
      expect(text, findsOneWidget);
      final rect = tester.getRect(text);
      expect(rect.left, greaterThan(previous));
      expect(rect.right, lessThanOrEqualTo(360));
      previous = rect.left;
    }
    await tester.tap(find.text('资料'));
    expect(selected, PineLedgerSegment.profile);
    expect(tester.takeException(), isNull);
  });

  testWidgets('导航支持键盘 Tab 与 Enter', (tester) async {
    PineTense? selected;
    await show(
        tester,
        TenseSwitcher(
            current: PineTense.present,
            onChanged: (value) => selected = value));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, PineTense.ledger);
  });

  for (final mode in SessionMode.values) {
    testWidgets('${mode.name} 陪驻：360 宽下正常读数与动作完整，完成即时回调', (tester) async {
      var completed = 0;
      var returned = 0;
      await show(
          tester,
          SessionPresenceBar(
              view: session(mode: mode),
              belongingDateText: '11月16日',
              onComplete: () => completed++,
              onReturnToPresent: () => returned++));
      expect(find.textContaining('本段归属11月16日'), findsOneWidget);
      expect(tester.getSize(find.byType(SessionPresenceBar)).height, 72);
      expect(
          tester.getRect(find.text('剩余 15:00')).right, lessThanOrEqualTo(360));
      await tester.tap(find.text('完成'));
      expect(completed, 1);
      await tester.tap(find.byTooltip('回到当下'));
      expect(returned, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('暂停超时、跨日、收工与镜像复合态仍可完成', (tester) async {
    var completed = 0;
    await show(
        tester,
        SessionPresenceBar(
            view: session(running: false, overtime: true),
            belongingDateText: '11月15日',
            crossDay: true,
            restingStillRunning: true,
            receivingMirror: true,
            onComplete: () => completed++,
            onReturnToPresent: () {}));
    expect(find.text('已进行 10:00'), findsOneWidget);
    expect(find.textContaining('已暂停'), findsOneWidget);
    expect(find.text('超时 +02:00'), findsOneWidget);
    expect(find.textContaining('今天已翻页，本段仍归11月15日'), findsOneWidget);
    expect(find.textContaining('今日已收工，专注仍在继续'), findsOneWidget);
    expect(find.textContaining('正在接收另一端的会话状态'), findsOneWidget);
    await tester.tap(find.text('完成'));
    expect(completed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('外部暂停超时镜像不禁用直接完成', (tester) async {
    var completed = 0;
    var resumed = 0;
    await show(
        tester,
        ExternalSessionPresenceCard(
            view: session(running: false, overtime: true),
            belongingDateText: '11月15日',
            crossDay: true,
            receivingMirror: true,
            onComplete: () => completed++,
            onPauseOrResume: () => resumed++));
    await tester.tap(find.text('完成专注'));
    expect(completed, 1);
    await tester.tap(find.text('继续'));
    expect(resumed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('安全副本创建中和失败均禁止裁决，失败可重试，成功即时裁决', (tester) async {
    var local = 0;
    var cloud = 0;
    var retries = 0;
    for (final status in AdjudicationStatus.values) {
      await show(
          tester,
          ConflictAdjudicationPanel(
              status: status,
              onKeepLocal: () => local++,
              onKeepCloud: () => cloud++,
              onRetrySafetyCopy: () => retries++));
      final enabled = status == AdjudicationStatus.readyToAdjudicate;
      final localButton = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, '保留本机数据'));
      final cloudButton = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, '保留云端数据'));
      expect(localButton.onPressed != null, enabled);
      expect(cloudButton.onPressed != null, enabled);
      if (enabled) {
        expect(tester.getTopLeft(find.text('本机安全副本已创建')).dy,
            lessThan(tester.getTopLeft(find.text('保留本机数据')).dy));
        await tester.tap(find.text('保留本机数据'));
        await tester.tap(find.text('保留云端数据'));
        expect(local, 1);
        expect(cloud, 1);
      }
      if (status == AdjudicationStatus.safetyCopyFailed) {
        await tester.tap(find.text('重试'));
        expect(retries, 1);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('时长保持自然语言，目标日只读且未设置有明确空态', (tester) async {
    await show(
        tester,
        Column(children: [
          const DurationText(185),
          TargetDayReadout(
              countdown: const Countdown(enabled: false),
              now: DateTime(2026, 11, 16))
        ]));
    expect(find.text('3 小时 5 分钟'), findsOneWidget);
    expect(find.textContaining('番茄'), findsNothing);
    expect(find.text('未设置目标日'), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('加载/禁用按钮不触发，恢复后即时触发，操作目标至少48', (tester) async {
    var count = 0;
    await show(tester,
        PineButton(label: '保存', loading: true, onPressed: () => count++));
    expect(tester.getSize(find.byType(PineButton)).height,
        greaterThanOrEqualTo(48));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(find.text('保存'), findsOneWidget);
    await show(tester, PineButton(label: '保存', onPressed: () => count++));
    await tester.tap(find.text('保存'));
    expect(count, 1);
  });

  testWidgets('美术勾选框保留键盘与禁用门控，操作后立即更新且命中区不缩小', (tester) async {
    var checked = false;
    var calls = 0;
    await show(
        tester,
        StatefulBuilder(
            builder: (context, setState) => PineCheckbox(
                value: checked,
                onChanged: (value) => setState(() {
                      checked = value!;
                      calls++;
                    }))));
    final initialSize = tester.getSize(find.byType(Checkbox));
    expect(initialSize.width, greaterThanOrEqualTo(48));
    expect(initialSize.height, greaterThanOrEqualTo(48));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(checked, isTrue);
    expect(calls, 1);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(tester.getSize(find.byType(Checkbox)), initialSize);
    await show(tester, PineCheckbox(value: checked, onChanged: null));
    await tester.tap(find.byType(Checkbox));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
