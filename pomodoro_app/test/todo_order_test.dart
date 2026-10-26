import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/models.dart';

/// 勾选排序：完成的按**勾选顺序**浮到顶部，第一条勾的排最上，
/// 之后每勾一条跟在上一条之后；取消勾选退回末尾。（2026-10-26 需求）
void main() {
  List<TodoItem> seed() => [
        TodoItem(id: 'a', text: 'A'),
        TodoItem(id: 'b', text: 'B'),
        TodoItem(id: 'c', text: 'C'),
        TodoItem(id: 'd', text: 'D'),
      ];

  List<String> texts(List<TodoItem> items) =>
      items.map((item) => item.text).toList();

  test('勾第一条 → 浮到最上面', () {
    final next = toggleTodoDone(seed(), 'c');
    expect(texts(next), ['C', 'A', 'B', 'D']);
    expect(next.first.done, isTrue);
  });

  test('再勾一条 → 跟在上一条之后（不是插到最前面）', () {
    var items = toggleTodoDone(seed(), 'c'); // C
    items = toggleTodoDone(items, 'a'); // A 应排在 C 之后
    expect(texts(items), ['C', 'A', 'B', 'D']);
    items = toggleTodoDone(items, 'd');
    expect(texts(items), ['C', 'A', 'D', 'B']);
    expect(items.take(3).every((item) => item.done), isTrue);
    expect(items.last.done, isFalse);
  });

  test('取消勾选 → 退回末尾，不打乱其它相对顺序', () {
    var items = toggleTodoDone(seed(), 'b'); // B A C D
    items = toggleTodoDone(items, 'c'); // B C A D
    expect(texts(items), ['B', 'C', 'A', 'D']);
    items = toggleTodoDone(items, 'b'); // 取消 B
    expect(texts(items), ['C', 'A', 'D', 'B']);
    expect(items.last.done, isFalse);
  });

  test('已完成区始终连续，未完成区保持原有相对顺序', () {
    var items = seed();
    for (final id in ['d', 'a', 'c']) {
      items = toggleTodoDone(items, id);
    }
    expect(texts(items), ['D', 'A', 'C', 'B']);
    expect(items.take(3).every((item) => item.done), isTrue);
  });

  test('id 不存在时原样返回（防并发下的脏输入）', () {
    final items = seed();
    expect(texts(toggleTodoDone(items, 'nope')), ['A', 'B', 'C', 'D']);
  });

  test('全部勾完再全部取消，顺序恢复为未完成区顺序', () {
    var items = seed();
    for (final id in ['a', 'b', 'c', 'd']) {
      items = toggleTodoDone(items, id);
    }
    expect(texts(items), ['A', 'B', 'C', 'D']);
    for (final id in ['c', 'a', 'd', 'b']) {
      items = toggleTodoDone(items, id);
    }
    expect(texts(items), ['C', 'A', 'D', 'B']);
    expect(items.any((item) => item.done), isFalse);
  });
}
