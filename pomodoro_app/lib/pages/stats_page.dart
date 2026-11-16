import 'package:flutter/material.dart';

import '../src/engine.dart';
import '../src/models.dart';
import '../src/sheets.dart';
import '../src/theme.dart';
import '../src/widgets.dart';

/// 专注报告（2026-11-16 整页化 + 重新装帧）。
///
/// 两套版式共用同一份取数与同一套纸阶，差别只在「信息如何组织」：
/// - 窄屏（< 720）：**R4 功课册** —— 一条嗓子读到底：总量 → 本周 → 七日 →
///   科目 → 本月 → 最近；
/// - 桌面（≥ 720）：**R5 图谱** —— 卷首横排 + 里程碑印盒、带轴的墨柱图、
///   科目台账（本周/上周/增减）、月历与明细并排、右缘竖排边注。
///
/// 装帧部件（书眉、分节记号、点线引导、双线收口、印章、折角内框）都在本文件里，
/// 因为它们只服务这一页；通用纸件仍走 `suzhi.dart`。
///
/// 取数口径与统计页旧版一致：只计 `counted` 记录，进行中的专注实时计入今日/本周。
class StatsPage extends StatefulWidget {
  const StatsPage({
    super.key,
    required this.data,
    required this.onChanged,
    this.onBack,
  });

  final AppData data;
  final ValueChanged<AppData> onChanged;

  /// 非空时书眉左侧出现「←」：手机端是返回上一页，桌面整页是退回日课。
  final VoidCallback? onBack;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  /// 本月回顾的月份偏移：0 = 当月，-1 = 上月。
  int _monthOffset = 0;

  AppData get data => widget.data;
  ValueChanged<AppData> get onChanged => widget.onChanged;
  VoidCallback? get onBack => widget.onBack;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final model = _ReportModel.of(data, DateTime.now(), _monthOffset);
    // 桌面整页是直接塞进 Stack 的，没有 Scaffold/Material 祖先；
    // 翻月、补记、事件行都要 Material 才能响应水波，所以在这里兜一层。
    return Material(
      color: PineColors.paper,
      child: wide ? _wide(context, model) : _narrow(context, model),
    );
  }

  // ==================== R4 · 功课册（窄屏） ====================

  Widget _narrow(BuildContext context, _ReportModel m) {
    final now = m.now;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      children: [
        _RunningHead(left: '松果 · 专注报告', right: '${now.year} / 第 ${m.weekNo} 周', onBack: onBack),
        const SizedBox(height: 16),
        // ── 卷首 ────────────────────────────────────────────────
        _HeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('专注报告',
                            style: PineText.serif(size: 26, weight: FontWeight.w600)),
                        const SizedBox(height: 5),
                        Text(
                          '${now.month} 月 ${now.day} 日 ${_weekCn(now.weekday)}',
                          style: PineText.mono(size: 10, color: PineColors.ink3)
                              .copyWith(letterSpacing: 1.2),
                        ),
                      ],
                    ),
                  ),
                  const SealStamp(text: '勤', solid: true, size: 26),
                ],
              ),
              const SizedBox(height: 12),
              _BigHours(
                minutes: m.stats.totalMinutes,
                size: 44,
              ),
              const SizedBox(height: 12),
              _MetaRow(items: [
                ('学 习 日', '${m.stats.totalDays}'),
                ('番 茄', '${m.stats.totalTomatoes}'),
                ('连 续', '${m.stats.streak} 日'),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 22),
        // ── 一 · 本周 ───────────────────────────────────────────
        SectionMark(no: '一', title: '本周', note: '第 ${m.weekNo} 周'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _BigHours(minutes: m.weekMinutes, size: 30),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: _Delta(minutes: m.weekDelta),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('枚 ${m.stats.weekCount} / ${m.data.weekGoal}',
                    style: PineText.mono(size: 10, color: PineColors.ink3)),
                const SizedBox(height: 4),
                _TomatoTicks(count: m.stats.weekCount, goal: m.data.weekGoal),
              ],
            ),
          ],
        ),
        const SizedBox(height: 9),
        _GoalBar(value: m.stats.weekCount / (m.data.weekGoal <= 0 ? 1 : m.data.weekGoal)),
        const SizedBox(height: 22),
        // ── 二 · 近七日 ─────────────────────────────────────────
        SectionMark(no: '二', title: '近七日', note: '单日最高 ${formatCompactMinutes(m.bestDay)}'),
        for (final day in m.days) _DayRow(day: day, colors: m.colors, maxMinutes: m.bestDay),
        const SizedBox(height: 8),
        _Legend(names: m.legend, colors: m.colors),
        const SizedBox(height: 22),
        // ── 三 · 科目 ───────────────────────────────────────────
        const SectionMark(no: '三', title: '科目', note: '全部历史'),
        _SubjectTable(m: m, compact: true),
        const SizedBox(height: 22),
        // ── 四 · 本月印记 ───────────────────────────────────────
        SectionMark(
          no: '四',
          title: '本月回顾',
          action: _MonthSwitch(
            label: '${m.monthAnchor.year} 年 ${m.monthAnchor.month} 月',
            onPrev: () => setState(() => _monthOffset--),
            onNext: () => setState(() => _monthOffset++),
          ),
        ),
        _MonthSummary(m: m),
        const SizedBox(height: 10),
        _MonthSeals(m: m),
        if (m.monthTotal <= 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('本月还没有专注记录',
                style: PineText.serif(size: 11.5, color: PineColors.ink3)),
          ),
        const SizedBox(height: 22),
        // ── 五 · 最近落账 ───────────────────────────────────────
        SectionMark(
          no: '五',
          title: '最近落账',
          note: '今日 ${m.todayCount} 条',
          action: _SmallAction(
            label: '＋ 补记',
            onTap: () => showManualSheet(
                context, data: data, onChanged: onChanged),
          ),
        ),
        for (final record in m.recent.take(5)) _RecentRow(record: record, compact: true),
        const SizedBox(height: 22),
        // ── 六 · 事件进展 ───────────────────────────────────────
        const SectionMark(no: '六', title: '事件进展', note: '跨轮次的累计容器'),
        _EventsSection(
          data: data,
          onChanged: onChanged,
          colorFor: (name) => m.colors[name] ?? PineColors.inkFaint,
        ),
        const SizedBox(height: 18),
        const _RunningFoot(note: '口径：已完成的专注记录，含手动补记', page: '1 / 1'),
      ],
    );
  }

  // ==================== R5 · 图谱（桌面） ====================

  Widget _wide(BuildContext context, _ReportModel m) {
    final now = m.now;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
      children: [
        _RunningHead(
          left: '松果 · 专注报告',
          right: '${now.year} 年 ${now.month} 月 ${now.day} 日 · 第 ${m.weekNo} 周 · 第 1 页',
          onBack: onBack,
        ),
        const SizedBox(height: 16),
        // ── 卷首 + 里程碑 ──────────────────────────────────────
        // ListView 里高度无界，stretch 的 Row 必须先拿到确定高度。
        IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _HeroCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('专注报告',
                                  style: PineText.serif(
                                      size: 26, weight: FontWeight.w600)),
                              const SizedBox(height: 5),
                              Text(
                                '自 ${m.firstDayLabel} 起 · ${now.month} 月 ${now.day} 日',
                                style: PineText.mono(size: 10, color: PineColors.ink3)
                                    .copyWith(letterSpacing: 1.2),
                              ),
                            ],
                          ),
                        ),
                        const SealStamp(text: '勤', solid: true, size: 26),
                        const SizedBox(width: 6),
                        const SealStamp(text: '持', size: 26),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _BigHours(minutes: m.stats.totalMinutes, size: 44),
                        const SizedBox(width: 18),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('日 均',
                                  style: PineText.serif(
                                      size: 8.5, color: PineColors.ink3)
                                      .copyWith(letterSpacing: 2)),
                              const SizedBox(height: 2),
                              Text(
                                formatCompactMinutes(m.stats.totalDays <= 0
                                    ? 0
                                    : m.stats.totalMinutes / m.stats.totalDays),
                                style: PineText.mono(size: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _MetaRow(items: [
                      ('学 习 日', '${m.stats.totalDays}'),
                      ('番 茄', '${m.stats.totalTomatoes}'),
                      ('连 续', '${m.stats.streak} 日'),
                      ('周 最 高', formatCompactMinutes(m.bestDay)),
                    ], maxWidth: 420),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(width: 210, child: _MilestoneCard(totalMinutes: m.stats.totalMinutes)),
          ],
        ),
        ),
        const SizedBox(height: 24),
        // ── 一 · 近七日 ────────────────────────────────────────
        const SectionMark(no: '一', title: '近七日', note: '按科目堆叠 · 单位 分钟'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _InkAxisChart(days: m.days, colors: m.colors, maxMinutes: m.maxAxisMinutes),
            ),
            const SizedBox(width: 22),
            SizedBox(width: 176, child: _WeekSidecard(m: m)),
          ],
        ),
        const SizedBox(height: 24),
        // ── 二 · 科目台账 ──────────────────────────────────────
        const SectionMark(no: '二', title: '科目台账', note: '近七日 / 全部历史'),
        _SubjectTable(m: m, compact: false),
        const SizedBox(height: 24),
        // ── 三 / 四 并排 ───────────────────────────────────────
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 268,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionMark(
                      no: '三',
                      title: '本月回顾',
                      action: _MonthSwitch(
                        label: '${m.monthAnchor.month} 月',
                        onPrev: () => setState(() => _monthOffset--),
                        onNext: () => setState(() => _monthOffset++),
                      ),
                    ),
                    _MonthSummary(m: m),
                    const SizedBox(height: 8),
                    _MonthSeals(m: m, showNote: true),
                    if (m.monthTotal <= 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('本月还没有专注记录',
                            style: PineText.serif(
                                size: 11, color: PineColors.ink3)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionMark(no: '四', title: '最近落账', note: '最近十条中的前五'),
                    for (final record in m.recent.take(5))
                      _RecentRow(record: record, compact: false),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 18,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _VerticalNote(text: m.marginNote),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SectionMark(no: '五', title: '事件进展', note: '跨轮次的累计容器'),
        _EventsSection(
          data: data,
          onChanged: onChanged,
          colorFor: (name) => m.colors[name] ?? PineColors.inkFaint,
        ),
        const SizedBox(height: 24),
        const _RunningFoot(note: '全部口径：已完成的专注记录，含手动补记', page: '1 / 1'),
      ],
    );
  }
}

