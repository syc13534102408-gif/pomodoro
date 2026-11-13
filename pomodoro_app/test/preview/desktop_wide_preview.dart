// 离屏渲染「桌面三栏书斋」→ outputs/desktop-wide-preview.png
//
// 不是测试（文件名不以 _test.dart 结尾，默认收集不会带上它）。
// 视口取定稿的 1120×680；<720 走单列专注舱的截图见 home_preview.dart。
// 预览脚本写完 PNG 后进程常驻不退出，看到日志「written」即可 Ctrl-C / kill。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pomodoro_app/main.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/theme.dart';

Future<void> _loadFonts() async {
  // 单 face TTF：TTC 集合注册不稳定，中文会渲染成方块。
  final file = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  // V3 令牌把标题/计时指向 'Songti SC'、时间戳指向 'SF Mono'；
  // 测试环境没有这些字体，统一注册到系统中文，避免预览里中文变方块。
  for (final family in <String>[
    'Roboto',
    'FlutterTest',
    'Ahem', // flutter_test 的默认族：不覆盖它，无 fontFamily 的正文全是方块
    'PineTest',
    'monospace',
    'Songti SC',
    'STSong',
    'serif',
    'SF Mono',
  ]) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
  }
  final icons = File('/Users/shuyichen/Documents/Codex/2026-08-13/pinecone/tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(
          ByteData.view(Uint8List.fromList(icons.readAsBytesSync()).buffer)));
    await loader.load();
  }
}

void main() {
  testWidgets('渲染桌面三栏书斋预览（1120×680）', (tester) async {
    await _loadFonts();
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(2240, 1360); // 1120×680 @2x

    final now = DateTime.now();
    final today = ymdOf(dayStart(now));
    final seed = AppData(
      tasks: [
        PineTask(name: '高数 · 第六章', color: kTaskPalette[0].toARGB32()),
        PineTask(name: '408 真题', color: kTaskPalette[3].toARGB32()),
        PineTask(name: '英语阅读', color: kTaskPalette[1].toARGB32()),
      ],
      records: [
        FocusRecord(
          id: 'live',
          taskName: '高数 · 第六章',
          minutes: 0,
          dayKey: today,
          status: RecordStatus.inProgress,
          at: now.subtract(const Duration(minutes: 28)),
        ),
        for (var d = 1; d <= 7; d++)
          FocusRecord(
            taskName: ['高数 · 第六章', '408 真题', '英语阅读'][d % 3],
            minutes: 50.0 + d * 12,
            dayKey: ymdOf(dayStart(now.subtract(Duration(days: d)))),
            status: RecordStatus.completed,
            at: now.subtract(Duration(days: d, hours: 1)),
          ),
      ],
      todos: {
        today: [
          TodoItem(text: '2018 数一复盘 · 18(2) 重做', done: true),
          TodoItem(text: '现控 ch5 下半 · 状态空间'),
          TodoItem(text: '英语真题 2019 阅读 2 篇'),
        ],
      },
      settings: const TimerSettings(focus: 50, short: 10, meal: 70),
      goalMinutes: 240,
      activeSession: ActiveSession(
        recordId: 'live',
        mode: SessionMode.focus,
        running: true,
        deadline: now.add(const Duration(seconds: 1312)),
        remaining: 1312,
      ),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flutter.pine-pomodoro': jsonEncode(seed.toMap()),
    });

    final shot = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: shot, child: const PomodoroApp()),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    final boundary =
        shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out =
        File('${Directory.current.path}/../outputs/desktop-wide-preview.png');
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('written: ${out.path}  ${image.width}×${image.height}');
    debugDefaultTargetPlatformOverride = null;
  });
}
