import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_app/pages/ledger_page.dart';
import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/sheets.dart';
import 'package:pomodoro_app/src/theme.dart';
import 'package:pomodoro_app/src/widgets.dart';

final now = DateTime(2026, 11, 16, 14, 30);
void main() {
  testWidgets('日期序列不补空的今天，删除最后条目即移除该日，跨日勾选状态独立', (tester) async {
    var data = AppData(todos: {
      '2026-11-14': [TodoItem(id: 'a', text: '往期事项')],
      '2026-11-17': [TodoItem(id: 'b', text: '明日事项')],
      '2026-11-18': [],
    });
    await tester.pumpWidget(MaterialApp(
        theme: buildPineTheme(),
        home: Scaffold(
            body: PlanPanel(
                data: data,
                now: now,
                onApply: (transform) =>
                    data = data.copyWith(todos: transform(data.todos))))));
    expect(find.text('今天'), findsNothing);
    expect(find.text('11/18'), findsNothing);
    expect(find.text('这一天没有待办'), findsOneWidget);
    await tester.tap(find.text('11/14'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(data.todos['2026-11-14']!.single.done, isTrue);
    expect(data.todos['2026-11-17']!.single.done, isFalse);
    await tester.tap(find.text('11/17'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    await tester.tap(find.text('11/14'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await tester.tap(find.byTooltip('删除待办'));
    await tester.pumpAndSettle();
    expect(find.text('11/14'), findsNothing);
    expect(data.todos['2026-11-17']!.single.id, 'b');
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(360, 800), const Size(500, 640)]) {
    for (final segment in [
      PineLedgerSegment.records,
      PineLedgerSegment.schedule
    ]) {
      testWidgets('$size $segment 有会话时导航、双时间或首项及固定动作完整可见', (tester) async {
        debugDefaultTargetPlatformOverride =
            size.width == 360 ? TargetPlatform.android : TargetPlatform.macOS;
        try {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          var data = AppData(tasks: [
            PineTask(name: '阅读')
          ], records: [
            FocusRecord(
                id: 'r',
                taskName: '阅读',
                minutes: 25,
                dayKey: '2026-11-15',
                status: RecordStatus.completed,
                at: DateTime(2026, 11, 16, 3, 12, 9))
          ], todos: {
            '2026-11-16': [TodoItem(text: '首条日程')],
          });
          data = TimerEngine.start(data, SessionMode.focus,
              now.subtract(const Duration(minutes: 10)));
          await tester.pumpWidget(MaterialApp(
              theme: buildPineTheme(),
              home: LedgerPage(
                  data: data,
                  now: now,
                  onChanged: (_) {},
                  onReturnToPresent: () {},
                  initialSegment: segment)));
          await tester.pumpAndSettle();
          void visible(Finder finder) {
            final rect = tester.getRect(finder.first);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
            expect(rect.bottom, lessThanOrEqualTo(size.height));
          }

          visible(find.byType(TenseSwitcher));
          visible(find.byType(LedgerSegmentSelector));
          visible(find.byType(SessionPresenceBar));
          if (segment == PineLedgerSegment.records) {
            visible(find.text('所属日期：2026-11-15'));
            visible(find.text('完成时刻：2026-11-16 03:12:09'));
            visible(find.text('补记'));
          } else {
            visible(find.text('首条日程'));
            visible(find.text('今天'));
            visible(find.text('添加'));
            visible(find.text('导入'));
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
  testWidgets('窄日程长文本完整换行，空态仍可导入与添加', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const text = '这是一条需要完整显示的很长日程，用来确认多行文字可以完整换行且编辑和删除动作没有遮住文字。';
    await tester.pumpWidget(MaterialApp(
        theme: buildPineTheme(),
        home: Scaffold(
            body: PlanPanel(
                data: AppData(todos: {
                  '2026-11-16': [TodoItem(text: text)]
                }),
                now: now,
                onApply: (_) {}))));
    await tester.pumpAndSettle();
    expect(find.text(text), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(
        theme: buildPineTheme(),
        home: Scaffold(
            body: PlanPanel(
                key: const ValueKey('empty'),
                data: AppData(),
                now: now,
                onApply: (_) {}))));
    expect(find.text('还没有日程'), findsOneWidget);
    expect(find.text('今天'), findsNothing);
    expect(find.text('导入'), findsOneWidget);
    expect(find.text('添加'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