// ============================================================================
// 取数
// ============================================================================

class _ReportModel {
  _ReportModel({
    required this.data,
    required this.now,
    required this.stats,
    required this.days,
    required this.subjects,
    required this.recent,
    required this.colors,
    required this.legend,
    required this.weekMinutes,
    required this.weekDelta,
    required this.bestDay,
    required this.maxAxisMinutes,
    required this.todayCount,
    required this.firstDayLabel,
    required this.marginNote,
    required this.monthDayMinutes,
    required this.monthActiveDays,
    required this.monthBest,
    required this.monthAnchor,
  });

  final AppData data;
  final DateTime now;
  final StatsView stats;
  final List<_DayCell> days;
  final List<_SubjectRow> subjects;
  final List<FocusRecord> recent;
  final Map<String, Color> colors;
  final List<String> legend;
  final double weekMinutes;
  final double weekDelta;
  final double bestDay;
  final double maxAxisMinutes;
  final int todayCount;
  final String firstDayLabel;
  final String marginNote;
  final Map<int, double> monthDayMinutes;
  final int monthActiveDays;
  final double monthBest;
  final DateTime monthAnchor;

  double get monthTotal =>
      monthDayMinutes.values.fold<double>(0, (a, b) => a + b);

  int get weekNo => isoWeekNumber(now);

