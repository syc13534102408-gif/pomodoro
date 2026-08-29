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

/// 进程被系统重启后，用保存的数据恢复通知文案。
class _PineTaskHandler extends fgt.TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, fgt.TaskStarter starter) async {
    final saved = await fgt.FlutterForegroundTask.getAllData();
    final title = saved['title']?.toString();
    final text = saved['text']?.toString();
    if (title == null || text == null) return;
    await fgt.FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// 安卓前台服务常驻通知，锁屏与后台可见。桌面端自动降级为空操作。
class ForegroundRunner {
  ForegroundRunner._();

  static const int _serviceId = 5150;
  static bool _initialised = false;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static void init() {
    if (!supported || _initialised) return;
    fgt.FlutterForegroundTask.init(
      androidNotificationOptions: fgt.AndroidNotificationOptions(
        channelId: 'pine_timer',
        channelName: '专注计时',
        channelDescription: '常驻显示当前专注或休息的剩余时间',
        channelImportance: fgt.NotificationChannelImportance.LOW,
        priority: fgt.NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        showWhen: false,
        visibility: fgt.NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const fgt.IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: fgt.ForegroundTaskOptions(
        eventAction: fgt.ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowAutoRestart: true,
      ),
    );
    _initialised = true;
  }

  static Future<void> _remember(String title, String text) async {
    await fgt.FlutterForegroundTask.saveData(key: 'title', value: title);
    await fgt.FlutterForegroundTask.saveData(key: 'text', value: text);
  }

  static Future<void> start({
    required String title,
    required String text,
  }) async {
    if (!supported) return;
    init();
    if (await fgt.FlutterForegroundTask.isRunningService) {
      await update(title: title, text: text);
      return;
    }
    await _remember(title, text);
    await fgt.FlutterForegroundTask.startService(
      serviceId: _serviceId,
      // specialUse 不受 Android 15 上 dataSync 的每日 6 小时限额约束。
      serviceTypes: const [fgt.ForegroundServiceTypes.specialUse],
      notificationTitle: title,
      notificationText: text,
      callback: pineForegroundCallback,
    );
  }

  static Future<void> update({
    required String title,
    required String text,
  }) async {
    if (!supported) return;
    if (!(await fgt.FlutterForegroundTask.isRunningService)) return;
    await _remember(title, text);
    await fgt.FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
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
