import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/plan_import.dart';

void main() {
  group('日程解析', () {
    test('三种日期写法都能解析，正文原样保留', () {
      final plan = parsePlan('''
10/24 2018 数一复盘 · 18(2) 重做 + 22、23 盲算
2026-10-25\t现控 ch5 下半 + ch6 全（收尾）
10-31  错题归并
''');

      expect(plan.dayCount, 3);
      expect(plan.total, 3);
      expect(plan.byDay['2026-10-24']!.single, '2018 数一复盘 · 18(2) 重做 + 22、23 盲算');
      expect(plan.byDay['2026-10-25']!.single, '现控 ch5 下半 + ch6 全（收尾）');
      expect(plan.byDay['2026-10-31']!.single, '错题归并');
      expect(plan.skipped, isEmpty);
    });

    test('日期键与"现在几点"无关：凌晨 00:30 与 03:30 解析出同一天', () {
      const text = '10/24 2018 复盘\n10/25 现控 ch5';
      // 统计日以凌晨 3 点分界：若按 dateKey(now) 算，00:30 会把 10/24 掉进 10-23。
      final beforeBoundary =
          parsePlan(text, now: DateTime(2026, 10, 24, 0, 30));
      final afterBoundary = parsePlan(text, now: DateTime(2026, 10, 24, 3, 30));

      expect(beforeBoundary.byDay.keys, afterBoundary.byDay.keys);
      expect(beforeBoundary.byDay.keys, ['2026-10-24', '2026-10-25']);
      // 反向证明坑真实存在：同一时刻的统计日键是前一天。
      expect(dateKey(DateTime(2026, 10, 24, 0, 30)), '2026-10-23');
    });

    test('注释、空行忽略；非法日期/空正文进 skipped 且带行号', () {
      final plan = parsePlan('''
# 这是注释
10/24 正常一条

13/45 不存在的日期
10/25
2/30 二月没有三十号
''');

      expect(plan.byDay.length, 1);
      expect(plan.byDay['2026-10-24']!.single, '正常一条');
      expect(plan.skipped.length, 3);
      expect(plan.skipped.first, contains('第 4 行'));
      expect(plan.skipped[2], contains('第 6 行'));
    });

    test('文本内同一天同一句只留一条', () {
      final plan = parsePlan('10/24 同一句\n10/24 同一句\n10/24 另一句');
      expect(plan.byDay['2026-10-24']!.length, 2);
    });

    test('没写年份时跨年回绕：12 月排 1 月计划落到明年', () {
      final plan = parsePlan('01/05 寒假计划', now: DateTime(2026, 12, 20));
      expect(plan.byDay.keys.single, '2027-01-05');
    });
  });

  group('合并进 todos', () {
    Map<String, List<TodoItem>> seed() => {
          '2026-10-24': [
            TodoItem(id: 'a', text: '2018 复盘', done: true),
          ],
        };

    test('幂等：重复导入不翻倍，已有条目的勾选状态保留', () {
      final plan = parsePlan('10/24 2018 复盘\n10/24 现控 ch5 上半');
      final first = mergePlanIntoTodos(seed(), plan);
      expect(first.added, 1);
      expect(first.duplicated, 1);
      expect(first.todos['2026-10-24']!.length, 2);
      expect(first.todos['2026-10-24']!.first.done, isTrue);

      final second = mergePlanIntoTodos(first.todos, plan);
      expect(second.added, 0);
      expect(second.duplicated, 2);
      expect(second.todos['2026-10-24']!.length, 2);
    });

    test('8 天日程能落到 8 个键上，且不动别的日期', () {
      final plan = parsePlan('''
10/24 2018 复盘
10/25 现控 ch5 下半
10/26 2021 数一 限时
10/27 816 真题① 限时
10/28 2017 数一 限时
10/29 816 真题② 限时
10/30 2015 数一 限时
10/31 错题归并
10/01 更早的一条
''');
      final merged = mergePlanIntoTodos(seed(), plan);
      expect(merged.added, 8);
      expect(merged.todos.keys, containsAll(<String>['2026-10-24', '2026-10-31']));
      expect(merged.todos['2026-10-01']!.single.text, '更早的一条');
      // 10/24 那条与 seed 里已有的同名条目重复，只补进其余 8 条。
      expect(merged.todos['2026-10-24']!.length, 1);
    });
  });

  test('真实 8 天日程：27 条全部落到 10/24–10/31 的 8 个键上', () {
    const real = """
10/24	2018 数一复盘 · 18(2) 重做 + 22、23 盲算
10/24	现控 ch5 上半 · 教材 + 例题
10/24	英语 · 单词 25min + 大作文① 35min
10/25	现控 ch5 下半 · 教材 + 习题
10/25	现控 ch6 全章（收尾）
10/25	产出「现控四块 ↔ 经典八题型」对应表
10/25	英语 · 单词 25min + 小作文① 15min + 阅读二刷 45min
10/26	★2021 数一 限时 3h（新格式首练）
10/26	数学 2021 逐题对答案 + 错题标注
10/26	816 题型总表 v0
10/26	英语 · 单词 25min + 大作文② 35min
10/27	★816 真题①＝2020 上交 限时 3h
10/27	数学 2021 逐题复盘（时间分配诊断）
10/27	英语 · 单词 25min + 小作文② 15min + 阅读二刷 45min
10/28	★2017 数一 限时 3h
10/28	816 真题① 逐题复盘
10/28	英语 · 单词 25min + 大作文③ 35min
10/29	★816 真题②＝2019 上交 限时 3h
10/29	数学 2017 逐题复盘
10/29	英语 · 单词 25min + 小作文③ 15min + 阅读二刷 45min
10/30	★2015 数一 限时 3h
10/30	816 真题② 逐题复盘
10/30	英语 · 单词 25min + 大作文④ 35min
10/31	2015 数一 复盘
10/31	8 天错题归并 + 错题本落 3 行
10/31	政治下单 20min（11 月启动清单）
10/31	英语 · 单词 25min + 阅读二刷 45min
""";
    final plan = parsePlan(real);
    expect(plan.skipped, isEmpty);
    expect(plan.dayCount, 8);
    expect(plan.total, 27);
    expect(plan.byDay.keys, [
      '2026-10-24', '2026-10-25', '2026-10-26', '2026-10-27',
      '2026-10-28', '2026-10-29', '2026-10-30', '2026-10-31',
    ]);
    final merged = mergePlanIntoTodos({}, plan);
    expect(merged.added, 27);
    expect(merged.duplicated, 0);
  });

  test('未来日期的 todos 键能往返 toMap/fromMap 不丢', () {
    final data = AppData(todos: {
      '2026-10-31': [TodoItem(text: '错题归并')],
    });
    final restored = AppData.fromMap(data.toMap());
    expect(restored.todos['2026-10-31']!.single.text, '错题归并');
    expect(hasFuturePlan(restored.todos, DateTime(2026, 10, 23)), isTrue);
    expect(hasFuturePlan(restored.todos, DateTime(2026, 11, 1)), isFalse);
  });
}