  static _ReportModel of(AppData data, DateTime now, int monthOffset) {
    final monthAnchor = DateTime(now.year, now.month + monthOffset, 1);
    final stats = StatsView.of(data, now);
    final statToday = statDayOf(now);
    final monday = mondayOf(statToday);
    final counted = data.records.where((r) => r.counted).toList();

    // 科目配色：优先用任务自己的颜色，没配过就按出现顺序取调色板。
    final colorOf = <String, Color>{};
    for (final task in data.tasks) {
      colorOf[task.name] = Color(task.color);
    }
    final order = <String>[];
    for (final record in counted) {
      if (!order.contains(record.taskName)) order.add(record.taskName);
    }
    final colors = <String, Color>{};
    for (var i = 0; i < order.length; i++) {
      colors[order[i]] = colorOf[order[i]] ??
          kTaskPalette[i % kTaskPalette.length];
    }

    // 七日
    final days = <_DayCell>[];
    final week = ['一', '二', '三', '四', '五', '六', '日'];
    var bestDay = 0.0;
    for (var i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final key = ymdOf(date);
      final perTask = <String, double>{};
      for (final record in counted) {
        if (record.dayKey != key) continue;
        perTask.update(record.taskName, (v) => v + record.minutes,
            ifAbsent: () => record.minutes);
      }
      // 进行中的专注时长由 StatsView 另行计入本周合计；这里不重复累加，
      // 避免「七日柱之和 ≠ 本周合计」。
      final total = perTask.values.fold<double>(0, (a, b) => a + b);
      if (total > bestDay) bestDay = total;
      days.add(_DayCell(
        index: i,
        label: week[i],
        dayOfMonth: date.day,
        month: date.month,
        minutes: total,
        perTask: perTask,
        isToday: i == statToday.difference(monday).inDays,
      ));
    }
    final todayIdx = statToday.difference(monday).inDays;
    if (todayIdx >= 0 && todayIdx < 7) {
      final cell = days[todayIdx];
      if (cell.minutes > bestDay) bestDay = cell.minutes;
    }

    // 上周合计（同口径：上周一到上周日）
    final lastMonday = monday.subtract(const Duration(days: 7));
    var lastWeek = 0.0;
    for (final record in counted) {
      final offset = record.day.difference(lastMonday).inDays;
      if (offset >= 0 && offset < 7) lastWeek += record.minutes;
    }

    // 科目台账
    final totals = <String, double>{};
    final weekTotals = <String, double>{};
    final lastTotals = <String, double>{};
    final lastSeen = <String, DateTime>{};
    final dayCount = <String, Set<String>>{};
    for (final record in counted) {
      totals.update(record.taskName, (v) => v + record.minutes,
          ifAbsent: () => record.minutes);
      dayCount.putIfAbsent(record.taskName, () => <String>{}).add(record.dayKey);
      final offset = record.day.difference(monday).inDays;
      if (offset >= 0 && offset < 7) {
        weekTotals.update(record.taskName, (v) => v + record.minutes,
            ifAbsent: () => record.minutes);
      }
      final lastOffset = record.day.difference(lastMonday).inDays;
      if (lastOffset >= 0 && lastOffset < 7) {
        lastTotals.update(record.taskName, (v) => v + record.minutes,
            ifAbsent: () => record.minutes);
      }
      final seen = lastSeen[record.taskName];
      if (seen == null || record.at.isAfter(seen)) {
        lastSeen[record.taskName] = record.at;
      }
    }
    final grand = totals.values.fold<double>(0, (a, b) => a + b);
    final subjects = totals.entries.map((entry) {
      final days = dayCount[entry.key]!.length;
      return _SubjectRow(
        name: entry.key,
        total: entry.value,
        week: weekTotals[entry.key] ?? 0,
        lastWeek: lastTotals[entry.key] ?? 0,
        studyDays: days,
        share: grand <= 0 ? 0 : entry.value / grand,
      );
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    // 本月回顾（可翻月）
    final monthDays = <int, double>{};
    for (final record in counted) {
      if (record.day.year != monthAnchor.year ||
          record.day.month != monthAnchor.month) {
        continue;
      }
      monthDays.update(record.day.day, (v) => v + record.minutes,
          ifAbsent: () => record.minutes);
    }

    // 最近落账
    final recent = counted.toList()..sort((a, b) => b.at.compareTo(a.at));

    // 图例：本周出现的科目，按分钟降序，最多 4 个
    final weekSorted = weekTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final legend = weekSorted.take(4).map((e) => e.key).toList();

    var monthBest = 0.0;
    for (final minutes in monthDays.values) {
      if (minutes > monthBest) monthBest = minutes;
    }

    final axisMax = _niceAxis(bestDay);
    final firstDay = counted.isEmpty
        ? statToday
        : counted.map((r) => r.day).reduce((a, b) => a.isBefore(b) ? a : b);

    final delta = stats.weekMinutes - lastWeek;
    final todayCount =
        counted.where((r) => r.dayKey == ymdOf(statToday)).length;

    return _ReportModel(
      data: data,
      now: now,
      stats: stats,
      days: days,
      subjects: subjects,
      recent: recent,
      colors: colors,
      legend: legend,
      weekMinutes: stats.weekMinutes,
      weekDelta: delta,
      bestDay: bestDay,
      maxAxisMinutes: axisMax,
      todayCount: todayCount,
      firstDayLabel: '${firstDay.year} 年 ${firstDay.month} 月 ${firstDay.day} 日',
      marginNote: delta >= 0
          ? '本周多 ${formatCompactMinutes(delta)}'
          : '本周少 ${formatCompactMinutes(-delta)}',
      monthDayMinutes: monthDays,
      monthActiveDays: monthDays.length,
      monthBest: monthBest,
      monthAnchor: monthAnchor,
    );
  }

  /// 柱图纵轴：向上取整到 2 小时一档，最少 2 小时。
  static double _niceAxis(double maxMinutes) {
    if (maxMinutes <= 0) return 120;
    final hours = (maxMinutes / 60).ceil();
    return (hours + (hours.isOdd ? 1 : 0)) * 60.0;
  }
}

class _DayCell {
  _DayCell({
    required this.index,
    required this.label,
    required this.dayOfMonth,
    required this.month,
    required this.minutes,
    required this.perTask,
    required this.isToday,
  });

  final int index;
  final String label;
  final int dayOfMonth;
  final int month;
  final double minutes;
  final Map<String, double> perTask;
  final bool isToday;
}

class _SubjectRow {
  _SubjectRow({
    required this.name,
    required this.total,
    required this.week,
    required this.lastWeek,
    required this.studyDays,
    required this.share,
  });

  final String name;
  final double total;
  final double week;
  final double lastWeek;
  final int studyDays;
  final double share;

  double get delta => week - lastWeek;
  double get daily => studyDays <= 0 ? 0 : total / studyDays;
}

// ============================================================================
// 装帧部件
// ============================================================================

/// 书眉 + 双线（1.5pt 浓墨 + 1pt 纸线）。
class _RunningHead extends StatelessWidget {
  const _RunningHead({required this.left, required this.right, this.onBack});

  final String left;
  final String right;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (onBack != null) ...[
              InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(PineRadius.seal),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_rounded,
                          size: 13, color: PineColors.ink3),
                      Text(' 返回',
                          style: PineText.serif(
                              size: 10, color: PineColors.ink3)),
                    ],
                  ),
                ),
              ),
            ],
            Text(
              left,
              style: PineText.mono(size: 9.5, color: PineColors.ink3)
                  .copyWith(letterSpacing: 1.6),
            ),
            const Spacer(),
            Text(
              right,
              style: PineText.mono(size: 9.5, color: PineColors.ink3)
                  .copyWith(letterSpacing: 1.4),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Container(height: 1.5, color: PineColors.ink),
        Container(height: 1, color: PineColors.lineStrong),
        const SizedBox(height: 3),
      ],
    );
  }
}

