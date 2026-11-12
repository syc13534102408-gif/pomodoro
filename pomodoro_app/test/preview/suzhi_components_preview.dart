// ignore_for_file: avoid_print, prefer_const_constructors, prefer_const_literals_to_create_immutables
// 设计走查工具（**不是测试**）：把 P1 素纸组件库离屏渲染成 PNG。
//
// 文件名不以 `_test.dart` 结尾，`flutter test` 默认收集不会带上它。
// 用法：flutter test test/preview/suzhi_components_preview.dart
// 产物：../outputs/suzhi-components-preview.png
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_app/src/theme.dart';
import 'package:pomodoro_app/src/ui/ui.dart';

Future<void> _loadFonts() async {
  final bytes = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf')
      .readAsBytesSync();
  // `PineText.serif` 显式指定 'Songti SC'，测试环境没有该字体；把系统中文
  // 字体注册到这些家族名下，预览里的中文才不会渲染成方块。
  for (final family in [
    'PineTest',
    'Songti SC',
    'serif',
    'monospace',
    'SF Mono',
  ]) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

Widget _board() {
  final baseTheme = buildPineTheme();
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    // `PineText.sans` 不指定字体族，测试环境默认 Ahem 没有中文字形 → 方块。
    // 把正文字体族也指向已加载的系统中文（仅影响离屏预览）。
    theme: baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(fontFamily: 'PineTest'),
    ),
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
            InscriptionRow(
              totalText: '全部历史累计 128 小时 40 分',
              rightText: '第 47 日 · 连续 12 日',
            ),
            Padding(
              padding: EdgeInsets.all(14),
              child: SuzhiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('高数 · 第六章 中值定理 ›',
                            style: PineText.serif(size: PineType.label)),
                        SectionSeal(text: '主题累计 · 八番'),
                      ],
                    ),
                    SizedBox(height: 10),
                    PaperClockDigits(
                      timeText: '28:14',
                      caption: '今日第五个番茄',
                      totalText: '/ 50:00',
                      note: '到点不停 · 继续累计',
                    ),
                    SizedBox(height: 12),
                    RuledScale(progress: 0.56, meta: '尺规进度 · 已历 28 分 (56%)'),
                    SizedBox(height: 12),
                    PaperChecklist(
                      title: '今日课业批注（点按即勾画或聚焦）',
                      trailing: '八日排程 ›',
                      items: [
                        PaperCheckItem(text: '2018 数一复盘 · 18(2) 证明重做', done: true),
                        PaperCheckItem(text: '现控 ch5 下半 · 状态空间判据', current: true),
                        PaperCheckItem(text: '英语真题 2019 阅读两篇精读'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: LedgerBar(
                kicker: '今日专注 · 目标 240 分',
                value: '3 小时 20 分',
                percent: '83%',
                detail: '已落 4 枚番茄 · 尚差 40 分',
                progress: 0.83,
                footLeft: '凌晨三时结算',
                footRight: '今日落账详单 ›',
              ),
            ),
            Padding(
              padding: EdgeInsets.all(14),
              child: PaperComposer(
                hintText: '✎ 添写今日课业，或手动补记一笔…',
                sealText: '今日收工',
                onSeal: () {},
                phases: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PaperButton(label: '专注 50', selected: true, onPressed: () {}),
                    SizedBox(width: 6),
                    PaperButton(label: '短休 10', onPressed: () {}),
                    SizedBox(width: 6),
                    PaperButton(label: '吃饭 70', onPressed: () {}),
                  ],
                ),
                actions: CinnabarButton(label: '暂停', onPressed: () {}),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(14),
              child: SuzhiCard(
                showRule: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('近七日水墨时长谱', style: PineText.serif(size: PineType.label)),
                    SizedBox(height: 12),
                    InkStackChart(
                      days: [
                        for (var i = 0; i < 7; i++)
                          InkStackDay(
                            label: '0${i + 5}',
                            minutes: [60.0 + i * 12, 45, 20, 10],
                            valueLabel: i == 6 ? '3h15' : null,
                            today: i == 6,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(14),
              child: ExLibrisCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('自 2026.9.26 起算', style: PineText.sans(size: PineType.caption)),
                    SizedBox(height: 6),
                    Text('128 小时 40 分', style: PineText.serif(size: PineType.num)),
                    SizedBox(height: 4),
                    Text('共 154 枚番茄 / 日均 2 小时 44 分',
                        style: PineText.sans(size: PineType.meta, color: PineColors.ink2)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(14),
              child: SuzhiCard(
                showRule: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('2026 年 11 月 · 钤印日历', style: PineText.serif(size: PineType.label)),
                    SizedBox(height: 10),
                    SealCalendar(
                      daysInMonth: 30,
                      firstWeekday: 1,
                      dayMinutes: {for (var d = 1; d <= 12; d++) d: 50.0 + d},
                      today: 12,
                    ),
                  ],
                ),
              ),
            ),
            PaperTabs(
              index: 0,
              labels: ['专注书房', '专注报告', '偏好设置'],
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('渲染 P1 素纸组件总览', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1170, 5400); // 390 × 1800 @3x
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    const key = ValueKey('shot');
    await tester.pumpWidget(RepaintBoundary(key: key, child: _board()));
    // 总览页没有动画：用有限 pump，别用 pumpAndSettle（会等满默认 10 分钟超时）。
    // 另外本预览脚本写完 PNG 后进程不退出，看到日志「渲染完成」即可 Ctrl-C / kill。
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    final out = File('../outputs/suzhi-components-preview.png');
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    print('渲染完成 → ${out.path}  ${image.width}×${image.height}');
  });
}
