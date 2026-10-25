import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pomodoro_app/main.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/plan_remote.dart';
import 'package:pomodoro_app/src/sheets.dart';
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

    expect(find.textContaining('今天还没安排'), findsOneWidget);
    expect(find.text('816 真题① 限时'), findsNothing);

    // 卡片本身只显示今天；跨天视图走「全部 ›」。
    await tester.tap(find.text('全部 ›').first);
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
    await tester.tap(find.text('全部 ›').first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(BrickButton, '导入').first);
    await tester.pumpAndSettle();

    // 日期必须相对"今天"生成：写死 10/24、10/25 会在真正的 10/25 那天
    // 与本页「今日日程」卡重复命中（2026-10-25 实测踩到）。
    final d1 = DateTime.now().add(const Duration(days: 3));
    final d2 = DateTime.now().add(const Duration(days: 4));
    String md(DateTime d) => '${d.month}/${d.day}';
    final text = '${md(d1)} 2018 数一复盘\n${md(d2)} 现控 ch5 下半';
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

  testWidgets('导入面板的 AI 解析：服务端结果替换输入框并进入预览', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    String? sent;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPlanSheet(
              context,
              data: AppData(),
              onApply: (_) {},
              now: DateTime(2026, 10, 23),
              remote: (text) async {
                sent = text;
                return '10/24\t2018 复盘（AI 抽出）';
              },
            ),
            child: const Text('打开日程'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开日程'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(BrickButton, '导入').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '下周六做 2018 复盘',
    );
    await tester.pump();
    await tester.tap(find.text('AI 解析'));
    await tester.pumpAndSettle();

    expect(sent, '下周六做 2018 复盘');
    expect(find.text('将写入 1 天 / 1 条'), findsOneWidget);
  });

  testWidgets('AI 解析失败时在面板里显示原因，不吞异常', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPlanSheet(
              context,
              data: AppData(),
              onApply: (_) {},
              remote: (_) async =>
                  throw PlanRemoteException('服务端未配置智能解析（缺少 PINE_LLM_API_KEY）'),
            ),
            child: const Text('打开日程'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开日程'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(BrickButton, '导入').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '随便一段',
    );
    await tester.pump();
    await tester.tap(find.text('AI 解析'));
    await tester.pumpAndSettle();

    expect(find.textContaining('PINE_LLM_API_KEY'), findsOneWidget);
  });

}