/// 页脚：落款 · 页码 · 小印。
class _RunningFoot extends StatelessWidget {
  const _RunningFoot({required this.note, required this.page});

  final String note;
  final String page;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Container(height: 1, color: PineColors.line),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('松果 · 专注时光',
                style: PineText.serif(size: 9.5, color: PineColors.ink3)
                    .copyWith(letterSpacing: 1)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: PineText.mono(size: 8.5, color: PineColors.ink3)
                    .copyWith(letterSpacing: .6),
              ),
            ),
            Text(page,
                style: PineText.mono(size: 8.5, color: PineColors.ink3)),
            const SizedBox(width: 8),
            const SealStamp(text: '记', size: 16),
          ],
        ),
      ],
    );
  }
}

/// 分节记号：汉字序号 + 短横 + 节名 + 右侧小注。
class SectionMark extends StatelessWidget {
  const SectionMark({
    super.key,
    required this.no,
    required this.title,
    this.note = '',
    this.action,
  });

  final String no;
  final String title;
  final String note;

  /// 右侧小控件（翻月、补记入口等）。非空时取代 note 的位置。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(no, style: PineText.serif(size: 11, color: PineColors.accent)),
          const SizedBox(width: 7),
          Container(width: 14, height: 1, color: PineColors.accent),
          const SizedBox(width: 8),
          Text(title,
              style: PineText.serif(
                      size: 13.5, weight: FontWeight.w600)
                  .copyWith(letterSpacing: 1)),
          const Spacer(),
          if (action != null)
            action!
          else if (note.isNotEmpty)
            Text(note,
                style: PineText.mono(size: 8.5, color: PineColors.ink3)
                    .copyWith(letterSpacing: .8)),
        ],
      ),
    );
  }
}

/// 印章：方框 + 宋体字。`solid` 为朱底白字。
class SealStamp extends StatelessWidget {
  const SealStamp({
    super.key,
    required this.text,
    this.solid = false,
    this.size = 22,
  });

  final String text;
  final bool solid;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: solid ? PineColors.accent : Colors.transparent,
        border: Border.all(
          color: solid ? PineColors.accent : PineColors.lineStrong,
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(2.5),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: PineText.serif(
          size: size * 0.42,
          weight: FontWeight.w600,
          color: solid ? PineColors.sheet : PineColors.ink3,
        ).copyWith(height: 1.05),
      ),
    );
  }
}

/// 卷首卡：抬升纸面 + inset 内框 + 右下折角。
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PineColors.sheet,
        border: Border.all(color: PineColors.lineStrong),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  border: Border.all(color: PineColors.line),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 15, 16, 14), child: child),
          // 折角：右下角一小片，切出「翻过一页」的暗示。
          Positioned(
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: CustomPaint(
                size: const Size(14, 14),
                painter: _DogEarPainter(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DogEarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paper = Paint()..color = PineColors.paper;
    final line = Paint()
      ..color = PineColors.lineStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paper);
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width, size.height), line);
    canvas.drawLine(
        Offset(size.width, size.height), Offset(0, size.height), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 大字读数：361(h)34(m)，单位小一号、淡墨。
class _BigHours extends StatelessWidget {
  const _BigHours({required this.minutes, required this.size});

  final double minutes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final total = minutes.round();
    final h = total ~/ 60;
    final mm = total % 60;
    final unit = PineText.serif(size: size * 0.38, color: PineColors.ink3)
        .copyWith(height: 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('$h',
            style: PineText.serif(size: size, weight: FontWeight.w600)
                .copyWith(height: .95, letterSpacing: -.5)),
        Text('h', style: unit),
        Text(mm.toString().padLeft(2, '0'),
            style: PineText.serif(size: size, weight: FontWeight.w600)
                .copyWith(height: .95, letterSpacing: -.5)),
        Text('m', style: unit),
      ],
    );
  }
}

/// 卷首三段元数据，竖线分隔。
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.items, this.maxWidth});

  final List<(String, String)> items;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: PineColors.line,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(items[i].$1,
                    style: PineText.serif(size: 8, color: PineColors.ink3)
                        .copyWith(letterSpacing: 1.6)),
                const SizedBox(height: 2),
                Text(items[i].$2, style: PineText.mono(size: 12.5)),
              ],
            ),
          ),
        ],
      ],
    );
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 9),
            Container(height: 0, color: PineColors.line),
            const SizedBox(height: 9),
            row,
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Row(
            children: List.generate(
              60,
              (i) => Expanded(
                child: Container(
                  height: 1,
                  color: i.isEven ? PineColors.lineStrong : Colors.transparent,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 增减：檀褐为增，淡墨为减。
class _Delta extends StatelessWidget {
  const _Delta({required this.minutes});

  final double minutes;

  @override
  Widget build(BuildContext context) {
    final negative = minutes < 0;
    final color = negative ? PineColors.ink3 : PineColors.accent;
    final text = formatCompactMinutes(minutes.abs());
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${negative ? '−' : '+'}$text',
            style: PineText.mono(size: 11, color: color)),
        Text(' 较上周',
            style: PineText.mono(size: 9, color: PineColors.ink3)),
      ],
    );
  }
}

/// 番茄小格：每格 4×8，超过目标的部分补一枚短横。
class _TomatoTicks extends StatelessWidget {
  const _TomatoTicks({required this.count, required this.goal});

  final int count;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final shown = goal <= 0 ? 0 : (goal / 5).ceil();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < (shown == 0 ? 1 : shown); i++)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Container(
              width: 4,
              height: 8,
              color: i * 5 < count ? PineColors.accent : PineColors.sunken,
            ),
          ),
      ],
    );
  }
}

