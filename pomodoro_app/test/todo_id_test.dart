import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/plan_import.dart';

/// 2026-10-25 实机 bug：日程导入后勾一条，同一天三条一起变勾。
/// 根因是批量创建时 `microsecondsSinceEpoch` 撞号（同 id 会被一起匹配）。
void main() {
  group('TodoItem id 唯一性', () {
    test('循环批量创建 200 条，id 全不相同', () {
      final ids = <String>{};
      for (var i = 0; i < 200; i++) {
        ids.add(TodoItem(text: '条目 $i').id);
      }
      expect(ids.length, 200);
    });

    test('粘贴导入一整天也能保证 id 唯一（导入路径同样走批量创建）', () {
      final plan = parsePlan([
        for (var i = 0; i < 30; i++) '10/29 任务 $i',
      ].join('\n'));
      final merged = mergePlanIntoTodos({}, plan);
      final ids = merged.todos['2026-10-29']!.map((item) => item.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids.length, 30);
    });

    test('显式传入 id 时保持原值（copyWith / 云端往返依赖这一点）', () {
      final item = TodoItem(id: 'fixed-id', text: 'x');
      expect(item.id, 'fixed-id');
      expect(item.copyWith(done: true).id, 'fixed-id');
    });
  });

  group('历史重复 id 的读盘修复', () {
    test('fromMap 遇到同 id 会给后来者换新 id', () {
      final data = AppData.fromMap(<String, dynamic>{
        'todos': {
          '2026-10-29': [
            {'id': 'dup', 'text': '任务 A', 'done': false},
            {'id': 'dup', 'text': '任务 B', 'done': true},
            {'id': 'dup', 'text': '任务 C', 'done': false},
          ],
        },
      });
      final items = data.todos['2026-10-29']!;
      expect(items.map((item) => item.id).toSet().length, 3);
      // 内容与完成状态不能被修复过程改动。
      expect(items.map((item) => item.text).toList(), ['任务 A', '任务 B', '任务 C']);
      expect(items[1].done, isTrue);
    });

    test('跨日期同 id 也会被拆开', () {
      final data = AppData.fromMap(<String, dynamic>{
        'todos': {
          '2026-10-29': [
            {'id': 'same', 'text': 'A', 'done': false},
          ],
          '2026-10-30': [
            {'id': 'same', 'text': 'B', 'done': false},
          ],
        },
      });
      final all = data.todos.values.expand((items) => items).map((e) => e.id).toList();
      expect(all.toSet().length, all.length);
    });
  });

  testWidgets('勾选只影响被点的那一条（回归）', (tester) async {
    // 这里直接验证"勾选按 id 匹配"的前提：三条不同 id 的待办，各自独立切换。
    final items = [
      TodoItem(text: 'A'),
      TodoItem(text: 'B'),
      TodoItem(text: 'C'),
    ];
    final todos = <String, List<TodoItem>>{'2026-10-29': items};
    final target = items[1];
    final next = {
      ...todos,
      '2026-10-29': [
        for (final entry in todos['2026-10-29']!)
          entry.id == target.id ? entry.copyWith(done: !entry.done) : entry,
      ],
    };
    expect(next['2026-10-29']!.where((e) => e.done).length, 1);
    expect(next['2026-10-29']![1].done, isTrue);
    // 顺带说明为什么撞号会"勾一片"：同 id 时上面的 where 会命中多条。
    final dup = [TodoItem(id: 'x', text: 'A'), TodoItem(id: 'x', text: 'B')];
    final flipped = [
      for (final entry in dup)
        entry.id == 'x' ? entry.copyWith(done: true) : entry,
    ];
    expect(flipped.where((e) => e.done).length, 2);
  });
}
