import 'models.dart';

/// 由 [AppData] 与当前时刻推导出的会话显示状态。
class SessionView {
  const SessionView({
    required this.mode,
    required this.running,
    required this.targetReached,
    required this.plannedSeconds,
    required this.remainingSeconds,
    required this.overtimeSeconds,
    required this.elapsedSeconds,
  });

  final SessionMode mode;
  final bool running;
  final bool targetReached;
  final int plannedSeconds;
  final int remainingSeconds;
  final int overtimeSeconds;
  final int elapsedSeconds;

  /// 环形进度 0..1，超时后恒为 1。
  double get progress => plannedSeconds <= 0
      ? 0
      : ((plannedSeconds - remainingSeconds) / plannedSeconds).clamp(0.0, 1.0);

  /// 专注已累计分钟数，与网页端一样保留 0.1 分钟精度。
  double get elapsedMinutes {
    final rounded = (elapsedSeconds / 6).round() / 10;
    return rounded < 0.1 ? 0 : rounded;
  }

  String get clockText {
    final seconds =
        targetReached ? overtimeSeconds : remainingSeconds.clamp(0, 86400);
    final sign = targetReached ? '+' : '';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$sign${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
  }

  static SessionView? of(AppData data, DateTime now) {
    final session = data.activeSession;
    if (session == null) return null;
    final planned = data.settings.forMode(session.mode) * 60;

    final int remaining;
    final int overtime;
    if (!session.running) {
      remaining = session.remaining < 0 ? 0 : session.remaining;
      overtime = session.overtimeElapsed;
    } else if (!session.targetReached) {
      remaining = session.deadline == null
          ? session.remaining
          : session.deadline!.difference(now).inSeconds.clamp(0, 86400);
      overtime = 0;
    } else {
      remaining = 0;
      final started = session.overtimeStartedAt;
      overtime = session.overtimeElapsed +
          (started == null ? 0 : now.difference(started).inSeconds.clamp(0, 86400));
    }

    return SessionView(
      mode: session.mode,
      running: session.running,
      targetReached: session.targetReached,
      plannedSeconds: planned,
      remainingSeconds: remaining,
      overtimeSeconds: overtime,
      elapsedSeconds: (planned - remaining + overtime).clamp(0, 86400 * 7),
    );
  }
}

/// 统计视图：今日、本周、连续天数与周内按任务分布。
class StatsView {
  const StatsView({
    required this.todayMinutes,
    required this.weekMinutes,
    required this.todayCount,
    required this.weekCount,
    required this.streak,
    required this.weekTaskTotals,
  });

  final double todayMinutes;
  final double weekMinutes;
  final int todayCount;
  final int weekCount;
  final int streak;

  /// 键为 0=周一 … 6=周日，值为 任务名 -> 分钟数。
  final Map<int, Map<String, double>> weekTaskTotals;

  double totalForDay(int index) {
    final row = weekTaskTotals[index];
    if (row == null) return 0;
    return row.values.fold<double>(0, (sum, value) => sum + value);
  }

  double maxDay() {
    var result = 0.0;
    for (var i = 0; i < 7; i++) {
      final total = totalForDay(i);
      if (total > result) result = total;
    }
    return result;
  }

