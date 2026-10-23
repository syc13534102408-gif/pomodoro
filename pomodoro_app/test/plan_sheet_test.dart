import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pomodoro_app/main.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/widgets.dart';

String _todayKey() => ymdOf(dayStart(DateTime.now()));

Future<void> _pumpHome(WidgetTester tester, AppData data) async {
  // 默认 800×600 视口装不下「今日日程」卡，会被滚出屏幕导致 tap 打空。
  tester.view.physicalSize = const Size(1000, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{
    'flutter.pine-pomodoro': jsonEncode(data.toMap()),
  });
  await tester.pumpWidget(const PomodoroApp());
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('今日日程卡显示今天条目，点一下即打勾（不计时）', (tester) async {
    final today = _todayKey();
    await _pumpHome(
      tester,
      AppData(todos: {
        today: [
          TodoItem(text: '现控 ch5 上半'),
          TodoItem(text: '英语 单词 25min'),
        ],
      }),
    );

    expect(find.text('今日日程'), findsOneWidget);
    expect(find.text('现控 ch5 上半'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);

    await tester.tap(find.text('现控 ch5 上半'));
    await tester.pump();

    expect(find.text('1/2'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('未来日期的日程不会出现在今日卡，但能打开日程面板看到分组', (tester) async {
    final today = DateTime.now();
    final tomorrow = ymdOf(dayStart(today.add(const Duration(days: 1))));
    await _pumpHome(
      tester,
      AppData(todos: {
        tomorrow: [TodoItem(text: '816 真题① 限时')],
      }),
    );

    expect(find.text('今天还没安排 · 点右上打开日程'), findsOneWidget);
    expect(find.text('816 真题① 限时'), findsNothing);

    await tester.tap(find.text('去安排'));
    await tester.pumpAndSettle();

    expect(find.text('日程'), findsOneWidget);
    expect(find.text('816 真题① 限时'), findsOneWidget);
    expect(
      find.text(chineseDate(today.add(const Duration(days: 1)),
          withYear: false)),
      findsWidgets,
    );
  });

  testWidgets('日程面板里粘贴导入：预览条数 → 确认后落到对应日期', (tester) async {
    await _pumpHome(tester, AppData());
    await tester.tap(find.text('去安排'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(BrickButton, '导入').first);
    await tester.pumpAndSettle();

    const text = '10/24 2018 数一复盘\n10/25 现控 ch5 下半';
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      text,
    );
    await tester.pumpAndSettle();
    expect(find.text('将写入 2 天 / 2 条'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, '导入'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2018 数一复盘'), findsOneWidget);
    expect(find.text('现控 ch5 下半'), findsOneWidget);
  });
}
