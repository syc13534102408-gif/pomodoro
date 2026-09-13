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

  /// 已累计时长 `mm:ss`，满 1 小时后为 `h:mm:ss`。
  /// 与 clockText（剩余/超时）互补，用于「已经专注了多久」这类展示。
  String get elapsedText {
    final seconds = elapsedSeconds.clamp(0, 86400 * 7);
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final rest = seconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = rest.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
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
    final statToday = statDayOf(now);
    final today = ymdOf(statToday);
    final monday = mondayOf(statToday);
    final counted = data.records.where((record) => record.counted).toList();

    double todayMinutes = 0;
    double weekMinutes = 0;
    final weekDayMinutes = List<double>.filled(7, 0);
    final weekTaskTotals = {for (var i = 0; i < 7; i++) i: <String, double>{}};
    final days = <String>{};

    for (final record in counted) {
      if (record.dayKey == today) {
        todayMinutes += record.minutes;
      }
      final offset = record.day.difference(monday).inDays;
      if (offset >= 0 && offset < 7) {
        weekMinutes += record.minutes;
        weekDayMinutes[offset] += record.minutes;
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
        final offset = statToday.difference(monday).inDays;
        if (offset >= 0 && offset < 7) {
          weekMinutes += live;
          weekDayMinutes[offset] += live;
          weekTaskTotals[offset]!.update(
            data.selectedTask.name,
            (value) => value + live,
            ifAbsent: () => live,
          );
        }
      }
    }

    // 番茄计数改为「时长当量」：满 50 分钟 1 个，缺口不足 15 分钟补齐（见
    // models.pomodoroEquiv），日/周/月历统一口径。原「完成次数」口径仅保留
    // 在 complete() 的休息轮换里。
    final todayCount = pomodoroEquiv(todayMinutes);
    final weekCount =
        weekDayMinutes.fold<int>(0, (sum, m) => sum + pomodoroEquiv(m));

    // 连续天数按统计日序列回溯（dateKey 已是统计日口径，cursor 用统计日零点
    // 直接格式化，避免 0~3 点时段错位）。
    var streak = 0;
    var cursor = statToday;
    if (!days.contains(ymdOf(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (days.contains(ymdOf(cursor))) {
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
      // 镜像会话（会话实时同步采纳的外来会话）在本机没有对应的进行中记录
      // （recordId 由发起端创建，实时同步只传快照不传记录）——完成时必须
      // 补建 completed 记录，否则这一轮会从统计里凭空消失。id 保持与发起端
      // 一致：镜像端上传后，发起端按同 id 将自己的 in_progress 记录收口为
      // completed，两端最终一致、只记一份。
      final recordExists = next.records.any((r) => r.id == session.recordId);
      if (recordExists) {
        next = next.copyWith(
          records: next.records.map((record) {
            if (record.id != session.recordId) return record;
            return record.copyWith(
              minutes: view.elapsedMinutes,
              status: RecordStatus.completed,
              // 把 at 推进到确认完成的瞬间，UI 的「完成于 HH:mm」才名副其实；
              // dayKey 保持开始计时时确定的归属日，跨午夜完成时两口径按设计分离。
              at: now,
            );
          }).toList(),
        );
      } else {
        next = next.copyWith(
          records: [
            FocusRecord(
              id: session.recordId,
              taskName: data.selectedTask.name,
              minutes: view.elapsedMinutes,
              dayKey: dateKey(now),
              status: RecordStatus.completed,
              at: now,
            ),
            ...next.records,
          ],
        );
      }
      // 休息轮换按「完成次数」口径（当量口径只用于统计展示，见 StatsView）。
      final completedToday = next.records
          .where((r) => r.counted && r.dayKey == dateKey(now))
          .length;
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

  /// 切换阶段：**不打断进行中的会话**。
  ///
  /// - 无会话：仅切换待开始模式；
  /// - 切到会话所属模式：若被挂起（暂停）则继续走表；
  /// - 切到其他模式：运行中自动暂停冻结（已专注时长与剩余都保留），
  ///   新模式以 idle 态呈现；切回原模式时时间从冻结点继续。
  /// 「挂起会话存在时开始新模式」由 complete() 语义承接：先按已专注时长
  /// 落记录，再自动进入休息——不丢数据，统计只记一份。
  static AppData switchMode(AppData data, SessionMode mode, DateTime now) {
    final session = data.activeSession;
    if (session == null) return data.copyWith(idleMode: mode);
    if (session.mode == mode) {
      // 切回会话所属模式：被挂起则继续走表，并把待开始模式归位。
      return session.running
          ? data.copyWith(idleMode: mode)
          : resume(data, now).copyWith(idleMode: mode);
    }
    final next = session.running ? pause(data, now) : data;
    return next.copyWith(idleMode: mode);
  }

  /// 会话实时镜像：用对端发布的快照重建本机会话（对等控制，见 docs/05 §8）。
  ///
  /// [sessionMap] 为 null 表示对端已无会话（完成/丢弃/未开始）→ 本机清会话
  /// （复用 discard：不写统计——记录由发起端经备份同步到达，避免双份统计）。
  /// 时间口径：deadline / overtimeStartedAt 是绝对时刻，直接信任对端时钟
  /// （两端 NTP 校时偏差为秒级，对 3 秒轮询间隔无感）。
  ///
  /// [taskName] 为快照携带的发起端任务名：本地任务列表中存在同名任务时
  /// **切换选中任务跟随发起端**——双端选中任务不同时，镜像端的显示、
  /// 「完成」落记录的任务名才与发起端一致。本地无同名任务时保持本机选择
  /// （前提：使用会话同步前先完成一次备份同步，使两端任务列表一致）。
  static AppData adoptRemoteSession(
    AppData data,
    Map<dynamic, dynamic>? sessionMap, {
    String? taskName,
  }) {
    if (sessionMap == null) {
      return data.activeSession == null ? data : discard(data);
    }
    final remote = ActiveSession.fromMap(sessionMap);
    if (remote == null) return data;
    var next = data.copyWith(activeSession: remote);
    if (taskName != null && taskName.isNotEmpty) {
      final idx = next.tasks.indexWhere((t) => t.name == taskName);
      if (idx >= 0 && idx != next.selectedIndex) {
        next = next.copyWith(selectedIndex: idx);
      }
    }
    return next;
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

/// 是否应采纳远端会话快照（纯函数，供镜像轮询与单测使用）。
///
/// 三重抑制：
/// - `remoteSeq <= 0`：云端无记录的空态，无内容可采纳；
/// - `remoteSeq <= lastSeenSeq`：重放/乱序（本机已见过更新的状态）；
/// - `remoteDeviceId == selfDeviceId`：本机自己发布的回声。
bool shouldAdoptRemoteSession({
  required int lastSeenSeq,
  required int remoteSeq,
  required String selfDeviceId,
  required String remoteDeviceId,
}) {
  if (remoteSeq <= 0) return false;
  if (remoteDeviceId.isEmpty || selfDeviceId.isEmpty) return false;
  return remoteSeq > lastSeenSeq && remoteDeviceId != selfDeviceId;
}
