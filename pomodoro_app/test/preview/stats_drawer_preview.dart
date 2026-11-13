// 离屏渲染「专注报告（macOS 右侧抽屉宽度 520×760）」→ outputs/stats-drawer-preview.png
//
// 用途：桌面宽窗（≥720）里报告页是右侧抽屉，宽度只有 ~520，
// 手机版 StatsPage 塞进去会不会挤 / 顶部会不会被吃掉两层标题，靠这张图看。
// 注意：字体注册沿用 mobile_focus_preview 的做法；跑完进程可能不退出，看到 "written" 即可 kill。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/pages/stats_page.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/theme.dart';

void main() {
  testWidgets('渲染桌面报告抽屉', (tester) async {
    final file = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      for (final family in <String>[
        'Roboto',
        'FlutterTest',
        'Ahem',
        'PineTest',
        'monospace',
        'Songti SC',
        'STSong',
        'Source Han Serif SC',
        'Noto Serif SC',
        'PingFang SC',
        'Hiragino Sans GB',
        'serif',
        'SF Mono',
      ]) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
        await loader.load();
      }
    }
    final icons = File(
        '/Users/shuyichen/Documents/Codex/2026-08-13/pinecone/tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(
            ByteData.view(Uint8List.fromList(icons.readAsBytesSync()).buffer)));
      await loader.load();
    }

    // 桌面（macOS）分支：报告页在抽屉里，宽度按 520 估算
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(712, 1520);

    final now = DateTime.now();
    String dayAgo(int n) =>
        ymdOf(dayStart(now.subtract(Duration(days: n))));

    // 近 7 天都有记录，四门课分色，今日最多（让七日堆叠柱有内容）
    final records = <FocusRecord>[
      for (final (n, plan) in <(int, List<(String, int)>)>[
        (6, [('高数 · 第六章', 55), ('408 真题', 40), ('英语真题', 25)]),
        (5, [('高数 · 第六章', 30), ('408 真题', 15), ('政治', 15)]),
        (4, [('高数 · 第六章', 90), ('408 真题', 70), ('英语真题', 40), ('政治', 20)]),
        (3, [('高数 · 第六章', 60), ('408 真题', 45), ('英语真题', 30), ('政治', 15)]),
        (2, [('高数 · 第六章', 100), ('408 真题', 80), ('英语真题', 45), ('政治', 25)]),
        (1, [('高数 · 第六章', 35), ('408 真题', 20), ('英语真题', 15), ('政治', 10)]),
        (0, [('高数 · 第六章', 80), ('408 真题', 55), ('英语真题', 42), ('政治', 23)]),
      ])
        for (final (task, minutes) in plan)
          FocusRecord(
            taskName: task,
            minutes: minutes.toDouble(),
            dayKey: dayAgo(n),
            status: RecordStatus.completed,
            at: now.subtract(Duration(days: n, hours: minutes % 5)),
          ),
    ];

    final data = AppData(
      tasks: [
        PineTask(name: '高数 · 第六章', color: kTaskPalette[0].toARGB32()),
        PineTask(name: '408 真题', color: kTaskPalette[3].toARGB32()),
        PineTask(name: '英语真题', color: kTaskPalette[1].toARGB32()),
        PineTask(name: '政治', color: kTaskPalette[2].toARGB32()),
      ],
      records: records,
      settings: const TimerSettings(focus: 50, short: 10, meal: 70),
      goalMinutes: 240,
      weekGoal: 20,
    );

    final shot = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: shot,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildPineTheme(),
        home: StatsPage(data: data, onChanged: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();

    final boundary =
        shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${Directory.current.path}/../outputs/stats-drawer-preview.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    debugPrint('written');
    debugDefaultTargetPlatformOverride = null;
  });
}
