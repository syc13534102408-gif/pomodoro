import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine.dart';
import 'models.dart';
import 'theme.dart';

/// 形态变体归属（对照 `p4-component-inventory.md` 第一节）：
///
/// - [PineVariant.active] 进行中变体：开放式几何组织、陪驻底色（[PinePalette.presence]）与
///   进行中边界（[PineRadius.active] = 24）；三阶段完全相同，不作形态区分。
///   适用于：会话陪驻条、外部会话陪驻、完成归属回执、阶段直选、当前会话读数、会话控制、会话准备。
/// - [PineVariant.settled] 沉淀变体：规整事实组、承载底色（[PinePalette.surface]）与
///   沉淀边界（[PineRadius.settled] = 16）；适用于记录、统计、事件、日程与资料中的已定型事实。
/// - [PineVariant.adjudication] 裁决变体：冲突裁决与安全副本确认独立边界（[PineRadius.adjudication] = 8）。
/// - [PineVariant.general] 通用 / 通用聚合：时态切换、台账分段选择、今日进度、收工动作、目标日读数等。
///   共享组件不得混用「进行中」与「沉淀」两种形态。
enum PineVariant { active, settled, adjudication, general }

/// 动效契约档位（对照 `p4-design-tokens.md` 与 `p4-component-inventory.md`）：
///
/// - [PineMotionContract.immediate] 操作响应 0ms：开始、暂停、继续、完成、重置、切换、收工、保存与裁决。
/// - [PineMotionContract.standard] 标准过渡 160ms：已生效内容的语境衔接。
/// - [PineMotionContract.maximum] 过渡上限 ≤200ms：所有允许过渡的绝对上限（不含连续计时）。
enum PineMotionContract {
  immediate(PineMotion.immediate),
  standard(PineMotion.standard),
  maximum(PineMotion.maximum);

  const PineMotionContract(this.duration);
  final Duration duration;
}

/// 一级时态入口（双时态：当下 / 台账）。
enum PineTense {
  present('当下'),
  ledger('台账');

  const PineTense(this.label);
  final String label;
}

/// 台账五个平权分段（记录 / 统计 / 事件 / 日程 / 资料）。
enum PineLedgerSegment {
  records('记录'),
  stats('统计'),
  events('事件'),
  schedule('日程'),
  profile('资料');

  const PineLedgerSegment(this.label);
  final String label;
}

/// 冲突裁决状态机（V7 裁决）。
enum AdjudicationStatus {
  /// 正在创建本机安全副本（加载态，裁决暂禁用）。
  creatingSafetyCopy,

  /// 本机安全副本已创建（待用户裁决）。
  readyToAdjudicate,

  /// 本机安全副本创建失败（提供明确重试动作，未成功前不得恢复）。
  safetyCopyFailed,
}

bool _isDesktopPlatform() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

Duration _effectiveDuration(BuildContext context, Duration base) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return reduceMotion ? Duration.zero : base;
}

/// 按 P4 文案表格式化阶段定稿名（`专注` / `短休` / `长休`）。
String pinePhaseCopy(SessionMode mode) => switch (mode) {
      SessionMode.focus => '专注',
      SessionMode.shortBreak => '短休',
      SessionMode.longBreak => '长休',
    };

/// 通用进行中变体表面容器。
///
/// - 变体：[PineVariant.active]（进行中变体，圆角 24，陪驻底色 `palette.presence`）
/// - 动效契约：语境衔接 ≤200ms（[PineMotion.maximum]）
class ActiveVariantSurface extends StatelessWidget {
  const ActiveVariantSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(PineSpacing.section),
    this.borderColor,
  });

  static const PineVariant variant = PineVariant.active;
  static const PineMotionContract motionContract = PineMotionContract.maximum;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    return AnimatedContainer(
      duration: _effectiveDuration(context, PineMotion.maximum),
      curve: Curves.easeOut,
      padding: padding,
      decoration: BoxDecoration(
        color: palette.presence,
        borderRadius: BorderRadius.circular(PineRadius.active),
        border: Border(
          left: BorderSide(
              color: borderColor ?? palette.divider, width: Paper.hairline),
        ),
      ),
      child: child,
    );
  }
}

/// 通用沉淀变体表面容器。
///
/// - 变体：[PineVariant.settled]（沉淀变体，圆角 16，承载底色 `palette.surface`）
/// - 动效契约：语境衔接 160ms（[PineMotion.standard]）
class SettledVariantSurface extends StatelessWidget {
  const SettledVariantSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(PineSpacing.section),
    this.borderColor,
    this.borderWidth = Paper.hairline,
  });

  static const PineVariant variant = PineVariant.settled;
  static const PineMotionContract motionContract = PineMotionContract.standard;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    return AnimatedContainer(
      duration: _effectiveDuration(context, PineMotion.standard),
      curve: Curves.easeOut,
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(PineRadius.settled),
        border: Border.all(
          color: borderColor ?? PineColors.surfaceHairline,
          width: borderWidth,
        ),
      ),
      child: child,
    );
  }
}

