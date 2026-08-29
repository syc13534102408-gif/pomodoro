import 'package:flutter/material.dart';

import 'theme.dart';

/// 专注阶段。存储值沿用网页端的英文 key，保证云端数据互通。
enum SessionMode { focus, shortBreak, longBreak }

extension SessionModeX on SessionMode {
  String get key => name;

  String get label => switch (this) {
        SessionMode.focus => '专注',
        SessionMode.shortBreak => '短休息',
        SessionMode.longBreak => '长休息',
      };

  bool get isFocus => this == SessionMode.focus;

  Color get color => switch (this) {
        SessionMode.focus => PineColors.tomato,
        SessionMode.shortBreak => PineColors.mint,
        SessionMode.longBreak => PineColors.gold,
      };

  static SessionMode from(dynamic value) => SessionMode.values.firstWhere(
        (mode) => mode.key == value || mode.label == value,
        orElse: () => SessionMode.focus,
      );
}

/// 记录状态。取值与网页端保持一致。
enum RecordStatus { inProgress, completed, manual, paused, interrupted }

extension RecordStatusX on RecordStatus {
  String get key => switch (this) {
        RecordStatus.inProgress => 'in_progress',
        RecordStatus.completed => 'completed',
        RecordStatus.manual => 'manual',
        RecordStatus.paused => 'paused',
        RecordStatus.interrupted => 'interrupted',
      };

  String get label => switch (this) {
        RecordStatus.inProgress => '进行中',
        RecordStatus.completed => '完成',
        RecordStatus.manual => '手动完成',
        RecordStatus.paused => '已暂停',
        RecordStatus.interrupted => '已中断',
      };

  /// 是否计入统计。与网页端 `counted()` 一致。
  bool get counted =>
      this == RecordStatus.completed || this == RecordStatus.manual;

  static RecordStatus from(dynamic value, {bool? completedFlag}) {
    final matched = RecordStatus.values.where(
      (status) => status.key == value || status.name == value,
    );
    if (matched.isNotEmpty) return matched.first;
    if (completedFlag == true) return RecordStatus.completed;
    return RecordStatus.interrupted;
  }
}

/// 本地日期键 `YYYY-MM-DD`，与网页端 `dateKey()` 一致。
String dateKey(DateTime date) => [
      date.year.toString().padLeft(4, '0'),
      date.month.toString().padLeft(2, '0'),
      date.day.toString().padLeft(2, '0'),
    ].join('-');

DateTime dayStart(DateTime date) => DateTime(date.year, date.month, date.day);

/// 本周一 00:00。
DateTime mondayOf(DateTime date) {
  final day = dayStart(date);
  return day.subtract(Duration(days: day.weekday - 1));
}

