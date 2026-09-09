import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart' as fgt;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'notification_policy.dart';

// ============================== 顶层常量与回调 ==============================

/// 进程内立即提醒（910）：桌面到点 / 测试提醒 / Android restore 补偿。
const int pineAlertNotificationId = 910;

/// 系统级到点闹钟（911）：开始计时即用 zonedSchedule 预排「计划结束时刻」，
/// 到点由 AlarmManager 触发，进程被杀也能准时弹。
const int pineAlarmNotificationId = 911;

/// 到点通知上的「忽略」动作 id：点击后只撤掉该通知，不改会话状态。
const String pineAlarmIgnoreAction = 'pine_alarm_ignore';

/// 到点提醒频道：专注或休息结束时提醒（横幅 + 系统通知音 + 振动）。
const String pineAlarmChannelId = 'pine_alert';
const String pineAlarmChannelName = '专注结束提醒';
const String pineAlarmChannelDescription = '专注或休息结束时提醒';

/// 911 通知的 payload，用于在回调里识别「这是到点闹钟」。
const String pineAlarmPayload = 'pine:end-alarm';

/// 后台 isolate 的 action 回调入口（点击「忽略」等不拉起界面的 action）。
///
/// flutter_local_notifications 要求后台回调必须是带 @pragma 的顶层函数。
/// 这里只做「撤掉已弹出的 911」这类轻量操作，不触碰会话状态。
@pragma('vm:entry-point')
void pineNotificationBackgroundResponse(NotificationResponse response) {
  if (response.id != pineAlarmNotificationId ||
      response.actionId != pineAlarmIgnoreAction) {
    return;
  }
  Notifier.cancelAlarmSilently();
}

/// 本地通知插件是否已初始化完成（同一 isolate 内共享，避免重复 initialize
/// 把 Notifier 注册的点击回调覆盖掉）。
Future<void>? _pluginInitTask;

Future<void> _ensurePlugin() {
  final running = _pluginInitTask;
  if (running != null) return running;
  final task = _doPluginInit();
  _pluginInitTask = task;
  unawaited(task.then<void>((_) {}, onError: (Object _) {
    // 初始化失败（例如无通知能力的测试环境）允许下次重试，不阻塞 UI。
    _pluginInitTask = null;
  }));
  return task;
}

Future<void> _doPluginInit() async {
  final plugin = FlutterLocalNotificationsPlugin();
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@drawable/ic_notification'),
    iOS: DarwinInitializationSettings(),
    macOS: DarwinInitializationSettings(),
  );
  await plugin.initialize(
    settings,
    // 前台/进程存活时的点击回调；冷启动信息在 Notifier.init 里查 launchDetails。
    onDidReceiveNotificationResponse: Notifier.handleNotificationTap,
    // 「忽略」等不拉起界面的 action 会走到后台 isolate。
    onDidReceiveBackgroundNotificationResponse:
        pineNotificationBackgroundResponse,
  );
}

// ============================== 前台服务入口 ==============================

/// 前台服务的入口回调。必须是顶层函数。
@pragma('vm:entry-point')
void pineForegroundCallback() {
  fgt.FlutterForegroundTask.setTaskHandler(_PineTaskHandler());
}

