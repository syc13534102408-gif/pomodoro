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
import '../src/ui/ui.dart';
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

  /// 收工仪式浮层（2026-11-11）。不弹 dialog：它要盖住整屏、自带遮罩与两段式
  /// 动画，而 AlertDialog 走内在宽度测量（docs/07 §7 #3/#7），装不住这些组件。
  bool _ceremonyOpen = false;
  Timer? _ceremonyTimer;

  /// 今日日程的「内联加一条」状态（不弹面板，直接在卡里输入）。
  bool _planAdding = false;
  final TextEditingController _planController = TextEditingController();
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
  static const _overlayPlan = 3;
  // 0=无抽屉 1=统计 2=设置 3=日程（方向 B 专注舱）
  int _desktopOverlay = _overlayNone;

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

  /// 备份同步低频巡检：每 3 分钟一次，先补传本机未上传的改动，再拉云端更新。
  /// onResume 自带 updatedAt 与 15 秒 minInterval 保护，重复调用安全；
  /// 失败静默（网络异常不影响计时）。
  void _startBackupSyncTimer() {
    _backupSyncTimer?.cancel();
    _backupSyncTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      if (!mounted || !_ready) return;
      unawaited(_syncNow());
    });
  }

  /// 先上传（有本地改动时）再拉取，顺序串行：
  /// 上传成功会刷新 lastSyncedAt，随后的拉取看到云端没有更新会自然跳过。
  Future<void> _syncNow() async {
    await _autoSync.afterLocalChange(_data);
    if (!mounted) return;
    await _autoSync.onResume(context, _data);
    if (!mounted) return;
    // 最后补传被占用/网络吞掉的那次「完成专注」（必达语义的兜底）。
    await _autoSync.flushPending(context, _data);
  }

  @override
  void dispose() {
    _planController.dispose();
    _ticker?.cancel();
    _stampTimer?.cancel();
    _ceremonyTimer?.cancel();
    _mirrorTimer?.cancel();
    _backupSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick(forcePersist: true);
      // 回到前台：先补传本机未上传的改动，再拉云端更新，最后补传被吞掉的完成记录。
      // 用 _syncNow 而不是只拉取——解锁后立刻点「完成」的那次上传曾被拉取挤掉。
      unawaited(_syncNow());
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
      // 退后台前尽力把本机改动推上去（失败无妨：回前台的周期巡检会补）。
      unawaited(_autoSync.afterLocalChange(_data));
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
    // 启动同步：先补传本机上次退出前没来得及上传的改动，再拉取云端更新，
    // 最后兜底补传被吞掉的完成记录（与回前台、每 3 分钟巡检同一套逻辑）。
    if (mounted) unawaited(_syncNow());
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
    final hadSession = _data.activeSession != null;
    setState(() => _data = next);
    _persist(force: force);
    // 用户一操作就刷新菜单栏，别等下一秒的 tick。
    _syncMenuBar();
    unawaited(_syncForeground());
    // 会话镜像：本机状态变化即广播（采纳远端状态时抑制，防乒乓）。
    unawaited(_publishSession(next, fromRemote: fromRemote));
    // 会话有无变化 → 重算轮询周期（空闲降频省云端调用费用）。
    if (_mirrorEnabled && hadSession != (next.activeSession != null)) {
      _startMirrorTimer();
    }
  }

  // ==================== 会话实时镜像 ====================

  /// 会话镜像轮询（自适应周期，2026-09-27 费用优化）。
  ///
  /// 有进行中会话：3 秒一次（实时跟随是镜像的核心体验）；
  /// 无会话空闲：30 秒一次——云端 SCF/COS 按调用计费，空闲期高频轮询
  /// 纯属浪费（每天后台待机 10 小时可省 ~1.4 万次云端调用/端）。
  /// 会话有无变化时由 [_apply] 调用本方法重算周期。
  void _startMirrorTimer() {
    _mirrorTimer?.cancel();
    final period = _data.activeSession != null
        ? const Duration(seconds: 3)
        : const Duration(seconds: 30);
    _mirrorTimer = Timer.periodic(period, (_) {
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

  /// 当前任务「还活着」的事件：优先进行中，没有就退回**最近暂停**的那个。
  ///
  /// 2026-11-06 修：原来只认 `isRunning`。事件一旦暂停，`_openEventActions` 就再也
  /// 找不到它，而「继续累计 / 完成 / 删除 / 编辑」全在那个面板里——等于**暂停即失联**。
  /// 多事件并存时，用户感受到的就是「切不回上一条事件」。
  FocusEvent? _activeEventFor(String taskName) {
    FocusEvent? paused;
    for (final event in _data.events) {
      if (event.taskName != taskName || event.isFinished) continue;
      if (event.isRunning) return event;
      if (paused == null ||
          (event.pausedAt ?? event.startedAt)
              .isAfter(paused.pausedAt ?? paused.startedAt)) {
        paused = event;
      }
    }
    return paused;
  }

  /// 打开当前任务事件的操作面板（暂停/继续/完成/编辑/删除）。
  void _openEventActions() {
    final event = _activeEventFor(_data.selectedTask.name);
    if (event == null) return;
    showEventActionSheet(context,
        data: _data, event: event, onChanged: _replace);
  }

  /// 事件入口（桌面舱任务行与手机任务卡共用）：有待处理事件 → 可点徽标；
  /// 没有 → 轻量「＋事件」。操作面板只从入口进，所以两个布局都必须有。
  Widget _eventChip() {
    final event = _activeEventFor(_data.selectedTask.name);
    if (event == null) {
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () =>
            showEventSheet(context, data: _data, onChanged: _replace),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: PineColors.line),
          ),
          child: const Text('＋事件',
              style: TextStyle(color: PineColors.sub, fontSize: 10)),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 130),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _openEventActions,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: PineColors.tint(PineColors.pine),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            // 暂停要写出来：不然徽标看着像还在累计。
            event.isPaused ? '${event.name} · 已暂停' : event.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: PineColors.pine, fontSize: 10),
          ),
        ),
      ),
    );
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
      // 开始专注 = 回到工作，「今日休息」标记自动作废（不用先去点「继续今日」）。
      if (next.isRestDay(now)) next = TimerEngine.resumeToday(next);
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

  Future<void> _confirm() async {
    final now = DateTime.now();
    final hadRecord = _data.records.length;
    final session = _data.activeSession;
    // 这一轮是不是专注：只有专注轮次才需要事后选主题。
    final focusRound =
        session != null ? session.mode.isFocus : _data.idleMode.isFocus;
    var next = TimerEngine.advance(_data, now);
    next = TimerEngine.syncMinutes(next, now);
    String? recordId;

    if (next.activeSession == null) {
      if (!next.idleMode.isFocus) return;
      // 尚未开始计时：按计划时长直接补记一轮，并自动进入休息。
      next = TimerEngine.addManual(
        next,
        taskName: next.selectedTask.name,
        minutes: next.settings.focus.toDouble(),
        at: now,
      );
      // 与 engine.complete 一致：自动休息固定短休（2026-11-07 起）。
      next = TimerEngine.start(next, SessionMode.shortBreak, now);
      recordId = next.records.isEmpty ? null : next.records.first.id;
    } else {
      recordId = next.activeSession!.recordId;
      next = TimerEngine.complete(next, now);
    }
    unawaited(Notifier.cancel());
    _apply(next, force: true);
    // 落了一条新记录（专注完成/直接记录）→ 完成章庆祝。
    if (next.records.length > hadRecord) _celebrate();
    _pulseGoalCard();
    // 完成专注（写入了记录）后自动上传，让网页端尽快看到。
    unawaited(_autoSync.afterFocus(context, next));

    // 记完再选主题（2026-11-11）：开始前不必先决定这一步属于谁。
    if (focusRound && recordId != null) {
      await _assignTopic(recordId);
    }
  }

  /// 完成后的主题归属：默认上次用过的主题，选完写回记录（含事件归属）。
  Future<void> _assignTopic(String recordId) async {
    if (!mounted) return;
    FocusRecord? record;
    for (final item in _data.records) {
      if (item.id == recordId) {
        record = item;
        break;
      }
    }
    if (record == null) return;
    final picked = await showTopicSheet(
      context,
      data: _data,
      timeLabel: '${formatHoursMinutes(record.minutes)} · 刚刚完成',
    );
    if (picked == null || !mounted) return;
    var next = TimerEngine.updateRecord(_data, recordId, taskName: picked.name);
    final index = _data.tasks.indexWhere((task) => task.id == picked.id);
    if (index >= 0) next = next.copyWith(selectedIndex: index);
    // 该主题若有进行中的事件，这条记录自动归入（与开始计时时的口径一致）。
    String? eventId;
    for (final event in _data.events) {
      if (event.isRunning && event.taskName == picked.name) {
        eventId = event.id;
        break;
      }
    }
    next = TimerEngine.setRecordEvent(next, recordId, eventId);
    _replace(next);
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

  /// 阶段条：**点谁进谁**。落账口径全在 [TimerEngine.switchPhase]（纯函数，有单测）。
  void _switchPhase(SessionMode mode) {
    final before = _data.records.length;
    final now = DateTime.now();
    final next = TimerEngine.switchPhase(_data, mode, now);
    // 点当前所在阶段引擎原样返回同一实例——别为一次空操作制造写盘与云端上传。
    if (identical(next, _data)) return;
    unawaited(Notifier.cancel());
    _apply(next, force: true);
    // 离开专注时收口写了记录 → 立刻上传，别等下次节流（与 _startBreak 同）。
    if (next.records.length > before) {
      unawaited(_autoSync.afterFocus(context, next));
    }
  }

  /// 今日休息（收工）：结束计时 + 标记今天休息，环内文案变「今日休息」。
  void _restToday() {
    final before = _data.records.length;
    final next = TimerEngine.restForToday(_data, DateTime.now());
    unawaited(Notifier.cancel());
    _apply(next, force: true);
    if (next.records.length > before) {
      unawaited(_autoSync.afterFocus(context, next));
    }
  }

  /// 撤销今日休息（继续今日）。
  void _resumeToday() {
    _apply(TimerEngine.resumeToday(_data), force: true);
  }

  /// 「收工」入口：今天还没收工 → 开仪式；已经收工 → 同一格撤销（继续今日）。
  ///
  /// 2026-11-11 起收工不再是"点一下就没了"的开关，而是一段有开头有结尾的仪式
  /// （[_RestCeremony]）。数据改动仍然只发生在仪式里按下「收工」那一刻。
  void _openRestCeremony() {
    if (_data.isRestDay(DateTime.now())) {
      _resumeToday();
      return;
    }
    setState(() => _ceremonyOpen = true);
  }

  /// 关掉仪式（「再学一会儿」/ 点遮罩）：不改任何数据。
  void _closeRestCeremony() {
    _ceremonyTimer?.cancel();
    _ceremonyTimer = null;
    if (!mounted || !_ceremonyOpen) return;
    setState(() => _ceremonyOpen = false);
  }

  /// 仪式里按下「收工」：**立刻**落标记（动画中途被杀也不丢），再让盖章停留 1.2 秒。
  /// 那 1.2 秒是"仪式感"真正的载体——点完立刻消失的确认框只是一个开关。
  void _confirmRest() {
    _restToday();
    _ceremonyTimer?.cancel();
    _ceremonyTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _ceremonyOpen = false);
    });
  }

  /// 第二控制行：阶段条（专注 / 短休 / 吃饭）+ 右侧「收工」。
  ///
  /// 2026-11-07 那版是「短休 / 吃饭 / 今日休息」三个等宽胶囊，三个毛病：
  /// ① 回不到主计时（只能绕去按 ✓「结束休息」）；② 三格长得一样，看不出在哪一段；
  /// ③ 点当前那段会把剩余时间重置成满格。现在：
  /// - 三段按 [SessionMode] 对称，**选中态就是"我在这"**，点当前段是幂等空操作；
  /// - 「收工」从"第三个休息选项"里拎出来单独一颗描边胶囊——它不是休息，是收尾，
  ///   点它进仪式而不是直接改状态。
  Widget _phaseRow() {
    final resting = _data.isRestDay(DateTime.now());
    // 与环内显示同一口径：挂起时显示的是待开始阶段，阶段条也照此高亮；
    // 已收工则一段都不选中（这一天不在任何阶段里）。
    final SessionMode? current = resting
        ? null
        : (_displaySession?.mode ?? _data.idleMode);
    return Row(
      children: [
        Expanded(
          child: PhaseSwitcher(
            current: current,
            minutesFor: (mode) => _data.settings.forMode(mode),
            onChanged: _switchPhase,
          ),
        ),
        const SizedBox(width: 8),
        _RestEntryChip(
          active: resting,
          onTap: resting ? _resumeToday : _openRestCeremony,
        ),
      ],
    );
  }

  void _replace(AppData next) {
    _apply(next, force: true);
    // 本地改动即刻排队上传云端（节流 20s、冲突静默），不必等下一次完成专注。
    unawaited(_autoSync.afterLocalChange(next));
  }

  /// 日程/待办：把一次「变换」套到**当前**数据上。
  /// 不能整份回写面板打开时的快照——面板存活期间可能发生云端采纳，回写会把新数据顶掉。
  void _applyTodos(TodosTransform transform) {
    _replace(_data.copyWith(todos: transform(_data.todos)));
  }

  /// 打开日程：桌面走右侧抽屉（与统计/设置同一套机制），手机走底部弹层。
  void _openPlanSheet() {
    if (_desktop) {
      setState(() => _desktopOverlay = _overlayPlan);
      return;
    }
    showPlanSheet(context, data: _data, onApply: _applyTodos);
  }

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
    // 收工仪式浮在**页面之上**（含桌面端三只抽屉之上）：它是"今天结束"这件事
    // 的独立场景，不该被抽屉或底部导航挤在旁边。
    return Stack(
      children: [
        Positioned.fill(child: _page(context)),
        if (_ceremonyOpen)
          Positioned.fill(
            child: _RestCeremony(
              stats: StatsView.of(_data, DateTime.now()),
              goalMinutes: _data.goalMinutes,
              resting: _data.isRestDay(DateTime.now()),
              onConfirm: _confirmRest,
              onCancel: _closeRestCeremony,
            ),
          ),
      ],
    );
  }

  Widget _page(BuildContext context) {
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
            StatsPage(data: _data, onChanged: _replace),
            SettingsPage(
              data: _data,
              onChanged: _replace,
              mirrorEnabled: _mirrorEnabled,
              onMirrorChanged: _setMirrorEnabled,
            ),
          ],
        ),
      ),
      // 定稿书签栏 40px：选中项顶部 2px 檀褐短线，取代 iOS 胶囊式底栏。
      bottomNavigationBar: PaperTabs(
        index: _tab,
        labels: const ['专注书房', '专注报告', '偏好设置'],
        onChanged: (index) => setState(() => _tab = index),
      ),
    );
  }

  /// 手机布局 · 专注页（V3 素纸书房）：
  /// 书眉 48 → 铭文 34 → 手稿页卡（主题 / 64px 活字读数 / 比例尺 / 内嵌今日课业）
  /// → 达成条 → 底部笺纸 Composer（阶段段选 + 三键）→ 书签栏（在 `_page`）。
  ///
  /// 只重排 widget 树：所有既有功能节点（`_taskPicker` / `_planCard` / `_phaseRow` /
  /// `_controls` / `_metrics` / `_recent` / `_cumulative`）与其回调原样保留，
  /// 只是把「圆环」换成「活字读数 + 尺规比例尺」，并把控制行收进 Composer。
  Widget _timerTab() {
    final now = DateTime.now();
    final session = _displaySession;
    final resting = _isResting(now);
    final view = resting ? _restView : _displayView(now);
    final stats = StatsView.of(_data, now);
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    final examText = _data.countdown.enabled
        ? '距考研 ${_data.countdown.daysFrom(now)} 日'
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 720;
        final gap = compact ? 8.0 : 12.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FolioBar(
              dateText: '${now.month}月${now.day}日 · 周${week[now.weekday - 1]}',
              examText: examText,
              syncText: _mirrorEnabled ? '已同步' : '本地',
              onMenu: _openPlanSheet,
            ),
            InscriptionRow(
              totalText: '全部历史累计 ${formatHoursMinutes(stats.totalMinutes)}',
              rightText: '第 ${stats.totalDays} 日 · 连续 ${stats.streak} 日',
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, compact ? 8 : 10, 16, 10),
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
                    if (_isSuspended()) ...[
                      SizedBox(height: gap),
                      _suspendBanner(),
                    ],
                    SizedBox(height: gap),
                    SuzhiCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _taskPicker(),
                          const SizedBox(height: 12),
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              PaperClockDigits(
                                timeText: resting ? '收工' : view.clockText,
                                caption: _caption(session, view),
                                totalText:
                                    '/ ${view.plannedSeconds ~/ 60}:00',
                                note: !resting && view.targetReached
                                    ? '到点不停 · 继续累计'
                                    : null,
                                overtime: !resting && view.targetReached,
                              ),
                              if (_stampVisible)
                                const Positioned(
                                  top: -10,
                                  right: -8,
                                  child: _CompletionStamp(),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          RuledScale(
                            progress: resting ? 1 : view.progress,
                            targetMinutes: view.plannedSeconds ~/ 60,
                            meta: '尺规进度 · 已历 ${view.elapsedSeconds ~/ 60} 分',
                          ),
                          const SizedBox(height: 12),
                          // 今日课业批注就地内嵌手稿页卡，不再另起一张卡。
                          _planCard(),
                        ],
                      ),
                    ),
                    SizedBox(height: gap),
                    _cumulative(stats),
                    SizedBox(height: gap),
                    _metrics(stats),
                    SizedBox(height: gap),
                    _recent(),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            PaperComposer(
              hintText: '✎ 添写今日课业，或手动补记一笔…',
              sealText: '今日收工',
              onSeal: resting ? _resumeToday : _openRestCeremony,
              phases: _phaseRow(),
              actions: _controls(session, view, suspended: _data.activeSession),
            ),
          ],
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
    // 定稿响应式：≥720 走「楮皮目录栏 / 日课笺中栏 / 专注手稿画布」三栏书斋；
    // <720 收成单列专注舱（440×600 最小窗的垂直预算断言依赖这条路径，勿改）。
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
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
                Positioned.fill(
                  child: wide
                      ? _desktopThreeColumn(session, view)
                      : _desktopCabin(session, view),
                ),
                if (_desktopOverlay != _overlayNone) ...[
                  // 遮罩：浓墨 18%，点任意处关闭（160ms 淡入）。
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
                          child: ColoredBox(
                            color: PineColors.ink.withAlpha(46),
                          ),
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
                // 窄窗：右上角三只抽屉开关（必须放在 Stack 最后、最上层）。
                // 宽窗三栏由楮皮目录栏提供同样的入口，这里不再重复一排按钮。
                if (!wide)
                  Positioned(
                    top: 10,
                    right: 14,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _desktopOverlayButton(
                          which: _overlayPlan,
                          icon: Icons.checklist_rtl_rounded,
                          tooltip: '日程',
                        ),
                        const SizedBox(width: 8),
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
              ],
            ),
          ),
        );
      },
    );
  }

  // ==================== V3 桌面三栏书斋（≥720px） ====================

  /// 216px 楮皮目录栏 + 弹性中栏（日课笺 / 落账手记 / Composer）+ 420px 手稿画布。
  /// 三栏内容全部复用现有功能节点，不新增任何业务状态。
  Widget _desktopThreeColumn(ActiveSession? session, SessionView view) {
    final now = DateTime.now();
    final stats = StatsView.of(_data, now);
    final resting = _isResting(now);
    final displayView = resting ? _restView : view;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const ValueKey('study-sidebar'),
          width: 216,
          child: _studySidebar(now, stats),
        ),
        Expanded(
          key: const ValueKey('study-center'),
          child: _studyCenter(now, stats, session, displayView, resting),
        ),
        SizedBox(
          key: const ValueKey('study-canvas'),
          width: 420,
          child: _studyCanvas(session, displayView, resting),
        ),
      ],
    );
  }

  Widget _studySidebar(DateTime now, StatsView stats) {
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    return Container(
      color: PineColors.sand,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('素纸书房', style: PineText.serif(size: PineType.body)),
          const SizedBox(height: 4),
          Text(
            '${now.month}月${now.day}日 周${week[now.weekday - 1]}',
            style: PineText.mono(size: PineType.caption, color: PineColors.ink2),
          ),
          const SizedBox(height: 18),
          Text('八日排程',
              style: PineText.serif(size: PineType.label, color: PineColors.ink2)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 7; i >= 0; i--)
                _dateSeal(now.subtract(Duration(days: i)), today: i == 0),
            ],
          ),
          const SizedBox(height: 18),
          Text('卷宗',
              style: PineText.serif(size: PineType.label, color: PineColors.ink2)),
          const SizedBox(height: 8),
          Row(
            children: [
              _desktopOverlayButton(
                which: _overlayPlan,
                icon: Icons.checklist_rtl_rounded,
                tooltip: '日程',
              ),
              const SizedBox(width: 8),
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
          // 事件徽标只出现在右侧手稿画布的主题行（`_taskPicker`），侧栏不再重复一份：
          // 两处同时渲染会让「暂停事件仍可点开」的 findsOneWidget 断言拿到 2 个。
          const SizedBox(height: 18),
          Text('专注主题卷宗',
              style: PineText.serif(size: PineType.label, color: PineColors.ink2)),
          const SizedBox(height: 6),
          Text('按主题累计 · 八日排程',
              style: PineText.sans(size: PineType.caption, color: PineColors.ink3)),
          const Spacer(),
          Text(
            '累计 ${formatHoursMinutes(stats.totalMinutes)}',
            style: PineText.serif(size: PineType.label, color: PineColors.ink2),
          ),
          const SizedBox(height: 4),
          Text(
            '第 ${stats.totalDays} 日 · 连续 ${stats.streak} 日',
            style: PineText.mono(size: PineType.caption, color: PineColors.ink3),
          ),
        ],
      ),
    );
  }

  Widget _dateSeal(DateTime date, {required bool today}) {
    return Container(
      width: 42,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: today ? PineColors.accent : PineColors.sheet,
        border: Border.all(
          color: today ? PineColors.accentDeep : PineColors.lineStrong,
        ),
        borderRadius: BorderRadius.circular(PineRadius.seal),
      ),
      child: Text(
        '${date.month}/${date.day}',
        style: PineText.mono(
          size: PineType.caption,
          color: today ? PineColors.sheet : PineColors.ink2,
        ),
      ),
    );
  }

  Widget _studyCenter(
    DateTime now,
    StatsView stats,
    ActiveSession? session,
    SessionView view,
    bool resting,
  ) {
    return Container(
      color: PineColors.paper,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('日课笺', style: PineText.serif(size: PineType.body)),
              const Spacer(),
              SectionSeal(text: '今日 ${stats.todayCount} 番'),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _desktopInfoCard(stats),
                  const SizedBox(height: 10),
                  _cumulative(stats),
                  const SizedBox(height: 10),
                  _recent(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          PaperComposer(
            hintText: '✎ 添写今日课业，或手动补记一笔…',
            sealText: '今日收工',
            onSeal: resting ? _resumeToday : _openRestCeremony,
            phases: _phaseRow(),
            actions: _controls(session, view, suspended: _data.activeSession),
          ),
        ],
      ),
    );
  }

  Widget _studyCanvas(
    ActiveSession? session,
    SessionView view,
    bool resting,
  ) {
    return Container(
      color: PineColors.paper,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: SizedBox.expand(
        child: SuzhiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _taskPicker(),
              const SizedBox(height: 20),
              PaperClockDigits(
                timeText: resting ? '收工' : view.clockText,
                caption: _caption(session, view),
                totalText: '/ ${view.plannedSeconds ~/ 60}:00',
                note: !resting && view.targetReached
                    ? '到点不停 · 继续累计'
                    : null,
                overtime: !resting && view.targetReached,
              ),
              const SizedBox(height: 24),
              RuledScale(
                progress: resting ? 1 : view.progress,
                targetMinutes: view.plannedSeconds ~/ 60,
                meta: '尺规进度 · 已历 ${view.elapsedSeconds ~/ 60} 分',
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: CinnabarButton(
                      label: '完成',
                      onPressed: () => _confirm(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PaperButton(label: '重置', onPressed: _discard),
                  ),
                ],
              ),
            ],
          ),
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
        shadowColor: PineColors.ink.withAlpha(51),
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
    final resting = _isResting(DateTime.now());
    // 500×640 是默认窗口，原布局内容 624.5pt > 视口 574pt，信息卡底缘被视口硬切
    // （2026-10-25 评审 P0-1）。按可用高度分档收紧，环径是最大的一块预算。
    final height = MediaQuery.sizeOf(context).height;
    final compact = height < 640;
    // 环径四档（2026-10-25 定）：默认窗 560×760 落在最高档，一屏 4 条日程。
    final ring = height >= 720
        ? Paper.ringMax
        : (compact ? Paper.ringMin : Paper.ringMid);
    final gapBase = compact ? 8.0 : 12.0;
    // 最小窗 440×600 实测还差 2pt（布局回归测试抓到），尾间隙按 4 网格收到 4。
    final gapTail = compact ? 4.0 : 12.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 52, 24, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isSuspended()) ...[
                  const SizedBox(height: 10),
                  _suspendBanner(),
                ],
                SizedBox(height: gapBase),
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
                          // Flexible 而非固定宽：窄屏（手机）上任务名自动收缩，
                          // 保证右侧的事件入口/徽标不被裁出屏外。
                          Flexible(
                            child: Text(
                              _data.selectedTask.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: PineColors.ink, fontSize: 12.5),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const SizedBox(width: 2),
                          _eventChip(),
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
                    progress: resting ? 1 : view.progress,
                    diameter: ring,
                    // 金色不能直接用 gold（对纸面 2.00:1），字与弧改 goldInk（3.40:1）；
                    // gold 只留给「按钮底 + ink 字」。
                    color: resting
                        ? PineColors.pine
                        : (view.targetReached
                            ? PineColors.goldInk
                            : view.mode.lineColor),
                    timeText: resting ? '收工' : view.clockText,
                    timeStyle: resting ? _restCenterStyle : null,
                    caption: _caption(session, view),
                    overtime: !resting && view.targetReached,
                    stamp: !resting && _stampVisible,
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: ConstrainedBox(
                    // 与信息卡同宽（452），左缘落在同一条 24 基准线上。
                    constraints:
                        const BoxConstraints(maxWidth: Paper.cabinColumn),
                    child: _controls(session, view,
                        suspended: _data.activeSession),
                  ),
                ),
                // 5pt 是量出来的：440×600 与 500×640 两档此前正好贴边，
                // 新加这一行必须把间距压到这里才不触发滚动（见 desktop_layout_test）。
                const SizedBox(height: 5),
                Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: Paper.cabinColumn),
                    child: _phaseRow(),
                  ),
                ),
                SizedBox(height: gapTail),
                _desktopInfoCard(stats),
                // 快捷键提示行已移除：500×640 下它整行落在视口外（评审 P0-1 改法⑤），
                // 快捷键在菜单栏与设置页都有。
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 底部信息小卡：今日进度 + 最近完成（含手动补记入口）。
  /// 最近记录行整行可点进详情（删除在详情内，与安卓共用逻辑）。
  /// 底部信息小卡（2026-10-25 改版）：
  /// 考试倒计时 → **今日日程（就地打勾）** → 今日进度。
  ///
  /// 「最近完成」整块移到统计抽屉：主窗只回答两件事——接下来做什么、今天做了多少。
  /// 这样日程从 1 行入口变成 3 行可勾清单，而总高度反而略降（最近完成块曾占 2 行 + 表头）。
  Widget _desktopInfoCard(StatsView stats) {
    final goal = _data.goalMinutes <= 0 ? 1 : _data.goalMinutes;
    final todayRatio = (stats.todayMinutes / goal).clamp(0.0, 1.0);
    final todayKey = ymdOf(dayStart(DateTime.now()));
    final planItems = _data.todos[todayKey] ?? const <TodoItem>[];
    final planDone = planItems.where((item) => item.done).length;
    // 日程行数按窗高分档：440×600 → 2、500×640 → 3、560×720 → 4、≥800 → 5
    // （超出折叠成「还有 N 条 ›」）。默认窗 560×760 落在 4 条档。
    final windowHeight = MediaQuery.sizeOf(context).height;
    final planRows = windowHeight < 640
        ? 2
        : (windowHeight < 720 ? 3 : (windowHeight < 800 ? 4 : 5));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: PineColors.card,
        borderRadius: BorderRadius.circular(Paper.cardRadius),
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
              const Text(
                '今日日程',
                style: TextStyle(
                    color: PineColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (planItems.isNotEmpty)
                Text(
                  '$planDone/${planItems.length}',
                  style: const TextStyle(color: PineColors.sub, fontSize: 11),
                ),
              const SizedBox(width: 2),
              InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: _openPlanSheet,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text(
                    '全部 ›',
                    style: TextStyle(color: PineColors.sub, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (planItems.isEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _openPlanSheet,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '今天还没安排 · 点这里排（支持粘贴导入）',
                  style: TextStyle(color: PineColors.sub, fontSize: 11),
                ),
              ),
            )
          else
            AnimatedTodoRows(
              items: planItems.take(planRows).toList(),
              rowHeight: 26,
              itemBuilder: (item) =>
                  _planRow(todayKey, item, fontSize: 12),
            ),
          if (planItems.length > planRows)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _openPlanSheet,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '还有 ${planItems.length - planRows} 条 ›',
                  style:
                      const TextStyle(color: PineColors.pine, fontSize: 11),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '今日 ${stats.todayMinutes.round()} / ${_data.goalMinutes} 分钟',
                style: const TextStyle(color: PineColors.sub, fontSize: 10),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: PineColors.track,
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
        ],
      ),
    );
  }

  /// 抽屉容器：右侧圆角 + 投影；内嵌统计/设置整页（各自 AppBar 兼作抽屉头）。
  Widget _desktopDrawer() {
    final width =
        (MediaQuery.sizeOf(context).width - 16).clamp(300.0, 356.0).toDouble();
    final page = _desktopOverlay == _overlayPlan
        ? Padding(
            // 横向内边距与统计/设置页对齐；顶部留给抽屉外的按钮带（见外层 Padding）。
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            child: PlanPanel(data: _data, onApply: _applyTodos),
          )
        : _desktopOverlay == _overlayStats
        ? StatsPage(data: _data, onChanged: _replace)
        : SettingsPage(
            data: _data,
            onChanged: _replace,
            mirrorEnabled: _mirrorEnabled,
            onMirrorChanged: _setMirrorEnabled,
          );
    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: PineColors.paper,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(PineRadius.card),
        ),
        boxShadow: [
          BoxShadow(
            color: PineColors.ink.withAlpha(51),
            blurRadius: 28,
            offset: const Offset(-6, 0),
          ),
        ],
      ),
      // 三只抽屉开关浮在窗口右上角（必须压在最上层才关得掉），
      // 这里让出 48pt 给它们：否则抽屉里的「导入」按钮会被正好盖住（2026-11-03 反馈）。
      child: Padding(
        padding: const EdgeInsets.only(top: 48),
        child: page,
      ),
    );
  }

  /// 环内 caption（2026-10-25 决策 A3）：只留**状态 + 序号**，不再带任务名。
  ///
  /// 任务行就在环上方 12pt、带色点，环内再写一遍是纯重复；而环在圆心下方 40pt
  /// 处的可用弦长只有 205pt，长任务名会被截断甚至压到 12pt 轨道上。
  /// 手机端同步（`BrickTimer` 与本方法同源），两端文案不再分叉。
  String _caption(ActiveSession? session, SessionView view) {
    // 今日休息态：环里直接写状态（省一行横幅，垂直预算只剩几 pt）。
    // 2026-11-11：带上今天的总账——收工后环心是「收工」，这行就是唯一的成绩单。
    if (session == null && _data.isRestDay(DateTime.now())) {
      final total = StatsView.of(_data, DateTime.now()).todayMinutes;
      return total <= 0 ? '今日休息' : '今日休息 · ${formatHoursMinutes(total)}';
    }
    if (session == null) return '准备开始';
    // 到点后的措辞分两种：专注是"还可以继续攒"，休息是"该回去了"。
    // 旧文案对休息也说「已超时 · 仍在累积」，等于叫人在休息里多待一会儿。
    if (view.targetReached) {
      return view.mode.isFocus ? '已超时 · 仍在累积' : '休息够了 · 切回专注';
    }
    if (!session.running) {
      if (view.mode.isFocus) return '已暂停';
      return '已暂停 · ${view.mode.label}';
    }
    if (view.mode == SessionMode.focus) return '专注中';
    return view.mode == SessionMode.shortBreak ? '起身活动一下' : '吃饭，慢慢来';
  }

  /// 收工态：今天已经没有"进行中的会话"，但环不该是空的。
  bool _isResting(DateTime now) =>
      _data.activeSession == null && _data.isRestDay(now);

  /// 收工态的合成视图：progress 恒为 1（整圈闭合），环心大字另有覆盖。
  ///
  /// 旧行为在收工后照样画一个 50:00 的空环 —— 对刚收工的人是"你还没开始"，
  /// 与「今天结束了」的正反馈正好相反。
  SessionView get _restView => const SessionView(
        mode: SessionMode.focus,
        running: false,
        targetReached: false,
        // progress 的分母不能是 0；1 − 0 = 1 → 整圈闭合。
        plannedSeconds: 1,
        remainingSeconds: 0,
        overtimeSeconds: 0,
        elapsedSeconds: 0,
      );

  /// 收工态环心字。**刻意不用 [brickNumberStyle]**：它指定 monospace，
  /// 而等宽字体没有中文字形，中文要交给系统回退链。
  static const TextStyle _restCenterStyle = TextStyle(
    color: PineColors.pine,
    fontSize: 34,
    fontWeight: FontWeight.w500,
    letterSpacing: 8,
    height: 1.1,
  );

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
          const SizedBox(width: 6),
          // 手机上也要能开/暂停事件：修前这个入口只在桌面舱的任务行里，
          // 安卓端等于"事件只能看不能动"（2026-11-06 补）。
          _eventChip(),
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

  /// 全部历史累计：只增不减的那三个数，紧贴主按钮下方。
  Widget _cumulative(StatsView stats) {
    if (stats.totalMinutes < 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: PineColors.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PineColors.line, width: 1),
      ),
      child: Row(
        children: [
          const Text(
            '累计',
            style: TextStyle(
              fontSize: 11,
              color: PineColors.sub,
              letterSpacing: .06,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatHoursMinutes(stats.totalMinutes),
            style: const TextStyle(
              fontSize: 14,
              color: PineColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '第 ${stats.totalDays} 天 · ${stats.totalTomatoes} 番茄',
            style: const TextStyle(
              fontSize: 10.5,
              color: PineColors.sub,
              letterSpacing: .02,
            ),
          ),
        ],
      ),
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

  /// 今日日程（**自然日**，不是凌晨 3 点的统计日）：只勾选，不计时。
  /// 今日日程（手机，2026-10-25 改版）：直接在主页面打勾，不再必须进面板。
  ///
  /// 只看今天、只做一件事——勾。跨天排程/导入仍在 `showPlanSheet`（点「全部 ›」）。
  /// 排序不重排：勾完留在原位，避免手指正点的那一行跳走。
  Widget _planCard() {
    final todayKey = ymdOf(dayStart(DateTime.now()));
    final items = _data.todos[todayKey] ?? const <TodoItem>[];
    final done = items.where((item) => item.done).length;
    const maxRows = 4;
    return BrickCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '今日日程',
                style: TextStyle(
                    color: PineColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (items.isNotEmpty)
                Text('$done/${items.length}',
                    style: const TextStyle(
                        color: PineColors.sub, fontSize: 12)),
              const SizedBox(width: 4),
              // 内联加一条：不弹面板，点开就在卡里输入。
              InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () => setState(() => _planAdding = !_planAdding),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Icon(
                    _planAdding ? Icons.close : Icons.add,
                    size: 16,
                    color: PineColors.pine,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: _openPlanSheet,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Text('全部 ›',
                      style:
                          TextStyle(color: PineColors.sub, fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (items.isEmpty && !_planAdding)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _planAdding = true),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('今天还没安排 · 点这里加一条',
                    style: TextStyle(color: PineColors.sub, fontSize: 12)),
              ),
            )
          else
            // 勾选后重排要有中间态：固定行高 + AnimatedPositioned 才滑得动。
            AnimatedTodoRows(
              items: items.take(maxRows).toList(),
              rowHeight: 26,
              itemBuilder: (item) =>
                  _planRow(todayKey, item, fontSize: 13),
            ),
          if (_planAdding)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.radio_button_unchecked,
                      size: 16, color: PineColors.faint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _planController,
                      autofocus: true,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '今天要做的一件事',
                        hintStyle:
                            TextStyle(color: PineColors.sub, fontSize: 12),
                      ),
                      onSubmitted: (_) => _addPlanItem(todayKey),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _addPlanItem(todayKey),
                    child: const Text('加',
                        style:
                            TextStyle(color: PineColors.pine, fontSize: 12)),
                  ),
                ],
              ),
            ),
          if (items.length > maxRows)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: _openPlanSheet,
                child: Text('还有 ${items.length - maxRows} 条 · 全部 ›',
                    style:
                        const TextStyle(color: PineColors.pine, fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  void _addPlanItem(String todayKey) {
    final text = _planController.text.trim();
    if (text.isEmpty) return;
    _planController.clear();
    _applyTodos((todos) => {
          ...todos,
          todayKey: [
            ...todos[todayKey] ?? const <TodoItem>[],
            TodoItem(text: text),
          ],
        });
    setState(() => _planAdding = false);
  }

  /// 长按编辑日程文本：只改文字，id / 勾选状态 / 所属日期都不动。
  Future<void> _editPlanItem(String dayKey, TodoItem item) async {
    final text = await showTodoEditDialog(context, initialText: item.text);
    if (text == null || text.isEmpty) return;
    _applyTodos((todos) => {
          ...todos,
          dayKey: [
            for (final entry in todos[dayKey] ?? const <TodoItem>[])
              entry.id == item.id ? entry.copyWith(text: text) : entry,
          ],
        });
  }

  void _removePlanItem(String dayKey, TodoItem item) {
    _applyTodos((todos) => {
          ...todos,
          dayKey: [
            for (final entry in todos[dayKey] ?? const <TodoItem>[])
              if (entry.id != item.id) entry,
          ],
        });
  }

  Widget _planRow(String dayKey, TodoItem item, {double fontSize = 12}) =>
      _PlanLine(
        item: item,
        fontSize: fontSize,
        desktop: _desktop,
        // 勾选即重排：完成的按勾选顺序浮到顶部（见 toggleTodoDone）。
        onToggle: () => _applyTodos((todos) => {
              ...todos,
              dayKey:
                  toggleTodoDone(todos[dayKey] ?? const <TodoItem>[], item.id),
            }),
        onEdit: () => _editPlanItem(dayKey, item),
        onRemove: () => _removePlanItem(dayKey, item),
      );

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
/// 日程条目（首页卡用）：点=勾选；铅笔常显=编辑；桌面端右键还有菜单；手机端长按也能编辑。
class _PlanLine extends StatelessWidget {
  const _PlanLine({
    required this.item,
    required this.fontSize,
    required this.desktop,
    required this.onToggle,
    required this.onEdit,
    required this.onRemove,
  });

  final TodoItem item;
  final double fontSize;
  final bool desktop;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final row = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onToggle,
      // 手机：长按编辑（触摸屏上没有右键）。桌面：长按不做任何事，避免和拖选冲突。
      onLongPress: desktop ? null : onEdit,
      onSecondaryTapDown: desktop
          ? (details) => showPlanItemMenu(
                context,
                details.globalPosition,
                onEdit: onEdit,
                onRemove: onRemove,
              )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              item.done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: item.done ? PineColors.pine : PineColors.faint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize,
                  color: item.done ? PineColors.sub : PineColors.ink,
                  decoration: item.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            // 常显编辑按钮：批量改内容时不用先悬停/右键（2026-10-26 反馈）。
            GestureDetector(
              onTap: onEdit,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Icon(Icons.edit_outlined,
                    size: 14, color: PineColors.sub),
              ),
            ),
          ],
        ),
      ),
    );
    if (!desktop) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: row,
    );
  }
}

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
              formatHoursMinutes(record.minutes),
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
    required this.diameter,
    this.timeStyle,
    this.stamp = false,
  });

  final double progress;
  final Color color;
  final String timeText;
  final String caption;
  final bool overtime;

  /// 环心大字样式；null 走 [brickNumberStyle]（等宽 + tabular）。
  /// 收工态环心写「收工」二字，等宽字体没有中文字形，必须整段覆盖。
  final TextStyle? timeStyle;

  /// 完成章（桌面）：一次专注完成时在环右上角盖下。
  final bool stamp;

  /// 环径由父级按可用高度决定（244 / 212 / 184），见 _desktopCabin。
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: RingProgressPainter(
              progress: progress,
              color: color,
              stroke: 3,
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeText,
                  style: timeStyle ??
                      brickNumberStyle(
                        // 小环降一档，避免数字顶到 12pt 轨道。
                        fontSize: diameter >= Paper.ringMax
                            ? 42
                            : (diameter < 200 ? 38 : 40),
                        color:
                            overtime ? PineColors.goldInk : PineColors.ink,
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

/// 阶段条右侧的「收工」入口。
///
/// 与三格阶段条刻意不同形：阶段条是**平铺的段选**（无边框、选中才上色），
/// 这颗是**一颗描边胶囊**（常态无底、hairline 边、sub 字）。它不是"第三种休息"，
/// 是"今天到此为止"，所以不能和短休/吃饭长得一样。
/// 收工态下它变成「继续今日」并整体上松绿——同一格既显示状态又是撤销入口。
class _RestEntryChip extends StatelessWidget {
  const _RestEntryChip({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = active ? PineColors.pine : PineColors.sub;
    return Semantics(
      button: true,
      label: active ? '继续今日（撤销收工）' : '收工',
      child: BrickPressable(
        onTap: onTap,
        shadowed: false,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? PineColors.tint(PineColors.pine) : PineColors.card,
            borderRadius: BorderRadius.circular(Paper.chipRadius),
            border: Border.all(
              color: active ? PineColors.pine : PineColors.line,
              width: Paper.chipBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.wb_sunny_outlined : Icons.bedtime_outlined,
                size: 14,
                color: accent,
              ),
              const SizedBox(width: 4),
              Text(
                active ? '继续今日' : '收工',
                maxLines: 1,
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 收工仪式（2026-11-11）。
///
/// 为什么不是 AlertDialog：① 它要盖住整屏并自带遮罩，才算"天黑下来"；
/// ② 对话框走内在宽度/高度测量，`docs/07 §7` 记着在这条路上踩过的两个坑
/// （stretch+Expanded、BrickButton 进 OverflowBar）；③ 仪式要两段式动画，
/// 对话框的 builder 不适合承载。
///
/// 两段式（由 [resting] 驱动，**不另设本地状态**——数据一落，第二幕就是事实）：
/// 1. 确认幕：松果按今日进度长成 → 报总账 → 「收工 / 再学一会儿」；
/// 2. 盖章幕：按下「收工」后 `restDate` 已落，松果盖住「收工」章，1.2 秒后自动收起。
///
/// 「再学一会儿」只关浮层，**一个字节都不改**——仪式不能变成惩罚。
class _RestCeremony extends StatelessWidget {
  const _RestCeremony({
    required this.stats,
    required this.goalMinutes,
    required this.resting,
    required this.onConfirm,
    required this.onCancel,
  });

  final StatsView stats;
  final int goalMinutes;

  /// 今天已经收工了吗：true = 盖章幕。
  final bool resting;

  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  /// 按目标达成度给一句收尾话。不做拟人化的夸张褒奖——"松林手帐"的调子偏克制。
  static String closingLine(double ratio) {
    if (ratio >= 1) return '目标达成 · 今天很稳';
    if (ratio >= 0.6) return '今天攒下了一整段完整的专注';
    if (ratio > 0) return '有开始，就已经和昨天不一样';
    return '今天没计时也算数 · 明天再来';
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final goal = goalMinutes <= 0 ? 1 : goalMinutes;
    final ratio = (stats.todayMinutes / goal).clamp(0.0, 1.0);
    final growTo = resting ? 1.0 : ratio;

    // 遮罩：盖章幕不再响应点击（1.2 秒后自动收起，别让人点空）。
    // 颜色取自 ink 令牌（禁止裸色值）。
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: resting ? null : onCancel,
            child: Container(color: PineColors.ink.withAlpha(118)),
          ),
        ),
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 14),
                child: child,
              ),
            ),
            // 矮窗口兜底：仪式卡固定 320 宽，但高度随内容长；窗口更矮时让它自己滚，
            // 否则 Column 会直接溢出（横屏手机 / 拖扁的桌面窗都会踩到）。
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height - 48,
              ),
              child: SingleChildScrollView(
                child: Container(
              width: 320,
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              decoration: BoxDecoration(
                color: PineColors.paper,
                borderRadius: BorderRadius.circular(Paper.cardRadius),
                boxShadow: Paper.shadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ceremonyPinecone(context, growTo, reduceMotion),
                  const SizedBox(height: 14),
                  Text(
                    resting ? '今日已收工' : '今天收工了',
                    style: const TextStyle(
                      color: PineColors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    resting ? '计时与提醒都关掉了 · 明天见' : closingLine(ratio),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: PineColors.sub,
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: PineColors.line),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: MetricTile(
                          value: '${stats.todayMinutes.round()} 分钟',
                          label: '今日专注',
                        ),
                      ),
                      Expanded(
                        child: MetricTile(
                          value: '${stats.todayCount} 个',
                          label: '番茄',
                        ),
                      ),
                      Expanded(
                        child: MetricTile(
                          value: '${stats.streak} 天',
                          label: '连续',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text(
                        '今日目标',
                        style: TextStyle(color: PineColors.sub, fontSize: 11),
                      ),
                      const Spacer(),
                      Text(
                        '$goalMinutes 分钟 · 达成 ${(ratio * 100).round()}%',
                        style: brickNumberStyle(
                          fontSize: 10,
                          color: PineColors.sub,
                          weight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  BrickProgress(value: ratio),
                  if (!resting) ...[
                    const SizedBox(height: 18),
                    BrickButton(
                      label: '收工',
                      icon: Icons.check_rounded,
                      height: 44,
                      onPressed: onConfirm,
                    ),
                    const SizedBox(height: 6),
                    // 次行动用 TextButton：胶囊已经给了主行动，这里只是"退出仪式"。
                    TextButton(
                      onPressed: onCancel,
                      child: const Text(
                        '再学一会儿',
                        style: TextStyle(color: PineColors.sub, fontSize: 13),
                      ),
                    ),
                  ],
                ],
              ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 松果：确认幕按进度自下而上长成，盖章幕一次性长满并盖上「收工」章。
  ///
  /// 两幕共用同一个 112×90 的画框、松果在其中居中——只多盖一枚印章。
  /// 换画框尺寸会让松果在第一幕→第二幕之间**跳一下**，而那正是要给正反馈的瞬间。
  Widget _ceremonyPinecone(
    BuildContext context,
    double growTo,
    bool reduceMotion,
  ) {
    final cone = SizedBox(
      width: 72,
      height: 86,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: growTo),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 720),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => CustomPaint(
          painter: _PineconePainter(growth: value),
        ),
      ),
    );
    return SizedBox(
      width: 112,
      height: 90,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: Center(child: cone)),
          // 印章压在松果**右下角外侧**，只咬住一角：盖在果体正中会把"长成的松果"
          // 整个遮掉，那正是要让用户看见的东西。
          if (resting)
            Positioned(
              right: -10,
              bottom: -4,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.4, end: 1),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 320),
                curve: Curves.elasticOut,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: const _RestStamp(),
              ),
            ),
        ],
      ),
    );
  }
}