/// 本周目标条：细横条 + 目标刻线。
class _GoalBar extends StatelessWidget {
  const _GoalBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final ratio = value.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 4,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: PineColors.sunken,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              FractionallySizedBox(
                widthFactor: ratio,
                child: Container(
                  decoration: BoxDecoration(
                    color: PineColors.accent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text('目标线 ${goalLabel(value)}',
                style: PineText.mono(size: 7.5, color: PineColors.inkFaint)
                    .copyWith(letterSpacing: 1)),
            const Spacer(),
          ],
        ),
      ],
    );
  }

  String goalLabel(double value) => '${(value * 100).round()}%';
}

/// 七日一行：日期 · 科目堆叠条 · 点线 · 时长。
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.colors,
    required this.maxMinutes,
  });

  final _DayCell day;
  final Map<String, Color> colors;
  final double maxMinutes;

  @override
  Widget build(BuildContext context) {
    final accent = day.isToday ? PineColors.accent : null;
    final entries = day.perTask.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final ratio = maxMinutes <= 0 ? 0.0 : day.minutes / maxMinutes;
    return Container(
      height: 26,
      decoration: BoxDecoration(
        border: Border(
          top: day.index == 0
              ? BorderSide.none
              : const BorderSide(color: PineColors.line, width: .5),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Row(
              children: [
                Text(day.label,
                    style: PineText.serif(
                        size: 11,
                        color: accent ?? PineColors.ink2)),
                const SizedBox(width: 3),
                Text(day.dayOfMonth.toString().padLeft(2, '0'),
                    style: PineText.serif(
                        size: 11,
                        weight: FontWeight.w600,
                        color: accent ?? PineColors.ink)),
              ],
            ),
          ),
          SizedBox(
            width: 134,
            height: 7,
            child: Row(
              children: [
                for (final entry in entries)
                  Expanded(
                    flex: (entry.value * 10).round().clamp(1, 100000),
                    child: Container(
                      margin: const EdgeInsets.only(right: 1),
                      color: colors[entry.key] ?? PineColors.inkFaint,
                    ),
                  ),
                if (entries.isEmpty)
                  Expanded(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: ratio.clamp(0, 1),
                      child: const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: DotLeader()),
          Text(
            day.minutes <= 0 ? '—' : formatCompactMinutes(day.minutes),
            style: PineText.mono(
                size: 10.5,
                color: accent ??
                    (day.minutes <= 0 ? PineColors.inkFaint : PineColors.ink2)),
          ),
        ],
      ),
    );
  }
}

/// 点线引导：4.5pt 间距的点阵，用来填满「名目 ↔ 数字」之间的空档。
class DotLeader extends StatelessWidget {
  const DotLeader({super.key, this.color, this.height = 1});

  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4, left: 6, right: 6),
        child: CustomPaint(
          size: const Size(double.infinity, 1),
          painter: _DotLeaderPainter(color ?? PineColors.lineStrong),
        ),
      ),
    );
  }
}

class _DotLeaderPainter extends CustomPainter {
  _DotLeaderPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var x = 0.0; x < size.width; x += 4.5) {
      canvas.drawLine(Offset(x, 0.5), Offset(x, 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotLeaderPainter old) => old.color != color;
}

/// 图例：本周科目色块 + 名称。
class _Legend extends StatelessWidget {
  const _Legend({required this.names, required this.colors});

  final List<String> names;
  final Map<String, Color> colors;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final name in names)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colors[name] ?? PineColors.inkFaint,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 4),
              Text(name,
                  style: PineText.serif(size: 9, color: PineColors.ink3)),
            ],
          ),
      ],
    );
  }
}

/// 科目表：紧凑版只放 累计/占比，完整版加 本周/上周/增减/日均。
class _SubjectTable extends StatelessWidget {
  const _SubjectTable({required this.m, required this.compact});

  final _ReportModel m;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rows = m.subjects;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubjectHeader(compact: compact),
        for (final row in rows) _SubjectLine(row: row, compact: compact, colors: m.colors),
        _TotalLine(m: m, compact: compact),
        const SizedBox(height: 2),
        Container(height: 1, color: PineColors.ink),
        const SizedBox(height: 2),
        Container(height: 1, color: PineColors.ink),
      ],
    );
  }
}

class _SubjectHeader extends StatelessWidget {
  const _SubjectHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style =
        PineText.serif(size: 8.5, color: PineColors.ink3).copyWith(letterSpacing: 1.4);
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PineColors.lineStrong)),
      ),
      child: Row(
        children: [
          SizedBox(width: compact ? 52 : 64, child: Text('科目', style: style)),
          const Expanded(child: SizedBox()),
          if (!compact) ...[
            SizedBox(width: 54, child: Text('本周', textAlign: TextAlign.right, style: style)),
            SizedBox(width: 54, child: Text('上周', textAlign: TextAlign.right, style: style)),
            SizedBox(width: 60, child: Text('增减', textAlign: TextAlign.right, style: style)),
            SizedBox(width: 58, child: Text('日均', textAlign: TextAlign.right, style: style)),
          ],
          SizedBox(
              width: compact ? 62 : 70,
              child: Text('累计', textAlign: TextAlign.right, style: style)),
          SizedBox(width: 40, child: Text('占比', textAlign: TextAlign.right, style: style)),
        ],
      ),
    );
  }
}

class _SubjectLine extends StatelessWidget {
  const _SubjectLine({
    required this.row,
    required this.compact,
    required this.colors,
  });

  final _SubjectRow row;
  final bool compact;
  final Map<String, Color> colors;