/// 逻辑日分隔（`p4-design-tokens.md` 分隔角色）：1px 逻辑日分隔线 + 必须同时出现的所属日期文字。
///
/// - 变体：[PineVariant.settled]（沉淀变体）
/// - 动效契约：0ms（静态边界，不设动画）
class LogicalDayDivider extends StatelessWidget {
  const LogicalDayDivider({
    super.key,
    required this.dateLabel,
    this.auxiliaryLabel,
  });

  static const PineVariant variant = PineVariant.settled;
  static const PineMotionContract motionContract = PineMotionContract.immediate;

  final String dateLabel;
  final String? auxiliaryLabel;

  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                dateLabel,
                style: PineText.sans(
                  size: PineType.auxiliary,
                  color: palette.textSecondary,
                  weight: FontWeight.w600,
                  height: PineLineHeight.auxiliary,
                ),
              ),
            ),
            if (auxiliaryLabel != null) ...[
              const SizedBox(width: PineSpacing.near),
              Text(
                auxiliaryLabel!,
                style: PineText.sans(
                  size: PineType.auxiliary,
                  color: palette.textAuxiliary,
                  height: PineLineHeight.auxiliary,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: PineSpacing.near),
        Container(height: Paper.hairline, color: palette.logicalDayDivider),
      ],
    );
  }
}

/// 任务标识色点 + 文本（状态色与任务色不得单独承担文本含义，无障碍朗读 `〈任务名〉，标识色〈色名〉`）。
///
/// - 变体：[PineVariant.settled]（沉淀变体）
/// - 动效契约：0ms
class TaskIdentityBadge extends StatelessWidget {
  const TaskIdentityBadge({
    super.key,
    required this.taskName,
    required this.color,
  });

  static const PineVariant variant = PineVariant.settled;
  static const PineMotionContract motionContract = PineMotionContract.immediate;

  final String taskName;
  final Color color;

  static const List<String> presetNames = <String>[
    '玫瑰',
    '青绿',
    '靛蓝',
    '琥珀',
    '堇紫',
    '草木',
  ];

