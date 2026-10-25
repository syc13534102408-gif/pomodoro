import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pomodoro_app/main.dart';
import 'package:pomodoro_app/src/models.dart';

/// 桌面「专注舱」在三种窗口尺寸下都不能溢出。
///
/// 2026-10-25 评审 P0-1：500×640 时列高 624.5 > 视口 574，信息卡底缘被硬切、
/// 最近完成第 3 条只剩字形顶。这里把三档尺寸钉成回归测试——溢出会被
/// flutter_test 直接判失败（RenderFlex overflow 在测试里是 error）。
AppData _dataWith(int recordCount) {
  final now = DateTime.now();
  return AppData(
    records: [
      for (var i = 0; i < recordCount; i++)
        FocusRecord(
          taskName: ['自控', '英语', '数学'][i % 3],
          minutes: 50.0 + i,
          dayKey: ymdOf(dayStart(now)),
          status: RecordStatus.completed,
          at: now.subtract(Duration(minutes: 30 * (i + 1))),
        ),
    ],
    settings: const TimerSettings(focus: 60, short: 10, long: 20),
  );
}

Future<void> _pumpDesktop(
  WidgetTester tester, {
  required double width,
  required double height,
  required int records,
}) async {
  // 必须在测试体结束前恢复：flutter_test 会在每例结束时断言「foundation debug
  // 变量未被改动」，用 addTearDown 恢复已经太晚。
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = Size(width * 2, height * 2);

  SharedPreferences.setMockInitialValues(<String, Object>{
    'flutter.pine-pomodoro': jsonEncode(_dataWith(records).toMap()),
  });
  await tester.pumpWidget(const PomodoroApp());
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in const <Size>[
    Size(440, 600), // 最小窗
    Size(500, 640), // 默认窗
    Size(560, 720), // 拉大
  ]) {
    testWidgets('桌面舱 ${size.width.toInt()}×${size.height.toInt()} 不溢出（3 条记录）',
        (tester) async {
      try {
        await _pumpDesktop(
          tester,
          width: size.width,
          height: size.height,
          records: 3,
        );
        expect(find.text('最近完成'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // 关键断言：舱是 SingleChildScrollView，内容超长**不会**报 overflow 异常，
        // 只会被裁掉。所以判据是「可滚动距离为 0」——不滚动就能看全。
        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          ),
        );
        expect(scrollable.position.maxScrollExtent, lessThanOrEqualTo(0.5),
            reason: '${size.width.toInt()}×${size.height.toInt()} 需要滚动才能看全，'
                '说明信息卡又被裁了（评审 P0-1 回归）');
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.reset();
      }
    });
  }

  testWidgets('默认窗只列 2 条最近完成，第 3 条走「全部 ›」', (tester) async {
    try {
      await _pumpDesktop(tester, width: 500, height: 640, records: 3);
      // 3 条记录里只有前 2 条出现在信息卡上（第三条被裁掉正是 P0-1 的现象）。
      expect(find.text('自控'), findsOneWidget);
      expect(find.text('英语'), findsOneWidget);
      expect(find.text('数学'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.reset();
    }
  });

  testWidgets('拉高到 720 后允许显示 3 条', (tester) async {
    try {
      await _pumpDesktop(tester, width: 560, height: 720, records: 3);
      expect(find.text('数学'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.reset();
    }
  });
}