  @override
  Widget build(BuildContext context) {
    final mono = PineText.mono(size: 10.5, color: PineColors.ink2);
    final monoDim = PineText.mono(size: 10.5, color: PineColors.ink3);
    return Container(
      height: compact ? 26 : 28,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: PineColors.line.withAlpha(180), width: .5),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: compact ? 52 : 64,
            child: Text(row.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PineText.serif(size: compact ? 11.5 : 12.5)),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: row.share.clamp(0.02, 1.0),
                child: Container(
                  height: 5,
                  margin: const EdgeInsets.only(right: 12),
                  color: colors[row.name] ?? PineColors.inkFaint,
                ),
              ),
            ),
          ),
          if (!compact) ...[
            SizedBox(width: 54, child: Text(_m(row.week), textAlign: TextAlign.right, style: mono)),
            SizedBox(width: 54, child: Text(_m(row.lastWeek), textAlign: TextAlign.right, style: monoDim)),
            SizedBox(
              width: 60,
              child: Text(
                row.delta == 0
                    ? '—'
                    : '${row.delta > 0 ? '+' : '−'}${row.delta.abs().round()}',
                textAlign: TextAlign.right,
                style: PineText.mono(
                    size: 10.5,
                    color: row.delta >= 0 ? PineColors.accent : PineColors.ink3),
              ),
            ),
            SizedBox(width: 58, child: Text('${row.daily.round()}', textAlign: TextAlign.right, style: monoDim)),
          ],
          SizedBox(
            width: compact ? 62 : 70,
            child: Text(formatCompactMinutes(row.total),
                textAlign: TextAlign.right, style: mono),
          ),
          SizedBox(
            width: 40,
            child: Text('${(row.share * 100).round()}%',
                textAlign: TextAlign.right, style: monoDim),
          ),
        ],
      ),
    );
  }

  String _m(double minutes) => minutes <= 0 ? '·' : '${minutes.round()}';
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({required this.m, required this.compact});

  final _ReportModel m;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bold = PineText.mono(size: 11, color: PineColors.ink);
    final total = m.subjects.fold<double>(0, (a, b) => a + b.total);
    final week = m.subjects.fold<double>(0, (a, b) => a + b.week);
    final last = m.subjects.fold<double>(0, (a, b) => a + b.lastWeek);
    final delta = week - last;
    return Container(
      height: 30,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: PineColors.ink)),
      ),
      child: Row(
        children: [
          SizedBox(
              width: compact ? 52 : 64,
              child: Text('合计',
                  style: PineText.serif(
                      size: 11.5, weight: FontWeight.w600))),
          const Expanded(child: SizedBox()),
          if (!compact) ...[
            SizedBox(width: 54, child: Text('${week.round()}', textAlign: TextAlign.right, style: bold)),
            SizedBox(width: 54, child: Text('${last.round()}', textAlign: TextAlign.right, style: bold)),
            SizedBox(
              width: 60,
              child: Text(
                '${delta >= 0 ? '+' : '−'}${delta.abs().round()}',
                textAlign: TextAlign.right,
                style: PineText.mono(size: 11, color: PineColors.accent),
              ),
            ),
            SizedBox(width: 58, child: Text('${m.stats.totalDays <= 0 ? 0 : (total / m.stats.totalDays).round()}', textAlign: TextAlign.right, style: bold)),
          ],
          SizedBox(
              width: compact ? 62 : 70,
              child: Text(formatCompactMinutes(total),
                  textAlign: TextAlign.right, style: bold)),
          SizedBox(
              width: 40,
              child: Text('${(m.subjects.fold<double>(0, (a, b) => a + b.share) * 100).round()}%',
                  textAlign: TextAlign.right, style: bold)),
        ],
      ),
    );
  }
}

/// 本月印记：7 列日圈，实心=满番、浅色=有记录、描边=今天。
class _MonthSeals extends StatelessWidget {
  const _MonthSeals({required this.m, this.showNote = false});

  final _ReportModel m;
  final bool showNote;

  @override
  Widget build(BuildContext context) {
    final anchor = m.monthAnchor;
    final daysInMonth = DateTime(anchor.year, anchor.month + 1, 0).day;
    final firstWeekday = DateTime(anchor.year, anchor.month, 1).weekday; // 1=周一
    final cells = <Widget>[];
    for (var i = 1; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final minutes = m.monthDayMinutes[day] ?? 0;
      cells.add(_SealCell(
        day: day,
        minutes: minutes,
        isToday: anchor.year == m.now.year &&
            anchor.month == m.now.month &&
            day == m.now.day,
      ));
    }
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final label in ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Center(
                  child: Text(label,
                      style: PineText.mono(size: 7.5, color: PineColors.inkFaint)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 3),
        for (var row = 0; row < cells.length ~/ 7; row++) ...[
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(child: Center(child: cells[row * 7 + col])),
            ],
          ),
          const SizedBox(height: 3),
        ],
        if (showNote) ...[
          const SizedBox(height: 6),
          Text(
            '本月 ${m.monthActiveDays} 天有记录 · 单日最高 ${formatCompactMinutes(m.monthBest)}',
            style: PineText.mono(size: 7.5, color: PineColors.ink3)
                .copyWith(letterSpacing: .6),
          ),
        ],
      ],
    );
  }
}

class _SealCell extends StatelessWidget {
  const _SealCell({
    required this.day,
    required this.minutes,
    required this.isToday,
  });

  final int day;
  final double minutes;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final full = minutes >= 50;
    final some = minutes > 0 && !full;
    final background = full
        ? PineColors.accent
        : some
            ? PineColors.accentSoft
            : Colors.transparent;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: isToday
            ? Border.all(color: PineColors.accent, width: 1)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '$day',
        style: PineText.mono(
          size: 8,
          color: full
              ? PineColors.sheet
              : some
                  ? PineColors.accent
                  : PineColors.inkFaint,
        ),
      ),
    );
  }
}

/// 最近落账一行：时刻 · 科目 · 课业 · 点线 · 时长。
class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.record, required this.compact});

  final FocusRecord record;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final at = record.at;
    final stamp = '${at.month}/${at.day} '
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return Container(
      height: compact ? 24 : 26,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: PineColors.line.withAlpha(180), width: .5),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: compact ? 42 : 64,
            child: Text(compact ? '${at.hour}:${at.minute.toString().padLeft(2, '0')}' : stamp,
                style: PineText.mono(size: 9.5, color: PineColors.ink3)),
          ),
          SizedBox(
            width: compact ? 46 : 52,
            child: Text(record.taskName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PineText.serif(size: 11.5)),
          ),
          Flexible(
            child: Text(
              record.status == RecordStatus.manual ? '手动补记' : '自动记录',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PineText.serif(size: 10, color: PineColors.ink3),
            ),
          ),
          const Expanded(child: DotLeader()),
          Text(formatCompactMinutes(record.minutes),
              style: PineText.mono(size: 10, color: PineColors.ink2)),
        ],
      ),
    );
  }
}

/// R5 的右缘竖排边注。
class _VerticalNote extends StatelessWidget {
  const _VerticalNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: 1,
      child: Text(
        text,
        maxLines: 1,
        style: PineText.serif(size: 8.5, color: PineColors.ink3)
            .copyWith(letterSpacing: 3),
      ),
    );
  }
}

