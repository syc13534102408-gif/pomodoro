// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/sheets.dart';
import 'package:pomodoro_app/src/theme.dart';

AppData _base() => AppData(
      settings: TimerSettings(focus: 50),
      tasks: [PineTask(name: '高数'), PineTask(name: '英语')],
      selectedIndex: 0,
    );

/// 两个事件：已完成「高数第六章」（60 分钟）+ 进行中「英语阅读」。
AppData _withEvents() {
  final t0 = DateTime(2026, 10, 12, 10);
  var data =
      TimerEngine.startEvent(_base(), name: '高数第六章', taskName: '高数', now: t0);
  final doneId = data.events.first.id;
  data = TimerEngine.addManual(data,
      taskName: '高数', minutes: 60, at: t0.add(const Duration(hours: 1)));
  data = TimerEngine.finishEvent(data, doneId, t0.add(const Duration(days: 1)));
  data = TimerEngine.startEvent(data,
      name: '英语阅读', taskName: '英语', now: t0.add(const Duration(days: 2)));
  return data;
}

void main() {
  testWidgets('事件档案窗口：汇总头 / 任务构成 / 分区 / 排序切换', (tester) async {
    final data = _withEvents();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showEventArchiveSheet(
              context,
              data: data,
              colorFor: (taskName) => PineColors.pine,
              onChanged: (_) {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('事件档案'), findsOneWidget);
    // 汇总头：2 个事件 · 60 分钟 = 1 小时 · 1 番茄 · 覆盖 1 天。
    expect(find.text('共 2 个事件 · 累计 1 小时 · 1 番茄 · 覆盖 1 天'),
        findsOneWidget);
    // 分区与条目。
    expect(find.text('进行中 1 个'), findsOneWidget);
    expect(find.text('已完成 1 个'), findsOneWidget);
    expect(find.text('高数第六章'), findsOneWidget);
    expect(find.text('英语阅读'), findsOneWidget);
    // 已完成行：完成日期 + 覆盖天数；进行中行显示状态。
    expect(find.textContaining('10/13 完成 · 1 天'), findsOneWidget);
    expect(find.textContaining('进行中 · 0 天'), findsOneWidget);
    // 任务构成行：高数 1 个 · 1 小时。
    expect(find.text('1 个 · 1 小时'), findsOneWidget);

    // 排序切换：按最近 → 按时长。
    expect(find.text('按最近'), findsOneWidget);
    await tester.tap(find.text('按最近'));
    await tester.pumpAndSettle();
    expect(find.text('按时长'), findsOneWidget);
  });

  testWidgets('事件档案窗口：无已完成事件时只显示进行中分区', (tester) async {
    final t0 = DateTime(2026, 10, 12, 10);
    final data = TimerEngine.startEvent(
        _base(), name: '英语阅读', taskName: '英语', now: t0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showEventArchiveSheet(
              context,
              data: data,
              colorFor: (taskName) => PineColors.pine,
              onChanged: (_) {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('共 1 个事件 · 累计 <1 分钟 · 0 番茄 · 覆盖 0 天'),
        findsOneWidget);
    expect(find.text('进行中 1 个'), findsOneWidget);
    expect(find.text('已完成 0 个'), findsOneWidget);
    expect(find.text('还没有已完成的事件'), findsOneWidget);
  });
}