/// 进程被系统重启后，用保存的数据恢复锁屏倒计时。
class _PineTaskHandler extends fgt.TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, fgt.TaskStarter starter) async {
    final saved = await fgt.FlutterForegroundTask.getAllData();
    await LockTimer.show(
      targetReached: saved['targetReached'] == true,
      deadlineMs: (saved['deadlineMs'] as num?)?.toInt(),
      overtimeStartedAtMs: (saved['overtimeStartedAtMs'] as num?)?.toInt(),
      fallbackText: saved['remainingTime']?.toString(),
      taskName: saved['taskName']?.toString(),
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 倒计时由系统 Chronometer 渲染（见 LockTimer），无需每秒刷新。
    // 进程被 ColorOS 冻结时重复事件同样会被挂起，靠它刷时间不可靠。
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// 安卓前台服务常驻通知，锁屏与后台可见。桌面端自动降级为空操作。
///
/// 服务本身只负责保活（WakeLock、自动重启）；倒计时显示由 [LockTimer]
/// 用系统 Chronometer 渲染，不依赖进程存活。
class ForegroundRunner {
  ForegroundRunner._();

  static const int _serviceId = 5150;
  static const String _notificationIconMetaData =
      'com.pine.pomodoro.service.NOTIFICATION_ICON';
  static const String lockChannelId = 'pine_lock_timer';
  static const String lockChannelName = '锁屏剩余时间';
  static const String lockChannelDescription = '计时运行时在锁屏显示剩余时间';
  static bool _initialised = false;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static void init() {
    if (!supported || _initialised) return;
    fgt.FlutterForegroundTask.init(
      androidNotificationOptions: fgt.AndroidNotificationOptions(
        // 使用新频道，避免已创建的旧低优先级频道继续隐藏锁屏通知。
        channelId: lockChannelId,
        channelName: lockChannelName,
        channelDescription: lockChannelDescription,
        channelImportance: fgt.NotificationChannelImportance.DEFAULT,
        priority: fgt.NotificationPriority.DEFAULT,
        enableVibration: false,
        playSound: false,
        showWhen: false,
        showBadge: false,
        onlyAlertOnce: true,
        visibility: fgt.NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const fgt.IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: fgt.ForegroundTaskOptions(
        // 倒计时不再依赖服务每秒回调：重复事件在进程被冻结时同样会停，
        // 反而造成"通知停走"的假象。走表交给系统 Chronometer。
        eventAction: fgt.ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowAutoRestart: true,
      ),
    );
    _initialised = true;
  }

  static Future<void> _remember(
    String remainingTime, {
    int? deadlineMs,
    int? overtimeStartedAtMs,
    bool targetReached = false,
    String? taskName,
  }) async {
    await fgt.FlutterForegroundTask.saveData(
      key: 'remainingTime',
      value: remainingTime,
    );
    if (deadlineMs != null) {
      await fgt.FlutterForegroundTask.saveData(
        key: 'deadlineMs',
        value: deadlineMs,
      );
    }
    if (overtimeStartedAtMs != null) {
      await fgt.FlutterForegroundTask.saveData(
        key: 'overtimeStartedAtMs',
        value: overtimeStartedAtMs,
      );
    }
    await fgt.FlutterForegroundTask.saveData(
      key: 'targetReached',
      value: targetReached,
    );
    if (taskName != null) {
      await fgt.FlutterForegroundTask.saveData(
        key: 'taskName',
        value: taskName,
      );
    }
  }

  static Future<void> start({
    required String remainingTime,
    int? deadlineMs,
    int? overtimeStartedAtMs,
    bool targetReached = false,
    String? taskName,
  }) async {
    if (!supported) return;
    init();
    if (await fgt.FlutterForegroundTask.isRunningService) {
      await update(
        remainingTime: remainingTime,
        deadlineMs: deadlineMs,
        overtimeStartedAtMs: overtimeStartedAtMs,
        targetReached: targetReached,
        taskName: taskName,
      );
      return;
    }
    await _remember(
      remainingTime,
      deadlineMs: deadlineMs,
      overtimeStartedAtMs: overtimeStartedAtMs,
      targetReached: targetReached,
      taskName: taskName,
    );
    await fgt.FlutterForegroundTask.startService(
      serviceId: _serviceId,
      // specialUse 不受 Android 15 上 dataSync 的每日 6 小时限额约束。
      serviceTypes: const [fgt.ForegroundServiceTypes.specialUse],
      notificationTitle: remainingTime,
      notificationText: '',
      notificationIcon: const fgt.NotificationIcon(
        metaDataName: _notificationIconMetaData,
      ),
      callback: pineForegroundCallback,
    );
    await LockTimer.show(
      targetReached: targetReached,
      deadlineMs: deadlineMs,
      overtimeStartedAtMs: overtimeStartedAtMs,
      fallbackText: remainingTime,
      taskName: taskName,
    );
  }

  static Future<void> update({
    required String remainingTime,
    int? deadlineMs,
    int? overtimeStartedAtMs,
    bool targetReached = false,
    String? taskName,
  }) async {
    if (!supported) return;
    if (!(await fgt.FlutterForegroundTask.isRunningService)) return;
    await _remember(
      remainingTime,
      deadlineMs: deadlineMs,
      overtimeStartedAtMs: overtimeStartedAtMs,
      targetReached: targetReached,
      taskName: taskName,
    );
    await fgt.FlutterForegroundTask.updateService(
      notificationTitle: remainingTime,
      notificationText: '',
      notificationIcon: const fgt.NotificationIcon(
        metaDataName: _notificationIconMetaData,
      ),
    );
    await LockTimer.show(
      targetReached: targetReached,
      deadlineMs: deadlineMs,
      overtimeStartedAtMs: overtimeStartedAtMs,
      fallbackText: remainingTime,
      taskName: taskName,
    );
  }

  static Future<void> stop() async {
    if (!supported) return;
    if (!(await fgt.FlutterForegroundTask.isRunningService)) return;
    await fgt.FlutterForegroundTask.stopService();
  }

  /// 跳转到系统电池优化设置。OPPO 等机型需要手动放行才能保证后台计时。
  static Future<void> openBatterySettings() async {
    if (!supported) return;
    await fgt.FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
  }

  /// 尝试直接申请忽略电池优化，失败时回退到设置页。
  static Future<bool> requestBatteryExemption() async {
    if (!supported) return true;
    final granted =
        await fgt.FlutterForegroundTask.requestIgnoreBatteryOptimization();
    if (granted) return true;
    await openBatterySettings();
    return false;
  }
}

// ============================== 锁屏倒计时 ==============================

/// 锁屏倒计时通知：用 Android 系统 Chronometer 渲染剩余/超时时长。
///
/// 走表由 SystemUI（系统进程）完成，不依赖本 App 进程存活——即使 ColorOS
/// 把进程冻结，锁屏上的时间也在走。这是"进程内每秒刷新"方案做不到的。
///
/// 与前台服务通知同 id、同频道：发布即原地替换其内容，不会出现第二条通知。
class LockTimer {
  LockTimer._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> _ensureInit() async {
    if (_ready) return;
    // 复用全局初始化（含点击回调），避免二次 initialize 覆盖回调。
    await _ensurePlugin();
    // 频道通常已由前台服务创建；进程被系统重启的恢复路径里可能还没有，
    // 幂等创建一次（已存在频道设置不会被覆盖）。
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            ForegroundRunner.lockChannelId,
            ForegroundRunner.lockChannelName,
            description: ForegroundRunner.lockChannelDescription,
          ),
        );
    _ready = true;
  }

  /// 按当前计时状态发布通知。
  ///
  /// [deadlineMs]：计划结束时刻；[overtimeStartedAtMs]：超时起点；
  /// [targetReached]：是否已到计划时长（超时倒计改为累计）。
  /// [fallbackText]：拿不到时间锚点时退回的静态文案。
  /// [taskName]：专注阶段的任务名，放进标题，锁屏与通知栏都完整可见。
  static Future<void> show({
    required bool targetReached,
    int? deadlineMs,
    int? overtimeStartedAtMs,
    String? fallbackText,
    String? taskName,
  }) async {
    if (!ForegroundRunner.supported) return;
    try {
      await _ensureInit();
      // 正常计时时从 deadline 往回数；超时后从起点往上数。
      final baseMs =
          targetReached ? (overtimeStartedAtMs ?? deadlineMs) : deadlineMs;
      if (baseMs == null) {
        await _plugin.show(
          ForegroundRunner._serviceId,
          fallbackText ?? '松果',
          null,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              ForegroundRunner.lockChannelId,
              ForegroundRunner.lockChannelName,
              channelDescription: ForegroundRunner.lockChannelDescription,
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              ongoing: true,
              icon: 'ic_notification',
              autoCancel: false,
              showWhen: false,
              onlyAlertOnce: true,
              visibility: NotificationVisibility.public,
            ),
          ),
        );
        return;
      }
      final details = AndroidNotificationDetails(
        ForegroundRunner.lockChannelId,
        ForegroundRunner.lockChannelName,
        channelDescription: ForegroundRunner.lockChannelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        ongoing: true,
        icon: 'ic_notification',
        autoCancel: false,
        showWhen: true,
        when: baseMs,
        usesChronometer: true,
        chronometerCountDown: !targetReached,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        channelShowBadge: false,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.stopwatch,
      );
      await _plugin.show(
        ForegroundRunner._serviceId,
        lockTimerTitle(targetReached: targetReached, taskName: taskName),
        null,
        NotificationDetails(android: details),
      );
    } catch (_) {
      // 锁屏通知属于可降级能力：失败时前台服务的静态标题仍然兜底。
    }
  }
}