/// 里程碑印盒：百/三/五/千，已达成实底，下一档描红。
class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({required this.totalMinutes});

  final double totalMinutes;

  static const _stops = [100.0, 300.0, 500.0, 1000.0];
  static const _marks = ['百', '三', '五', '千'];

  @override
  Widget build(BuildContext context) {
    final hours = totalMinutes / 60;
    var next = 0;
    for (var i = 0; i < _stops.length; i++) {
      if (hours < _stops[i]) {
        next = i;
        break;
      }
      next = i + 1;
    }
    final remain = next < _stops.length
        ? (_stops[next] - hours) * 60
        : 0.0;
    final progress = next >= _stops.length
        ? 1.0
        : (hours / _stops[next]).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: PineColors.sheet,
        border: Border.all(color: PineColors.lineStrong),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('里 程 碑',
              style: PineText.mono(size: 8, color: PineColors.ink3)
                  .copyWith(letterSpacing: 1.6)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < _stops.length; i++)
                Column(
                  children: [
                    SealStamp(
                      text: _marks[i],
                      solid: hours >= _stops[i],
                      size: 30,
                    ),
                    const SizedBox(height: 4),
                    Text('${_stops[i].round()}h',
                        style: PineText.mono(
                            size: 7,
                            color: hours >= _stops[i]
                                ? PineColors.ink3
                                : PineColors.inkFaint)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: PineColors.line),
          const SizedBox(height: 9),
          Text(next < _stops.length ? '距 ${_stops[next].round()}h 还差' : '已达成全部',
              style: PineText.mono(size: 8, color: PineColors.ink3)),
          const SizedBox(height: 3),
          if (next < _stops.length)
            _BigHours(minutes: remain, size: 19)
          else
            Text('千里之行',
                style: PineText.serif(
                    size: 15, weight: FontWeight.w600, color: PineColors.accent)),
          const SizedBox(height: 8),
          SizedBox(
            height: 4,
            child: Stack(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: PineColors.sunken,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: progress,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: PineColors.accent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 本周侧栏：图例 + 合计 + 目标。
class _WeekSidecard extends StatelessWidget {
  const _WeekSidecard({required this.m});

  final _ReportModel m;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final name in m.legend)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: m.colors[name] ?? PineColors.inkFaint,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 6),
                Text(name, style: PineText.serif(size: 11)),
                const Spacer(),
                Text(
                    formatCompactMinutes(
                        m.days.fold<double>(
                            0, (a, d) => a + (d.perTask[name] ?? 0))),
                    style: PineText.mono(size: 9, color: PineColors.ink3)),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Container(height: 1, color: PineColors.ink),
        const SizedBox(height: 7),
        Text('本 周 合 计',
            style: PineText.mono(size: 8, color: PineColors.ink3)
                .copyWith(letterSpacing: 1.2)),
        const SizedBox(height: 3),
        _BigHours(minutes: m.weekMinutes, size: 24),
        const SizedBox(height: 4),
        _Delta(minutes: m.weekDelta),
        const SizedBox(height: 10),
        Text('目标 ${m.data.weekGoal} 枚 · 已 ${m.stats.weekCount} 枚',
            style: PineText.mono(size: 8, color: PineColors.ink3)),
        const SizedBox(height: 5),
        _GoalBar(
            value: m.stats.weekCount / (m.data.weekGoal <= 0 ? 1 : m.data.weekGoal)),
      ],
    );
  }
}

/// 带纵轴的墨柱图：0 / 2h / 4h / 6h 虚线。
class _InkAxisChart extends StatelessWidget {
  const _InkAxisChart({
    required this.days,
    required this.colors,
    required this.maxMinutes,
  });

  final List<_DayCell> days;
  final Map<String, Color> colors;
  final double maxMinutes;

