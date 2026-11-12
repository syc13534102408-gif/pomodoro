// 离屏渲染「阶段条 + 收工仪式」→ outputs/preview-*.png
//
// 不是测试（文件名不以 _test.dart 结尾，默认收集不会带上它）。
// 用途：改完阶段条/收工仪式后用人眼看一眼：三格 + 收工胶囊是否挤、仪式卡是否通透。
// 注意：测试环境只有 Ahem 测试字体，中文一律出方块——只能验几何与节奏（间距、
// 换行、有没有挤在一起），不能验字形。字号与颜色仍可从图上读出来。
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
import 'package:pomodoro_app/src/widgets.dart';

AppData _seed({bool rest = false, bool withRecords = true}) {
  final now = DateTime.now();
  final today = ymdOf(dayStart(now));
  final data = AppData(
    tasks: [PineTask(name: '自控'), PineTask(name: '高数')],
    records: [
      if (withRecords) ...[
        FocusRecord(
          taskName: '自控',
          minutes: 50,
          dayKey: today,
          status: RecordStatus.completed,
          at: now.subtract(const Duration(hours: 4)),
        ),
        FocusRecord(
          taskName: '高数',
          minutes: 50,
          dayKey: today,
          status: RecordStatus.completed,
          at: now.subtract(const Duration(hours: 3)),
        ),
        FocusRecord(
          taskName: '自控',
          minutes: 46,
          dayKey: today,
          status: RecordStatus.completed,
          at: now.subtract(const Duration(hours: 1)),
        ),
      ],
    ],
    todos: {
      today: [
        TodoItem(text: '现控 ch5 下半', done: true),
        TodoItem(text: '英语单词 25-30 分钟'),
      ],
    },
    settings: const TimerSettings(focus: 50, short: 10, meal: 40),
    goalMinutes: 200,
  );
  return rest
      ? data.copyWith(restDate: ymdOf(dayStart(now)))
      : data;
}

Future<void> _shoot(
  WidgetTester tester,
  String name, {
  required AppData data,
  required Size size,
  Future<void> Function()? after,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = Size(size.width * 2, size.height * 2);
  SharedPreferences.setMockInitialValues(<String, Object>{
    'flutter.pine-pomodoro': jsonEncode(data.toMap()),
  });
  final shot = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(key: shot, child: const PomodoroApp()),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  if (after != null) await after();
  final boundary =
      shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final out = File('${Directory.current.path}/../outputs/preview-$name.png');
  out.writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('written: ${out.path}');
  // 必须先把 App 卸载掉再收尾：否则 App 的 periodic Timer（ticker/镜像轮询）
  // 还挂在 fake async 里，进程会在出图之后僵住不退出（2026-11-11 实测）。
  await tester.pumpWidget(const SizedBox.shrink());
  debugDefaultTargetPlatformOverride = null;
  tester.view.reset();
}

void main() {
  testWidgets('阶段条 · 560×760', (tester) async {
    await _shoot(tester, 'phase-560x760',
        data: _seed(), size: const Size(560, 760));
  });

  testWidgets('阶段条 · 最小窗 440×600', (tester) async {
    await _shoot(tester, 'phase-440x600',
        data: _seed(), size: const Size(440, 600));
  });

  testWidgets('阶段条 · 短休进行中', (tester) async {
    await _shoot(tester, 'phase-break', data: _seed(),
        size: const Size(560, 760), after: () async {
      await tester.tap(find.text('短休'));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('收工仪式 · 确认幕', (tester) async {
    await _shoot(tester, 'ceremony-open', data: _seed(),
        size: const Size(560, 760), after: () async {
      await tester.tap(find.text('收工'));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('收工仪式 · 盖章幕', (tester) async {
    await _shoot(tester, 'ceremony-sealed', data: _seed(),
        size: const Size(560, 760), after: () async {
      await tester.tap(find.text('收工'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(BrickButton, '收工'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  testWidgets('收工态主界面', (tester) async {
    await _shoot(tester, 'resting', data: _seed(rest: true),
        size: const Size(560, 760));
  });
}