  /// 本周出现过的任务名，按累计分钟数降序，用于图例配色。
  List<String> tasksInWeek() {
    final totals = <String, double>{};
    for (final row in weekTaskTotals.values) {
      row.forEach((name, minutes) {
        totals.update(name, (v) => v + minutes, ifAbsent: () => minutes);
      });
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((entry) => entry.key).toList();
  }

  static StatsView of(AppData data, DateTime now) {
    final today = dateKey(now);
    final monday = mondayOf(now);
    final counted = data.records.where((record) => record.counted).toList();

    double todayMinutes = 0;
    double weekMinutes = 0;
    var todayCount = 0;
    var weekCount = 0;
    final weekTaskTotals = {for (var i = 0; i < 7; i++) i: <String, double>{}};
    final days = <String>{};

    for (final record in counted) {
      final day = record.day;
      if (record.dayKey == today) {
        todayMinutes += record.minutes;
        todayCount += 1;
      }
      final offset = day.difference(monday).inDays;
      if (offset >= 0 && offset < 7) {
        weekMinutes += record.minutes;
        weekCount += 1;
        weekTaskTotals[offset]!.update(
          record.taskName,
          (value) => value + record.minutes,
          ifAbsent: () => record.minutes,
        );
      }
      days.add(record.dayKey);
    }

    // 进行中的专注时长实时计入今日与本周。
    final view = SessionView.of(data, now);
    if (view != null && view.mode.isFocus) {
      final live = view.elapsedMinutes;
      if (live > 0) {
        todayMinutes += live;
        final offset = dayStart(now).difference(monday).inDays;
        if (offset >= 0 && offset < 7) {
          weekMinutes += live;
          weekTaskTotals[offset]!.update(
            data.selectedTask.name,
            (value) => value + live,
            ifAbsent: () => live,
          );
        }
      }
    }

    var streak = 0;
    var cursor = dayStart(now);
    if (!days.contains(dateKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (days.contains(dateKey(cursor))) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return StatsView(
      todayMinutes: todayMinutes,
      weekMinutes: weekMinutes,
      todayCount: todayCount,
      weekCount: weekCount,
      streak: streak,
      weekTaskTotals: weekTaskTotals,
    );
  }
}

/// 会话状态机。所有方法都是纯函数，返回新的 [AppData]。
class TimerEngine {
  TimerEngine._();

  /// 超过计划时长后开始累计超时。
  static AppData advance(AppData data, DateTime now) {
    final session = data.activeSession;
    if (session == null || !session.running || session.targetReached) {
      return data;
    }
    if (session.deadline != null && now.isBefore(session.deadline!)) {
      return data;
    }
    return data.copyWith(
      activeSession: session.copyWith(
        targetReached: true,
        remaining: 0,
        // 从计划结束时刻起算，保证后台期间经过的时间也计入超时。
        overtimeStartedAt: session.deadline ?? now,
        overtimeElapsed: 0,
        clearDeadline: true,
      ),
    );
  }

  /// 把当前已累计分钟数写回进行中的记录。
  static AppData syncMinutes(AppData data, DateTime now) {
    final session = data.activeSession;
    if (session == null) return data;
    final view = SessionView.of(data, now);
    if (view == null || !session.mode.isFocus) return data;
    final minutes = view.elapsedMinutes;
    final records = data.records.map((record) {
      if (record.id != session.recordId) return record;
      if (record.status != RecordStatus.inProgress) return record;
      return record.copyWith(minutes: minutes);
    }).toList();
    return data.copyWith(records: records);
  }

  static AppData start(AppData data, SessionMode mode, DateTime now) {
    final planned = data.settings.forMode(mode) * 60;
    // 只有专注阶段需要一条进行中的记录；休息阶段不写入统计。
    final FocusRecord? record = mode.isFocus
        ? FocusRecord(
            taskName: data.selectedTask.name,
            minutes: 0,
            dayKey: dateKey(now),
            status: RecordStatus.inProgress,
            at: now,
          )
        : null;
    return data.copyWith(
      records: record == null ? data.records : [record, ...data.records],
      idleMode: mode,
      activeSession: ActiveSession(
        recordId: record?.id ?? 'break-${now.microsecondsSinceEpoch}',
        mode: mode,
        running: true,
        deadline: now.add(Duration(seconds: planned)),
        remaining: planned,
      ),
    );
  }

  /// 暂停：冻结剩余时间或超时累计。
  static AppData pause(AppData data, DateTime now) {
    final session = data.activeSession;
    if (session == null || !session.running) return data;
    final view = SessionView.of(data, now);
    if (view == null) return data;

    final paused = session.targetReached
        ? session.copyWith(
            running: false,
            remaining: 0,
            overtimeElapsed: view.overtimeSeconds,
            clearOvertimeStartedAt: true,
          )
        : session.copyWith(
            running: false,
            remaining: view.remainingSeconds,
            clearDeadline: true,
          );
    return syncMinutes(data.copyWith(activeSession: paused), now);
  }

  static AppData resume(AppData data, DateTime now) {
    final session = data.activeSession;
    if (session == null || session.running) return data;
    final resumed = session.targetReached
        ? session.copyWith(running: true, overtimeStartedAt: now)
        : session.copyWith(
            running: true,
            deadline: now.add(Duration(seconds: session.remaining)),
          );
    return data.copyWith(activeSession: resumed);
  }

  /// 确认完成：记录本次专注，并自动进入下一段休息；休息结束则回到专注但不自动开始。
  static AppData complete(AppData data, DateTime now) {
    final session = data.activeSession;
    if (session == null) return data;
    final view = SessionView.of(data, now);
    if (view == null) return data;

    var next = data;
    if (session.mode.isFocus) {
      next = next.copyWith(
        records: next.records.map((record) {
          if (record.id != session.recordId) return record;
          return record.copyWith(
            minutes: view.elapsedMinutes,
            status: RecordStatus.completed,
          );
        }).toList(),
      );
      final completedToday = StatsView.of(next, now).todayCount;
      final nextMode = completedToday % 4 == 0 && completedToday > 0
          ? SessionMode.longBreak
          : SessionMode.shortBreak;
      next = next.copyWith(clearActiveSession: true);
      return start(next, nextMode, now);
    }

    // 休息结束：清除会话，回到专注但不自动开始。
    return next.copyWith(
      idleMode: SessionMode.focus,
      clearActiveSession: true,
      records: next.records
          .where((record) => record.id != session.recordId)
          .toList(),
    );
  }

  /// 重置：丢弃当前未完成会话，不写入统计。
  static AppData discard(AppData data) {
    final session = data.activeSession;
    if (session == null) return data;
    return data.copyWith(
      idleMode: session.mode,
      clearActiveSession: true,
      records: data.records
          .where((record) => record.id != session.recordId)
          .toList(),
    );
  }

  /// 切换阶段：中断当前会话并回到待开始状态。
  static AppData switchMode(AppData data, SessionMode mode) {
    final session = data.activeSession;
    if (session == null) return data.copyWith(idleMode: mode);
    return discard(data).copyWith(idleMode: mode);
  }

  /// 手动补记一条已完成记录。
  static AppData addManual(
    AppData data, {
    required String taskName,
    required double minutes,
    required DateTime at,
  }) =>
      data.copyWith(
        records: [
          FocusRecord(
            taskName: taskName,
            minutes: minutes,
            dayKey: dateKey(at),
            status: RecordStatus.manual,
            at: at,
          ),
          ...data.records,
        ],
      );

  /// 冷启动恢复：补齐跨过截止点的状态。
  static AppData restore(AppData data, DateTime now) =>
      syncMinutes(advance(data, now), now);
}
