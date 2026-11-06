// 离屏渲染「桌面抽屉里的日程面板」→ outputs/plan-drawer-preview.png
//
// 不是测试：文件名不以 _test.dart 结尾，默认收集不会带上它。
// 用途：人眼确认「导入按钮没被右上角三只抽屉按钮盖住」这类遮挡问题。
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/sheets.dart';
import 'package:pomodoro_app/src/theme.dart';

void main() {
  testWidgets('渲染日程抽屉预览', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(1120, 1520); // 560×760

    final now = DateTime.now();
    String key(int offset) => ymdOf(dayStart(now.add(Duration(days: offset))));

    final data = AppData(
      todos: {
        // 往期：2026-11-06 起日期条也收录过去的日子，预览里带上两三天，
        // 好确认「今天那格左边会露出前一天小半格」这个可发现性提示。
        key(-3): [TodoItem(text: '往期：816 真题② 限时', done: true)],
        key(-1): [
          TodoItem(text: '往期：现控 ch5 上半', done: true),
          TodoItem(text: '往期：英语单词', done: true),
        ],
        key(0): [
          TodoItem(text: '现控 ch5 下半 + ch6 全 收尾', done: true),
          TodoItem(text: '产出「现控四块 ↔ 经典八题型」对应表'),
          TodoItem(text: '英语单词 25–30 分钟'),
        ],
        key(1): [TodoItem(text: '816 真题① 限时 3h')],
        key(3): [TodoItem(text: '2017 数一 限时'), TodoItem(text: '复盘')],
      },
    );

    final shotKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: PineColors.paper,
          body: RepaintBoundary(
            key: shotKey,
            child: Stack(
              children: [
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 340,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: PineColors.paper,
                      borderRadius:
                          BorderRadius.horizontal(left: Radius.circular(18)),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: SizedBox(),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 340,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: PineColors.paper,
                      borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(18)),
                      boxShadow: Paper.shadow,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                        child: PlanPanel(data: data, onApply: (_) {}),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 14,
                  child: Row(
                    children: [
                      for (final icon in <IconData>[
                        Icons.checklist_rtl_rounded,
                        Icons.bar_chart_rounded,
                        Icons.tune_rounded,
                      ])
                        Container(
                          width: 34,
                          height: 34,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: PineColors.card,
                            borderRadius:
                                BorderRadius.circular(Paper.chipRadius),
                            boxShadow: Paper.shadow,
                          ),
                          child: Icon(icon, size: 18, color: PineColors.ink),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final boundary =
        shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    // toImage 必须在 runAsync 里跑，否则会卡在测试的伪时钟上。
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 2);
      final ByteData? png =
          await image.toByteData(format: ui.ImageByteFormat.png);
      final out = File(
          '${Directory.current.path}/../outputs/plan-drawer-preview.png');
      await out.writeAsBytes(png!.buffer.asUint8List());
      // ignore: avoid_print
      print('written: ${out.path}');
    });
  });
}
