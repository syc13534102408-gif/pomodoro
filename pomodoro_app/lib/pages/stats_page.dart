import 'package:flutter/material.dart';

import '../src/engine.dart';
import '../src/models.dart';
import '../src/theme.dart';
import '../src/widgets.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.data});

  final AppData data;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  /// 0 = 本周，1 = 上周（只影响顶部聚合与分布，本月回顾始终为当前自然月）。
  int _weekOffset = 0;

  AppData get data => widget.data;

  Color _colorFor(String taskName) {
    for (final task in data.tasks) {
      if (task.name == taskName) return task.swatch;
    }
    return PineColors.sub;
  }

  /// 本周/上周七天的分色堆叠数据（周一至周日）。
  List<List<BrickBarSegment>> _stacks(StatsView stats) {
    final rows = <List<BrickBarSegment>>[];
    for (var day = 0; day < 7; day++) {
      final row = stats.weekTaskTotals[day];
      if (row == null || row.isEmpty) {
        rows.add(const <BrickBarSegment>[]);
        continue;
      }
      final entries = row.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      rows.add(<BrickBarSegment>[
        for (final entry in entries)
          BrickBarSegment(value: entry.value, color: _colorFor(entry.key)),
      ]);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final viewNow = today.subtract(Duration(days: 7 * _weekOffset));
    final stats = StatsView.of(data, viewNow);
    // 只看上周时不再标「今」。
    final todayIndex = _weekOffset == 0 ? today.weekday - 1 : -1;
    final maxY = _niceMax(stats.maxDay());
    final legend = stats.tasksInWeek();
    final weekTotal = stats.weekMinutes;

    return Scaffold(
      appBar: AppBar(title: const Text('专注报告')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        children: [
          // 周期切换：本周 / 上周。
          Row(
            children: [
              _periodChip('本周', 0),
              const SizedBox(width: 8),
              _periodChip('上周', 1),
            ],
          ),
          const SizedBox(height: 12),
          // 汇总便签（R1：周目标按「次」，N / 20 个番茄）。
          BrickCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('本周累计 · 已专注',
                    style:
                        TextStyle(color: PineColors.sub, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  formatMinutes(stats.weekMinutes),
                  style: brickNumberStyle(fontSize: 30),
                ),
                const SizedBox(height: 8),
                Text(
                  _weekGoalCaption(stats),
                  style: brickNumberStyle(
                      fontSize: 12, color: PineColors.sub),
                ),
                const SizedBox(height: 10),
                BrickProgress(
                  value: data.weekGoal <= 0
                      ? 0
                      : (stats.weekCount / data.weekGoal).clamp(0.0, 1.0),
                  color: PineColors.gold,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _MonthlyReview(data: data),
          const SizedBox(height: 16),
          BrickCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  title: '每周分布',
                  trailing: Text(
                    '单位：分钟',
                    style: TextStyle(color: PineColors.sub, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 12),
                BrickBars(
                  stacks: _stacks(stats),
                  maxY: maxY,
                  todayIndex: todayIndex,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          BrickCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: '事件构成'),
                const SizedBox(height: 8),
                if (legend.isEmpty)
                  const Text(
                    '本周还没有专注记录',
                    style: TextStyle(color: PineColors.sub, fontSize: 12),
                  )
                else
                  for (final name in legend)
                    _LegendRow(
                      name: name,
                      minutes: _totalForTask(stats, name),
                      percent: weekTotal <= 0
                          ? 0
                          : _totalForTask(stats, name) / weekTotal,
                      color: _colorFor(name),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _weekGoalCaption(StatsView stats) {
    final goal = data.weekGoal;
    final count = stats.weekCount;
    final remain = goal - count;
    return remain > 0
        ? '本周 $count / $goal 个番茄 · 还差 $remain 个'
        : '本周 $count / $goal 个番茄 · 已达成';
  }

  Widget _periodChip(String label, int offset) {
    final selected = _weekOffset == offset;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _weekOffset = offset),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? PineColors.tint(PineColors.pine)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? PineColors.pine : PineColors.sub,
            ),
          ),
        ),
      ),
    );
  }

  double _totalForTask(StatsView stats, String name) {
    var total = 0.0;
    for (final row in stats.weekTaskTotals.values) {
      final value = row[name];
      if (value != null) total += value;
    }
    return total;
  }

  /// 纵轴上限取整到易读档位，避免低数据量时刻度出现小数。
  double _niceMax(double value) {
    if (value <= 0) return 10;
    const steps = <double>[10, 20, 30, 60, 120, 180, 300, 480, 720, 1440];
    for (final step in steps) {
      if (value <= step * 0.8) return step;
    }
    return (value * 1.25);
  }
}

/// 图例行：色点（圆，无描边）+ 名称 + 时长 + 等宽百分比。
class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.name,
    required this.minutes,
    required this.percent,
    required this.color,
  });

  final String name;
  final double minutes;
  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PineColors.ink, fontSize: 12),
            ),
          ),
          Text(
            formatMinutes(minutes),
            style: brickNumberStyle(fontSize: 11, color: PineColors.sub),
          ),
          const SizedBox(width: 10),
          Text(
            '${(percent * 100).round()}%',
            style: brickNumberStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// 本月回顾：累计/次数/日均/天数 + 月历打卡格（底色=分钟、数字=番茄数）
/// + 按事件分布。纯 UI 只读（D2），不改 engine 周聚合逻辑。
class _MonthlyReview extends StatelessWidget {
  const _MonthlyReview({required this.data});

  final AppData data;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // 月历按「统计日」分桶：直接用记录的归属日键（dayKey，凌晨 3 点分界），
    // 不用 record.at——at 可能是恢复时合成的零点占位值（00:00），按 at 分桶
    // 会把整天的记录错分到前一天（2026-09-10 数据事故根因之一）。
    final statNow = statDayOf(now);
    final ym = '${statNow.year}-${statNow.month.toString().padLeft(2, '0')}';
    final monthRecords = data.records.where((record) =>
        record.counted && record.dayKey.startsWith(ym)).toList();
    final minutes = monthRecords.fold<double>(0, (sum, r) => sum + r.minutes);
    // 番茄数统一走时长当量（满 50 分钟 1 个，缺口不足 15 分钟补齐）。
    final count = pomodoroEquiv(minutes);
    final activeDays = monthRecords.map((r) => r.dayKey.substring(8)).toSet().length;
    final daysInMonth = DateTime(statNow.year, statNow.month + 1, 0).day;
    final dayValues = List<double>.filled(daysInMonth, 0);
    final byTask = <String, double>{};
    for (final record in monthRecords) {
      final day = int.parse(record.dayKey.substring(8, 10));
      dayValues[day - 1] += record.minutes;
      byTask[record.taskName] = (byTask[record.taskName] ?? 0) + record.minutes;
    }
    // 格内数字 = 当日番茄当量（按当日总分钟换算，非记录条数）。
    final dayCounts = [
      for (final m in dayValues) pomodoroEquiv(m),
    ];
    final monthName = '${statNow.year}年${statNow.month}月';
    final tasks = byTask.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final taskPeak = tasks.isEmpty ? 1.0 : tasks.first.value;

    return BrickCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: '本月回顾',
            trailing: Text(
              monthName,
              style: const TextStyle(color: PineColors.sub, fontSize: 11),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  value: formatMinutes(minutes),
                  label: '本月累计',
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: '$count 次',
                  label: '完成次数',
                  accent: PineColors.pine,
                ),
              ),
              Expanded(
                child: MetricTile(
                  // 日均只除以有学习的天数：完全没学的一天不计入分母。
                  value: activeDays > 0
                      ? '${(minutes / activeDays).round()} 分'
                      : '0 分',
                  label: '日均(学习日)',
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: '$activeDays 天',
                  label: '专注天数',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Text(
                '月历打卡',
                style: TextStyle(color: PineColors.sub, fontSize: 11),
              ),
              Spacer(),
              Text(
                '底色=时长 · 数字=番茄数',
                style: TextStyle(color: PineColors.sub, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MonthGrid(
            year: statNow.year,
            month: statNow.month,
            dayValues: dayValues,
            dayCounts: dayCounts,
            todayDay: statNow.day,
          ),
          if (tasks.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              '$monthName 按事件',
              style: const TextStyle(color: PineColors.sub, fontSize: 11),
            ),
            const SizedBox(height: 10),
            for (final entry in tasks) ...[
              _TaskBar(
                name: entry.key,
                minutes: entry.value,
                max: taskPeak,
                color: _colorFor(entry.key),
              ),
              const SizedBox(height: 10),
            ],
          ] else ...[
            const SizedBox(height: 14),
            const Text(
              '本月还没有专注记录',
              style: TextStyle(color: PineColors.sub, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Color _colorFor(String taskName) {
    for (final task in data.tasks) {
      if (task.name == taskName) return task.swatch;
    }
    return PineColors.sub;
  }
}

/// 月历打卡格：7 列（周一为第一列），每月首日按实际星期对齐；
/// 底色 = 当日专注分钟（松绿色阶），格内数字 = 当日番茄数，今日带松绿描边。
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.year,
    required this.month,
    required this.dayValues,
    required this.dayCounts,
    required this.todayDay,
  });

  final int year;
  final int month;
  final List<double> dayValues;
  final List<int> dayCounts;
  final int todayDay;

  static const List<String> _week = ['一', '二', '三', '四', '五', '六', '日'];

  /// 松绿离散色阶（4 档）：直接叠在卡纸白上，档间明度差拉开到人眼可辨，
  /// 最深档沉过品牌松绿并配白字。旧实现用 α=90–240 连续叠色，最浅档与
  /// 卡底几乎同色、最深档仍浅于松绿，深浅阶梯看不清。
  static const List<Color> _ramp = [
    Color(0xFFD6E5DA), // 1 档 · 浅纸绿（有记录）
    Color(0xFF97C0A6), // 2 档
    Color(0xFF4E7A5B), // 3 档 · 品牌松绿
    Color(0xFF3B5D47), // 4 档 · 深林绿（配白字）
  ];

  /// 时长 → 档位（0 = 无记录）。桶宽大致对齐 25/50 分钟番茄节奏，
  /// 让「1 档≈1 个番茄」这类直觉成立。
  int _step(double minutes) {
    if (minutes <= 0) return 0;
    if (minutes <= 45) return 1;
    if (minutes <= 135) return 2;
    if (minutes <= 240) return 3;
    return 4;
  }

  Color _level(double minutes) {
    final s = _step(minutes);
    return s == 0 ? Colors.transparent : _ramp[s - 1];
  }

  /// 深档（3、4 档，底接近/深于松绿）用白字 + 纸白描边；
  /// 浅档与空档用墨字 + 松绿描边，保证今日标记在两种底上都可读。
  bool _deep(double minutes) => _step(minutes) >= 3;

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(year, month, 1).weekday; // 1..7（周一起）
    final daysInMonth = DateTime(year, month + 1, 0).day;

    Widget cell(int? day) {
      if (day == null) {
        return const SizedBox(height: 30);
      }
      final minutes = dayValues[day - 1];
      final count = dayCounts[day - 1];
      final isToday = day == todayDay;
      return Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _level(minutes),
          borderRadius: BorderRadius.circular(7),
          border: isToday
              ? Border.all(
                  color: _deep(minutes) ? PineColors.card : PineColors.pine,
                  width: 1.5,
                )
              : null,
        ),
        child: Text(
          '$count',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
            color: _deep(minutes)
                ? PineColors.card
                : (count > 0 ? PineColors.ink : PineColors.sub),
            fontFeatures: kNumericFont,
          ),
        ),
      );
    }

    final cells = <Widget>[
      for (var i = 1; i < firstWeekday; i++) cell(null),
      for (var day = 1; day <= daysInMonth; day++) cell(day),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox(height: 30));
    }

    final rows = <Widget>[];
    for (var start = 0; start < cells.length; start += 7) {
      rows.add(Row(
        children: [
          for (final c in cells.skip(start).take(7)) ...[
            Expanded(child: Padding(padding: const EdgeInsets.all(1.5), child: c)),
          ],
        ],
      ));
    }

    return Column(
      children: [
        Row(
          children: [
            const Spacer(),
            for (var i = 0; i < _ramp.length; i++)
              Container(
                width: 11,
                height: 11,
                margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
                decoration: BoxDecoration(
                  color: _ramp[i],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            const SizedBox(width: 6),
            const Text(
              '时长少 → 多',
              style: TextStyle(color: PineColors.sub, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final w in _week)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: const TextStyle(
                        color: PineColors.sub, fontSize: 10),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        ...rows,
      ],
    );
  }
}

class _TaskBar extends StatelessWidget {
  const _TaskBar({
    required this.name,
    required this.minutes,
    required this.max,
    required this.color,
  });

  final String name;
  final double minutes;
  final double max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = max <= 0 ? 0.0 : (minutes / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PineColors.ink, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatMinutes(minutes),
              style: brickNumberStyle(fontSize: 12, color: PineColors.sub),
            ),
          ],
        ),
        const SizedBox(height: 8),
        BrickProgress(value: ratio, color: color),
      ],
    );
  }
}
