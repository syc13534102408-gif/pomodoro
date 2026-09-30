// ignore_for_file: prefer_const_constructors
// 设计走查工具（**不是测试**）：把真实的统计页离屏渲染成 PNG。
//
// 文件名不以 `_test.dart` 结尾，所以 `flutter test` 的默认收集不会带上它——
// 它不assert任何东西，且一次性渲染 960×3734 的位图开销较大，混进常规套件会拖慢/拖垮整轮。
//
// 用法：
//   flutter test test/preview/stats_preview.dart
// 产物：
//   ../outputs/stats-preview.png

// 依赖 macOS 自带的中文字体；缺失时整体跳过而不是报错。
import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_app/pages/stats_page.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/sheets.dart';
import 'package:pomodoro_app/src/theme.dart';
import 'package:pomodoro_app/src/widgets.dart';

/// 测试环境默认字体渲染成方块，必须显式加载一个含中文的字体。
/// 同时把 'monospace' 也指向它——`brickNumberStyle` 显式指定了该族。
Future<void> _loadFonts() async {
  final bytes = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf')
      .readAsBytesSync();
  for (final family in ['PineTest', 'monospace']) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
  final icons = File(
      '/Users/shuyichen/Documents/Codex/2026-08-13/pinecone/tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  }
}

String _dayKey(DateTime d) => [
      d.year.toString().padLeft(4, '0'),
      d.month.toString().padLeft(2, '0'),
      d.day.toString().padLeft(2, '0'),
    ].join('-');

/// 造一份贴近真实使用的数据：4 个事件（进行中/暂停/已完成×2）+ 本周零散记录。
AppData _sample() {
  final now = DateTime.now();
  DateTime daysAgo(int n, [int hour = 10]) {
    final d = now.subtract(Duration(days: n));
    return DateTime(d.year, d.month, d.day, hour);
  }

  FocusRecord rec(String task, double minutes, int ago,
          {String? eventId, int hour = 10}) =>
      FocusRecord(
        taskName: task,
        minutes: minutes,
        dayKey: _dayKey(daysAgo(ago)),
        status: RecordStatus.completed,
        at: daysAgo(ago, hour),
        eventId: eventId,
      );

  const running = 'ev-gaoshu';
  const paused = 'ev-xiandai';
  const done1 = 'ev-jixian';
  const done2 = 'ev-yingyu';

  final records = <FocusRecord>[
    // 进行中：高数第六章（跨 3 天，累计 185 分钟）
    rec('数学真题', 50, 2, eventId: running, hour: 9),
    rec('数学真题', 50, 1, eventId: running, hour: 14),
    rec('数学真题', 35, 1, eventId: running, hour: 20),
    rec('数学真题', 50, 0, eventId: running, hour: 9),
    // 暂停：线代错题二刷（跨 2 天，75 分钟）
    rec('错题整理', 25, 4, eventId: paused, hour: 16),
    rec('错题整理', 50, 3, eventId: paused, hour: 15),
    // 已完成：极限与连续
    rec('数学真题', 50, 8, eventId: done1, hour: 9),
    rec('数学真题', 50, 7, eventId: done1, hour: 10),
    // 已完成：英语阅读精读
    rec('看网课', 35, 6, eventId: done2, hour: 21),
    // 本周零散（不属于任何事件），把其余区块填满
    rec('看网课', 45, 2, hour: 21),
    rec('看网课', 40, 1, hour: 22),
    rec('错题整理', 30, 0, hour: 15),
    rec('数学真题', 20, 0, hour: 8),
    rec('看网课', 50, 3, hour: 20),
    rec('数学真题', 50, 4, hour: 9),
    rec('错题整理', 45, 5, hour: 11),
  ];

  return AppData(
    tasks: [
      PineTask(name: '数学真题', color: kTaskPalette[0].toARGB32()),
      PineTask(name: '错题整理', color: kTaskPalette[1].toARGB32()),
      PineTask(name: '看网课', color: kTaskPalette[2].toARGB32()),
    ],
    records: records,
    events: [
      FocusEvent(
        id: running,
        name: '高数第六章 · 中值定理',
        taskName: '数学真题',
        startedAt: daysAgo(2, 9),
      ),
      FocusEvent(
        id: paused,
        name: '线代错题二刷',
        taskName: '错题整理',
        startedAt: daysAgo(4, 16),
        pausedAt: daysAgo(1, 18),
      ),
      FocusEvent(
        id: done1,
        name: '极限与连续',
        taskName: '数学真题',
        startedAt: daysAgo(8, 9),
        finishedAt: daysAgo(4, 18),
      ),
      FocusEvent(
        id: done2,
        name: '英语阅读精读',
        taskName: '看网课',
        startedAt: daysAgo(6, 21),
        finishedAt: daysAgo(2, 22),
      ),
    ],
  );
}

void main() {
  final fontFile = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
  if (!fontFile.existsSync()) {
    // 换个平台就没有这个字体，直接跳过（这里只是给人看的工具）。
    return;
  }
  setUpAll(_loadFonts);

  testWidgets('渲染统计页', (tester) async {
    tester.view.physicalSize = const Size(1440, 5600); // 480 × 1867 @3x
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final theme = buildPineTheme();
    final themed = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'PineTest'),
    );

    const key = ValueKey('shot');
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        theme: themed,
        debugShowCheckedModeBanner: false,
        home: Platform.environment['PREVIEW_MARKS'] == '1'
            ? const _MarkBoard()
            : StatsPage(data: _sample(), onChanged: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();

    // 可选：直接打开「全部记录」面板（首页「最近完成 → 全部」的落点）
    if (Platform.environment['PREVIEW_RECORDS'] == '1') {
      final data = _sample();
      final ctx = tester.element(find.byType(StatsPage));
      unawaited(showAllRecordsSheet(
        ctx,
        data: data,
        colorFor: (name) => data.tasks
            .firstWhere((task) => task.name == name,
                orElse: () => data.tasks.first)
            .swatch,
        onChanged: (_) {},
      ));
      await tester.pumpAndSettle();
    }

    // 可选：点开「查看全部」，把「已完成事件」清单也截下来
    if (Platform.environment['PREVIEW_SHEET'] == '1') {
      await tester.tap(find.text('查看全部'));
      await tester.pumpAndSettle();
    }

    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    final name = Platform.environment['PREVIEW_OUT'] ?? 'stats-preview.png';
    final out = File('../outputs/$name');
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('渲染完成 → ${out.path}  ${image.width}×${image.height}');
  });
}

