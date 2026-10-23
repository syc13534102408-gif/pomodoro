import 'models.dart';

/// 日程文本的解析与合并（纯 Dart，不依赖 Flutter，可单测）。
///
/// 为什么单独一个文件：**日程的日期键必须与"现在几点"解耦**。
/// `todos` 是按天存的 `Map<日期键, List<TodoItem>>`，而仓库里所有既有写操作
/// 都用 `dateKey(DateTime.now())`——统计日以凌晨 3 点分界，意味着 10/24 的
/// 00:00–02:59 写入会落到 `2026-10-23`。日程必须按**目标日**算键
/// （`ymdOf(目标日)`），否则用户在凌晨排明天，任务会掉进昨天。
///
/// 输入格式（一行一条，`#` 开头为注释，空行忽略）：
///
/// ```
/// 10/24 2018 数一复盘 · 18(2) 重做 + 22、23 盲算
/// 2026-10-25<TAB>现控 ch5 下半 + ch6 全（收尾）
/// 10-31  错题归并
/// ```
///
/// 日期支持 `M/D`、`M-D`、`YYYY-M-D`、`YYYY/M/D`；年月日与正文之间用
/// **制表符或多个空格**更好，单个空格也接受（首个空白段之后全部算正文）。
class PlanEntry {
  const PlanEntry({required this.dayKey, required this.text});

  /// 目标日的自然日键 `YYYY-MM-DD`（**不是**统计日口径）。
  final String dayKey;
  final String text;

  @override
  String toString() => '$dayKey $text';
}

/// 解析结果：按日期分组的条目 + 被跳过的行（带原因，供预览展示）。
class PlanParseResult {
  const PlanParseResult({required this.byDay, required this.skipped});

  final Map<String, List<String>> byDay;

  /// 形如 `第 3 行：无法识别日期`，导入前必须原样展示给用户。
  final List<String> skipped;

  int get total => byDay.values.fold(0, (sum, items) => sum + items.length);

  int get dayCount => byDay.length;

  bool get isEmpty => total == 0;
}

/// 合并结果：新 todos + 实际新增条数 + 因重复被跳过的条数。
class PlanMergeResult {
  const PlanMergeResult({
    required this.todos,
    required this.added,
    required this.duplicated,
  });

  final Map<String, List<TodoItem>> todos;
  final int added;
  final int duplicated;
}

final RegExp _fullDate = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})\s+(.*)$');
final RegExp _shortDate = RegExp(r'^(\d{1,2})[-/](\d{1,2})\s+(.*)$');

/// 解析一段日程文本。[now] 只用于**推断年份**（没写年份时）与跨年回绕，
/// 绝不参与"把条目归到哪一天"的计算。
PlanParseResult parsePlan(String text, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final byDay = <String, List<String>>{};
  final skipped = <String>[];
  final seen = <String>{};
  final lines = text.split('\n');

  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i].trim();
    if (raw.isEmpty || raw.startsWith('#')) continue;

    DateTime? day;
    String body = '';

    final full = _fullDate.firstMatch(raw);
    if (full != null) {
      day = _safeDate(
        int.parse(full.group(1)!),
        int.parse(full.group(2)!),
        int.parse(full.group(3)!),
      );
      body = full.group(4)!;
    } else {
      final short = _shortDate.firstMatch(raw);
      if (short != null) {
        final month = int.parse(short.group(1)!);
        final dayOfMonth = int.parse(short.group(2)!);
        final year = _inferYear(month, clock);
        day = _safeDate(year, month, dayOfMonth);
        body = short.group(3)!;
      }
    }

    if (day == null) {
      skipped.add('第 ${i + 1} 行：无法识别日期 → $raw');
      continue;
    }
    body = body.trim();
    if (body.isEmpty) {
      skipped.add('第 ${i + 1} 行：只有日期没有内容');
      continue;
    }

    final key = ymdOf(day);
    if (!seen.add('$key\u0000$body')) continue; // 同一天同一句：文本内天然去重
    byDay.putIfAbsent(key, () => <String>[]).add(body);
  }

  return PlanParseResult(byDay: byDay, skipped: skipped);
}

/// 没写年份时的推断：默认取当前年；若月日已经"过去很久"（超过半年），
/// 视为明年的日程——排 1 月计划时不会掉回今年 1 月。
int _inferYear(int month, DateTime now) {
  final candidate = DateTime(now.year, month, 1);
  final threshold = DateTime(now.year, now.month, 1)
      .subtract(const Duration(days: 183));
  return candidate.isBefore(threshold) ? now.year + 1 : now.year;
}

/// 非法日期（2 月 30 日、13 月）返回 null，交给上层作为跳过行展示。
DateTime? _safeDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// 把解析结果并进现有 todos：**幂等**（同日同文本视为重复）、保留原条目与勾选状态、
/// 新条目追加在当天末尾（保持文本里的顺序）。
PlanMergeResult mergePlanIntoTodos(
  Map<String, List<TodoItem>> todos,
  PlanParseResult plan,
) {
  final next = <String, List<TodoItem>>{
    for (final entry in todos.entries) entry.key: List<TodoItem>.of(entry.value),
  };
  var added = 0;
  var duplicated = 0;

  for (final entry in plan.byDay.entries) {
    final items = next.putIfAbsent(entry.key, () => <TodoItem>[]);
    final existingTexts = items.map((item) => item.text).toSet();
    for (final text in entry.value) {
      if (existingTexts.contains(text)) {
        duplicated++;
        continue;
      }
      items.add(TodoItem(text: text));
      existingTexts.add(text);
      added++;
    }
  }

  return PlanMergeResult(todos: next, added: added, duplicated: duplicated);
}

/// 未来日期的键是否会被"只留最近 N 天"之类的清理逻辑吃掉——目前没有这种逻辑，
/// 这条断言函数留给单测与将来的代码评审一个显式的锚点。
bool hasFuturePlan(Map<String, List<TodoItem>> todos, DateTime now) {
  final today = ymdOf(dayStart(now));
  return todos.keys.any((key) => key.compareTo(today) > 0 && todos[key]!.isNotEmpty);
}