class PineTask {
  PineTask({
    String? id,
    required this.name,
    int? color,
    this.count = 0,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        color = color ?? kTaskPalette[0].toARGB32();

  final String id;
  final String name;
  final int color;
  final int count;

  Color get swatch => Color(color);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'color': color,
        'count': count,
      };

  PineTask copyWith({String? name, int? color, int? count}) => PineTask(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        count: count ?? this.count,
      );

  static PineTask fromMap(Map<dynamic, dynamic> map, int fallbackIndex) {
    final rawColor = map['color'];
    return PineTask(
      id: map['id']?.toString(),
      name: (map['name'] ?? '未命名事件').toString(),
      color: rawColor is num
          ? rawColor.toInt()
          : kTaskPalette[fallbackIndex % kTaskPalette.length].toARGB32(),
      count: (map['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class FocusRecord {
  FocusRecord({
    String? id,
    required this.taskName,
    required this.minutes,
    required this.dayKey,
    required this.status,
    DateTime? at,
    this.completedFlag = false,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        at = at ?? DateTime.now();

  final String id;
  final String taskName;
  final double minutes;

  /// 本地日期键 `YYYY-MM-DD`，序列化为 JSON 的 `date` 字段。
  final String dayKey;
  final RecordStatus status;
  final DateTime at;
  final bool completedFlag;

  bool get counted => status.counted || completedFlag;

  DateTime get day => DateTime.parse(dayKey);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': taskName,
        'minutes': minutes,
        'status': status.key,
        'date': dayKey,
        'at': at.toIso8601String(),
        if (completedFlag) 'completed': true,
      };

  FocusRecord copyWith({
    String? taskName,
    double? minutes,
    String? dayKey,
    RecordStatus? status,
  }) =>
      FocusRecord(
        id: id,
        taskName: taskName ?? this.taskName,
        minutes: minutes ?? this.minutes,
        dayKey: dayKey ?? this.dayKey,
        status: status ?? this.status,
        at: at,
        completedFlag: completedFlag,
      );

  static FocusRecord fromMap(Map<dynamic, dynamic> map) {
    final rawDate = map['date']?.toString();
    final parsed = rawDate == null ? null : DateTime.tryParse(rawDate);
    final day = parsed ?? DateTime.now();
    return FocusRecord(
      id: map['id']?.toString(),
      taskName: (map['name'] ?? map['taskName'] ?? '已删除事件').toString(),
      minutes: (map['minutes'] as num?)?.toDouble() ?? 0,
      dayKey: dateKey(day),
      status: RecordStatusX.from(map['status'],
          completedFlag: map['completed'] == true),
      at: parsed,
      completedFlag: map['completed'] == true,
    );
  }
}

class TodoItem {
  TodoItem({
    String? id,
    required this.text,
    this.done = false,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  final String id;
  final String text;
  final bool done;

  Map<String, dynamic> toMap() => {'id': id, 'text': text, 'done': done};

  TodoItem copyWith({String? text, bool? done}) => TodoItem(
        id: id,
        text: text ?? this.text,
        done: done ?? this.done,
      );

  static TodoItem fromMap(Map<dynamic, dynamic> map) => TodoItem(
        id: map['id']?.toString(),
        text: (map['text'] ?? '').toString(),
        done: map['done'] == true,
      );
}

/// 进行中的会话。字段与网页端 `data.activeSession` 一致。
class ActiveSession {
  const ActiveSession({
    required this.recordId,
    required this.mode,
    required this.running,
    this.deadline,
    this.remaining = 0,
    this.targetReached = false,
    this.overtimeElapsed = 0,
    this.overtimeStartedAt,
    this.reminderId,
  });

  final String recordId;
  final SessionMode mode;
  final bool running;

  /// 运行中且未到达计划时长时的截止时刻；暂停或超时后为 null。
  final DateTime? deadline;

  /// 暂停时保留的剩余秒数；超时后为 0。
  final int remaining;

  /// 计划时长是否已到（进入超时继续计时）。
  final bool targetReached;

  /// 超时计时的已确认秒数（暂停时冻结）。
  final int overtimeElapsed;

  /// 超时计时最近一次开始的时刻，运行且已超时时有效。
  final DateTime? overtimeStartedAt;
  final String? reminderId;

  Map<String, dynamic> toMap() => {
        'recordId': recordId,
        'mode': mode.key,
        'deadline': deadline?.toIso8601String(),
        'remaining': remaining,
        'running': running,
        'targetReached': targetReached,
        'overtimeElapsed': overtimeElapsed,
        'overtimeStartedAt': overtimeStartedAt?.toIso8601String(),
        'reminderId': reminderId,
      };

  ActiveSession copyWith({
    bool? running,
    DateTime? deadline,
    int? remaining,
    bool? targetReached,
    int? overtimeElapsed,
    DateTime? overtimeStartedAt,
    String? reminderId,
    bool clearDeadline = false,
    bool clearOvertimeStartedAt = false,
  }) =>
      ActiveSession(
        recordId: recordId,
        mode: mode,
        running: running ?? this.running,
        deadline: clearDeadline ? null : (deadline ?? this.deadline),
        remaining: remaining ?? this.remaining,
        targetReached: targetReached ?? this.targetReached,
        overtimeElapsed: overtimeElapsed ?? this.overtimeElapsed,
        overtimeStartedAt: clearOvertimeStartedAt
            ? null
            : (overtimeStartedAt ?? this.overtimeStartedAt),
        reminderId: reminderId ?? this.reminderId,
      );

  static ActiveSession? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final recordId = raw['recordId']?.toString();
    if (recordId == null) return null;
    DateTime? parse(Object? value) =>
        value == null ? null : DateTime.tryParse(value.toString());
    return ActiveSession(
      recordId: recordId,
      mode: SessionModeX.from(raw['mode']),
      running: raw['running'] == true,
      deadline: parse(raw['deadline']),
      remaining: (raw['remaining'] as num?)?.toInt() ?? 0,
      targetReached: raw['targetReached'] == true,
      overtimeElapsed: (raw['overtimeElapsed'] as num?)?.toInt() ?? 0,
      overtimeStartedAt: parse(raw['overtimeStartedAt']),
      reminderId: raw['reminderId']?.toString(),
    );
  }
}

class SyncState {
  const SyncState({
    this.deviceCode = '',
    this.auto = false,
    this.lastUploadedAt,
    this.lastSyncedAt,
    this.lastSyncedHash = '',
  });

  final String deviceCode;
  final bool auto;
  final DateTime? lastUploadedAt;
  final DateTime? lastSyncedAt;
  final String lastSyncedHash;

  Map<String, dynamic> toMap() => {
        'deviceCode': deviceCode,
        'auto': auto,
        'lastUploadedAt': lastUploadedAt?.toIso8601String(),
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
        'lastSyncedHash': lastSyncedHash,
      };

  SyncState copyWith({
    String? deviceCode,
    bool? auto,
    DateTime? lastUploadedAt,
    DateTime? lastSyncedAt,
    String? lastSyncedHash,
  }) =>
      SyncState(
        deviceCode: deviceCode ?? this.deviceCode,
        auto: auto ?? this.auto,
        lastUploadedAt: lastUploadedAt ?? this.lastUploadedAt,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastSyncedHash: lastSyncedHash ?? this.lastSyncedHash,
      );

  static SyncState fromMap(dynamic raw) {
    if (raw is! Map) return const SyncState();
    DateTime? parse(Object? value) =>
        value == null ? null : DateTime.tryParse(value.toString());
    return SyncState(
      deviceCode: (raw['deviceCode'] ?? '').toString(),
      auto: raw['auto'] == true,
      lastUploadedAt: parse(raw['lastUploadedAt']),
      lastSyncedAt: parse(raw['lastSyncedAt']),
      lastSyncedHash: (raw['lastSyncedHash'] ?? '').toString(),
    );
  }
}

class TimerSettings {
  const TimerSettings({this.focus = 50, this.short = 10, this.long = 25});

  final int focus;
  final int short;
  final int long;

  int forMode(SessionMode mode) => switch (mode) {
        SessionMode.focus => focus,
        SessionMode.shortBreak => short,
        SessionMode.longBreak => long,
      };

  Map<String, dynamic> toMap() =>
      {'focus': focus, 'short': short, 'long': long};

  TimerSettings copyWith({int? focus, int? short, int? long}) => TimerSettings(
        focus: focus ?? this.focus,
        short: short ?? this.short,
        long: long ?? this.long,
      );

  static TimerSettings fromMap(dynamic raw) {
    if (raw is! Map) return const TimerSettings();
    int read(String key, int fallback) =>
        (raw[key] as num?)?.toInt() ?? fallback;
    return TimerSettings(
      focus: read('focus', 50),
      short: read('short', 10),
      long: read('long', 25),
    );
  }
}

/// 完整应用数据。字段与网页端 `data` 对齐，保证云端双向兼容。
class AppData {
  AppData({
    List<PineTask>? tasks,
    List<FocusRecord>? records,
    Map<String, List<TodoItem>>? todos,
    TimerSettings? settings,
    this.idleMode = SessionMode.focus,
    this.selectedIndex = 0,
    this.goalTarget = 8,
    this.weekGoal = 20,
    this.soundEnabled = true,
    this.notifyEnabled = true,
    this.activeSession,
    SyncState? sync,
  })  : tasks = tasks ?? _defaultTasks(),
        records = records ?? [],
        todos = todos ?? {},
        settings = settings ?? const TimerSettings(),
        sync = sync ?? const SyncState();

  final List<PineTask> tasks;
  final List<FocusRecord> records;
  final Map<String, List<TodoItem>> todos;
  final TimerSettings settings;

  /// 未开始计时时展示的阶段。仅保存在本机，不进入云端净荷。
  final SessionMode idleMode;
  final int selectedIndex;
  final int goalTarget;
  final int weekGoal;
  final bool soundEnabled;
  final bool notifyEnabled;
  final ActiveSession? activeSession;
  final SyncState sync;

  static List<PineTask> _defaultTasks() => [
        PineTask(name: '数学真题', color: kTaskPalette[0].toARGB32()),
        PineTask(name: '错题整理', color: kTaskPalette[1].toARGB32()),
        PineTask(name: '看网课', color: kTaskPalette[2].toARGB32()),
      ];

  PineTask get selectedTask =>
      tasks.isEmpty ? PineTask(name: '未命名事件') : tasks[selectedIndex];

  /// 云端上传用的净荷：剔除推送订阅与提醒 id 等本机信息。
  Map<String, dynamic> toCloudMap() => {
        'tasks': tasks.map((task) => task.toMap()).toList(),
        'records': records.map((record) => record.toMap()).toList(),
        'todos': {
          for (final entry in todos.entries)
            entry.key: entry.value.map((item) => item.toMap()).toList(),
        },
        'settings': settings.toMap(),
        'selected': selectedIndex,
        'goalTarget': goalTarget,
        'weekGoal': weekGoal,
        'soundEnabled': soundEnabled,
        'notifyEnabled': notifyEnabled,
      };

  Map<String, dynamic> toMap() => {
        ...toCloudMap(),
        'idleMode': idleMode.key,
        'activeSession': activeSession?.toMap(),
        'sync': sync.toMap(),
      };

  AppData copyWith({
    List<PineTask>? tasks,
    SessionMode? idleMode,
    List<FocusRecord>? records,
    Map<String, List<TodoItem>>? todos,
    TimerSettings? settings,
    int? selectedIndex,
    int? goalTarget,
    int? weekGoal,
    bool? soundEnabled,
    bool? notifyEnabled,
    ActiveSession? activeSession,
    bool clearActiveSession = false,
    SyncState? sync,
  }) =>
      AppData(
        tasks: tasks ?? this.tasks,
        idleMode: idleMode ?? this.idleMode,
        records: records ?? this.records,
        todos: todos ?? this.todos,
        settings: settings ?? this.settings,
        selectedIndex: selectedIndex ?? this.selectedIndex,
        goalTarget: goalTarget ?? this.goalTarget,
        weekGoal: weekGoal ?? this.weekGoal,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        notifyEnabled: notifyEnabled ?? this.notifyEnabled,
        activeSession:
            clearActiveSession ? null : (activeSession ?? this.activeSession),
        sync: sync ?? this.sync,
      );

  /// 兼容旧版本安卓数据与网页端数据。
  static AppData fromMap(Map<dynamic, dynamic> map) {
    final rawTasks = map['tasks'];
    final tasks = rawTasks is List
        ? [
            for (var i = 0; i < rawTasks.length; i++)
              PineTask.fromMap(Map<dynamic, dynamic>.from(rawTasks[i] as Map), i),
          ]
        : _defaultTasks();

    final rawRecords = map['records'];
    final records = rawRecords is List
        ? rawRecords
            .whereType<Map>()
            .map((item) => FocusRecord.fromMap(Map<dynamic, dynamic>.from(item)))
            .toList()
        : <FocusRecord>[];

    final todos = <String, List<TodoItem>>{};
    final rawTodos = map['todos'];
    if (rawTodos is Map) {
      rawTodos.forEach((key, value) {
        if (value is! List) return;
        todos[key.toString()] = value
            .whereType<Map>()
            .map((item) => TodoItem.fromMap(Map<dynamic, dynamic>.from(item)))
            .toList();
      });
    }

    final settings = TimerSettings.fromMap(map['settings']);
    final selected = (map['selected'] as num?)?.toInt() ?? 0;

    return AppData(
      tasks: tasks,
      records: records,
      todos: todos,
      settings: settings,
      idleMode: SessionModeX.from(map['idleMode']),
      selectedIndex: selected.clamp(0, tasks.isEmpty ? 0 : tasks.length - 1),
      goalTarget: (map['goalTarget'] as num?)?.toInt() ??
          (map['goal'] as num?)?.toInt() ??
          8,
      weekGoal: (map['weekGoal'] as num?)?.toInt() ?? 20,
      soundEnabled: map['soundEnabled'] != false,
      notifyEnabled: map['notifyEnabled'] != false,
      activeSession: ActiveSession.fromMap(map['activeSession']),
      sync: SyncState.fromMap(map['sync']),
    );
  }
}