/// 造型板：在真实尺寸下看松果，再放两个大尺寸看形状。
class _MarkBoard extends StatelessWidget {
  const _MarkBoard();

  @override
  Widget build(BuildContext context) => Container(
        color: PineColors.paper,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            for (final size in const [11.0, 12.0, 14.0, 17.0])
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      child: Text('$size px',
                          style: const TextStyle(
                              fontSize: 11, color: PineColors.sub)),
                    ),
                    Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: '3.7'),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 3),
                            child:
                                PineconeMark(size: size, color: PineColors.ink),
                          ),
                        ),
                      ]),
                      style: TextStyle(fontSize: size, color: PineColors.ink),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const Text('番茄（跟随文字色 / 语义红）',
                style: TextStyle(fontSize: 11, color: PineColors.sub)),
            const SizedBox(height: 10),
            for (final size in const [12.0, 17.0])
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: '3.7'),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 3),
                            child:
                                TomatoMark(size: size, color: PineColors.ink),
                          ),
                        ),
                      ]),
                      style: TextStyle(fontSize: size, color: PineColors.ink),
                    ),
                    const SizedBox(width: 28),
                    Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: '3.7'),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 3),
                            child:
                                TomatoMark(size: size, color: PineColors.focus),
                          ),
                        ),
                      ]),
                      style: TextStyle(fontSize: size, color: PineColors.ink),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            const Text('大图看造型',
                style: TextStyle(fontSize: 11, color: PineColors.sub)),
            const SizedBox(height: 12),
            Row(
              children: [
                PineconeMark(size: 120, color: PineColors.pine),
                const SizedBox(width: 20),
                TomatoMark(size: 120, color: PineColors.focus),
              ],
            ),
          ],
        ),
      );
}
