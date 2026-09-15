import 'package:flutter/material.dart';

import 'engine.dart';
import 'models.dart';
import 'theme.dart';

/// 数据类文本统一用的等宽样式（mono + w600 + tabular 防抖）。
TextStyle brickNumberStyle({
  double fontSize = 14,
  Color color = PineColors.ink,
  FontWeight weight = FontWeight.w600,
}) =>
    TextStyle(
      fontFamily: 'monospace',
      color: color,
      fontSize: fontSize,
      fontWeight: weight,
      letterSpacing: 0,
      fontFeatures: kNumericFont,
    );

/// 纸面卡片：白纸底 + 20 圆角 + 柔和投影。传入 [onTap] 时整块可压（轻微缩放）。
class BrickCard extends StatelessWidget {
  const BrickCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
    this.onTap,
    this.radius = Paper.cardRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;

  /// 传入后整块可点，按下轻微缩放。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? PineColors.card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: Paper.shadow,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return BrickPressable(
      onTap: onTap,
      shadowed: false,
      child: card,
    );
  }
}

/// 纸面按压内核：按下时整体轻微缩小（scale .97）+ 自带投影随子件收敛，
/// 松手回弹。键盘焦点 = 2px 松绿描边。
class BrickPressable extends StatefulWidget {
  const BrickPressable({
    super.key,
    required this.onTap,
    required this.child,
    this.semanticLabel,
    this.onLongPress,
    this.shadowed = true,
    this.pressDuration = const Duration(milliseconds: 160),
  });

  final VoidCallback? onTap;
  final Widget child;
  final String? semanticLabel;
  final VoidCallback? onLongPress;

  /// 为自身无装饰的子件补柔和投影（带装饰的卡片请传 false）。
  final bool shadowed;
  final Duration pressDuration;

  @override
  State<BrickPressable> createState() => _BrickPressableState();
}

class _BrickPressableState extends State<BrickPressable> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  bool get _enabled => widget.onTap != null;

  void _set(bool value) {
    if (!_enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  void _setHover(bool value) {
    if (!_enabled || _hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : widget.pressDuration;
    final pressed = _pressed && !reduceMotion;
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        onShowHoverHighlight: _setHover,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        child: MouseRegion(
          onEnter: (_) => _setHover(true),
          onExit: (_) => _setHover(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _set(true),
            onTapUp: (_) => _set(false),
            onTapCancel: () => _set(false),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: AnimatedScale(
              scale: pressed ? 0.97 : 1.0,
              duration: duration,
              curve: Curves.easeOutCubic,
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: widget.shadowed ? Paper.shadow : null,
                  borderRadius: BorderRadius.circular(Paper.cardRadius),
                  border: _focused
                      ? Border.all(color: PineColors.pine, width: 2)
                      : null,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 纸面按钮：胶囊形。变体由 [color]/[foregroundColor] 决定；
/// 主行动请传 ink 底 card 字（R2），「完成」类传 gold 底 ink 字。
class BrickButton extends StatelessWidget {
  const BrickButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailing,
    this.color = PineColors.ink,
    this.foregroundColor = PineColors.card,
    this.height = 46,
    this.expand = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
    this.semanticLabel,
    this.loading = false,
    this.pressDuration = const Duration(milliseconds: 160),
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// 图标按钮没有可见文字时用它补语义标签。
  final String? semanticLabel;
  final bool loading;
  final Duration pressDuration;

  /// 文字右侧的补充内容（如阶段分钟数）。
  final Widget? trailing;

  final Color color;
  final Color foregroundColor;
  final double height;

  /// 只放图标时置 false，宽度收缩到与高度一致。
  final bool expand;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return BrickPressable(
      onTap: enabled ? onPressed : null,
      semanticLabel: semanticLabel ?? (label.isEmpty ? null : label),
      pressDuration: pressDuration,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 父级宽度无界（例如放在带 Spacer 的 Row 尾部）时不能撑满，
          // 退化为按内容收缩，避免拿到 Infinity 约束。
          final fill = expand && constraints.hasBoundedWidth;
          // 纯图标按钮做成圆形；其余按内容收缩，只有 fill 时撑满。
          final iconOnly = label.isEmpty && icon != null;
          final inset = label.isEmpty ? EdgeInsets.zero : padding;
          return Container(
            height: height,
            width: fill ? double.infinity : (iconOnly ? height : null),
            padding: inset,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled ? color : PineColors.faint,
              shape: iconOnly ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: iconOnly ? null : BorderRadius.circular(height / 2),
            ),
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: PineColors.card,
                    ),
                  )
                : _content(fill: fill, enabled: enabled),
          );
        },
      ),
    );
  }

  Widget _content({required bool fill, required bool enabled}) {
    final textStyle = TextStyle(
      color: enabled ? foregroundColor : PineColors.sub,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );

    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textStyle,
    );

    return Row(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null)
          Icon(icon,
              size: 18, color: enabled ? foregroundColor : PineColors.sub),
        if (label.isNotEmpty) ...[
          if (icon != null) const SizedBox(width: 8),
          if (fill) Flexible(child: text) else text,
        ],
        if (trailing != null) ...[
          const SizedBox(width: 6),
          trailing!,
        ],
      ],
    );
  }
}