/// 收工章：与「专注完成」章同语言（墨绿描边圆 + 小字），内容换成「收工」。
class _RestStamp extends StatelessWidget {
  const _RestStamp();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.16,
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: PineColors.paper,
          shape: BoxShape.circle,
          border: Border.all(color: PineColors.pine, width: 2),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check, size: 12, color: PineColors.pine),
            Text(
              '收工',
              style: TextStyle(
                color: PineColors.pine,
                fontSize: 9,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 今日长成的松果：18 枚鳞片**自下而上**按进度点亮。
///
/// 为什么是松果：App 就叫 pinecone，日期条右侧那枚小松标是全站唯一的品牌记号
/// （见 `_dateHeader`）。收工时给它一个"长成"的动作，比再画一圈进度弧更像一件事——
/// 环已经在主界面上报过一次数了，仪式该给的是另一个说法。
///
/// 画法照真松果的样子：每枚鳞片是一个**朝下的半圆**，行与行重叠 25%、自下而上叠画，
/// 上面一行压住下面一行的"平顶"，于是整棵读起来是层层叠叠的鳞片而不是一堆圆点。
/// 行数自下而上 4/4/4/3/2/1：下宽上尖，收口在顶部。
class _PineconePainter extends CustomPainter {
  const _PineconePainter({required this.growth});

  /// 0..1，按比例点亮鳞片（自下而上，行内自左向右）。
  final double growth;

  static const List<int> _rows = [4, 4, 4, 3, 2, 1];
  static const int _total = 18;

  /// 设计盒（鳞片半径 8.5、行距 13 时的实际外框），按可用空间等比缩放。
  /// 高宽比约 1.3：松果是竖着的椭球，做方了像一堆碗。
  static const double _designW = 63.5;
  static const double _designH = 82.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = (size.width / _designW).clamp(0.0, size.height / _designH);
    if (scale <= 0) return;
    const radius = 8.5;
    const pitchY = 13.0;
    const gapX = 15.5;
    final r = radius * scale;
    final filled =
        (growth.clamp(0.0, 1.0) * _total).round().clamp(0, _total);

    final originX = size.width / 2;
    final originY = (size.height - _designH * scale) / 2;
    final bottomY = originY + _designH * scale - r;

    final fillPaint = Paint()..style = PaintingStyle.fill;
    // 空鳞片用 faint 而不是 line：line 对纸面只有 1.19:1，"还没长成的部分"
    // 几乎看不见，整棵就只剩下半截，读不出"长成了多少"。
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * scale
      ..color = PineColors.faint;
    // 已长成的鳞片之间用纸色刻一道缝：不刻就并成一条实心带，看不出层次。
    final carvePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * scale
      ..color = PineColors.paper;

    var drawn = 0;
    for (var row = 0; row < _rows.length; row++) {
      final count = _rows[row];
      final cy = bottomY - row * pitchY * scale;
      for (var i = 0; i < count; i++) {
        final cx = originX + (i - (count - 1) / 2) * gapX * scale;
        final path = _scalePath(cx, cy, r);
        if (drawn < filled) {
          fillPaint.color = PineColors.pine;
          canvas.drawPath(path, fillPaint);
          canvas.drawPath(path, carvePaint);
        } else {
          canvas.drawPath(path, outlinePaint);
        }
        drawn++;
      }
    }
  }

  /// 一枚鳞片：比正圆略瘦的朝下半圆（宽度 > 高度的一半），平顶留给上一行压。
  static Path _scalePath(double cx, double cy, double r) => Path()
    ..addArc(
      Rect.fromCenter(center: Offset(cx, cy), width: r * 1.86, height: r * 2),
      0,
      3.141592653589793,
    )
    ..close();

  @override
  bool shouldRepaint(_PineconePainter old) => old.growth != growth;
}
