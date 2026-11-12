// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_app/src/theme.dart';
import 'package:pomodoro_app/src/ui/ui.dart';

/// P1 组件库的最小回归：结构能渲染、交互回调能通、令牌约束不被绕过。
Widget _harness({
  required bool toggleValue,
  required ValueChanged<bool> onToggle,
  required int tab,
  required ValueChanged<int> onTab,
}) {
  return MaterialApp(
    theme: buildPineTheme(),
    home: Scaffold(
      backgroundColor: PineColors.paper,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FolioBar(
              dateText: '11月12日 · 周四',
              examText: '距考研 32 日',
              syncText: '已同步',
            ),
            const InscriptionRow(
              totalText: '全部历史累计 128 小时 40 分',
              rightText: '第 47 日 · 连续 12 日',
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SuzhiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionSeal(text: '主题累计 · 八番'),
                    const SizedBox(height: 8),
                    const PaperClockDigits(
                      timeText: '28:14',
                      caption: '专注中',
                      totalText: '/ 50:00',
                      note: '到点不停 · 继续累计',
                    ),
                    const SizedBox(height: 8),
                    const RuledScale(progress: 0.56, meta: '尺规进度 · 已历 28 分'),
                    const SizedBox(height: 8),
                    PaperChecklist(
                      title: '今日课业批注',
                      trailing: '八日排程 ›',
                      items: const [
                        PaperCheckItem(text: '高数 · 中值定理', done: true),
                        PaperCheckItem(text: '现控 ch5', current: true),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: LedgerBar(
                kicker: '今日专注 · 目标 240 分',
                value: '3 小时 20 分',
                percent: '83%',
                detail: '已落 4 枚',
                progress: 0.83,
                footLeft: '凌晨三时结算',
                footRight: '今日落账详单 ›',
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: PaperComposer(
                hintText: '✎ 添写今日课业，或手动补记一笔…',
                sealText: '今日收工',
                onSeal: () {},
                phases: const PaperButton(label: '专注 50', selected: true),
                actions: const CinnabarButton(label: '暂停'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: PaperToggle(
                value: toggleValue,
                onChanged: onToggle,
                label: '自动同步',
              ),
            ),
            InkStackChart(
              days: [
                for (var i = 0; i < 7; i++)
                  InkStackDay(
                    label: '0${i + 5}',
                    minutes: [60.0 + i * 5, 30, 20, 10],
                    today: i == 6,
                  ),
              ],
            ),
            const ExLibrisCard(child: Text('128 小时 40 分')),
            const SealCalendar(
              daysInMonth: 30,
              firstWeekday: 3,
              dayMinutes: {1: 50, 12: 120},
              today: 12,
            ),
            PaperTabs(
              index: tab,
              labels: const ['专注书房', '专注报告', '偏好设置'],
              onChanged: onTab,
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('P1 组件全部能渲染，令牌色与铜尺刻度生效', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_harness(
      toggleValue: true,
      onToggle: (_) {},
      tab: 0,
      onTab: (_) {},
    ));
    expect(find.byType(FolioBar), findsOneWidget);
    expect(find.byType(InscriptionRow), findsOneWidget);
    expect(find.byType(SuzhiCard), findsWidgets);
    expect(find.byType(SectionSeal), findsWidgets);
    expect(find.byType(PaperClockDigits), findsOneWidget);
    expect(find.byType(RuledScale), findsOneWidget);
    expect(find.byType(PaperChecklist), findsOneWidget);
    expect(find.byType(LedgerBar), findsOneWidget);
    expect(find.byType(PaperComposer), findsOneWidget);
    expect(find.byType(InkStackChart), findsOneWidget);
    expect(find.byType(ExLibrisCard), findsOneWidget);
    expect(find.byType(SealCalendar), findsOneWidget);
    expect(find.byType(PaperTabs), findsOneWidget);
    expect(find.text('28:14'), findsOneWidget);
    expect(find.text('专注中'), findsOneWidget);
    // 堆叠柱必须有实际宽度：Column 默认不拉伸时宽度会塌成 0，
    // 视觉上只剩今日柱描边的一条细线（2026-11-12 预览发现的回归）。
    final firstBar = tester.getSize(find.byKey(const ValueKey('ink-bar-05')));
    expect(firstBar.width, greaterThan(20));
    expect(firstBar.height, greaterThan(20));
    // 色段本身也要有宽度：内层 Column 不拉伸时 ColoredBox 宽为 0，
    // 柱子会只剩一个空心描边框。
    final segment = tester.getSize(find.descendant(
      of: find.byType(InkStackChart),
      matching: find.byType(ColoredBox),
    ).first);
    expect(segment.width, greaterThan(20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('390 宽手机视口下组件不横向溢出', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_harness(
      toggleValue: false,
      onToggle: (_) {},
      tab: 0,
      onTab: (_) {},
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('书签栏与素纸拨子把点击交给调用方，不自己持有状态', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 3000);
    addTearDown(tester.view.reset);
    var tab = 0;
    var toggle = false;
    await tester.pumpWidget(_harness(
      toggleValue: toggle,
      onToggle: (v) => toggle = v,
      tab: tab,
      onTab: (i) => tab = i,
    ));
    await tester.tap(find.text('专注报告'));
    await tester.pump();
    expect(tab, 1);

    await tester.tap(find.text('自动同步'));
    await tester.pump();
    expect(toggle, isTrue);
  });
}
