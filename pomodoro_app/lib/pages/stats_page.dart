import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../src/engine.dart';
import '../src/models.dart';
import '../src/theme.dart';
import '../src/widgets.dart';

const List<String> _weekLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

class StatsPage extends StatelessWidget {
  const StatsPage({super.key, required this.data});

  final AppData data;

  Color _colorFor(String taskName) {
    for (final task in data.tasks) {
      if (task.name == taskName) return task.swatch;
    }
    return PineColors.muted;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final stats = StatsView.of(data, now);
    final todayIndex = now.weekday - 1;
    final maxY = _niceMax(stats.maxDay());
    final legend = stats.tasksInWeek();

    return Scaffold(
      appBar: AppBar(title: const Text('专注报告')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '本周累计',
                      style: TextStyle(color: PineColors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatMinutes(stats.weekMinutes),
                      style: const TextStyle(
                        color: PineColors.ink,
                        fontSize: 30,
                        height: 1.1,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${stats.weekCount} / ${data.weekGoal} 次',
                style: const TextStyle(
                  color: PineColors.gold,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: data.weekGoal <= 0
                  ? 0
                  : (stats.weekCount / data.weekGoal).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: PineColors.ink.withValues(alpha: 0.09),
              valueColor: const AlwaysStoppedAnimation(PineColors.gold),
            ),
          ),
          const SizedBox(height: 22),
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  title: '本周专注时长',
                  trailing: Text(
                    '周一至周日',
                    style: TextStyle(color: PineColors.muted, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 240,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxY,
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY / 2,
                        getDrawingHorizontalLine: (_) => const FlLine(
                          color: PineColors.line,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                            interval: maxY / 2,
                            getTitlesWidget: (value, meta) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(
                                '${value.toInt()}m',
                                style: const TextStyle(
                                  color: PineColors.muted,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index > 6) {
                                return const SizedBox();
                              }
                              final isToday = index == todayIndex;
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _weekLabels[index],
                                  style: TextStyle(
                                    color: isToday
                                        ? PineColors.gold
                                        : PineColors.muted,
                                    fontSize: 11,
                                    fontWeight: isToday
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < 7; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: stats.totalForDay(i),
                                width: 26,
                                borderRadius: BorderRadius.zero,
                                color: PineColors.tomato,
                                rodStackItems: _stackFor(stats, i),
                              ),
                            ],
                          ),
                      ],
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => PineColors.panel,
                          tooltipRoundedRadius: 8,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final total = stats.totalForDay(group.x);
                            return BarTooltipItem(
                              '${_weekLabels[group.x]}\n',
                              const TextStyle(
                                color: PineColors.muted,
                                fontSize: 11,
                              ),
                              children: [
                                TextSpan(
                                  text: formatMinutes(total),
                                  style: const TextStyle(
                                    color: PineColors.ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                if (legend.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (final name in legend)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: _colorFor(name),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              name,
                              style: const TextStyle(
                                color: PineColors.paper,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _MonthlyReview(data: data),
          const SizedBox(height: 14),
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: '本周事件分布'),
                const SizedBox(height: 12),
                if (legend.isEmpty)
                  const Text(
                    '本周还没有专注记录',
                    style: TextStyle(color: PineColors.muted, fontSize: 12),
                  )
                else
                  for (final name in legend) ...[
                    _TaskBar(
                      name: name,
                      minutes: _totalForTask(stats, name),
                      max: legend.fold<double>(
                        0,
                        (max, item) {
                          final value = _totalForTask(stats, item);
                          return value > max ? value : max;
                        },
                      ),
                      color: _colorFor(name),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<BarChartRodStackItem> _stackFor(StatsView stats, int day) {
    final row = stats.weekTaskTotals[day];
    if (row == null || row.isEmpty) return const [];
    final entries = row.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final items = <BarChartRodStackItem>[];
    var cursor = 0.0;
    for (final entry in entries) {
      final next = cursor + entry.value;
      items.add(BarChartRodStackItem(
        cursor,
        next,
        _colorFor(entry.key),
      ));
      cursor = next;
    }
    return items;
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

/// 本月回顾：累计/次数/日均 + 本月逐日条 + 按事件分布。
/// 直接在统计页内计算，不改动 engine 的周聚合逻辑。
class _MonthlyReview extends StatelessWidget {
  const _MonthlyReview({required this.data});

  final AppData data;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthRecords = data.records.where((record) =>
        record.counted &&
        record.at.year == now.year &&
        record.at.month == now.month);
    final minutes = monthRecords.fold<double>(0, (sum, r) => sum + r.minutes);
    final count = monthRecords.length;
    final activeDays = monthRecords.map((r) => r.at.day).toSet().length;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final dayValues = List<double>.filled(daysInMonth, 0);
    final byTask = <String, double>{};
    for (final record in monthRecords) {
      dayValues[record.at.day - 1] += record.minutes;
      byTask[record.taskName] = (byTask[record.taskName] ?? 0) + record.minutes;
    }
    final monthName = '${now.year}年${now.month}月';
    final peak = dayValues.reduce((a, b) => a > b ? a : b);
    final tasks = byTask.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final taskPeak = tasks.isEmpty ? 1.0 : tasks.first.value;

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: '本月回顾',
            trailing: Text(
              monthName,
              style: const TextStyle(color: PineColors.muted, fontSize: 11),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  value: formatMinutes(minutes),
                  label: '本月累计',
                  accent: PineColors.tomato,
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: '$count 次',
                  label: '完成次数',
                  accent: PineColors.gold,
                ),
              ),
              Expanded(
                child: MetricTile(
                  value:
                      '${(minutes / (now.day == 0 ? 1 : now.day)).round()} 分',
                  label: '日均(本月)',
                  accent: PineColors.mint,
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
          const SizedBox(height: 16),
          Text(
            '$monthName 逐日',
            style: const TextStyle(color: PineColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var day = 0; day < daysInMonth; day++) ...[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Container(
                        decoration: BoxDecoration(
                          color: dayValues[day] > 0
                              ? PineColors.tomato
                              : PineColors.line.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                        height:
                            peak <= 0 ? 3 : 4 + (dayValues[day] / peak) * 48,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (tasks.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              '$monthName 按事件',
              style: const TextStyle(color: PineColors.muted, fontSize: 11),
            ),
            const SizedBox(height: 10),
            for (final entry in tasks) ...[
              _TaskBar(
                name: entry.key,
                minutes: entry.value,
                max: taskPeak,
                color: _colorFor(entry.key),
              ),
              const SizedBox(height: 8),
            ],
          ] else ...[
            const SizedBox(height: 14),
            const Text(
              '本月还没有专注记录',
              style: TextStyle(color: PineColors.muted, fontSize: 12),
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
    return PineColors.muted;
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
                style: const TextStyle(color: PineColors.paper, fontSize: 13),
              ),
            ),
            Text(
              formatMinutes(minutes),
              style: const TextStyle(color: PineColors.ink, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 7,
            backgroundColor: PineColors.ink.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