  // 已存色值不改写；仅将表现映射到当前模式的有限标识色。
  static int _colorIndex(Color color) {
    final value = color.toARGB32();
    var nearest = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < presetNames.length; i++) {
      for (final candidateColor in [
        PinePalette.light.taskColors[i],
        const [
          Color(0xFFE89AA6),
          Color(0xFF7CC6B3),
          Color(0xFF8EB7ED),
          Color(0xFFD8B36A),
          Color(0xFFB7A0E3),
          Color(0xFFA9C77A),
        ][i],
      ]) {
        final candidate = candidateColor.toARGB32();
        if (candidate == value) return i;
        final red = ((value >> 16) & 255) - ((candidate >> 16) & 255);
        final green = ((value >> 8) & 255) - ((candidate >> 8) & 255);
        final blue = (value & 255) - (candidate & 255);
        final distance = (red * red + green * green + blue * blue).toDouble();
        if (distance < bestDistance) {
          bestDistance = distance;
          nearest = i;
        }
      }
    }
    return nearest;
  }

  static String resolveColorName(Color color, PinePalette palette) =>
      presetNames[_colorIndex(color)];

  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final index = _colorIndex(color);
    final resolvedName = presetNames[index];
    return Semantics(
      label: '$taskName，标识色$resolvedName',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: PineSize.taskGraphic,
            height: PineSize.taskGraphic,
            decoration: BoxDecoration(
              color: palette.taskColors[index],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: PineSpacing.near),
          Flexible(
            child: Text(
              taskName,
              style: PineText.sans(
                size: PineType.body,
                color: palette.textPrimary,
                height: PineLineHeight.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 全局与导航 1：时态切换（当下 / 台账）
// ============================================================================

/// 时态切换：在「当下」与「台账」之间切换，不改变当前会话。
///
/// - 变体：[PineVariant.general]（通用）
/// - 状态：当前时态；仅冲突裁决阻断（[blockedByAdjudication]）时禁用；无加载
/// - 动效契约：切换响应 0ms（[PineMotion.immediate]），语境衔接 160ms（[PineMotion.standard]）
/// - 布局预算：手机 48dp / 桌面 40pt
class TenseSwitcher extends StatelessWidget {
  const TenseSwitcher({
    super.key,
    required this.current,
    required this.onChanged,
    this.blockedByAdjudication = false,
  });

  static const PineVariant variant = PineVariant.general;
  static const PineMotionContract responseContract =
      PineMotionContract.immediate;
  static const PineMotionContract transitionContract =
      PineMotionContract.standard;

  final PineTense current;
  final ValueChanged<PineTense> onChanged;
  final bool blockedByAdjudication;

  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final desktop = _isDesktopPlatform();
    final barHeight = desktop ? 40.0 : 48.0;
    final minTouch =
        desktop ? PineSize.minTouchDesktop : PineSize.minTouchAndroid;
    final transition = _effectiveDuration(context, PineMotion.standard);

    return Container(
      height: barHeight,
      padding: const EdgeInsets.symmetric(horizontal: PineSpacing.section),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(
          bottom: BorderSide(color: palette.divider, width: Paper.hairline),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < PineTense.values.length; i++) ...[
            if (i > 0) const SizedBox(width: PineSpacing.near),
            Expanded(
              child: _TenseTab(
                tense: PineTense.values[i],
                selected: PineTense.values[i] == current,
                enabled: !blockedByAdjudication,
                minHeight: minTouch < barHeight ? minTouch : barHeight,
                transition: transition,
                onTap: () {
                  if (blockedByAdjudication) return;
                  if (PineTense.values[i] == current) return;
                  // 0ms 立即提交切换，不等待动画。
                  onChanged(PineTense.values[i]);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TenseTab extends StatelessWidget {
  const _TenseTab({
    required this.tense,
    required this.selected,
    required this.enabled,
    required this.minHeight,
    required this.transition,
    required this.onTap,
  });

  final PineTense tense;
  final bool selected;
  final bool enabled;
  final double minHeight;
  final Duration transition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final fg = !enabled
        ? palette.textAuxiliary
        : (selected ? palette.textPrimary : palette.textSecondary);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: tense.label,
      child: _ImmediateAction(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: AnimatedContainer(
            duration: transition,
            curve: Curves.easeOut,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: PineSpacing.section,
              vertical: PineSpacing.micro,
            ),
            decoration: const BoxDecoration(
              color: Colors.transparent,
            ),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(tense.label,
                          style: PineText.sans(
                            size: PineType.body,
                            color: fg,
                            weight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            height: PineLineHeight.body,
                          )),
                    ]),
                  ),
                ),
                Container(
                  height: 2,
                  color: selected ? palette.action : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 全局与导航 2：台账分段选择（记录 / 统计 / 事件 / 日程 / 资料）
// ============================================================================

/// 台账分段选择：平权承载「记录、统计、事件、日程、资料」五段。
///
/// - 变体：[PineVariant.general]（通用）
/// - 状态：当前分段；仅冲突裁决阻断（[blockedByAdjudication]）时禁用；无加载
/// - 动效契约：选择响应 0ms（[PineMotion.immediate]），内容衔接 160ms（[PineMotion.standard]）；
///   禁止重排与隐藏（五段固定顺序、始终全显）
/// - 布局预算：手机 48dp / 桌面 40pt
class LedgerSegmentSelector extends StatelessWidget {
  const LedgerSegmentSelector({
    super.key,
    required this.current,
    required this.onChanged,
    this.blockedByAdjudication = false,
  });

  static const PineVariant variant = PineVariant.general;
  static const PineMotionContract responseContract =
      PineMotionContract.immediate;
  static const PineMotionContract transitionContract =
      PineMotionContract.standard;

  final PineLedgerSegment current;
  final ValueChanged<PineLedgerSegment> onChanged;
  final bool blockedByAdjudication;

  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final desktop = _isDesktopPlatform();
    final barHeight = desktop ? 40.0 : 48.0;
    final minTouch =
        desktop ? PineSize.minTouchDesktop : PineSize.minTouchAndroid;
    final transition = _effectiveDuration(context, PineMotion.standard);

    return Container(
      height: barHeight,
      padding: const EdgeInsets.symmetric(horizontal: PineSpacing.near),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(
          bottom: BorderSide(color: palette.divider, width: Paper.hairline),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < PineLedgerSegment.values.length; i++) ...[
            if (i > 0) const SizedBox(width: PineSpacing.micro),
            Expanded(
              child: _LedgerSegmentTab(
                segment: PineLedgerSegment.values[i],
                selected: PineLedgerSegment.values[i] == current,
                enabled: !blockedByAdjudication,
                minHeight: minTouch < barHeight ? minTouch : barHeight,
                transition: transition,
                onTap: () {
                  if (blockedByAdjudication) return;
                  if (PineLedgerSegment.values[i] == current) return;
                  // 0ms 立即提交，不等待动画。
                  onChanged(PineLedgerSegment.values[i]);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LedgerSegmentTab extends StatelessWidget {
  const _LedgerSegmentTab({
    required this.segment,
    required this.selected,
    required this.enabled,
    required this.minHeight,
    required this.transition,
    required this.onTap,
  });

  final PineLedgerSegment segment;
  final bool selected;
  final bool enabled;
  final double minHeight;
  final Duration transition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final fg = !enabled
        ? palette.textAuxiliary
        : (selected ? palette.textPrimary : palette.textSecondary);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: segment.label,
      child: _ImmediateAction(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: AnimatedContainer(
            duration: transition,
            curve: Curves.easeOut,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: PineSpacing.micro),
            decoration: const BoxDecoration(
              color: Colors.transparent,
            ),
            child: Column(
              children: [
                Expanded(
                    child: Center(
                        child: Text(segment.label,
                            style: PineText.sans(
                              size: PineType.body,
                              color: fg,
                              weight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                              height: PineLineHeight.body,
                            )))),
                Container(
                    height: 2,
                    color: selected ? palette.action : Colors.transparent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 全局与导航 3：会话陪驻条（应用内跨视图陪驻）
// ============================================================================

/// 会话陪驻条：在任意应用内视图保持当前会话可读、可完成、可回到当下。
///
/// - 变体：[PineVariant.active]（进行中变体：陪驻底色 `palette.presence`、进行中圆角 `24`；三阶段同形）
/// - 状态：运行 / 暂停 / 超时 / 跨日 / 已收工仍运行；**完成永不禁用**；镜像接收中作为辅助加载说明
/// - 动效契约：完成与回到当下响应 0ms（[PineMotion.immediate]）；辅助说明衔接 ≤200ms（[PineMotion.maximum]）
/// - 布局预算：手机 72dp / 桌面 64pt（固定；仅非 V1 且会话存在时计入）
class SessionPresenceBar extends StatelessWidget {
  const SessionPresenceBar({
    super.key,
    required this.view,
    required this.belongingDateText,
    required this.onComplete,
    required this.onReturnToPresent,
    this.crossDay = false,
    this.restingStillRunning = false,
    this.receivingMirror = false,
  });

  static const PineVariant variant = PineVariant.active;
  static const PineMotionContract responseContract =
      PineMotionContract.immediate;
  static const PineMotionContract transitionContract =
      PineMotionContract.maximum;

  final SessionView view;

  /// 本段归属的逻辑日文案（如 `11月16日`）。
  final String belongingDateText;

  /// 完成回调（永不禁用，0ms 响应）。
  final VoidCallback onComplete;

  /// 回到当下回调（不改变会话，0ms 响应）。
  final VoidCallback onReturnToPresent;

  /// 是否已跨过逻辑日分界（`今天已翻页，本段仍归〈所属日期〉`）。
  final bool crossDay;

  /// 是否已宣告今日收工但当前段仍在继续（`今日已收工，〈阶段〉仍在继续`）。
  final bool restingStillRunning;

  /// 是否正在接收另一端的会话镜像（`正在接收另一端的会话状态`）。
  final bool receivingMirror;

  Color _stateColor(PinePalette palette) {
    if (!view.running) return palette.paused;
    if (view.targetReached) return palette.overtime;
    return switch (view.mode) {
      SessionMode.focus => palette.focus,
      SessionMode.shortBreak => palette.shortBreak,
      SessionMode.longBreak => palette.longBreak,
    };
  }

  String _statusLabel() {
    final phase = pinePhaseCopy(view.mode);
    if (!view.running) return '$phase · 已暂停';
    if (view.targetReached) return '$phase · 超时中';
    return '$phase中';
  }

  String _auxiliaryLine() {
    final phase = pinePhaseCopy(view.mode);
    final parts = <String>[
      if (crossDay)
        '今天已翻页，本段仍归$belongingDateText'
      else
        '本段归属$belongingDateText',
      if (restingStillRunning) '今日已收工，$phase仍在继续',
      if (receivingMirror) '正在接收另一端的会话状态',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final desktop = _isDesktopPlatform();
    final height = desktop ? 64.0 : 72.0;
    final minTouch =
        desktop ? PineSize.minTouchDesktop : PineSize.minTouchAndroid;
    final stateColor = _stateColor(palette);
    final secondaryReadout =
        view.targetReached ? '超时 ${view.clockText}' : '剩余 ${view.clockText}';
    final auxText = '${_statusLabel()} · ${_auxiliaryLine()}';

    return Container(
      constraints: BoxConstraints(minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: PineSpacing.section),
      decoration: BoxDecoration(
        color: palette.presence,
        borderRadius: BorderRadius.circular(PineRadius.active),
        border:
            Border(left: BorderSide(color: stateColor, width: Paper.hairline)),
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Text('已进行 ${view.elapsedText}',
                        style: PineText.sans(
                            color: palette.textPresence,
                            height: PineLineHeight.body)),
                    Text(secondaryReadout,
                        style: PineText.mono(
                            size: PineType.auxiliary,
                            color: palette.textSecondary,
                            height: PineLineHeight.auxiliary)),
                  ])),
              const SizedBox(width: PineSpacing.near),
              Tooltip(
                  message: '回到当下',
                  child: _ImmediateAction(
                      onTap: onReturnToPresent,
                      child: Semantics(
                          button: true,
                          label: '回到当下',
                          child: SizedBox(
                              width: minTouch,
                              height: minTouch,
                              child: Icon(Icons.home_outlined,
                                  size: PineSize.stateGraphic,
                                  color: palette.textPrimary))))),
              const SizedBox(width: PineSpacing.near),
              _PresenceActionButton(
                  label: '完成', minTouch: minTouch, onTap: onComplete),
            ]),
            const SizedBox(height: PineSpacing.micro),
            AnimatedSwitcher(
                duration: _effectiveDuration(context, PineMotion.maximum),
                child: Row(key: ValueKey<String>(auxText), children: [
                  _SessionStateMarker(view: view),
                  const SizedBox(width: PineSpacing.near),
                  Expanded(
                      child: Text(auxText,
                          style: PineText.sans(
                              size: PineType.auxiliary,
                              color: palette.textAuxiliary,
                              height: PineLineHeight.auxiliary))),
                ])),
          ]),
    );
  }
}

class _PresenceActionButton extends StatelessWidget {
  const _PresenceActionButton(
      {required this.label, required this.minTouch, required this.onTap});
  final String label;
  final double minTouch;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          minimumSize: Size(minTouch, minTouch),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(
              horizontal: PineSpacing.section, vertical: PineSpacing.micro),
        ),
        child: Text(label),
      );
}

// ============================================================================
// 全局与导航 4：外部会话陪驻（Android 锁屏与通知 / macOS 菜单栏与置顶计时窗）
// ============================================================================

/// 外部会话陪驻：在 Android 锁屏与通知、macOS 菜单栏与置顶计时窗呈现同一会话并直接完成。
///
/// - 变体：[PineVariant.active]（进行中变体：陪驻底色 `palette.presence`、进行中圆角 `24`、常驻读数 `28/34`）
/// - 状态：运行 / 暂停 / 超时 / 跨日；**完成永不禁用**；镜像接收中作为加载说明
/// - 动效契约：开始镜像、暂停、继续、完成均 0ms（[PineMotion.immediate]）；出现与退出 ≤200ms（[PineMotion.maximum]）
/// - 文案契约：
///   - `外部.当前读数`：`〈阶段〉 · 〈已进行或超时〉`
///   - `外部.归属`：`本段归〈所属日期〉`（跨日时同时陈述 `今天已翻页，本段仍归〈所属日期〉`）
///   - `外部.完成`：`完成〈阶段〉`
class ExternalSessionPresenceCard extends StatelessWidget {
  const ExternalSessionPresenceCard({
    super.key,
    required this.view,
    required this.belongingDateText,
    required this.onComplete,
    this.onPauseOrResume,
    this.crossDay = false,
    this.receivingMirror = false,
  });

  static const PineVariant variant = PineVariant.active;
  static const PineMotionContract responseContract =
      PineMotionContract.immediate;
  static const PineMotionContract transitionContract =
      PineMotionContract.maximum;

  final SessionView view;
  final String belongingDateText;

  /// 直接完成回调（永不禁用，0ms 响应）。
  final VoidCallback onComplete;

  /// 可选暂停 / 继续回调（0ms 响应）。
  final VoidCallback? onPauseOrResume;
  final bool crossDay;
  final bool receivingMirror;

  Color _stateColor(PinePalette palette) {
    if (!view.running) return palette.paused;
    if (view.targetReached) return palette.overtime;
    return switch (view.mode) {
      SessionMode.focus => palette.focus,
      SessionMode.shortBreak => palette.shortBreak,
      SessionMode.longBreak => palette.longBreak,
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final desktop = _isDesktopPlatform();
    final actionHeight =
        desktop ? PineSize.primaryActionDesktop : PineSize.primaryActionAndroid;
    final stateColor = _stateColor(palette);
    final phase = pinePhaseCopy(view.mode);

    // 外部.当前读数：〈阶段〉 · 〈已进行或超时〉
    final primaryReadout =
        view.targetReached ? view.clockText : view.elapsedText;

    final secondaryStatus = view.targetReached
        ? '$phase · 超时中 · 已进行 ${view.elapsedText}${view.running ? '' : ' · 已暂停'}'
        : '$phase · 已进行 · 剩余 ${view.clockText}${view.running ? '' : ' · 已暂停'}';

    final belongingLine =
        crossDay ? '今天已翻页，本段仍归$belongingDateText' : '本段归$belongingDateText';

    return AnimatedContainer(
      duration: _effectiveDuration(context, PineMotion.maximum),
      curve: Curves.easeOut,
      constraints: BoxConstraints(minHeight: desktop ? 130 : 134),
      padding: const EdgeInsets.symmetric(horizontal: PineSpacing.section),
      decoration: BoxDecoration(
        color: palette.presence,
        borderRadius: BorderRadius.circular(PineRadius.active),
        border:
            Border(left: BorderSide(color: stateColor, width: Paper.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _SessionStateMarker(view: view),
              const SizedBox(width: PineSpacing.near),
              Expanded(
                child: Text(
                  primaryReadout,
                  style: PineText.presence(color: palette.textPresence),
                ),
              ),
            ],
          ),
          const SizedBox(height: PineSpacing.micro),
          Text(
            secondaryStatus,
            style: PineText.sans(
              size: PineType.auxiliary,
              color: palette.textSecondary,
              height: PineLineHeight.auxiliary,
            ),
          ),
          Text(
            receivingMirror ? '$belongingLine · 正在接收另一端的会话状态' : belongingLine,
            style: PineText.sans(
              size: PineType.auxiliary,
              color: palette.textAuxiliary,
              height: PineLineHeight.auxiliary,
            ),
          ),
          const SizedBox(height: PineSpacing.near),
          Row(
            children: [
              if (onPauseOrResume != null) ...[
                Expanded(
                  child: SizedBox(
                    height: actionHeight,
                    child: OutlinedButton(
                      onPressed: onPauseOrResume,
                      child: Text(view.running ? '暂停' : '继续'),
                    ),
                  ),
                ),
                const SizedBox(width: PineSpacing.near),
              ],
              Expanded(
                child: SizedBox(
                  height: actionHeight,
                  child: FilledButton(
                    // 完成永不禁用
                    onPressed: onComplete,
                    child: Text('完成$phase'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 全局与导航 5：完成归属回执
// ============================================================================

/// 完成归属回执：完成后明确本段计入哪个逻辑日（`本段已计入〈所属日期〉`）。
///
/// - 变体：[PineVariant.active]（进行中变体：陪驻底色 `palette.presence`、进行中圆角 `24`）
/// - 状态：已计入今日 / 已计入其他逻辑日（[crossDayTodayUnchanged] 为真时附带
///   `本段计入〈所属日期〉，今日合计不变`）；无禁用；无加载
/// - 动效契约：落记录 0ms 后立即出现（[PineMotion.immediate]），语境衔接 160ms（[PineMotion.standard]）
/// - 布局预算：手机 40dp / 桌面 36pt
class CompletionAttributionReceipt extends StatelessWidget {
  const CompletionAttributionReceipt({
    super.key,
    required this.belongingDateText,
    this.crossDayTodayUnchanged = false,
  });

  static const PineVariant variant = PineVariant.active;
  static const PineMotionContract responseContract =
      PineMotionContract.immediate;
  static const PineMotionContract transitionContract =
      PineMotionContract.standard;

  final String belongingDateText;

  /// 当本段归属前一逻辑日導致今日合计不变时，展示 `本段计入〈所属日期〉，今日合计不变`。
  final bool crossDayTodayUnchanged;

  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final desktop = _isDesktopPlatform();
    final minHeight = desktop ? 36.0 : 40.0;

    return AnimatedContainer(
      duration: _effectiveDuration(context, PineMotion.standard),
      curve: Curves.easeOut,
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: PineSpacing.section,
        vertical: PineSpacing.micro,
      ),
      decoration: BoxDecoration(
        color: palette.presence,
        borderRadius: BorderRadius.circular(PineRadius.active),
        border: Border(
            left: BorderSide(color: palette.divider, width: Paper.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '本段已计入$belongingDateText',
                  style: PineText.sans(
                    size: PineType.body,
                    color: palette.textPresence,
                    weight: FontWeight.w400,
                    height: PineLineHeight.body,
                  ),
                ),
                if (crossDayTodayUnchanged) ...[
                  const SizedBox(height: PineSpacing.micro),
                  Text(
                    '本段计入$belongingDateText，今日合计不变',
                    style: PineText.sans(
                      size: PineType.auxiliary,
                      color: palette.textAuxiliary,
                      height: PineLineHeight.auxiliary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 全局与导航 6：冲突裁决（V7 裁决）
// ============================================================================

/// 冲突裁决：宣告安全副本结果并由用户选择保留哪份数据。
///
/// - 变体：[PineVariant.adjudication]（裁决独立边界 `PineRadius.adjudication` = 4，承载底色 `palette.surface`）
/// - 状态：
///   - [AdjudicationStatus.creatingSafetyCopy]：正在创建本机安全副本（加载态，裁决暂禁用）
///   - [AdjudicationStatus.readyToAdjudicate]：本机安全副本已创建（先于裁决选项出现，用户可裁决）
///   - [AdjudicationStatus.safetyCopyFailed]：本机安全副本创建失败，请重试。（保留明确重试语义，裁决禁用）
/// - 动效契约：进入与裁决均 0ms（[PineMotion.immediate]）；不得等待动画
class ConflictAdjudicationPanel extends StatelessWidget {
  const ConflictAdjudicationPanel({
    super.key,
    required this.status,
    required this.onKeepLocal,
    required this.onKeepCloud,
    required this.onRetrySafetyCopy,
    this.localSummary,
    this.cloudSummary,
  });

  static const PineVariant variant = PineVariant.adjudication;
  static const PineMotionContract motionContract = PineMotionContract.immediate;

  final AdjudicationStatus status;
  final VoidCallback onKeepLocal;
  final VoidCallback onKeepCloud;
  final VoidCallback onRetrySafetyCopy;
  final String? localSummary;
  final String? cloudSummary;

  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final desktop = _isDesktopPlatform();
    final actionHeight =
        desktop ? PineSize.primaryActionDesktop : PineSize.primaryActionAndroid;
    final canAdjudicate = status == AdjudicationStatus.readyToAdjudicate;

    final safetyBannerText = switch (status) {
      AdjudicationStatus.creatingSafetyCopy => '正在创建本机安全副本',
      AdjudicationStatus.readyToAdjudicate => '本机安全副本已创建',
      AdjudicationStatus.safetyCopyFailed => '本机安全副本创建失败，请重试。',
    };

    return Container(
      padding: const EdgeInsets.all(PineSpacing.section),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(PineRadius.adjudication),
        border: Border.all(color: palette.adjudication, width: Paper.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: PineSize.stateGraphic, color: palette.adjudication),
              const SizedBox(width: PineSpacing.near),
              Expanded(
                child: Text(
                  '同步冲突',
                  style: PineText.aggregate(color: palette.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: PineSpacing.near),
          Text(
            '本机与云端数据都有改动。选择保留哪份数据后，才会继续同步。',
            style: PineText.sans(
              size: PineType.body,
              color: palette.textPrimary,
              height: PineLineHeight.body,
            ),
          ),
          const SizedBox(height: PineSpacing.section),
          // 安全副本事实框：必须先于裁决选项出现且不可折叠或隐藏。
          Container(
            padding: const EdgeInsets.all(PineSpacing.section),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(PineRadius.adjudication),
              border: Border.all(
                color: status == AdjudicationStatus.safetyCopyFailed
                    ? palette.adjudication
                    : palette.divider,
                width: Paper.hairline,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    safetyBannerText,
                    style: PineText.sans(
                      size: PineType.body,
                      color: palette.textPrimary,
                      weight: FontWeight.w600,
                      height: PineLineHeight.body,
                    ),
                  ),
                ),
                if (status == AdjudicationStatus.safetyCopyFailed) ...[
                  const SizedBox(width: PineSpacing.near),
                  OutlinedButton(
                    onPressed: onRetrySafetyCopy,
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(PineSize.minTouchAndroid, actionHeight),
                    ),
                    child: const Text('重试'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: PineSpacing.section),
          Row(
            children: [
              Expanded(
                child: _DataScopeBox(
                  title: '本机数据',
                  summary: localSummary,
                ),
              ),
              const SizedBox(width: PineSpacing.near),
              Expanded(
                child: _DataScopeBox(
                  title: '云端数据',
                  summary: cloudSummary,
                ),
              ),
            ],
          ),
          const SizedBox(height: PineSpacing.section),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: actionHeight,
                  child: OutlinedButton(
                    onPressed: canAdjudicate ? onKeepLocal : null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(PineSize.minTouchAndroid, actionHeight),
                    ),
                    child: const Text('保留本机数据'),
                  ),
                ),
              ),
              const SizedBox(width: PineSpacing.near),
              Expanded(
                child: SizedBox(
                  height: actionHeight,
                  child: OutlinedButton(
                    onPressed: canAdjudicate ? onKeepCloud : null,
                    child: const Text('保留云端数据'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DataScopeBox extends StatelessWidget {
  const _DataScopeBox({required this.title, this.summary});

  final String title;
  final String? summary;

  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    return Container(
      padding: const EdgeInsets.all(PineSpacing.near),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(PineRadius.adjudication),
        border: Border.all(color: palette.divider, width: Paper.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: PineText.sans(
              size: PineType.body,
              color: palette.textPrimary,
              weight: FontWeight.w600,
              height: PineLineHeight.body,
            ),
          ),
          if (summary != null) ...[
            const SizedBox(height: PineSpacing.micro),
            Text(
              summary!,
              style: PineText.sans(
                size: PineType.auxiliary,
                color: palette.textSecondary,
                height: PineLineHeight.auxiliary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 即时动作同时支持触控、Enter、Space 与辅助技术。
class _ImmediateAction extends StatelessWidget {
  const _ImmediateAction(
      {required this.onTap,
      required this.child,
      this.behavior = HitTestBehavior.opaque});
  final VoidCallback? onTap;
  final Widget child;
  final HitTestBehavior behavior;
  @override
  Widget build(BuildContext context) => PineFocusRing(
        child: FocusableActionDetector(
          enabled: onTap != null,
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
              onTap?.call();
              return null;
            })
          },
          child: Semantics(
              onTap: onTap,
              child: GestureDetector(
                  behavior: behavior, onTap: onTap, child: child)),
        ),
      );
}

/// 陪驻只使用同源小标识，完整开放弧留给当前会话读数。
class _SessionStateMarker extends StatelessWidget {
  const _SessionStateMarker({required this.view});
  final SessionView view;
  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final phase = switch (view.mode) {
      SessionMode.focus => palette.focus,
      SessionMode.shortBreak => palette.shortBreak,
      SessionMode.longBreak => palette.longBreak,
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.circle, size: PineSize.taskGraphic, color: phase),
      if (!view.running)
        Icon(Icons.pause, size: PineSize.stateGraphic, color: palette.paused),
      if (view.targetReached)
        Icon(Icons.add, size: PineSize.stateGraphic, color: palette.overtime),
    ]);
  }
}

/// 无业务状态的计时弧。完整 V1 接线留待该视图迁移；本批用真实组件预览验收工艺。
class SessionTimerArc extends StatelessWidget {
  const SessionTimerArc(
      {super.key, required this.view, this.size = PineTimerArc.compactBox});
  final SessionView view;
  final double size;
  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final phaseColor = switch (view.mode) {
      SessionMode.focus => palette.focus,
      SessionMode.shortBreak => palette.shortBreak,
      SessionMode.longBreak => palette.longBreak,
    };
    return SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _SessionArcPainter(
            progress: view.plannedSeconds > 0
                ? (view.elapsedSeconds / view.plannedSeconds).clamp(0.0, 1.0)
                : null,
            active: view.running ? phaseColor : palette.paused,
            track: palette.divider,
          ),
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              _SessionStateMarker(view: view),
              const SizedBox(width: PineSpacing.micro),
              Text(pinePhaseCopy(view.mode),
                  style: PineText.sans(
                      size: PineType.auxiliary, color: phaseColor)),
              if (!view.running)
                Text('已暂停',
                    style: PineText.sans(
                        size: PineType.auxiliary, color: palette.paused)),
            ]),
            Text('已进行',
                style: PineText.sans(
                    size: PineType.auxiliary, color: palette.textSecondary)),
            Text(view.elapsedText, style: PineText.session()),
            Text(
                view.plannedSeconds <= 0
                    ? '准备'
                    : view.targetReached
                        ? '超时 ${view.clockText}'
                        : '剩余 ${view.clockText}',
                style: PineText.mono(
                    size: PineType.body,
                    color: view.targetReached
                        ? palette.overtime
                        : palette.textSecondary)),
          ])),
        ));
  }
}

class _SessionArcPainter extends CustomPainter {
  const _SessionArcPainter(
      {required this.progress, required this.active, required this.track});
  final double? progress;
  final Color active, track;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius =
        (size.shortestSide - PineTimerArc.endDot - 2 * PineTimerArc.separator) /
            2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    // Flutter 以三点为零；契约以十二点为零。
    const start = (PineTimerArc.startDegrees - 90) * math.pi / 180;
    const sweep = PineTimerArc.sweepDegrees * math.pi / 180;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = PineTimerArc.stroke;
    canvas.drawArc(rect, start, sweep, false, paint..color = track);
    if (progress == null) return;
    if (progress! > 0) {
      canvas.drawArc(
          rect, start, sweep * progress!, false, paint..color = active);
    }
    final end = start + sweep * progress!;
    final dot = center + Offset(math.cos(end), math.sin(end)) * radius;
    canvas.drawCircle(dot, PineTimerArc.endDot / 2 + PineTimerArc.separator,
        Paint()..color = Colors.white);
    canvas.drawCircle(dot, PineTimerArc.endDot / 2, Paint()..color = active);
  }

  @override
  bool shouldRepaint(_SessionArcPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      active != oldDelegate.active ||
      track != oldDelegate.track;
}