// ============================== 到点提醒与提示音 ==============================

/// 到点提醒与提示音。
///
/// 职责分工（与 notification_policy.decideEndRing 保持一致）：
/// - 911：Android 系统级到点闹钟，开始计时即预排，进程被杀也准时弹。
/// - 910：桌面到点 / 测试提醒 / Android「restore 检测已到点但进程刚醒」补偿。
/// - chime：asset 三音，仅桌面/设置页试听；Android 到点不再播（防双响）。
class Notifier {
  Notifier._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final AudioPlayer _player = AudioPlayer();

  static bool get androidSupported => !kIsWeb && Platform.isAndroid;

  /// 主界面注册的「回到专注首页」回调（用户点击 911 到点通知时触发）。
  static void Function()? onOpenHomeRequested;

  /// 本次启动是否来自 911 到点通知（用户已见过到点提醒，无需再补偿弹 910）。
  static bool launchedByAlarmNotification = false;

  /// 最近一次成功预排的系统闹钟结束时刻（ms）。用于幂等：同一结束时刻不重复排。
  static int? _scheduledDeadlineMs;

  static bool _exactPromptStarted = false;

  static Future<void>? _initTask;

  /// restore 补偿（910）持久化去重标记。key 记录「最近一次已补偿的超时会话」，
  /// 同一次「超时运行中」会话只补弹一次，避免每次冷启动重复提醒。
  static const String _restoreMarkerKey = 'pine_restore_compensated_910';

