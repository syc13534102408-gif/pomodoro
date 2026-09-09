import 'models.dart';

/// 通知职责划分的平台分类。
///
/// 只有 Android 拥有系统级 AlarmManager（可由插件预排 911、进程被杀也准时弹）；
/// macOS/桌面等没有系统级精确闹钟，只能走进程内提醒（910 + asset 三音）。
/// 用纯 Dart 枚举而不是 `Platform.isAndroid`，保证决策函数可被单测覆盖。
enum NotifyPlatform { android, other }

extension NotifyPlatformX on NotifyPlatform {
  bool get isAndroid => this == NotifyPlatform.android;
}

/// 到点提醒文案。911 系统闹钟与 910 进程内提醒共用同一份，避免双份文案漂移。
class EndAlarmCopy {
  const EndAlarmCopy({required this.title, required this.body});

  final String title;
  final String body;
}

/// 一次「到点」事件的通知决策结果。
class EndRingDecision {
  const EndRingDecision({
    required this.showLocalAlert,
    required this.playChime,
    required this.copy,
  });

  /// 是否需要立即弹 910（桌面到点 / Android restore 补偿场景）。
  final bool showLocalAlert;

  /// 是否需要播放 asset 三音（仅非 Android；Android 由系统通知音负责）。
  final bool playChime;

  final EndAlarmCopy copy;
}

/// 专注/休息「计划时长已到」的标题与正文。
///
/// [taskName] 为当前专注任务名（仅专注阶段传入），拼接进正文方便用户识别；
/// 休息阶段无任务名，维持简洁文案。
EndAlarmCopy endAlarmCopyFor({required SessionMode mode, String? taskName}) {
  if (mode.isFocus) {
    final name = (taskName == null || taskName.isEmpty) ? null : taskName;
    return EndAlarmCopy(
      title: '松果 · 计划时长已到',
      body: name == null
          ? '这一轮计划时长已到，继续专注会累计更多时长。'
          : '「$name」计划时长已到，继续专注会累计更多时长。',
    );
  }
  return const EndAlarmCopy(
    title: '松果 · 休息结束',
    body: '休息结束，可以开始下一轮专注。',
  );
}

/// 锁屏/通知栏常驻倒计时通知的标题。
///
/// 专注中把任务名放进标题，visibility PUBLIC 下锁屏与通知栏同样完整可见
/// （产品已明确不需要为隐私隐藏任务名）；休息或没有任务名时维持原
/// 「计时中/已超时」文案。
String lockTimerTitle({required bool targetReached, String? taskName}) {
  if (taskName != null && taskName.isNotEmpty) {
    return targetReached
        ? '松果 · 已超时：$taskName'
        : '松果 · 专注：$taskName';
  }
  return targetReached ? '松果 · 已超时' : '松果 · 计时中';
}

/// 是否应为正在进行的会话预排系统级 911 到点闹钟。
///
/// 仅在 Android 上成立：通知开关开启、会话处于运行、尚未到点、且有可用的
/// 计划结束时刻。由调用方在每次状态同步时求值，配合 Notifier 内部按结束
/// 时刻去重，实现幂等。
bool shouldScheduleSystemAlarm({
  required NotifyPlatform platform,
  required bool notifyEnabled,
  required bool running,
  required bool targetReached,
  required bool hasDeadline,
  bool notificationsGranted = true,
}) =>
    platform.isAndroid &&
    notifyEnabled &&
    notificationsGranted &&
    running &&
    !targetReached &&
    hasDeadline;

/// 一次「到点」事件（tick 翻转 / restore 检测到已超时）应如何响铃。
///
/// 「谁负责弹」的定死策略：
/// - Android：到点响铃统一归系统级 911（开始计时即预排，进程被杀也准时）；
///   进程内 tick 翻转时 **不再** alert 910，避免与 911 双响。
///   910 只保留给 restore 补偿场景（进程刚醒、检测到会话已过 targetReached）。
/// - macOS/桌面：无系统级闹钟，维持进程内 alert 910 + asset 三音。
///
/// [restoreCompensation] 表示本次求值是否处于「restore 检测到已到点但进程刚醒」，
/// 只有这种情况下 Android 才允许走 910。
EndRingDecision decideEndRing({
  required SessionMode mode,
  String? taskName,
  required bool notifyEnabled,
  required bool soundEnabled,
  required NotifyPlatform platform,
  required bool restoreCompensation,
  bool notificationsGranted = true,
}) {
  final isAndroid = platform.isAndroid;
  final canNotify = notifyEnabled && notificationsGranted;
  // Android 到点由 911 负责；仅 restore 补偿场景需要进程内补弹 910。
  final showLocalAlert = canNotify && (isAndroid ? restoreCompensation : true);
  // Android 的到点铃声以系统通知音为准，不再播 asset 三音防双响。
  final playChime = soundEnabled && !isAndroid;
  return EndRingDecision(
    showLocalAlert: showLocalAlert,
    playChime: playChime,
    copy: endAlarmCopyFor(mode: mode, taskName: taskName),
  );
}
