import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/storage.dart';
import 'package:pomodoro_app/src/widgets.dart';

void main() {
  group('Countdown.daysFrom', () {
    const exam = Countdown(label: '2027 考研初试', date: '2026-12-19');

    test('目标当天为 0，按自然日跨天', () {
      expect(exam.daysFrom(DateTime(2026, 12, 19)), 0);
      expect(exam.daysFrom(DateTime(2026, 12, 19, 23, 59)), 0);
      expect(exam.daysFrom(DateTime(2026, 12, 18, 23, 59)), 1);
      expect(exam.daysFrom(DateTime(2026, 12, 20, 0, 1)), -1);
    });

    test('2026-09-13 距 2026-12-19 为 97 天', () {
      expect(exam.daysFrom(DateTime(2026, 9, 13, 16, 49)), 97);
    });

    test('跨年与闰年 2 月 29 日', () {
      const leap = Countdown(date: '2028-02-29');
      expect(leap.daysFrom(DateTime(2028, 2, 28)), 1);
      expect(leap.daysFrom(DateTime(2028, 3, 1)), -1);
      expect(leap.daysFrom(DateTime(2028, 1, 1)), 59);
    });

    test('日期非法时回落默认值，不产生空倒计时', () {
      final bad = Countdown.fromMap({'date': 'not-a-date', 'label': '  '});
      expect(bad.date, Countdown.defaultDate);
      expect(bad.label, Countdown.defaultLabel);
      expect(bad.daysFrom(DateTime(2026, 9, 13)), 97);
    });

    test('enabled 缺省为 true，显式 false 才关闭', () {
      expect(Countdown.fromMap(null).enabled, isTrue);
      expect(Countdown.fromMap({'enabled': false}).enabled, isFalse);
    });
  });

  group('Countdown 序列化', () {
    test('toMap / fromMap 往返', () {
      const custom = Countdown(enabled: false, label: '复试', date: '2027-03-20');
      final back = Countdown.fromMap(custom.toMap());
      expect(back.enabled, isFalse);
      expect(back.label, '复试');
      expect(back.date, '2027-03-20');
    });
  });

  group('AppData 集成', () {
    const custom = Countdown(
      enabled: false,
      label: '复试',
      date: '2027-03-20',
    );

    test('倒计时进本机存档、但不进云端净荷', () {
      final data = AppData().copyWith(countdown: custom);
      expect(data.toMap()['countdown'], isNotNull);
      // 网页端尚无该字段：上传会被回传净荷覆盖丢失，故刻意剔除。
      expect(data.toCloudMap().containsKey('countdown'), isFalse);
    });

    test('本机存档往返保留倒计时', () {
      final restored =
          AppData.fromMap(AppData().copyWith(countdown: custom).toMap());
      expect(restored.countdown.label, '复试');
      expect(restored.countdown.date, '2027-03-20');
      expect(restored.countdown.enabled, isFalse);
    });

    test('云同步恢复后保留本机倒计时设置', () {
      final local = AppData().copyWith(countdown: custom);
      final merged = mergeFromCloud(local, AppData().toCloudMap());
      expect(merged.countdown.label, '复试');
      expect(merged.countdown.date, '2027-03-20');
      expect(merged.countdown.enabled, isFalse);
    });

    test('copyWith 不改动未提及字段', () {
      final base = AppData().copyWith(countdown: custom);
      expect(base.copyWith(goalMinutes: 300).countdown.date, '2027-03-20');
    });
  });

  group('chineseDate', () {
    test('含年 / 不含年', () {
      expect(chineseDate(DateTime(2026, 12, 19)), '2026年12月19日 周六');
      expect(chineseDate(DateTime(2026, 12, 19), withYear: false), '12月19日 周六');
      expect(chineseDate(DateTime(2026, 9, 13)), '2026年9月13日 周日');
    });
  });

  group('CountdownCard 渲染', () {
    Future<void> pump(
      WidgetTester tester,
      Countdown countdown,
      DateTime now, {
      bool compact = false,
    }) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CountdownCard(
                countdown: countdown,
                now: now,
                compact: compact,
              ),
            ),
          ),
        );

    testWidgets('常规态：名称 + 考试日期 + 剩余天数', (tester) async {
      await pump(tester, const Countdown(), DateTime(2026, 9, 13, 16, 49));
      expect(find.text('2027 考研初试'), findsOneWidget);
      expect(find.text('2026年12月19日 周六'), findsOneWidget);
      expect(find.text('97'), findsOneWidget);
      expect(find.text('天'), findsOneWidget);
      expect(find.text('今天开考'), findsNothing);
    });

    testWidgets('当天：改为「今天开考」，不再显示天数', (tester) async {
      await pump(tester, const Countdown(), DateTime(2026, 12, 19, 8, 30));
      expect(find.text('今天开考'), findsOneWidget);
      expect(find.text('97'), findsNothing);
      expect(find.text('天'), findsNothing);
    });

    testWidgets('已过：显示「考试已结束」', (tester) async {
      await pump(tester, const Countdown(), DateTime(2027, 1, 1));
      expect(find.text('考试已结束'), findsOneWidget);
      expect(find.text('天'), findsNothing);
    });

    testWidgets('compact 单行内同时含名称、日期与天数', (tester) async {
      await pump(
        tester,
        const Countdown(),
        DateTime(2026, 9, 13),
        compact: true,
      );
      expect(
        find.textContaining('2027 考研初试', findRichText: true),
        findsWidgets,
      );
      expect(
        find.textContaining('12月19日 周六', findRichText: true),
        findsWidgets,
      );
      expect(find.text('97'), findsOneWidget);
    });

    testWidgets('目标日不可解析时不渲染（防御脏数据）', (tester) async {
      // 构造函数不做校验，只有 fromMap 才回落默认值；这里直接喂脏日值。
      await pump(
        tester,
        const Countdown(label: '脏数据', date: 'x'),
        DateTime(2026, 9, 13),
      );
      expect(find.text('脏数据'), findsNothing);
      expect(find.text('天'), findsNothing);
    });
  });
}