/// 细进度条：轨道浅米色、填充为语义色（专注/完成金/松绿），圆角 6。
class BrickProgress extends StatelessWidget {
  const BrickProgress({
    super.key,
    required this.value,
    this.color = PineColors.pine,
    this.trackColor = PineColors.line,
    this.height = 6,
  });

  /// 0 ~ 1，超出自动截断。
  final double value;
  final Color color;
  final Color trackColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ratio = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(3),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            if (ratio > 0)
              Container(
                width: constraints.maxWidth * ratio,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 纸面开关：轨道圆角胶囊，开=松绿底白钮 / 关=浅米底白钮。
class BrickSwitch extends StatelessWidget {
  const BrickSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        // 控件本身 24px 高，外扩到 44px 保证触摸目标。
        child: SizedBox(
          width: 52,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 42,
              height: 24,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value ? PineColors.pine : PineColors.line,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Align(
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 计时主卡（松林手帐版）：白纸卡 + 顶部短阶段色条 + 状态 caption +
/// 大号等宽时钟 + 细进度；超时态色条与时钟转金。
class BrickTimer extends StatelessWidget {
  const BrickTimer({
    super.key,
    required this.view,
    required this.caption,
  });

  final SessionView view;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final overtime = view.targetReached;
    final phase = overtime ? PineColors.gold : view.mode.color;
    final clockColor = overtime ? PineColors.gold : PineColors.ink;
    return Semantics(
      label: '$caption，${view.clockText}',
      child: BrickCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final clockSize = (constraints.maxWidth * 0.28).clamp(40.0, 88.0);
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 顶部短色条：阶段色语义的小面积表达。
                Container(
                  width: 56,
                  height: 6,
                  decoration: BoxDecoration(
                    color: phase,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: phase,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PineColors.sub,
                          fontSize: 12,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Expanded 让 FittedBox 拿到有界高度，矮卡片下数字自动缩小。
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      view.clockText,
                      style: brickNumberStyle(
                        fontSize: clockSize,
                        color: clockColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                BrickProgress(
                  value: view.progress,
                  color: phase,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 阶段切换：三段胶囊。选中 = 阶段色浅底 + 实心色点 + 深色字；
/// 未选中 = 浅字 + 无色点。
class ModeSwitcher extends StatelessWidget {
  const ModeSwitcher({
    super.key,
    required this.current,
    required this.minutesFor,
    required this.onChanged,
  });

  final SessionMode current;
  final int Function(SessionMode mode) minutesFor;
  final ValueChanged<SessionMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < SessionMode.values.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _ModeBrick(
              mode: SessionMode.values[i],
              minutes: minutesFor(SessionMode.values[i]),
              selected: SessionMode.values[i] == current,
              onTap: () => onChanged(SessionMode.values[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _ModeBrick extends StatelessWidget {
  const _ModeBrick({
    required this.mode,
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  final SessionMode mode;
  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = PineColors.tint(mode.color);
    return Semantics(
      button: true,
      selected: selected,
      label: mode.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? tint : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: selected ? mode.color : PineColors.line,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                mode.label,
                style: TextStyle(
                  color: selected ? PineColors.ink : PineColors.sub,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$minutes',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: selected ? PineColors.ink : PineColors.sub,
                  fontFeatures: kNumericFont,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分区标题：松绿竖条 + 标题字，可选右侧补充内容。
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: PineColors.pine,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: PineColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      );
}

/// 数值指标块（纸面紧凑版）：主数字大号等宽，单位小字同行基线对齐，
/// 数值行永不换行（数字与「分钟/小时/天」之间不再被折行拆散），
/// 超宽时整行等比缩排；标签单行截断。适用于 3–4 等分窄列。
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.value,
    required this.label,
    this.accent,
  });

  final String value;
  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final parts = _splitValue(value);
    final numberStyle = brickNumberStyle(
      fontSize: 17,
      color: accent ?? PineColors.ink,
      weight: FontWeight.w700,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          // 数值行固定高度：并排多块时行高恒等、标签不错位。
          height: 24,
          // scaleDown：内容放得下就不缩放；放不下整行等比缩小，绝不换行/溢出。
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(parts.number, maxLines: 1, style: numberStyle),
                if (parts.unit.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  Text(
                    parts.unit,
                    maxLines: 1,
                    style: const TextStyle(
                      color: PineColors.sub,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: PineColors.sub, fontSize: 12),
        ),
      ],
    );
  }

  /// 把「数值 单位」串拆成主数字与单位两段（`25 分钟` → `25` / `分钟`；
  /// `1 小时 45分` → `1` / `小时 45分`）。整串不带空格时全部作主数字处理。
  static ({String number, String unit}) _splitValue(String value) {
    final space = value.indexOf(' ');
    if (space <= 0) return (number: value, unit: '');
    return (
      number: value.substring(0, space),
      unit: value.substring(space).trim(),
    );
  }
}

/// 柱状图的一段：某任务在某天的分钟数。
class BrickBarSegment {
  const BrickBarSegment({required this.value, required this.color});

  final double value;
  final Color color;
}

/// 周直方图（纸面版）：圆角堆叠柱、无描边，今日列松绿高亮，空日浅色占位。
class BrickBars extends StatelessWidget {
  const BrickBars({
    super.key,
    required this.stacks,
    required this.maxY,
    required this.todayIndex,
    this.height = 150,
  });

  /// 每天的分段，长度固定 7（周一至周日）。
  final List<List<BrickBarSegment>> stacks;
  final double maxY;
  final int todayIndex;
  final double height;

  static const List<String> labels = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: _BrickBarsPainter(stacks: stacks, maxY: maxY),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: _DayLabel(
                      text: labels[i],
                      highlight: i == todayIndex,
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

class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.text, required this.highlight});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    if (!highlight) {
      return Text(
        text,
        style: const TextStyle(color: PineColors.sub, fontSize: 11),
      );
    }
    // 今日：松绿字 + 上方「今」角标（顶部留白由下方 painter 对齐线承担）。
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: PineColors.pine,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            '今',
            style: TextStyle(color: Colors.white, fontSize: 9, height: 1.4),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          text,
          style: const TextStyle(
            color: PineColors.pine,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _BrickBarsPainter extends CustomPainter {
  _BrickBarsPainter({required this.stacks, required this.maxY});

  final List<List<BrickBarSegment>> stacks;
  final double maxY;

  static const int _slots = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = size.height;
    final plotHeight = size.height;
    if (plotHeight <= 0 || size.width <= 0 || maxY <= 0) return;

    final slot = size.width / _slots;
    final barWidth = slot * 0.52;

    // 基线 + 半高网格线（浅色细线）。
    final gridPaint = Paint()
      ..strokeWidth = 1
      ..color = PineColors.line;
    canvas.drawLine(
        Offset(0, baseline), Offset(size.width, baseline), gridPaint);
    final halfPaint = Paint()
      ..strokeWidth = 1
      ..color = PineColors.line.withValues(alpha: 0.6);
    canvas.drawLine(Offset(0, baseline - plotHeight / 2),
        Offset(size.width, baseline - plotHeight / 2), halfPaint);

    final fill = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < _slots; i++) {
      final left = slot * i + (slot - barWidth) / 2;
      final segments = i < stacks.length ? stacks[i] : null;
      if (segments == null || segments.isEmpty) {
        // 空档位：圆角浅色占位块。
        final stub = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, baseline - 8, barWidth, 8),
          const Radius.circular(4),
        );
        canvas.drawRRect(stub, fill..color = PineColors.line);
        continue;
      }
      // 自底向上计算各段矩形。
      var cursor = baseline;
      var topRect = Rect.zero;
      var topColor = PineColors.line;
      for (final segment in segments) {
        final barHeight = (segment.value / maxY) * plotHeight;
        if (barHeight <= 0) continue;
        final rect =
            Rect.fromLTWH(left, cursor - barHeight, barWidth, barHeight);
        canvas.drawRect(rect, fill..color = segment.color);
        topRect = rect;
        topColor = segment.color;
        cursor -= barHeight;
      }
      // 最顶段补圆角（只圆上方两角）。
      if (topRect != Rect.zero) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            topRect,
            topLeft: const Radius.circular(6),
            topRight: const Radius.circular(6),
          ),
          fill..color = topColor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BrickBarsPainter old) =>
      old.stacks != stacks || old.maxY != maxY;
}

/// 分钟数格式化：统一保留到整数分钟。
String formatMinutes(double minutes) {
  final total = minutes.round();
  if (total >= 60) {
    final hours = total ~/ 60;
    final rest = total - hours * 60;
    final restText = rest == 0 ? '' : ' $rest分';
    return '$hours 小时$restText';
  }
  return '$total 分钟';
}

/// 考试倒计时。
///
/// - `compact = false`（默认）：独立小卡，两行——上行「色条 + 名称」、
///   下行考试日期，右侧大号天数。用于移动端专注页顶部。
/// - `compact = true`：单行——「色条 + 名称 + 日期」左对齐，天数右对齐。
///   用于桌面专注舱底部信息卡内嵌（不新增卡片，维持「极简无卡」）。
///
/// 紧迫语义由天数派生，是模块唯一的状态语言：
/// 剩余 > 7 天 = 松绿；1–7 天（冲刺）= 专注红；0 天 = 「今天开考」；
/// 已过 = 淡色「考试已结束」。不额外引入新色，全部取自方案 E 令牌。
class CountdownCard extends StatelessWidget {
  const CountdownCard({
    super.key,
    required this.countdown,
    required this.now,
    this.compact = false,
    this.onTap,
  });

  final Countdown countdown;

  /// 计算天数用的当前时刻（由页面每秒重建时传入，组件内不取系统时钟，
  /// 保证同帧内多处显示一致、也便于测试）。
  final DateTime now;
  final bool compact;

  /// 点击进入倒计时设置。
  final VoidCallback? onTap;

  /// ≤7 天进入冲刺期。
  static const int _sprintDays = 7;

  @override
  Widget build(BuildContext context) {
    final target = countdown.target;
    if (target == null) return const SizedBox.shrink();

    final days = countdown.daysFrom(now);
    final sprint = days > 0 && days <= _sprintDays;
    final accent = days < 0
        ? PineColors.faint
        : sprint || days == 0
            ? PineColors.focus
            : PineColors.pine;

    final bar = Container(
      width: 3,
      height: compact ? 12 : 14,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(2),
      ),
    );

    if (compact) {
      final row = Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            bar,
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: countdown.label,
                      style: const TextStyle(
                        color: PineColors.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: '  ${chineseDate(target, withYear: false)}',
                      style: const TextStyle(
                        color: PineColors.sub,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            _tail(days, compact: true),
          ],
        ),
      );
      if (onTap == null) return row;
      return BrickPressable(onTap: onTap, shadowed: false, child: row);
    }

    return BrickCard(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    bar,
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        countdown.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PineColors.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                // 缩进 11 = 色条 3 + 间距 8，与上一行文字左缘对齐。
                Padding(
                  padding: const EdgeInsets.only(left: 11),
                  child: Text(
                    chineseDate(target),
                    style: const TextStyle(
                      color: PineColors.sub,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _tail(days, compact: false),
        ],
      ),
    );
  }

  /// 右侧天数区。分档文案见类注释。
  Widget _tail(int days, {required bool compact}) {
    if (days < 0) {
      return const Text(
        '考试已结束',
        style: TextStyle(
          color: PineColors.faint,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (days == 0) {
      return const Text(
        '今天开考',
        style: TextStyle(
          color: PineColors.focus,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    final sprint = days <= _sprintDays;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$days',
          style: brickNumberStyle(
            fontSize: compact ? 18 : 24,
            color: sprint ? PineColors.focus : PineColors.ink,
          ),
        ),
        const SizedBox(width: 3),
        const Text(
          '天',
          style: TextStyle(
            color: PineColors.sub,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
