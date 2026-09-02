import 'dart:async';

import 'package:flutter/material.dart';

import '../src/cloud_auto.dart';
import '../src/cloud_sync.dart';
import '../src/engine.dart';
import '../src/models.dart';
import '../src/notifications.dart';
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
  String _foregroundKey = '';
  DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);
  late final AutoCloudSync _autoSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoSync = AutoCloudSync(
      sync: CloudSync(),
      apply: (data) async {
        if (!mounted) return;
        _apply(data, force: true);
      },
    );
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick(forcePersist: true);
      // 回到前台：拉取网页端可能刚上传的更新。
      unawaited(_autoSync.onResume(context, _data));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
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
    await _syncForeground();
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
    unawaited(_syncForeground());
  }

  void _persist({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastPersist).inSeconds < 10) return;
    _lastPersist = now;
    unawaited(Storage.save(_data));
  }

  void _apply(AppData next, {bool force = false}) {
    setState(() => _data = next);
    _persist(force: force);
    unawaited(_syncForeground());
  }

  void _announce(SessionMode? mode) {
    final title = mode == SessionMode.focus
        ? '松果 · 计划时长已到'
        : (mode == null ? '松果 · 计时结束' : '松果 · 休息结束');
    final body = mode == SessionMode.focus
        ? '这一轮计划时长已到，继续专注会累计更多时长。'
        : '休息结束，可以开始下一轮专注。';
    if (_data.notifyEnabled) {
      unawaited(Notifier.alert(title: title, body: body));
    }
    if (_data.soundEnabled) unawaited(Notifier.chime());
  }

  Future<void> _syncForeground() async {
    if (_syncingForeground) return;
    _syncingForeground = true;
    try {
      final view = SessionView.of(_data, DateTime.now());
      if (view == null || !view.running) {
        if (_foregroundKey.isNotEmpty) {
          _foregroundKey = '';
          await ForegroundRunner.stop();
        }
        return;
      }
      // 只在状态切换（模式/运行/超时）时更新通知：倒计时由系统 Chronometer
      // 走表，逐秒重发反而会与系统渲染互相覆盖。
      final key =
          '${_data.activeSession?.mode.key}|${view.running}|${view.targetReached}';
      if (key == _foregroundKey) return;
      _foregroundKey = key;
      final active = _data.activeSession;
      await ForegroundRunner.start(
        remainingTime: view.clockText,
        deadlineMs: active?.deadline?.millisecondsSinceEpoch,
        overtimeStartedAtMs: active?.overtimeStartedAt?.millisecondsSinceEpoch,
        targetReached: view.targetReached,
      );
    } catch (_) {
      // 前台服务不可用时不应影响计时。
    } finally {
      _syncingForeground = false;
    }
  }

  void _toggleRun() {
    final now = DateTime.now();
    var next = TimerEngine.advance(_data, now);
    final session = next.activeSession;
    if (session == null) {
      next = TimerEngine.start(next, next.idleMode, now);
    } else if (session.running) {
      next = TimerEngine.pause(next, now);
    } else {
      next = TimerEngine.resume(next, now);
    }
    _apply(next, force: true);
  }

  void _confirm() {
    final now = DateTime.now();
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
      final count = StatsView.of(next, now).todayCount;
      final breakMode = count > 0 && count % 4 == 0
          ? SessionMode.longBreak
          : SessionMode.shortBreak;
      next = TimerEngine.start(next, breakMode, now);
    } else {
      next = TimerEngine.complete(next, now);
    }
    unawaited(Notifier.cancel());
    _apply(next, force: true);
    // 完成专注（写入了记录）后自动上传，让网页端尽快看到。
    unawaited(_autoSync.afterFocus(context, next));
  }

  void _discard() {
    if (_data.activeSession == null) return;
    unawaited(Notifier.cancel());
    _apply(TimerEngine.discard(_data), force: true);
  }

  void _switchMode(SessionMode mode) {
    unawaited(Notifier.cancel());
    _apply(TimerEngine.switchMode(_data, mode), force: true);
  }

  void _replace(AppData next) => _apply(next, force: true);

  Future<void> _openStats() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StatsPage(data: _data)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(data: _data, onChanged: _replace),
      ),
    );
    if (mounted) setState(() {});
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
        body: Center(child: CircularProgressIndicator(color: PineColors.gold)),
      );
    }
    final now = DateTime.now();
    final session = _data.activeSession;
    final view = SessionView.of(_data, now) ?? _idleView;
    final stats = StatsView.of(_data, now);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 720;
            return Padding(
              padding: EdgeInsets.fromLTRB(18, compact ? 2 : 8, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  SizedBox(height: compact ? 6 : 12),
                  ModeSwitcher(
                    current: view.mode,
                    minutesFor: _data.settings.forMode,
                    onChanged: _switchMode,
                  ),
                  SizedBox(height: compact ? 8 : 14),
                  _taskPicker(),
                  Expanded(
                    flex: compact ? 4 : 5,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: compact ? 210 : 280,
                          maxWidth: compact ? 232 : 292,
                        ),
                        child: RingTimer(
                          view: view,
                          caption: _caption(session, view),
                        ),
                      ),
                    ),
                  ),
                  _controls(session, view),
                  SizedBox(height: compact ? 8 : 12),
                  _metrics(stats),
                  SizedBox(height: compact ? 5 : 8),
                  _todoRow(),
                  SizedBox(height: compact ? 4 : 8),
                  Expanded(flex: compact ? 2 : 3, child: _recent()),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _caption(ActiveSession? session, SessionView view) {
    if (session == null) return '准备开始';
    if (!session.running) return '已暂停';
    if (view.targetReached) return '已超出计划时长';
    return view.mode.label;
  }

  Widget _header() {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PineColors.tomato,
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Text(
              '松',
              style: TextStyle(
                color: PineColors.deep,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '松果',
                style: TextStyle(
                  color: PineColors.ink,
                  fontSize: 17,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '专注时光',
                style: TextStyle(color: PineColors.muted, fontSize: 10),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            tooltip: '统计详情',
            icon: const Icon(Icons.bar_chart_rounded),
            onPressed: _openStats,
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _taskPicker() {
    final task = _data.selectedTask;
    return Align(
      alignment: Alignment.center,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showTaskSheet(context, data: _data, onChanged: _replace),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: PineColors.dark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: PineColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: task.swatch,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  task.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PineColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.unfold_more_rounded,
                  size: 15, color: PineColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls(ActiveSession? session, SessionView view) {
    final primary = session == null ? '开始' : (session.running ? '暂停' : '继续');
    final confirm =
        session == null ? '直接记录' : (view.mode.isFocus ? '完成并开始休息' : '结束休息');

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: FilledButton.icon(
            onPressed: _toggleRun,
            style: FilledButton.styleFrom(
              backgroundColor: view.mode.color,
              foregroundColor: PineColors.deep,
            ),
            icon: Icon(
              session?.running == true
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 20,
            ),
            label: Text(primary),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: OutlinedButton.icon(
            onPressed: _confirm,
            style: OutlinedButton.styleFrom(
              foregroundColor: PineColors.gold,
              side: const BorderSide(color: PineColors.gold),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(confirm, style: const TextStyle(fontSize: 13)),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 50,
          width: 50,
          child: IconButton.filledTonal(
            tooltip: '重置（不记录）',
            style: IconButton.styleFrom(
              backgroundColor: PineColors.panel,
              foregroundColor: PineColors.muted,
            ),
            icon: const Icon(Icons.restart_alt, size: 20),
            onPressed: _discard,
          ),
        ),
      ],
    );
  }

  Widget _metrics(StatsView stats) {
    final goal = _data.goalMinutes <= 0 ? 1 : _data.goalMinutes;
    final progress = (stats.todayMinutes / goal).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border:
            Border.symmetric(horizontal: BorderSide(color: PineColors.line)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('今日目标',
                  style: TextStyle(color: PineColors.muted, fontSize: 11)),
              const Spacer(),
              Text(
                '${stats.todayMinutes.round()} / ${_data.goalMinutes} 分钟',
                style: const TextStyle(color: PineColors.ink, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: PineColors.ink.withValues(alpha: 0.10),
              valueColor: const AlwaysStoppedAnimation(PineColors.tomato),
            ),
          ),
          const SizedBox(height: 10),
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
                  accent: PineColors.mint,
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: '${stats.streak} 天',
                  label: '连续专注',
                  accent: PineColors.gold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _todoRow() {
    final items = _data.todos[dateKey(DateTime.now())] ?? [];
    final done = items.where((item) => item.done).length;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showTodoSheet(context, data: _data, onChanged: _replace),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.checklist_rounded,
                size: 17, color: PineColors.mint),
            const SizedBox(width: 9),
            const Text('今日清单',
                style: TextStyle(color: PineColors.paper, fontSize: 13)),
            const Spacer(),
            Text(
              items.isEmpty ? '添加' : '$done / ${items.length}',
              style: const TextStyle(color: PineColors.muted, fontSize: 12),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: PineColors.muted),
          ],
        ),
      ),
    );
  }

  Widget _recent() {
    final items =
        _data.records.where((record) => record.counted).take(30).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: '最近完成',
          trailing: TextButton.icon(
            onPressed: () =>
                showManualSheet(context, data: _data, onChanged: _replace),
            icon: const Icon(Icons.add, size: 15),
            label: const Text('补记', style: TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text(
                    '完成一轮专注后会出现在这里',
                    style: TextStyle(color: PineColors.muted, fontSize: 12),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final record = items[index];
                    final color = _colorFor(record.taskName);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 8,
                        height: 8,
                        decoration:
                            BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      title: Text(
                        record.taskName,
                        style: const TextStyle(
                            color: PineColors.paper, fontSize: 13),
                      ),
                      subtitle: Text(
                        '${record.status.label} · ${record.at.hour.toString().padLeft(2, '0')}:${record.at.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                            color: PineColors.muted, fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatMinutes(record.minutes),
                            style: const TextStyle(
                              color: PineColors.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 15),
                            onPressed: () => _deleteRecord(record),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Color _colorFor(String taskName) {
    for (final task in _data.tasks) {
      if (task.name == taskName) return task.swatch;
    }
    return PineColors.muted;
  }

  Future<void> _deleteRecord(FocusRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text(
            '「${record.taskName}」${formatMinutes(record.minutes)} 会从统计中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _replace(_data.copyWith(
      records: _data.records.where((item) => item.id != record.id).toList(),
    ));
  }
}