  static String _restoreMarker(String recordId, int anchorMs) =>
      '$recordId@$anchorMs';

  /// 初始化（幂等）：加载 timezone 数据库 → 初始化插件 → 建频道 → 查冷启动。
  static Future<void> init() {
    final running = _initTask;
    if (running != null) return running;
    final created = _doInit();
    _initTask = created;
    unawaited(created.then<void>((_) {}, onError: (Object _) {
      _initTask = null;
    }));
    return created;
  }

  static Future<void> _doInit() async {
    if (androidSupported) {
      // timezone 数据库只需加载一次（同步完成，很快）；放异步里不阻塞 UI。
      // tz.local 默认是 UTC，但 zonedSchedule 按「绝对时刻」触发，
      // 用 tz.TZDateTime.from 转换后 epoch 不变，闹钟仍然准时。
      tzdata.initializeTimeZones();
    }
    await _ensurePlugin();
    await createChannel();
    await _checkColdLaunch();
  }

  static AndroidFlutterLocalNotificationsPlugin? _androidImpl() =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> createChannel() async {
    await _androidImpl()?.createNotificationChannel(
      const AndroidNotificationChannel(
        pineAlarmChannelId,
        pineAlarmChannelName,
        description: pineAlarmChannelDescription,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  /// 冷启动分支：App 是被 911 到点通知点开的 → 回到首页并标记已见。
  static Future<void> _checkColdLaunch() async {
    if (!androidSupported) return;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || details.didNotificationLaunchApp != true) return;
      final response = details.notificationResponse;
      if (response == null || response.id != pineAlarmNotificationId) return;
      launchedByAlarmNotification = true;
      // 「忽略」动作不会拉起 Activity；能走到这里说明是主点击。
      onOpenHomeRequested?.call();
    } catch (_) {
      // 冷启动信息属于可降级能力：拿不到就按普通启动处理。
    }
  }

  /// 前台/进程存活时的点击与 action 回调。
  static void handleNotificationTap(NotificationResponse response) {
    final id = response.id;
    if (id == null || id != pineAlarmNotificationId) return;
    if (response.actionId == pineAlarmIgnoreAction) {
      // 「忽略」：只撤掉该通知，不改会话状态。
      cancelAlarmSilently();
      return;
    }
    // 主点击：用户希望回到 App 首页。
    launchedByAlarmNotification = true;
    onOpenHomeRequested?.call();
  }

  /// 请求通知权限（Android 13+ 弹系统授权；幂等，已授权时无骚扰）。
  static Future<void> requestPermission() async {
    await init();
    await _androidImpl()?.requestNotificationsPermission();
    if (!kIsWeb && Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: false, sound: true);
    }
    if (!kIsWeb && Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: false, sound: true);
    }
  }

  /// Android 12+ 精确闹钟授权入口。只尝试一次；被拒后由排程分支自动降级
  /// inexactAllowWhileIdle。授权成功后清掉缓存，让下一次同步以精确模式重排。
  static Future<void> maybeRequestExactAlarmPermission() async {
    if (!androidSupported || _exactPromptStarted) return;
    _exactPromptStarted = true;
    try {
      final android = _androidImpl();
      final canSchedule = await android?.canScheduleExactNotifications();
      if (canSchedule == true) return;
      final granted = await android?.requestExactAlarmsPermission();
      if (granted == true) {
        _scheduledDeadlineMs = null;
      }
    } catch (_) {
      // 授权入口失败（厂商定制等）不阻塞：降级分支已处理。
    }
  }

  /// 当前是否已获系统通知权限。Android 之外一律视为允许。
  static Future<bool> notificationsGranted() async {
    if (!androidSupported) return true;
    await init();
    try {
      return (await _androidImpl()?.areNotificationsEnabled()) ?? false;
    } catch (_) {
      // 拿不到权限态时按“允许”处理，避免静默丢提醒。
      return true;
    }
  }

  /// 911 到点通知是否仍在通知栏（未点/未滑掉）。用于 restore 补偿去重：
  /// 若系统闹钟已弹出并还在通知栏，就不再补弹 910。
  static Future<bool> isAlarmNotificationActive() async {
    if (!androidSupported) return false;
    await init();
    try {
      final active = await _plugin.getActiveNotifications();
      return active.any((item) => item.id == pineAlarmNotificationId);
    } catch (_) {
      return false;
    }
  }

  /// A2：同一次「超时运行中」会话是否已经做过 restore 补偿（910）。
  ///
  /// [anchorMs] 用超时起点（无则计划结束时刻）标识“同一段超时”，配合
  /// recordId 一起持久化，跨冷启动生效。读不到标记时按“未补偿”处理。
  static Future<bool> restoreCompensationDone({
    required String recordId,
    required int anchorMs,
  }) async {
    if (!androidSupported) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_restoreMarkerKey) ==
          _restoreMarker(recordId, anchorMs);
    } catch (_) {
      return false;
    }
  }

  /// A2：记录「该超时会话已做过 restore 补偿」。
  static Future<void> markRestoreCompensationDone({
    required String recordId,
    required int anchorMs,
  }) async {
    if (!androidSupported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _restoreMarkerKey,
        _restoreMarker(recordId, anchorMs),
      );
    } catch (_) {
      // 持久化失败可忽略：最坏情况是下次冷启动再补一次。
    }
  }

  /// 预排「计划结束时刻」的系统闹钟（id 911）。
  ///
  /// 幂等：与上次成功的结束时刻相同则直接返回；不同则先撤旧排程再排新的。
  /// Android 12+ 未授权精确闹钟时降级为 inexactAllowWhileIdle（可能延迟）。
  /// 返回是否成功（失败不缓存，下次同步会重试）。
  static Future<bool> scheduleEndAlarm({
    required DateTime deadline,
    required SessionMode mode,
    String? taskName,
  }) async {
    if (!androidSupported) return false;
    await init();
    final deadlineMs = deadline.millisecondsSinceEpoch;
    if (_scheduledDeadlineMs == deadlineMs) return true;
    final copy = endAlarmCopyFor(mode: mode, taskName: taskName);
    try {
      if (_scheduledDeadlineMs != null) {
        await _plugin.cancel(pineAlarmNotificationId);
      }
      final android = _androidImpl();
      final exactGranted =
          (await android?.canScheduleExactNotifications()) ?? false;
      await _plugin.zonedSchedule(
        pineAlarmNotificationId,
        copy.title,
        copy.body,
        tz.TZDateTime.from(deadline, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            pineAlarmChannelId,
            pineAlarmChannelName,
            channelDescription: pineAlarmChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            icon: 'ic_notification',
            autoCancel: true,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            actions: [AndroidNotificationAction(pineAlarmIgnoreAction, '忽略')],
          ),
        ),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: exactGranted
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: pineAlarmPayload,
      );
      _scheduledDeadlineMs = deadlineMs;
      return true;
    } catch (_) {
      _scheduledDeadlineMs = null;
      return false;
    }
  }

  /// 撤掉已预排/已弹出的 911 系统闹钟（暂停/切阶段/重置/完成/关通知时调用）。
  static Future<void> cancelEndAlarm() async {
    _scheduledDeadlineMs = null;
    if (!androidSupported) return;
    try {
      await init();
      await _plugin.cancel(pineAlarmNotificationId);
    } catch (_) {
      // 撤闹钟失败可忽略：下一次状态同步会再尝试。
    }
  }

  /// 后台 isolate 用的轻量撤除（不重新 init，失败静默）。
  static void cancelAlarmSilently() {
    _scheduledDeadlineMs = null;
    if (!androidSupported) return;
    unawaited(_plugin.cancel(pineAlarmNotificationId).catchError((Object _) {}));
  }

  static Future<void> alert({
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(
      pineAlertNotificationId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          pineAlarmChannelId,
          pineAlarmChannelName,
          icon: 'ic_notification',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          category: AndroidNotificationCategory.alarm,
        ),
        iOS: DarwinNotificationDetails(presentSound: true),
        macOS: DarwinNotificationDetails(presentSound: true),
      ),
    );
  }

  static Future<void> cancel() async {
    if (_initTask == null) return;
    await _plugin.cancel(pineAlertNotificationId);
  }

  /// 三音提示音。
  static Future<void> chime() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/chime.wav'));
    } catch (_) {
      // 桌面端缺少音频设备时静默忽略，不打断计时。
    }
  }
}