  @override
  Widget build(BuildContext context) {
    final ticks = maxMinutes <= 120 ? 2 : (maxMinutes / 120).ceil();
    return SizedBox(
      height: 180,
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 纵轴注记
                SizedBox(
                  width: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = ticks; i >= 0; i--)
                        Expanded(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Transform.translate(
                              offset: const Offset(0, -4),
                              child: Text(
                                i == 0 ? '0' : '${i * 2}h',
                                style: PineText.mono(
                                    size: 7.5, color: PineColors.inkFaint),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Stack(
                    children: [
                      // 网格线
                      Positioned.fill(
                        child: Column(
                          children: [
                            for (var i = 0; i <= ticks; i++)
                              Expanded(
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: CustomPaint(
                                    size: const Size(double.infinity, 1),
                                    painter: _DashedLinePainter(
                                      color: i == ticks
                                          ? PineColors.lineStrong
                                          : PineColors.line,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // 柱
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final day in days)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5),
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor:
                                        (day.minutes / maxMinutes).clamp(0.0, 1.0),
                                    child: Container(
                                      width: double.infinity,
                                      decoration: const BoxDecoration(
                                        color: PineColors.sunken,
                                        borderRadius: BorderRadius.vertical(
                                            top: Radius.circular(1)),
                                      ),
                                      child: Column(
                                        children: [
                                          for (final entry in (day.perTask.entries
                                                  .toList()
                                                ..sort((a, b) =>
                                                    a.value.compareTo(b.value))))
                                            Expanded(
                                              flex:
                                                  (entry.value * 10).round().clamp(1, 100000),
                                              child: Container(
                                                margin: const EdgeInsets.only(top: 1),
                                                color: colors[entry.key] ??
                                                    PineColors.inkFaint,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const SizedBox(width: 30),
              for (final day in days)
                Expanded(
                  child: Center(
                    child: Text(
                      day.isToday ? '${day.label} · 今日' : day.label,
                      style: PineText.mono(
                        size: 7.5,
                        color: day.isToday
                            ? PineColors.accent
                            : PineColors.ink3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, 0.5), Offset(x + 3, 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}


/// 翻月：‹ 2026 年 11 月 ›，只有本月回顾用。
class _MonthSwitch extends StatelessWidget {
  const _MonthSwitch({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ArrowButton(icon: Icons.chevron_left_rounded, onTap: onPrev),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(label,
              style: PineText.mono(size: 8.5, color: PineColors.ink3)
                  .copyWith(letterSpacing: .6)),
        ),
        _ArrowButton(icon: Icons.chevron_right_rounded, onTap: onNext),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 必须给确定尺寸：这段 Row 在 IntrinsicHeight 里算固有高度，
    // 裸的 InkResponse 会算出无界高度（实测 100000pt，整行报溢出）。
    return SizedBox(
      width: 20,
      height: 20,
      child: InkResponse(
        onTap: onTap,
        radius: 10,
        child: Icon(icon, size: 14, color: PineColors.ink3),
      ),
    );
  }
}

/// 分节右侧的小动作（如「＋ 补记」）：纯文字，不用图标按钮。
class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PineRadius.seal),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Text(label,
            style: PineText.serif(size: 10, color: PineColors.ink2)),
      ),
    );
  }
}

/// 本月累计一行：本月累计 Xh Ym · N 天有记录。
class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.m});

  final _ReportModel m;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('本月累计',
            style: PineText.serif(size: 10.5, color: PineColors.ink3)
                .copyWith(letterSpacing: 1)),
        const SizedBox(width: 7),
        _BigHours(minutes: m.monthTotal, size: 19),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            m.monthActiveDays <= 0
                ? '尚无记录'
                : '${m.monthActiveDays} 天有记录 · 单日最高 ${formatCompactMinutes(m.monthBest)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PineText.mono(size: 8.5, color: PineColors.ink3)
                .copyWith(letterSpacing: .4),
          ),
        ),
      ],
    );
  }
}

/// 事件进展（专注事件 = 跨轮次的累计容器）。
///
/// 视觉换成素纸：分节记号在外面（SectionMark），这里只排「进行中 + 最近归档」。
/// 交互与旧版完全一致——行点开明细、⋯ 出操作面板、「事件档案」进总档。
class _EventsSection extends StatelessWidget {
  const _EventsSection({
    required this.data,
    required this.onChanged,
    required this.colorFor,
  });

  final AppData data;
  final ValueChanged<AppData> onChanged;
  final Color Function(String taskName) colorFor;

  @override
  Widget build(BuildContext context) {
    final running = data.events.where((e) => e.isRunning).toList();
    final paused = data.events.where((e) => e.isPaused).toList();
    final finished = data.events.where((e) => e.isFinished).toList()
      ..sort((a, b) =>
          (b.finishedAt ?? b.startedAt).compareTo(a.finishedAt ?? a.startedAt));
    final live = [...running, ...paused];

    if (live.isEmpty && finished.isEmpty) {
      return Text('还没有进行中的事件（在计时页任务行开启）',
          style: PineText.serif(size: 11, color: PineColors.ink3));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (live.isEmpty)
          Text('暂无进行中', style: PineText.mono(size: 9, color: PineColors.ink3))
        else
          for (var i = 0; i < live.length; i++) ...[
            if (i > 0) Container(height: .5, color: PineColors.line),
            _eventRow(context, live[i]),
          ],
        if (finished.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(height: 1, color: PineColors.line),
          const SizedBox(height: 7),
          InkWell(
            borderRadius: BorderRadius.circular(PineRadius.seal),
            onTap: () => showEventArchiveSheet(
              context,
              data: data,
              colorFor: colorFor,
              onChanged: onChanged,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('已完成 ${finished.length} 个',
                      style: PineText.mono(size: 9, color: PineColors.ink3)),
                  const SizedBox(width: 4),
                  Text('事件档案',
                      style: PineText.serif(size: 10, color: PineColors.celadon)),
                  const Icon(Icons.chevron_right_rounded,
                      size: 13, color: PineColors.celadon),
                ],
              ),
            ),
          ),
          for (final event in finished.take(3)) _finishedRow(context, event),
        ],
      ],
    );
  }

  Widget _open(BuildContext context, FocusEvent event, Widget child) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => showEventDetailSheet(
          context,
          data: data,
          event: event,
          colorFor: colorFor,
        ),
        child: child,
      );

  Widget _eventRow(BuildContext context, FocusEvent event) {
    final count = eventStatsOf(data, event.id).tomatoCount;
    final accent = colorFor(event.taskName);
    final shown = count <= 8 ? count : 7;
    return Row(
      children: [
        Expanded(
          child: _open(
            context,
            event,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      event.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PineText.serif(size: 13, weight: FontWeight.w600),
                    ),
                  ),
                  if (event.isPaused) ...[
                    const SizedBox(width: 6),
                    Text('已暂停',
                        style: PineText.serif(
                            size: 10, color: PineColors.goldInk)),
                  ],
                  const Expanded(child: DotLeader()),
                  for (var i = 0; i < shown; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Container(
                        width: 4,
                        height: 11,
                        decoration: BoxDecoration(
                          color: accent.withAlpha(190),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                    ),
                  if (count > 8)
                    Text('+${count - 7}',
                        style: PineText.mono(size: 9, color: PineColors.ink3)),
                  const SizedBox(width: 10),
                  Text(
                    formatCompactMinutes(eventStatsOf(data, event.id).minutes),
                    style: PineText.mono(size: 11, color: PineColors.ink),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.more_horiz, size: 18, color: PineColors.ink3),
          tooltip: '暂停 / 继续 / 完成 / 编辑',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          visualDensity: VisualDensity.compact,
          onPressed: () => showEventActionSheet(
            context,
            data: data,
            event: event,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _finishedRow(BuildContext context, FocusEvent event) {
    final stats = eventStatsOf(data, event.id);
    final done = event.finishedAt ?? event.startedAt;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => showEventDetailSheet(
        context,
        data: data,
        event: event,
        colorFor: colorFor,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 13,
              decoration: BoxDecoration(
                color: colorFor(event.taskName).withAlpha(168),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                event.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PineText.serif(size: 12, color: PineColors.ink2),
              ),
            ),
            Text('${done.month}/${done.day} 完成',
                style: PineText.mono(size: 9, color: PineColors.ink3)),
            const SizedBox(width: 10),
            Text(formatCompactMinutes(stats.minutes),
                style: PineText.mono(size: 10, color: PineColors.ink3)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 小工具
// ============================================================================

String _weekCn(int weekday) => const ['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

int isoWeekNumber(DateTime date) {
  final thursday = date.add(Duration(days: 3 - ((date.weekday + 6) % 7)));
  final firstThursday = DateTime(thursday.year, 1, 4);
  final shift = 3 - ((firstThursday.weekday + 6) % 7);
  final anchor = firstThursday.add(Duration(days: shift));
  return 1 + (thursday.difference(anchor).inDays ~/ 7);
}
