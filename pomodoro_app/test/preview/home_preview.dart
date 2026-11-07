// 离屏渲染「桌面主窗」→ outputs/home-cabin-preview-macos.png
//
// 不是测试（文件名不以 _test.dart 结尾，默认收集不会带上它）。
// 用途：改布局后用人眼看一眼环、控制行、新增的休息行有没有挤在一起/错位。
// 注意：测试环境没有中文字体，文字会渲染成方框，只能验几何与节奏。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pomodoro_app/main.dart';
import 'package:pomodoro_app/src/models.dart';

void main() {
  testWidgets('渲染桌面主窗预览（macOS 布局）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(1120, 1520); // 560×760
    // 不给 mock 初值，App 会卡在首屏加载动画（SharedPreferences 抛异常），截出来是转圈。
    final now = DateTime.now();
    final seed = AppData(
      tasks: [PineTask(name: '自控'), PineTask(name: '高数')],
      records: [
        FocusRecord(
          id: 'r1',
          taskName: '自控',
          minutes: 50,
          dayKey: ymdOf(dayStart(now)),
          status: RecordStatus.completed,
          at: now.subtract(const Duration(hours: 2)),
        ),
      ],
      todos: {
        ymdOf(dayStart(now)): [
          TodoItem(text: '现控 ch5 下半', done: true),
          TodoItem(text: '英语单词 25-30 分钟'),
        ],
      },
      settings: const TimerSettings(focus: 50, short: 10, meal: 40),
      goalMinutes: 350,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flutter.pine-pomodoro': jsonEncode(seed.toMap()),
    });
    final shot = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: shot, child: const PomodoroApp()),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final boundary = shot.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('${Directory.current.path}/../outputs/home-cabin-preview-macos.png');
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('written: ${out.path}');
    debugDefaultTargetPlatformOverride = null;
  });
}
