import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'engine.dart';
import 'models.dart';
import 'theme.dart';

/// 原生菜单栏菜单被点击时回传给 Dart 的动作。
///
/// 这里只描述「用户想做什么」，真正的状态变更一律交给 [TimerEngine]，
/// 保证菜单栏与主界面共用同一份数据源，不出现两套计时状态。
enum MenuBarAction {
  /// 开始 / 暂停 / 继续（三态合一，语义与空格键一致）。
  toggle,

  /// 确认完成：专注写记录并进入休息，休息则结束。
  complete,

  /// 重置（丢弃当前这轮，不写统计）。
  discard,
}

/// 菜单栏一次刷新的完整状态（纯数据 → 可单测）。
class MenuBarState {
  const MenuBarState({
    required this.title,
    required this.head,
    required this.detail,
    required this.primary,
    required this.confirm,
    required this.canReset,
    required this.tint,
    required this.elapsed,
    required this.progress,
    required this.active,
  });

  /// 菜单栏常驻文本，与叶子图标并排，尽量短。
  final String title;

  /// 下拉菜单第一行：当前阶段 · 任务名。
  final String head;

  /// 下拉菜单第二行：剩余 / 超时 / 暂停说明。
  final String detail;

  /// 主按钮文案：开始 / 暂停 / 继续。
  final String primary;

  /// 确认按钮文案：完成并开始休息 / 结束休息 / 直接记录。
  final String confirm;

  /// 是否有进行中的会话可重置。
  final bool canReset;

  /// 图标与文字配色（ARGB，与 `Color.toARGB32()` 一致）。
  final int tint;

  /// 已累计时长 `mm:ss`（悬浮小窗主数字）。
  final String elapsed;

  /// 进度 0..1，超时后为 1（悬浮小窗进度条）。
  final double progress;

  /// 是否有进行中的会话；为 false 时悬浮小窗自动隐藏。
  final bool active;
}

String _modeShort(SessionMode mode) => switch (mode) {
      SessionMode.focus => '专注',
      SessionMode.shortBreak => '短休',
      SessionMode.longBreak => '长休',
    };

/// 由 [AppData] 推导菜单栏状态的纯函数。
///
/// - 空闲：只显示「松果」，中性灰
/// - 专注中：番茄红；短休/长休：薄荷绿
/// - 到点后继续计时：金色，clockText 自带 `+` 前缀
/// - 暂停：中性灰，冻结在剩余时刻
MenuBarState menuBarStateOf(AppData data, DateTime now) {
  final view = SessionView.of(data, now);

  // 没有进行中的会话：菜单栏退化为品牌名，菜单里给出今日进度。
  if (view == null) {
    final stats = StatsView.of(data, now);
    return MenuBarState(
      title: '松果',
      head: '未开始 · ${data.idleMode.label}',
      detail: '今日 ${stats.todayMinutes.round()} / ${data.goalMinutes} 分钟',
      primary: '开始',
      confirm: '直接记录',
      canReset: false,
      tint: PineColors.sub.toARGB32(),
      elapsed: '00:00',
      progress: 0,
      active: false,
    );
  }

  final short = _modeShort(view.mode);
  final isFocus = view.mode.isFocus;
  final head = isFocus ? '专注中 · ${data.selectedTask.name}' : '${view.mode.label}中';
  final confirm = isFocus ? '完成并开始休息' : '结束休息';

  // 暂停：冻结在剩余（或超时）时刻，配色转灰，一眼能看出没在走。
  if (!view.running) {
    return MenuBarState(
      // 暂停也显示已累计时长：此时它冻结在暂停时刻，正是「专注了多久」。
      title: '暂停 ${view.elapsedText}',
      head: '${view.mode.label} · 已暂停',
      detail: view.targetReached
          ? '已专注 ${view.elapsedText}，超出计划 ${view.clockText}'
          : '已专注 ${view.elapsedText}，剩余 ${view.clockText}',
      primary: '继续',
      confirm: confirm,
      canReset: true,
      tint: PineColors.sub.toARGB32(),
      elapsed: view.elapsedText,
      progress: view.progress,
      active: true,
    );
  }

  // 到点后不自动结束，继续累计超时 → 金色提示。
  if (view.targetReached) {
    return MenuBarState(
      title: '$short ${view.elapsedText}',
      head: head,
      detail: '已专注 ${view.elapsedText}，超出计划 ${view.clockText}',
      primary: '暂停',
      confirm: confirm,
      canReset: true,
      tint: PineColors.gold.toARGB32(),
      elapsed: view.elapsedText,
      progress: 1,
      active: true,
    );
  }

  return MenuBarState(
    title: '$short ${view.elapsedText}',
    head: head,
    detail: '已专注 ${view.elapsedText}，剩余 ${view.clockText}',
    primary: '暂停',
    confirm: confirm,
    canReset: true,
    tint: (isFocus ? PineColors.focus : PineColors.mint).toARGB32(),
    elapsed: view.elapsedText,
    progress: view.progress,
    active: true,
  );
}

/// macOS 菜单栏（屏幕右上角状态栏）计时显示。
///
/// Flutter 侧每秒推送一次状态，原生 `NSStatusItem` 负责渲染；
/// 用户点击菜单栏图标弹出菜单，动作经同一条通道回传 Dart。
/// 非 macOS 平台全部为空操作，不影响安卓/网页。
class MenuBarTimer {
  MenuBarTimer._();

  static const MethodChannel _channel = MethodChannel('pine/menu_bar');

  static bool get supported => !kIsWeb && Platform.isMacOS;

  /// 注册原生菜单点击回调；重复调用以最后一次为准。
  static void listen(void Function(MenuBarAction action) onAction) {
    if (!supported) return;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'action') return null;
      final id = (call.arguments as Map<Object?, Object?>?)?['id'];
      switch (id) {
        case 'toggle':
          onAction(MenuBarAction.toggle);
        case 'complete':
          onAction(MenuBarAction.complete);
        case 'discard':
          onAction(MenuBarAction.discard);
      }
      return null;
    });
  }

  /// 推送一次状态。原生侧会在文本/配色没变时跳过重绘。
  static void update(MenuBarState state) {
    if (!supported) return;
    _channel.invokeMethod<void>('update', <String, Object?>{
      'title': state.title,
      'head': state.head,
      'detail': state.detail,
      'primary': state.primary,
      'confirm': state.confirm,
      'canReset': state.canReset,
      'tint': state.tint,
      'elapsed': state.elapsed,
      'progress': state.progress,
      'active': state.active,
    }).catchError((Object _) {
      // 菜单栏是可降级能力：原生未就绪时不影响计时本身。
    });
  }
}
