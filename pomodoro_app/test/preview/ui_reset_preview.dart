// 显式运行：flutter test --no-pub test/preview/ui_reset_preview.dart
// PNG 位于仓库 outputs/ui-reset-preview/，默认测试收集不包含此文件。
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_app/pages/ledger_page.dart';
import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/records_view.dart';
import 'package:pomodoro_app/src/theme.dart';
import 'package:pomodoro_app/src/widgets.dart';

final previewNow = DateTime(2026, 11, 16, 14, 30);
AppData previewData() => AppData(tasks: [
      PineTask(name: '阅读与笔记', color: kTaskPalette[0].toARGB32()),
      PineTask(name: '项目研究', color: kTaskPalette[1].toARGB32()),
    ], events: [
      FocusEvent(
          id: 'ev',
          name: '理解系统的反馈',
          taskName: '阅读与笔记',
          startedAt: DateTime(2026, 11, 14))
    ], records: [
      FocusRecord(
          id: 'r1',
          taskName: '阅读与笔记',
          minutes: 65,
          dayKey: '2026-11-16',
          status: RecordStatus.completed,
          at: DateTime(2026, 11, 16, 13, 42, 18),
          eventId: 'ev'),
      FocusRecord(
          id: 'r2',
          taskName: '项目研究',
          minutes: 40,
          dayKey: '2026-11-15',
          status: RecordStatus.completed,
          at: DateTime(2026, 11, 16, 3, 12, 9)),
      FocusRecord(
          id: 'r3',
          taskName: '',
          minutes: 25,
          dayKey: '2026-11-15',
          status: RecordStatus.manual,
          at: DateTime(2026, 11, 15, 20, 26, 53)),
    ], todos: {
      '2026-11-13': [TodoItem(id: 'p1', text: '整理读书笔记', done: true)],
      '2026-11-15': [TodoItem(id: 'p2', text: '梳理反馈路径', done: true)],
      '2026-11-16': [
        TodoItem(id: 'p3', text: '阅读系统思考的第三章', done: true),
        TodoItem(id: 'p4', text: '完成研究提纲，整理今天的疑问'),
        TodoItem(id: 'p5', text: '复核模型边界与关键假设')
      ],
      '2026-11-18': [TodoItem(id: 'p6', text: '研究进展复盘')],
    });
const previewSession = SessionView(
    mode: SessionMode.focus,
    running: true,
    targetReached: false,
    plannedSeconds: 3000,
    remainingSeconds: 1740,
    overtimeSeconds: 0,
    elapsedSeconds: 1260);

Future<void> fonts() async {
  final bytes = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf')
      .readAsBytesSync();
  for (final family in [
    'Ahem',
    'Roboto',
    'FlutterTest',
    'sans-serif',
    'PinePreview',
    'SF Mono',
    'Menlo',
    'monospace'
  ]) {
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  }
  final icons = File(
      '../tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
      .load();
}

Future<void> capture(
    WidgetTester tester, String name, Size size, Widget body) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  final key = GlobalKey();
  final base = buildPineTheme(brightness: Brightness.dark);
  final theme = base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'PinePreview'),
    filledButtonTheme: FilledButtonThemeData(
        style: base.filledButtonTheme.style!.copyWith(
            textStyle: WidgetStatePropertyAll(base
                .filledButtonTheme.style!.textStyle!
                .resolve({})!.copyWith(fontFamily: 'PinePreview')))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: base.outlinedButtonTheme.style!.copyWith(
            textStyle: WidgetStatePropertyAll(base
                .outlinedButtonTheme.style!.textStyle!
                .resolve({})!.copyWith(fontFamily: 'PinePreview')))),
  );
  await tester.pumpWidget(
      MaterialApp(theme: theme, home: RepaintBoundary(key: key, child: body)));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../outputs/ui-reset-preview/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
  await tester.pumpWidget(const SizedBox.shrink());
}

