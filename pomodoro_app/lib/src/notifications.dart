import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart' as fgt;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  }

  static Future<void> start({
    required String remainingTime,
    int? deadlineMs,
    int? overtimeStartedAtMs,
    bool targetReached = false,
  }) async {
    if (!supported) return;
    init();
    if (await fgt.FlutterForegroundTask.isRunningService) {
      await update(
        remainingTime: remainingTime,
        deadlineMs: deadlineMs,
        overtimeStartedAtMs: overtimeStartedAtMs,
        targetReached: targetReached,
      );
      return;
    }
    await _remember(
      remainingTime,
      deadlineMs: deadlineMs,
      overtimeStartedAtMs: overtimeStartedAtMs,
      targetReached: targetReached,
    );
    await fgt.FlutterForegroundTask.startService(
      serviceId: _serviceId,
      // specialUse 不受 Android 15 上 dataSync 的每日 6 小时限额约束。
      serviceTypes: const [fgt.ForegroundServiceTypes.specialUse],
      notificationTitle: remainingTime,
      notificationText: '',
      callback: pineForegroundCallback,
    );
    await LockTimer.show(
      targetReached: targetReached,
      deadlineMs: deadlineMs,
      overtimeStartedAtMs: overtimeStartedAtMs,
      fallbackText: remainingTime,
    );
  }

  static Future<void> update({
    required String remainingTime,
    int? deadlineMs,
    int? overtimeStartedAtMs,
    bool targetReached = false,
  }) async {
    if (!supported) return;
    if (!(await fgt.FlutterForegroundTask.isRunningService)) return;
    await _remember(
      remainingTime,
      deadlineMs: deadlineMs,
      overtimeStartedAtMs: overtimeStartedAtMs,
      targetReached: targetReached,
    );
    await fgt.FlutterForegroundTask.updateService(
      notificationTitle: remainingTime,
      notificationText: '',
    );
    await LockTimer.show(
      targetReached: targetReached,
      deadlineMs: deadlineMs,
      overtimeStartedAtMs: overtimeStartedAtMs,
      fallbackText: remainingTime,
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
  static bool _initialised = false;

  static Future<void> _ensureInit() async {
    if (_initialised) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
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
    _initialised = true;
  }

  /// 按当前计时状态发布通知。
  ///
  /// [deadlineMs]：计划结束时刻；[overtimeStartedAtMs]：超时起点；
  /// [targetReached]：是否已到计划时长（超时倒计改为累计）。
  /// [fallbackText]：拿不到时间锚点时退回的静态文案。
  static Future<void> show({
    required bool targetReached,
    int? deadlineMs,
    int? overtimeStartedAtMs,
    String? fallbackText,
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
        targetReached ? '松果 · 已超时' : '松果 · 计时中',
        null,
        NotificationDetails(android: details),
      );
    } catch (_) {
      // 锁屏通知属于可降级能力：失败时前台服务的静态标题仍然兜底。
    }
  }
}

/// 到点提醒与提示音。
class Notifier {
  Notifier._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final AudioPlayer _player = AudioPlayer();
  static bool _initialised = false;

  static const int _alertId = 910;
  static const String _channelId = 'pine_alert';
  static const String _channelName = '专注结束提醒';

  static Future<void> init() async {
    if (_initialised) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);
    await createChannel();
    _initialised = true;
  }

  static Future<void> createChannel() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: '专注或休息结束时提醒',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  static Future<void> requestPermission() async {
    await init();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
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

  static Future<void> alert({
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(
      _alertId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
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
    if (!_initialised) return;
    await _plugin.cancel(_alertId);
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
