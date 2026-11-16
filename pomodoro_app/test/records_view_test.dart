import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/records_view.dart';
import 'package:pomodoro_app/src/theme.dart';
import 'package:pomodoro_app/src/widgets.dart';

AppData sample() => AppData(tasks: [
      PineTask(name: '阅读')
    ], records: [
      FocusRecord(
          id: 'a',
          taskName: '阅读',
          minutes: 65,
          dayKey: '2026-11-14',
          status: RecordStatus.completed,
          at: DateTime(2026, 11, 16, 4, 12, 35)),
      FocusRecord(
          id: 'b',
          taskName: '阅读',
          minutes: 30,
          dayKey: '2026-11-15',
          status: RecordStatus.completed,
          at: DateTime(2026, 11, 15, 23, 12, 9)),
      FocusRecord(
          id: 'c',
          taskName: '',
          minutes: 20,
          dayKey: '2026-11-14',
          status: RecordStatus.manual,
          at: DateTime(2026, 11, 15, 2, 9, 1)),
    ]);
void main() {
  testWidgets('全量组按所属日排序，完成时刻交错也不拆组，组内倒序到秒', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = sample();
    await tester.pumpWidget(MaterialApp(
        theme: buildPineTheme(),
        home: Scaffold(
            body: RecordsPanel(data: data, onEdit: (_) {}, onAdd: () {}))));
    final a = find.byKey(const ValueKey('record-a'));
    final b = find.byKey(const ValueKey('record-b'));
    final c = find.byKey(const ValueKey('record-c'));
    expect(tester.getTopLeft(b).dy, lessThan(tester.getTopLeft(a).dy));
    expect(tester.getTopLeft(a).dy, lessThan(tester.getTopLeft(c).dy));
    expect(find.descendant(of: a, matching: find.text('所属日期：2026-11-14')),
        findsOneWidget);
    expect(
        find.descendant(of: a, matching: find.text('完成时刻：2026-11-16 04:12:35')),
        findsOneWidget);
    expect(find.text('所属日期 2026-11-14'), findsOneWidget);
    expect(find.textContaining('番茄'), findsNothing);
    expect(find.descendant(of: c, matching: find.text('无任务')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(360, 800), const Size(500, 640)]) {
    testWidgets('$size 双时间字段及补记动作首屏完整可见', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          theme: buildPineTheme(),
          home: Scaffold(
              body:
                  RecordsPanel(data: sample(), onEdit: (_) {}, onAdd: () {}))));
      for (final label in [
        '补记',
        '所属日期：2026-11-14',
        '完成时刻：2026-11-16 04:12:35'
      ]) {
        final rect = tester.getRect(find.text(label).first);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('表单拒绝非整数/非正时长和未来时刻，不提交；合法保存不改跨日归属', (tester) async {
    final data = sample();
    AppData? result;
    await tester.pumpWidget(MaterialApp(
        theme: buildPineTheme(),
        home: Scaffold(
            body: RecordEditor(
                data: data,
                record: data.records.first,
                now: DateTime(2026, 11, 17),
                onSaved: (next) => result = next))));
    final fields = find.byType(TextField);
    for (final invalid in ['0', '-1', '1.5']) {
      await tester.enterText(fields.first, invalid);
      await tester.pump();
      expect(
          tester.widget<PineButton>(find.byType(PineButton)).onPressed, isNull);
      expect(result, isNull);
    }
    await tester.enterText(fields.first, '70');
    for (final invalid in [
      '2026-11-18 00:00:00',
      '2026-02-30 12:00:00',
      '不是时刻'
    ]) {
      await tester.enterText(fields.last, invalid);
      await tester.pump();
      expect(
          tester.widget<PineButton>(find.byType(PineButton)).onPressed, isNull);
    }
    await tester.enterText(fields.last, '2026-11-16 04:12:35');
    await tester.pump();
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    expect(result!.records.first.minutes, 70);
    expect(result!.records.first.dayKey, '2026-11-14');
    expect(result!.records.first.at, data.records.first.at);
  });
}
