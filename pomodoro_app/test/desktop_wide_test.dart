import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pomodoro_app/main.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/ui/ui.dart';

/// P5 三栏书斋的几何回归（2026-11-12）。
///
/// 设计稿：`1120×680` → `216px 楮皮目录栏` + `弹性中栏` + `420px 专注手稿画布`；
/// `<720px` 收成单列（这条仍由 `desktop_layout_test` 的 440×600 断言守住，未放宽）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1120×680 三栏就位，宽度精确且不裁切', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1120, 680);
    try {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.pine-pomodoro': jsonEncode(AppData().toMap()),
      });
      await tester.pumpWidget(const PomodoroApp());
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }

      Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
      final sidebar = rect('study-sidebar');
      final center = rect('study-center');
      final canvas = rect('study-canvas');

      expect(sidebar.width, 216);
      expect(canvas.width, 420);
      expect(center.width, 1120 - 216 - 420);
      expect(sidebar.height, 680);
      expect(canvas.height, 680);

      // 三栏内容都在，且是素纸组件（不是旧版单列圆环舱）。
      expect(find.text('素纸书房'), findsOneWidget);
      expect(find.text('日课笺'), findsOneWidget);
      expect(find.byType(RuledScale), findsWidgets);
      expect(find.byType(PaperComposer), findsOneWidget);
      // 440×600 路径依赖的功能节点在宽屏同样保留。
      expect(find.text('今日日程'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.reset();
    }
  });

  testWidgets('窄窗 560×760 仍是单列专注舱，不出现三栏', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(1120, 1520);
    try {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.pine-pomodoro': jsonEncode(AppData().toMap()),
      });
      await tester.pumpWidget(const PomodoroApp());
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }

      expect(find.byKey(const ValueKey('study-sidebar')), findsNothing);
      expect(find.byKey(const ValueKey('study-canvas')), findsNothing);
      expect(find.text('今日日程'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.reset();
    }
  });
}
