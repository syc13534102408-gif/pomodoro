// 离屏渲染「手机专注页」→ outputs/mobile-focus-preview.png（人工看布局用）
//
// 注意：为了显示中文这里用 FontLoader 装了系统字体，跑完进程可能不退出，
// 看到 "written" 就可以 Ctrl-C / kill。
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

void main() {
  testWidgets('渲染手机专注页预览', (tester) async {
    // 用 TTF 而不是 Hiragino Sans GB.ttc：TTC 集合在这个 FontLoader 用法下
    // 注册不稳定，预览里中文会一片方块。Arial Unicode 是单 face，实测全正常。
    final file = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      // V3 素纸令牌把标题/计时指向 'Songti SC'、时间戳指向 'SF Mono'；
      // 测试环境没有这些字体，全部注册到系统中文，否则预览里中文是方块。
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
    }
    // 图标也要注册：否则 Menu / 播放 / 勾选等 MaterialIcons 全渲染成空方框。
    final icons = File('/Users/shuyichen/Documents/Codex/2026-08-13/pinecone/tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(
            ByteData.view(Uint8List.fromList(icons.readAsBytesSync()).buffer)));
      await loader.load();
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(780, 1688);
    final now = DateTime.now();
    final today = ymdOf(dayStart(now));
    final seed = AppData(
      tasks: [
        PineTask(name: '高数 · 第六章', color: kTaskPalette[0].toARGB32()),
        PineTask(name: '408 真题', color: kTaskPalette[3].toARGB32()),
      ],
      records: [
        FocusRecord(
          id: 'live',
          taskName: '高数 · 第六章',
          minutes: 0,
          dayKey: today,
          status: RecordStatus.inProgress,
          at: now.subtract(const Duration(minutes: 21)),
        ),
        FocusRecord(
          taskName: '高数 · 第六章',
          minutes: 200,
          dayKey: today,
          status: RecordStatus.completed,
          at: now.subtract(const Duration(hours: 1)),
        ),
        FocusRecord(
          taskName: '408 真题',
          minutes: 320,
          dayKey: ymdOf(dayStart(now.subtract(const Duration(days: 1)))),
          status: RecordStatus.completed,
          at: now.subtract(const Duration(days: 1)),
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
        deadline: now.add(const Duration(seconds: 1694)),
        remaining: 1694,
      ),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flutter.pine-pomodoro': jsonEncode(seed.toMap()),
    });
    final shot = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: shot, child: const PomodoroApp()));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final boundary = shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${Directory.current.path}/../outputs/mobile-focus-preview.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    debugPrint('written');
    debugDefaultTargetPlatformOverride = null;
  });
}