class ComponentOverview extends StatelessWidget {
  const ComponentOverview({super.key});
  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    Widget section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: PineSpacing.far),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title,
              style: PineText.sans(
                  size: PineType.auxiliary, color: palette.textAuxiliary)),
          const SizedBox(height: PineSpacing.near),
          child
        ]));
    return Scaffold(
        body: Padding(
            padding: const EdgeInsets.all(PineSpacing.far),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('当下与台账',
                      style: PineText.aggregate(color: palette.textPrimary)),
                  const SizedBox(height: PineSpacing.near),
                  Text('共享组件 · 暗色模式',
                      style: PineText.sans(color: palette.textSecondary)),
                  const SizedBox(height: PineSpacing.far),
                  section(
                      '01  时态与分段',
                      Column(children: [
                        TenseSwitcher(
                            current: PineTense.ledger, onChanged: (_) {}),
                        LedgerSegmentSelector(
                            current: PineLedgerSegment.records,
                            onChanged: (_) {}),
                      ])),
                  section(
                      '02  进行中 · 开放边界',
                      SessionPresenceBar(
                          view: previewSession,
                          belongingDateText: '2026-11-16',
                          onComplete: () {},
                          onReturnToPresent: () {})),
                  section(
                      '03  记录事实 · 双时间字段',
                      RecordFactTile(
                          data: previewData(),
                          record: previewData().records[1])),
                  section(
                      '04  归属回执',
                      const CompletionAttributionReceipt(
                          belongingDateText: '2026-11-15',
                          crossDayTodayUnchanged: true)),
                  section(
                      '05  应用外陪驻',
                      ExternalSessionPresenceCard(
                          view: previewSession,
                          belongingDateText: '2026-11-16',
                          onComplete: () {},
                          onPauseOrResume: () {})),
                  section(
                      '06  聚合、目标日与设置',
                      SettledVariantSurface(
                          child: Row(children: [
                        const Expanded(
                            child: AggregateReadout(
                                value: '105 分钟', label: '今日专注')),
                        const Expanded(
                            child: AggregateReadout(
                                value: '2 个', label: '今日已落番茄')),
                        SettingsSwitch(value: true, onChanged: (_) {}),
                      ]))),
                  section(
                      '07  逻辑日、目标日与聚合进度',
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const LogicalDayDivider(
                                dateLabel: '所属日期 2026-11-16',
                                auxiliaryLabel: '3 条'),
                            const SizedBox(height: PineSpacing.section),
                            TargetDayReadout(
                                countdown: const Countdown(), now: previewNow),
                            const SizedBox(height: PineSpacing.section),
                            const AggregateProgress(value: .65),
                            const SizedBox(height: PineSpacing.section),
                            PineButton(label: '保存', onPressed: () {}),
                          ])),
                  section(
                      '08  安全副本与独立裁决边界',
                      ConflictAdjudicationPanel(
                          status: AdjudicationStatus.readyToAdjudicate,
                          onKeepLocal: () {},
                          onKeepCloud: () {},
                          onRetrySafetyCopy: () {},
                          localSummary: '本机最近修改 14:20',
                          cloudSummary: '云端最近修改 13:55')),
                ])));
  }
}

void main() {
  testWidgets('生成组件总览与 V2/V5 暗色预览', (tester) async {
    try {
      await fonts();
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await capture(tester, 'components-dark', const Size(800, 1900),
          const ComponentOverview());
      for (final segment in [
        PineLedgerSegment.records,
        PineLedgerSegment.schedule
      ]) {
        final code =
            segment == PineLedgerSegment.records ? 'v2-records' : 'v5-schedule';
        for (final size in [const Size(500, 640), const Size(960, 720)]) {
          await capture(
              tester,
              '$code-${size.width.toInt()}-dark',
              size,
              LedgerPage(
                  data: TimerEngine.start(previewData(), SessionMode.focus,
                      previewNow.subtract(const Duration(minutes: 21))),
                  onChanged: (_) {},
                  onReturnToPresent: () {},
                  initialSegment: segment,
                  now: previewNow));
        }
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        await capture(
            tester,
            '$code-360-dark',
            const Size(360, 800),
            LedgerPage(
                data: TimerEngine.start(previewData(), SessionMode.focus,
                    previewNow.subtract(const Duration(minutes: 21))),
                onChanged: (_) {},
                onReturnToPresent: () {},
                initialSegment: segment,
                now: previewNow));
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.reset();
    }
  });
}
