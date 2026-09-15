import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../src/cloud_auto.dart';
import '../src/cloud_sync.dart';
import '../src/engine.dart';
import '../src/menu_bar_timer.dart';
import '../src/models.dart';
import '../src/notification_policy.dart';
import '../src/notifications.dart';
import '../src/session_channel.dart';
import '../src/sheets.dart';
import '../src/storage.dart';
import '../src/theme.dart';
import '../src/widgets.dart';
import 'settings_page.dart';
import 'stats_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  AppData _data = AppData();
  Timer? _ticker;
  bool _ready = false;
  bool _syncingForeground = false;
  bool _goalPulse = false;
  bool _stampVisible = false;
  Timer? _stampTimer;
  String _foregroundKey = '';
  DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);
  late final AutoCloudSync _autoSync;

  /// 桌面端（macOS）专属导航，与安卓手机布局互不影响。
  static bool get _desktop => defaultTargetPlatform == TargetPlatform.macOS;

  /// 真实运行在 Android 上（widget test 的宿主是 macOS，不能用 defaultTargetPlatform 判断）。
  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  static const _overlayNone = 0;
  static const _overlayStats = 1;
  static const _overlaySettings = 2;
  int _desktopOverlay = _overlayNone; // 0=无抽屉 1=统计 2=设置（方向 B 专注舱）

  /// 手机端底部导航当前 Tab（专注 / 报告 / 设置，D1）。
  int _tab = 0;

  /// 上一次按策略期望的系统闹钟结束时刻；null 表示当前不想要 911。
  /// 与 Notifier 内部缓存不同：它记录的是「进程内已成功预排的时刻」，
  /// 这里记录的是「按当前状态应该存在的排程」，用于去重与开关联动。
  int? _desiredAlarmDeadlineMs;

  // ==================== 会话实时镜像（对等控制，方案 A 短轮询） ====================

  /// 传输失败一律静默：镜像能力可降级，绝不影响本地计时。
  SessionChannel? _sessionChannel;
  Timer? _mirrorTimer;

  /// 备份同步的低频定时拉取：Mac 端 App 常驻前台时 lifecycle 不变化、
  /// 不会触发 onResume，没有它 Mac 的数据会一直停留在上次启动时刻。
  Timer? _backupSyncTimer;
  bool _mirrorEnabled = false;

  /// 全局单调序号：本机发布与远端采纳共用一个计数，保证后写者胜。
  int _sessionSeq = 0;

  /// 本机设备标识（首次运行生成，存独立 prefs 键，不进云净荷）。
  String _deviceId = '';

  /// 上一次发布的会话内容摘要，内容没变就不发（抑制乒乓）。
  String? _lastPublishedSessionJson;

  static const _mirrorPrefsKey = 'pine-session-mirror';
  static const _deviceIdPrefsKey = 'pine-device-id';

  NotifyPlatform get _notifyPlatform =>
      _isAndroid ? NotifyPlatform.android : NotifyPlatform.other;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 用户点击 911 到点通知 → 回到专注首页（冷启动由 Notifier 查 launchDetails
    // 后走同一个回调；bootstrap 完成后才真正消费）。
    Notifier.onOpenHomeRequested = _openHomeFromNotification;
    _autoSync = AutoCloudSync(
      sync: CloudSync(),
      apply: (data) async {
        if (!mounted) return;
        _apply(data, force: true);
      },
    );
    unawaited(_bootstrap());
    if (_desktop) {
      // 菜单栏菜单的点击动作与快捷键走同一套引擎方法，不另起状态。
      MenuBarTimer.listen(_onMenuBarAction);
    }
  }

  /// 点击到点通知后回到专注首页（手机切到「专注」Tab；桌面切回计时页）。
  void _openHomeFromNotification() {
    if (!mounted) return;
    setState(() {
      _tab = 0;
      _desktopOverlay = _overlayNone;
    });
  }

  void _onMenuBarAction(MenuBarAction action) {
    // 菜单栏是顶层意图：若抽屉打开先收起，再执行动作。
    _desktopCloseOverlay();
    switch (action) {
      case MenuBarAction.toggle:
        _toggleRun();
      case MenuBarAction.complete:
        _confirm();
      case MenuBarAction.discard:
        _discard();
    }
  }

  /// 备份同步低频拉取：每 3 分钟一次，onResume 自带 updatedAt 与 15 秒
  /// minInterval 保护，重复调用安全；失败静默（网络异常不影响计时）。
  void _startBackupSyncTimer() {
    _backupSyncTimer?.cancel();
    _backupSyncTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      if (!mounted || !_ready) return;
      unawaited(_autoSync.onResume(context, _data));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stampTimer?.cancel();
    _mirrorTimer?.cancel();
    _backupSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick(forcePersist: true);
      // 回到前台：拉取网页端可能刚上传的更新。
      unawaited(_autoSync.onResume(context, _data));
      // 镜像轮询只在前台跑（后台冻结时轮询无意义），回前台立即收敛一次。
      if (_mirrorEnabled) {
        _startMirrorTimer();
        unawaited(_pollSessionMirror());
      }
      _startBackupSyncTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _mirrorTimer?.cancel();
      _backupSyncTimer?.cancel();
      _persist(force: true);
    }
  }

  Future<void> _bootstrap() async {
    // 通知与前台服务属于可降级能力：初始化失败或挂起都不应阻塞计时界面。
    unawaited(Notifier.init().catchError((Object _) {}));
    try {
      ForegroundRunner.init();
    } catch (_) {
      // 桌面端或不具备前台服务的环境直接跳过。
    }

    AppData loaded;
    try {
      loaded = await Storage.load().timeout(const Duration(seconds: 8));
    } catch (_) {
      loaded = AppData();
    }
    final restored = TimerEngine.restore(loaded, DateTime.now());
    if (!mounted) return;
    setState(() {
      _data = restored;
      _ready = true;
    });
    _persist(force: true);
    _startTicker();
    _startBackupSyncTimer();
    // 会话实时镜像：读开关与本机设备标识，开启则启动前台轮询。
    try {
      final prefs = await SharedPreferences.getInstance();
      _mirrorEnabled = prefs.getBool(_mirrorPrefsKey) ?? false;
      _deviceId = prefs.getString(_deviceIdPrefsKey) ?? '';
      if (_deviceId.isEmpty) {
        final rand = DateTime.now().microsecondsSinceEpoch.toRadixString(16) +
            DateTime.now().hashCode.toRadixString(16);
        _deviceId =
            'pine-${rand.replaceAll('-', '').padRight(12, '0').substring(0, 12)}';
        await prefs.setString(_deviceIdPrefsKey, _deviceId);
      }
      if (_mirrorEnabled) _startMirrorTimer();
    } catch (_) {
      // 镜像初始化失败不影响主流程。
    }
    await _syncForeground();
    // 冷启动来自 911 到点通知时，launchDetails 会经 Notifier 回调切回首页；
    // 这里再补一次状态消费（幂等，只是确保 tab 正确）。
    if (mounted) _openHomeFromNotification();
    // Android restore 补偿：进程刚醒且会话已过 targetReached（如被强制停止后
    // 重新打开）时补弹 910——这是 910 在 Android 上仅剩的使用场景。
    if (mounted) unawaited(_compensateRestoredAlarm(restored));
    // 启动时拉取一次云端更新（已绑定同步码的情况下）。
    if (mounted) unawaited(_autoSync.onResume(context, _data));
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick({bool forcePersist = false}) {
    if (!mounted || !_ready) return;
    final now = DateTime.now();
    var next = TimerEngine.advance(_data, now);
    final reachedBefore = _data.activeSession?.targetReached ?? false;
    final reachedAfter = next.activeSession?.targetReached ?? false;
    if (!reachedBefore && reachedAfter) _announce(next.activeSession?.mode);
    next = TimerEngine.syncMinutes(next, now);
    setState(() => _data = next);
    _persist(force: forcePersist);
    // macOS 菜单栏：每秒跟随本地计时走表。
    _syncMenuBar();
    unawaited(_syncForeground());
  }

  /// 把当前状态推给 macOS 菜单栏。原生侧会在文案没变时跳过重绘。
  void _syncMenuBar() {
    if (!_desktop) return;
    MenuBarTimer.update(menuBarStateOf(_data, DateTime.now()));
  }

  void _persist({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastPersist).inSeconds < 10) return;
    _lastPersist = now;
    unawaited(Storage.save(_data));
  }

  void _apply(AppData next, {bool force = false, bool fromRemote = false}) {
    setState(() => _data = next);
    _persist(force: force);
    // 用户一操作就刷新菜单栏，别等下一秒的 tick。
    _syncMenuBar();
    unawaited(_syncForeground());
    // 会话镜像：本机状态变化即广播（采纳远端状态时抑制，防乒乓）。
    unawaited(_publishSession(next, fromRemote: fromRemote));
  }

  // ==================== 会话实时镜像 ====================

  void _startMirrorTimer() {
    _mirrorTimer?.cancel();
    _mirrorTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_pollSessionMirror());
    });
  }

  /// 广播本机会话快照。内容与上次相同则跳过；失败静默。
  Future<void> _publishSession(AppData next, {bool fromRemote = false}) async {
    if (fromRemote || !_mirrorEnabled || !_ready) return;
    final code = next.sync.deviceCode;
    if (code.isEmpty) return;
    try {
      (_sessionChannel ??= SessionChannel());
      final session = next.activeSession;
      final payloadJson = jsonEncode(session?.toMap());
      // 内容没变就不发：idle 期间 _apply 的重复调用、恢复同一状态等场景。
      if (payloadJson == _lastPublishedSessionJson) return;
      _lastPublishedSessionJson = payloadJson;
      // seq 用 epoch 毫秒：两端各自的独立计数器会撞号（交错发布时 N vs N），
      // 撞号 + 严格大于判定会让对端的更新被静默忽略——「Mac 已完成、手机
      // 还在进行」的根因。毫秒时间戳全局单调，后写者胜才真正成立。
      final seq = DateTime.now().millisecondsSinceEpoch;
      _sessionSeq = seq;
      await _sessionChannel!.publish(
        deviceCode: code,
        deviceId: _deviceId,
        seq: seq,
        session: session?.toMap(),
        taskName: next.selectedTask.name,
      );
    } catch (_) {
      // 发布失败不影响本地状态；下次状态变化会再带新 seq 发布。
    }
  }

  /// 轮询远端会话快照，有更新且非本机回声时采纳。
  Future<void> _pollSessionMirror() async {
    if (!mounted || !_mirrorEnabled || !_ready) return;
    final code = _data.sync.deviceCode;
    if (code.isEmpty) return;
    try {
      (_sessionChannel ??= SessionChannel());
      final remote = await _sessionChannel!.poll(code);
      if (!mounted) return;
      if (!shouldAdoptRemoteSession(
        lastSeenSeq: _sessionSeq,
        remoteSeq: remote.seq,
        selfDeviceId: _deviceId,
        remoteDeviceId: remote.deviceId,
      )) {
        return;
      }
      _sessionSeq = remote.seq;
      if (remote.session == null) {
        // 对端完成/丢弃/未开始：本机清会话（不写统计，记录走备份同步）。
        if (_data.activeSession == null) return;
        _apply(TimerEngine.discard(_data), force: true, fromRemote: true);
      } else {
        _apply(
          TimerEngine.adoptRemoteSession(
            _data,
            remote.session,
            taskName: remote.taskName,
          ),
          force: true,
          fromRemote: true,
        );
      }
    } catch (_) {
      // 网络/格式问题静默：3 秒后下一轮再试。
    }
  }

  /// 设置页开关回调（独立 prefs 键，不进云净荷——两端各自开关，无需同步）。
  Future<void> _setMirrorEnabled(bool enabled) async {
    setState(() => _mirrorEnabled = enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_mirrorPrefsKey, enabled);
    } catch (_) {}
    if (enabled) {
      _startMirrorTimer();
      unawaited(_pollSessionMirror());
    } else {
      _mirrorTimer?.cancel();
    }
  }

  /// 进程内到点翻转（每秒 tick 检测到 targetReached 由 false→true）。
  ///
  /// 谁负责弹：Android 到点响铃已由开始计时时预排的 911 系统闹钟负责，这里
  /// 对 Android 不 alert 910、也不 chime（防双响）；macOS/桌面维持 alert + chime。
  void _announce(SessionMode? mode) {
    if (mode == null) return;
    final decision = decideEndRing(
      mode: mode,
      taskName: _currentFocusTaskName(_data.activeSession),
      notifyEnabled: _data.notifyEnabled,
      soundEnabled: _data.soundEnabled,
      platform: _notifyPlatform,
      restoreCompensation: false,
    );
    if (decision.showLocalAlert) {
      unawaited(Notifier.alert(
        title: decision.copy.title,
        body: decision.copy.body,
      ));
    }
    if (decision.playChime) unawaited(Notifier.chime());
  }

  /// 当前会话的任务名：仅专注阶段返回（取记录里 inProgress 的 taskName，
  /// 取不到回退 selectedTask.name）；休息阶段返回 null，维持原文案。
  String? _currentFocusTaskName(ActiveSession? session) {
    if (session == null || !session.mode.isFocus) return null;
    for (final record in _data.records) {
      if (record.id == session.recordId &&
          record.status == RecordStatus.inProgress) {
        return record.taskName;
      }
    }
    return _data.selectedTask.name;
  }

  /// Android restore 补偿：冷启动恢复后发现「会话在运行且已过计划时长」，
  /// 说明进程在到点前后没机会走 tick 翻转；若系统闹钟也没能弹出（例如
  /// 被强制停止后重启），这里补弹一次 910。
  ///
  /// QA A2：同一次「超时运行中」会话只补弹一次（持久化标记跨冷启动生效），
  /// 避免每次冷启动重复提醒；从 911 点击进入 / 911 仍在通知栏也视为已提醒
  /// 并记录标记，不再补弹。
  Future<void> _compensateRestoredAlarm(AppData data) async {
    if (!_isAndroid) return;
    final active = data.activeSession;
    if (active == null || !active.running || !active.targetReached) return;
    if (!data.notifyEnabled) return;
    final anchorMs = active.overtimeStartedAt?.millisecondsSinceEpoch ??
        active.deadline?.millisecondsSinceEpoch ??
        0;
    try {
      if (await Notifier.restoreCompensationDone(
        recordId: active.recordId,
        anchorMs: anchorMs,
      )) {
        return; // 同一次超时已补偿过，跳过。
      }
    } catch (_) {
      // 查询失败不阻塞，按“未补偿”处理。
    }
    if (Notifier.launchedByAlarmNotification) {
      // 用户是从 911 到点通知点进来的，已经见过提醒。
      await Notifier.markRestoreCompensationDone(
        recordId: active.recordId,
        anchorMs: anchorMs,
      );
      return;
    }
    try {
      if (await Notifier.isAlarmNotificationActive()) {
        // 911 仍在通知栏：系统闹钟已送达，视为已提醒并记录。
        await Notifier.markRestoreCompensationDone(
          recordId: active.recordId,
          anchorMs: anchorMs,
        );
        return;
      }
    } catch (_) {
      // 查询失败不阻塞，按“需要补偿”处理。
    }
    final decision = decideEndRing(
      mode: active.mode,
      taskName: _currentFocusTaskName(active),
      notifyEnabled: data.notifyEnabled,
      soundEnabled: data.soundEnabled,
      platform: _notifyPlatform,
      restoreCompensation: true,
      notificationsGranted: await Notifier.notificationsGranted(),
    );
    if (decision.showLocalAlert) {
      unawaited(Notifier.alert(
        title: decision.copy.title,
        body: decision.copy.body,
      ));
      await Notifier.markRestoreCompensationDone(
        recordId: active.recordId,
        anchorMs: anchorMs,
      );
    }
    if (decision.playChime) unawaited(Notifier.chime());
  }

  /// 把当前状态同步给前台服务（锁屏倒计时）与系统级 911 到点闹钟。
  ///
  /// - 前台服务：只在状态切换（模式/运行/超时）时更新——倒计时由系统
  ///   Chronometer 走表，逐秒重发反而会与系统渲染互相覆盖。
  /// - 911：按通知策略决定要不要排/撤；同一结束时刻由 Notifier 内部与
  ///   [_desiredAlarmDeadlineMs] 双重去重，状态不变时不产生平台调用。
  Future<void> _syncForeground() async {
    if (_syncingForeground) return;
    _syncingForeground = true;
    try {
      final now = DateTime.now();
      final view = SessionView.of(_data, now);
      final active = _data.activeSession;
      await _syncEndAlarm(view, active);
      if (view == null || !view.running) {
        if (_foregroundKey.isNotEmpty) {
          _foregroundKey = '';
          await ForegroundRunner.stop();
        }
        return;
      }
      final key = '${active?.mode.key}|${view.running}|${view.targetReached}';
      if (key == _foregroundKey) return;
      _foregroundKey = key;
      await ForegroundRunner.start(
        remainingTime: view.clockText,
        deadlineMs: active?.deadline?.millisecondsSinceEpoch,
        overtimeStartedAtMs: active?.overtimeStartedAt?.millisecondsSinceEpoch,
        targetReached: view.targetReached,
        taskName: _currentFocusTaskName(active),
      );
    } catch (_) {
      // 前台服务/系统闹钟不可用时不应影响计时。
    } finally {
      _syncingForeground = false;
    }
  }

  /// 系统级 911 到点闹钟的「要排/要撤」决策执行。
  ///
  /// QA A1：到点翻转（targetReached false→true）那一刻不撤 911——此刻闹钟刚
  /// 送达/仍在通知栏，立即 cancel 会让已送达的提醒“闪断”。911 只会在
  /// 完成/暂停/丢弃/切模式/关闭通知开关/会话清空等主动动作下被撤除。
  Future<void> _syncEndAlarm(SessionView? view, ActiveSession? active) async {
    final deadline = active?.deadline;
    final shouldSchedule = view != null &&
        shouldScheduleSystemAlarm(
          platform: _notifyPlatform,
          notifyEnabled: _data.notifyEnabled,
          running: view.running,
          targetReached: view.targetReached,
          hasDeadline: deadline != null,
        );
    if (shouldSchedule) {
      final target = deadline!;
      final desiredMs = target.millisecondsSinceEpoch;
      if (desiredMs == _desiredAlarmDeadlineMs) return;
      final scheduled = await Notifier.scheduleEndAlarm(
        deadline: target,
        mode: active!.mode,
        taskName: _currentFocusTaskName(active),
      );
      // 只在排程成功时记录期望值；失败留空让下一次同步重试。
      if (scheduled) _desiredAlarmDeadlineMs = desiredMs;
      return;
    }
    // 不在“要排”状态。若正处于 Android 超时运行中（911 已送达或仍在通知
    // 栏，进程内 _announce 又刻意不弹 910 防双响），保留 911 等待用户处理，
    // 直到出现主动动作（暂停/完成/丢弃/切模式/关通知/清会话）才撤除。
    final keepDeliveredAlarm = _isAndroid &&
        _data.notifyEnabled &&
        view != null &&
        view.running &&
        view.targetReached;
    if (keepDeliveredAlarm) return;
    if (_desiredAlarmDeadlineMs == null) return;
    _desiredAlarmDeadlineMs = null;
    await Notifier.cancelEndAlarm();
  }

  void _toggleRun() {
    final now = DateTime.now();
    var next = TimerEngine.advance(_data, now);
    final session = next.activeSession;
    if (session == null) {
      final started = TimerEngine.start(next, next.idleMode, now);
      // P0-2 权限时机：首次开始专注即请求通知权限（幂等，不打扰已授权用户）。
      // 精确闹钟授权同理，只尝试一次；被拒自动降级 inexact。
      if (started.activeSession?.mode.isFocus == true &&
          _data.notifyEnabled &&
          _isAndroid) {
        unawaited(Notifier.requestPermission().catchError((Object _) => false));
        unawaited(Notifier.maybeRequestExactAlarmPermission());
      }
      next = started;
    } else if (session.running) {
      next = TimerEngine.pause(next, now);
    } else {
      next = TimerEngine.resume(next, now);
    }
    _apply(next, force: true);
  }

  void _confirm() {
    final now = DateTime.now();
    final hadRecord = _data.records.length;
    var next = TimerEngine.advance(_data, now);
    next = TimerEngine.syncMinutes(next, now);

    if (next.activeSession == null) {
      if (!next.idleMode.isFocus) return;
      // 尚未开始计时：按计划时长直接补记一轮，并自动进入休息。
      next = TimerEngine.addManual(
        next,
        taskName: next.selectedTask.name,
        minutes: next.settings.focus.toDouble(),
        at: now,
      );
      // 休息轮换按完成次数口径（同 engine.complete）。
      final count = next.records
          .where((r) => r.counted && r.dayKey == dateKey(now))
          .length;
      final breakMode = count > 0 && count % 4 == 0
          ? SessionMode.longBreak
          : SessionMode.shortBreak;
      next = TimerEngine.start(next, breakMode, now);
    } else {
      next = TimerEngine.complete(next, now);
    }
    unawaited(Notifier.cancel());
    _apply(next, force: true);
    // 落了一条新记录（专注完成/直接记录）→ 完成章庆祝。
    if (next.records.length > hadRecord) _celebrate();
    _pulseGoalCard();
    // 完成专注（写入了记录）后自动上传，让网页端尽快看到。
    unawaited(_autoSync.afterFocus(context, next));
  }

  void _pulseGoalCard() {
    if (!mounted) return;
    setState(() => _goalPulse = true);
    Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _goalPulse = false);
    });
  }

  /// 完成一次专注：右上角盖「专注完成」章（P8）。减弱动画时跳过。
  void _celebrate() {
    if (!mounted) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return;
    setState(() => _stampVisible = true);
    _stampTimer?.cancel();
    _stampTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _stampVisible = false);
    });
  }

  void _discard() {
    if (_data.activeSession == null) return;
    unawaited(Notifier.cancel());
    _apply(TimerEngine.discard(_data), force: true);
  }

  void _switchMode(SessionMode mode) {
    unawaited(Notifier.cancel());
    _apply(TimerEngine.switchMode(_data, mode, DateTime.now()), force: true);
  }

  void _replace(AppData next) => _apply(next, force: true);

  /// 会话是否处于「挂起」：会话存在，但用户切到了其他模式——
  /// 会话被暂停冻结保留，切回其所属模式即继续。
  bool _isSuspended() {
    final session = _data.activeSession;
    return session != null && session.mode != _data.idleMode;
  }

  /// 当前应显示的会话：挂起时返回 null（显示所选模式的待开始视图），
  /// 并由 [_suspendBanner] 提示挂起中的会话。
  ActiveSession? get _displaySession =>
      _isSuspended() ? null : _data.activeSession;

  SessionView _displayView(DateTime now) {
    if (_isSuspended()) return _idleView;
    return SessionView.of(_data, now) ?? _idleView;
  }

  /// 挂起提示条：告诉用户「没丢，切回就继续」。
  Widget _suspendBanner() {
    final session = _data.activeSession!;
    final view = SessionView.of(_data, DateTime.now());
    final left = view?.clockText ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: PineColors.tint(PineColors.gold),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${session.mode.label}已暂停 · $left · 切回「${session.mode.label}」继续',
        style: const TextStyle(color: PineColors.ink, fontSize: 12),
      ),
    );
  }

  SessionView get _idleView {
    final planned = _data.settings.forMode(_data.idleMode) * 60;
    return SessionView(
      mode: _data.idleMode,
      running: false,
      targetReached: false,
      plannedSeconds: planned,
      remainingSeconds: planned,
      overtimeSeconds: 0,
      elapsedSeconds: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: PineColors.ink)),
      );
    }
    // macOS 走独立桌面布局（专注舱 + 统计/设置抽屉），安卓保持手机布局不变。
    if (_desktop) return _buildDesktop(context);
    // 手机布局：底部导航 3 Tab（专注 / 报告 / 设置），三页共享同一 AppData
    // （沿用桌面 IndexedStack 同源数据的先例；逻辑层零改动）。
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            _timerTab(),
            StatsPage(data: _data),
            SettingsPage(
              data: _data,
              onChanged: _replace,
              mirrorEnabled: _mirrorEnabled,
              onMirrorChanged: _setMirrorEnabled,
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer),
            label: '专注',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_rounded),
            label: '报告',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }

  /// 手机布局 · 专注子页（方案 E）：日期行 → 阶段 → 任务 → 计时卡 → 控制行
  /// → 今日卡 → 最近记录。整页可滚动，杜绝小屏/大字号溢出。
  Widget _timerTab() {
    final now = DateTime.now();
    final session = _displaySession;
    final view = _displayView(now);
    final stats = StatsView.of(_data, now);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 720;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, compact ? 6 : 10, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _dateHeader(),
              if (_data.countdown.enabled) ...[
                SizedBox(height: compact ? 8 : 10),
                CountdownCard(
                  countdown: _data.countdown,
                  now: now,
                  onTap: () => showCountdownSheet(context,
                      data: _data, onChanged: _replace),
                ),
              ],
              SizedBox(height: compact ? 8 : 12),
              ModeSwitcher(
                current: _data.idleMode,
                minutesFor: _data.settings.forMode,
                onChanged: _switchMode,
              ),
              if (_isSuspended()) ...[
                SizedBox(height: compact ? 8 : 12),
                _suspendBanner(),
              ],
              SizedBox(height: compact ? 8 : 12),
              _taskPicker(),
              SizedBox(height: compact ? 10 : 14),
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    maxHeight: compact ? 200 : 260,
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      BrickTimer(
                        view: view,
                        caption: _caption(session, view),
                      ),
                      if (_stampVisible)
                        const Positioned(
                          top: -10,
                          right: -8,
                          child: _CompletionStamp(),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: compact ? 8 : 12),
              _controls(session, view, suspended: _data.activeSession),
              SizedBox(height: compact ? 8 : 12),
              _metrics(stats),
              SizedBox(height: compact ? 8 : 12),
              _recent(),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  // ==================== macOS 桌面（方向 B · 专注舱 + 统计/设置抽屉） ====================
  // 定位：菜单栏常驻计时的「可视化同伴」——主窗只聚焦当前会话；统计与设置收进
  // 右上角两只抽屉（右滑入、Esc / 点遮罩 / 再点同键关闭）。抽屉内直接嵌入统计/
  // 设置整页，与安卓同源数据与组件，页面后续改动自动同步。拖宽只留白，不拉伸。

  Widget _buildDesktop(BuildContext context) {
    final now = DateTime.now();
    final session = _displaySession;
    final view = _displayView(now);
    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyR): _desktopReset,
          const SingleActivator(LogicalKeyboardKey.space): _desktopToggle,
          const SingleActivator(LogicalKeyboardKey.escape):
              _desktopCloseOverlay,
        },
        child: Stack(
          children: [
            Positioned.fill(child: _desktopCabin(session, view)),
            // 右上角：统计 / 设置抽屉开关（打开时高亮，再点同键或 Esc 关闭）。
            Positioned(
              top: 10,
              right: 14,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _desktopOverlayButton(
                    which: _overlayStats,
                    icon: Icons.bar_chart_rounded,
                    tooltip: '统计',
                  ),
                  const SizedBox(width: 8),
                  _desktopOverlayButton(
                    which: _overlaySettings,
                    icon: Icons.tune_rounded,
                    tooltip: '设置',
                  ),
                ],
              ),
            ),
            if (_desktopOverlay != _overlayNone) ...[
              // 遮罩：ink 18%，点任意处关闭（160ms 淡入）。
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _desktopCloseOverlay,
                      child: const ColoredBox(color: Color(0x2E33302A)),
                    ),
                  ),
                ),
              ),
              // 抽屉：右侧滑入 220ms（内容切换时重放入场）。
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Transform.translate(
                    offset: Offset(48 * (1 - value), 0),
                    child: child,
                  ),
                  child: _desktopDrawer(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _desktopToggle() {
    if (_desktopOverlay != _overlayNone) return;
    _toggleRun();
  }

  void _desktopReset() {
    if (_desktopOverlay != _overlayNone) return;
    _discard();
  }

  void _desktopCloseOverlay() {
    if (_desktopOverlay == _overlayNone) return;
    setState(() => _desktopOverlay = _overlayNone);
  }

  Widget _desktopOverlayButton({
    required int which,
    required IconData icon,
    required String tooltip,
  }) {
    final on = _desktopOverlay == which;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: on ? PineColors.tint(PineColors.pine) : PineColors.card,
        borderRadius: BorderRadius.circular(10),
        elevation: on ? 0 : 1,
        shadowColor: const Color(0x3333302A),
        child: InkWell(
          customBorder:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onTap: () => setState(
            () => _desktopOverlay = on ? _overlayNone : which,
          ),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              icon,
              size: 16,
              color: on ? PineColors.pine : PineColors.sub,
            ),
          ),
        ),
      ),
    );
  }

  /// 专注舱 B（极简）：段选 → 任务行 → 大环形计时 → 控制 → 信息小卡。
  /// 主体无卡片容器，大环是唯一视觉中心；「今日进度 + 最近完成 + 手动补记」
  /// 收进底部一张信息小卡。窗口矮时可滚动，拖宽只留白。
  Widget _desktopCabin(ActiveSession? session, SessionView view) {
    final stats = StatsView.of(_data, DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 52, 24, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: ModeSwitcher(
                      current: _data.idleMode,
                      minutesFor: _data.settings.forMode,
                      onChanged: _switchMode,
                    ),
                  ),
                ),
                if (_isSuspended()) ...[
                  const SizedBox(height: 10),
                  _suspendBanner(),
                ],
                const SizedBox(height: 12),
                // 任务行（轻量，非卡片）：整行可点换任务。
                Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => showTaskSheet(context,
                        data: _data, onChanged: _replace),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _TaskSwatch(
                              color: _data.selectedTask.swatch, size: 9),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: Text(
                              _data.selectedTask.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: PineColors.ink, fontSize: 12.5),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right,
                              size: 15, color: PineColors.faint),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: _DesktopRing(
                    progress: view.progress,
                    color:
                        view.targetReached ? PineColors.gold : view.mode.color,
                    timeText: view.clockText,
                    caption: _caption(session, view),
                    overtime: view.targetReached,
                    stamp: _stampVisible,
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: _controls(session, view,
                        suspended: _data.activeSession),
                  ),
                ),
                const SizedBox(height: 16),
                _desktopInfoCard(stats),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    '空格 开始/暂停 · R 重置 · Esc 关抽屉',
                    style: TextStyle(color: PineColors.faint, fontSize: 10.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 底部信息小卡：今日进度 + 最近完成（含手动补记入口）。
  /// 最近记录行整行可点进详情（删除在详情内，与安卓共用逻辑）。
  Widget _desktopInfoCard(StatsView stats) {
    final goal = _data.goalMinutes <= 0 ? 1 : _data.goalMinutes;
    final todayRatio = (stats.todayMinutes / goal).clamp(0.0, 1.0);
    final items = _data.records.where((record) => record.counted).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: PineColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: Paper.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 倒计时以单行内嵌在信息卡顶部（舱保持「极简无卡」不加新卡片）。
          if (_data.countdown.enabled) ...[
            CountdownCard(
              countdown: _data.countdown,
              now: DateTime.now(),
              compact: true,
              onTap: () =>
                  showCountdownSheet(context, data: _data, onChanged: _replace),
            ),
            const SizedBox(height: 9),
            const Divider(height: 1, color: PineColors.line),
            const SizedBox(height: 9),
          ],
          Row(
            children: [
              Text(
                '今日 ${stats.todayMinutes.round()} / ${_data.goalMinutes} 分钟',
                style: const TextStyle(color: PineColors.sub, fontSize: 10),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: PineColors.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: todayRatio,
                    child: Container(
                      decoration: BoxDecoration(
                        color: PineColors.pine,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                '最近完成',
                style: TextStyle(
                    color: PineColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () =>
                    showManualSheet(context, data: _data, onChanged: _replace),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Text(
                    '＋ 补记',
                    style: TextStyle(
                        color: PineColors.pine,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '完成一轮专注后会出现在这里',
                style: TextStyle(color: PineColors.faint, fontSize: 11),
              ),
            )
          else
            for (final record in items.take(3))
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => showRecordDetailSheet(
                  context,
                  data: _data,
                  record: record,
                  color: _colorFor(record.taskName),
                  onChanged: _replace,
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                  child: Row(
                    children: [
                      _TaskSwatch(color: _colorFor(record.taskName), size: 9),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          record.taskName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: PineColors.ink, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${record.status.label} · ${record.at.hour.toString().padLeft(2, '0')}:${record.at.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                            color: PineColors.sub, fontSize: 10.5),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        formatMinutes(record.minutes),
                        style: brickNumberStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  /// 抽屉容器：右侧圆角 + 投影；内嵌统计/设置整页（各自 AppBar 兼作抽屉头）。
  Widget _desktopDrawer() {
    final width =
        (MediaQuery.sizeOf(context).width - 16).clamp(300.0, 356.0).toDouble();
    final page = _desktopOverlay == _overlayStats
        ? StatsPage(data: _data)
        : SettingsPage(
            data: _data,
            onChanged: _replace,
            mirrorEnabled: _mirrorEnabled,
            onMirrorChanged: _setMirrorEnabled,
          );
    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: PineColors.paper,
        borderRadius: BorderRadius.horizontal(left: Radius.circular(18)),
        boxShadow: [
          BoxShadow(
            color: Color(0x3333302A),
            blurRadius: 28,
            offset: Offset(-6, 0),
          ),
        ],
      ),
      child: page,
    );
  }

  String _caption(ActiveSession? session, SessionView view) {
    final taskName = _data.selectedTask.name;
    if (session == null) return '准备开始';
    if (view.targetReached) return '已超时 · $taskName';
    if (!session.running) {
      if (view.mode.isFocus) {
        final count = StatsView.of(_data, DateTime.now()).todayCount + 1;
        return '已暂停 · 第 $count 个番茄 · $taskName';
      }
      return '已暂停 · ${view.mode.label}';
    }
    if (view.mode == SessionMode.focus) {
      final count = StatsView.of(_data, DateTime.now()).todayCount + 1;
      return '第 $count 个番茄 · $taskName';
    }
    return view.mode == SessionMode.shortBreak ? '起身活动一下' : '长休息，恢复状态';
  }

  /// 手机布局顶部：日期（今日语境）+ 右侧松果小标（纸面风格）。
  Widget _dateHeader() {
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    final now = DateTime.now();
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Text(
            '${now.month}月${now.day}日 周${week[now.weekday - 1]}',
            style: const TextStyle(color: PineColors.sub, fontSize: 13),
          ),
          const Spacer(),
          Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: PineColors.pine,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: PineColors.paper,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(width: 6, height: 6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskPicker() {
    final task = _data.selectedTask;
    return BrickCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      onTap: () => showTaskSheet(context, data: _data, onChanged: _replace),
      child: Row(
        children: [
          _TaskSwatch(color: task.swatch, size: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              task.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PineColors.ink, fontSize: 14),
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: PineColors.sub),
        ],
      ),
    );
  }

  Widget _controls(
    ActiveSession? session,
    SessionView view, {
    ActiveSession? suspended,
  }) {
    final primary = session == null ? '开始' : (session.running ? '暂停' : '继续');
    // 挂起会话存在时（显示的是另一模式的 idle 视图），「完成」按钮承接
    // 挂起会话的 complete 语义：专注 → 按已专注时长落记录并自动休息；
    // 休息 → 结束休息。
    final confirm = suspended != null
        ? (suspended.mode.isFocus ? '完成并休息' : '结束休息')
        : session == null
            ? '直接记录'
            : (view.mode.isFocus ? '完成并开始休息' : '结束休息');

    return Row(
      children: [
        Expanded(
          child: BrickButton(
            label: primary,
            icon: session?.running == true
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            // R2：主行动一律墨底纸字；阶段语义交给色条/caption/进度。
            color: PineColors.ink,
            onPressed: _toggleRun,
          ),
        ),
        const SizedBox(width: 10),
        // 「完成 / 直接记录」：金底墨字（R2）。
        BrickButton(
          label: '',
          semanticLabel: confirm,
          icon: Icons.check_rounded,
          color: PineColors.gold,
          foregroundColor: PineColors.ink,
          onPressed: _confirm,
        ),
        const SizedBox(width: 10),
        BrickButton(
          label: '',
          semanticLabel: '重置（不记录）',
          icon: Icons.restart_alt_rounded,
          color: PineColors.line,
          foregroundColor: PineColors.ink,
          onPressed: _discard,
        ),
      ],
    );
  }

  Widget _metrics(StatsView stats) {
    final goal = _data.goalMinutes <= 0 ? 1 : _data.goalMinutes;
    final progress = (stats.todayMinutes / goal).clamp(0.0, 1.0);
    return _goalCard(
      BrickCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          children: [
            SectionHeader(
              title: '今日目标',
              trailing: Text(
                '${stats.todayMinutes.round()} / ${_data.goalMinutes} 分钟 · ${stats.todayCount} 个番茄',
                style: brickNumberStyle(fontSize: 11, color: PineColors.sub),
              ),
            ),
            const SizedBox(height: 12),
            BrickProgress(value: progress),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: MetricTile(
                    value: formatMinutes(stats.todayMinutes),
                    label: '今日专注',
                  ),
                ),
                Expanded(
                  child: MetricTile(
                    value: formatMinutes(stats.weekMinutes),
                    label: '本周专注',
                    accent: PineColors.focus,
                  ),
                ),
                Expanded(
                  child: MetricTile(
                    value: '${stats.streak} 天',
                    label: '连续专注',
                    accent: PineColors.focus,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _goalCard(Widget child) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedScale(
      scale: _goalPulse && !reduceMotion ? 1.02 : 1,
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: child,
    );
  }

  Widget _recent() {
    // 按完成时刻倒序——多端合并后数组顺序不再保证新在前，
    // 依赖数组位置会让新记录沉底不显示（2026-09-10 事故）。
    final items = _data.records.where((record) => record.counted).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    final rows = <Widget>[];
    for (var i = 0; i < items.length && i < 8; i++) {
      if (i > 0) {
        rows.add(const Divider(height: 1, color: PineColors.line));
      }
      final record = items[i];
      rows.add(_RecentRow(
        record: record,
        color: _colorFor(record.taskName),
        onTap: () => showRecordDetailSheet(
          context,
          data: _data,
          record: record,
          color: _colorFor(record.taskName),
          onChanged: _replace,
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: '最近记录',
          trailing: BrickButton(
            label: '补记',
            icon: Icons.add,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: PineColors.card,
            foregroundColor: PineColors.pine,
            onPressed: () =>
                showManualSheet(context, data: _data, onChanged: _replace),
          ),
        ),
        const SizedBox(height: 10),
        BrickCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: Text(
                      '完成一轮专注后会出现在这里',
                      style: TextStyle(color: PineColors.sub, fontSize: 12),
                    ),
                  ),
                )
              : Column(children: rows),
        ),
      ],
    );
  }

  Color _colorFor(String taskName) {
    for (final task in _data.tasks) {
      if (task.name == taskName) return task.swatch;
    }
    return PineColors.sub;
  }
}

/// 最近记录行（手机）：整行可点 → 记录详情 sheet；删除在详情内进行。
class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.record,
    required this.color,
    required this.onTap,
  });

  final FocusRecord record;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BrickPressable(
      onTap: onTap,
      shadowed: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            _TaskSwatch(color: color, size: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.taskName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PineColors.ink, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${record.status.label} · ${record.at.hour.toString().padLeft(2, '0')}:${record.at.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: PineColors.sub, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatMinutes(record.minutes),
              style: brickNumberStyle(fontSize: 13),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: PineColors.sub),
          ],
        ),
      ),
    );
  }
}

/// 任务色点：圆点，无描边（纸面）。
class _TaskSwatch extends StatelessWidget {
  const _TaskSwatch({required this.color, this.size = 12});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// 大环形计时（主舱 B）：无卡片容器，圆环是唯一视觉中心。
/// 圆环随进度收弧（阶段色），中心等宽大数字 + 状态 caption；超时整环金色。
class _DesktopRing extends StatelessWidget {
  const _DesktopRing({
    required this.progress,
    required this.color,
    required this.timeText,
    required this.caption,
    required this.overtime,
    this.stamp = false,
  });

  final double progress;
  final Color color;
  final String timeText;
  final String caption;
  final bool overtime;

  /// 完成章（桌面）：一次专注完成时在环右上角盖下。
  final bool stamp;

  static const double _diameter = 244;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _diameter,
      height: _diameter,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _RingPainter(progress: progress, color: color),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeText,
                  style: brickNumberStyle(
                    fontSize: 50,
                    color: overtime ? PineColors.gold : PineColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: PineColors.sub, fontSize: 11),
                ),
              ],
            ),
          ),
          if (stamp)
            const Positioned(
              top: -8,
              right: -6,
              child: _CompletionStamp(),
            ),
        ],
      ),
    );
  }
}

/// 圆环：纸色轨道 + 阶段色圆弧（顺时针从 12 点起），超时后整环闭合。
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Offset.zero & size;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = PineColors.line;
    canvas.drawCircle(rect.center, (size.width - stroke) / 2, track);
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      rect.deflate(stroke / 2),
      -3.14159 / 2,
      6.28318 * p,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// 完成章（P8）：一次专注完成时在计时卡右上角盖下，弹性入场。
class _CompletionStamp extends StatelessWidget {
  const _CompletionStamp();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.elasticOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Transform.rotate(
        angle: -0.18,
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PineColors.card.withValues(alpha: 0.85),
            shape: BoxShape.circle,
            border: Border.all(color: PineColors.pine, width: 2.5),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check, size: 16, color: PineColors.pine),
              Text(
                '专注完成',
                style: TextStyle(
                  color: PineColors.pine,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
