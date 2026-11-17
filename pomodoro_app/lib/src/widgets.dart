import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'common_components.dart';
import 'models.dart';
import 'theme.dart';

export 'common_components.dart';

bool get _desktop => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
double get _touch =>
    _desktop ? PineSize.minTouchDesktop : PineSize.minTouchAndroid;

/// 等宽数字只服务读数；调用者逐视图迁移时改用对应五档文字样式。
TextStyle pineNumberStyle({
  double fontSize = PineType.auxiliary,
  Color color = PineColors.textPrimary,
  FontWeight weight = FontWeight.w600,
}) =>
    PineText.mono(size: fontSize, color: color, weight: weight);

/// 已定型事实容器；会话语境必须另用 ActiveVariantSurface。
class SettledCard extends StatelessWidget {
  const SettledCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(PineSpacing.section),
      this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final surface = SizedBox(
        width: double.infinity,
        child: SettledVariantSurface(padding: padding, child: child));
    return onTap == null
        ? surface
        : PinePressable(onTap: onTap, child: surface);
  }
}

/// 鼠标、触控、键盘使用同一即时回调；没有延迟动作或缩放内容。
class PinePressable extends StatelessWidget {
  const PinePressable(
      {super.key,
      required this.onTap,
      required this.child,
      this.semanticLabel,
      this.onLongPress});
  final VoidCallback? onTap;
  final Widget child;
  final String? semanticLabel;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Semantics(
      button: true,
      enabled: onTap != null || onLongPress != null,
      label: semanticLabel,
      child: PineFocusRing(
          child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                  onTap: onTap,
                  onLongPress: onLongPress,
                  borderRadius: BorderRadius.circular(PineRadius.settled),
                  splashFactory: NoSplash.splashFactory,
                  overlayColor:
                      const WidgetStatePropertyAll(Colors.transparent),
                  focusColor: PinePalette.of(context).presence,
                  child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minWidth: _touch, minHeight: _touch),
                      child: child)))));
}

/// 通用编辑动作，使用沉淀边界；会话动作由进行中组件单独承载。
class PineButton extends StatelessWidget {
  const PineButton(
      {super.key,
      required this.label,
      this.onPressed,
      this.icon,
      this.trailing,
      this.color,
      this.foregroundColor,
      this.height,
      this.expand = true,
      this.padding =
          const EdgeInsets.symmetric(horizontal: PineSpacing.section),
      this.semanticLabel,
      this.loading = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? trailing;
  final Color? color;
  final Color? foregroundColor;
  final double? height;
  final bool expand;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final primaryHeight = _desktop
        ? PineSize.primaryActionDesktop
        : PineSize.primaryActionAndroid;
    final requested = height ?? primaryHeight;
    final effectiveHeight = requested < _touch ? _touch : requested;
    return Semantics(
        label: semanticLabel,
        child: LayoutBuilder(builder: (context, constraints) {
          final fill = expand && constraints.hasBoundedWidth;
          return SizedBox(
              height: effectiveHeight,
              width: fill ? double.infinity : null,
              child: FilledButton(
                  onPressed: loading ? null : onPressed,
                  style: pinePrimaryButtonStyle(
                          background: color,
                          foreground: foregroundColor,
                          loading: loading)
                      .merge(FilledButton.styleFrom(
                          backgroundColor: color ?? palette.action,
                          foregroundColor: foregroundColor ?? Colors.white,
                          padding: label.isEmpty ? EdgeInsets.zero : padding,
                          minimumSize: Size(_touch, effectiveHeight),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(PineRadius.settled)),
                          textStyle: Theme.of(context)
                              .textTheme
                              .labelLarge!
                              .merge(PineText.sans(
                                  size: PineType.body,
                                  weight: FontWeight.w600)))),
                  child: Row(
                      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (loading)
                          SizedBox(
                              width: PineSize.stateGraphic,
                              height: PineSize.stateGraphic,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: foregroundColor ?? Colors.white))
                        else if (icon != null)
                          Icon(icon, size: PineSize.stateGraphic),
                        if ((loading || icon != null) && label.isNotEmpty)
                          const SizedBox(width: PineSpacing.near),
                        if (label.isNotEmpty) Flexible(child: Text(label)),
                        if (trailing != null) ...[
                          const SizedBox(width: PineSpacing.micro),
                          trailing!
                        ],
                      ])));
        }));
  }
}

/// 聚合进度即时更新，不伪装成当前会话。
class AggregateProgress extends StatelessWidget {
  const AggregateProgress(
      {super.key,
      required this.value,
      this.color,
      this.trackColor,
      this.height = PineSpacing.micro});
  final double value;
  final Color? color;
  final Color? trackColor;
  final double height;
  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    return LinearProgressIndicator(
        value: value.isNaN ? 0 : value.clamp(0.0, 1.0),
        color: color ?? palette.action,
        backgroundColor: trackColor ?? palette.divider,
        minHeight: height);
  }
}

/// 资料开关：支持禁用，命中区遵循平台下限，键盘与读屏可操作。
class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch(
      {super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: _desktop ? 48 : 56,
      height: _touch,
      child: PineFocusRing(child: Switch(value: value, onChanged: onChanged)));
}

class FactSectionHeader extends StatelessWidget {
  const FactSectionHeader({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: Text(title,
                style: PineText.serif(
                    color: PinePalette.of(context).textPrimary,
                    weight: FontWeight.w600,
                    height: PineLineHeight.body))),
        if (trailing != null) trailing!,
      ]);
}

/// 聚合主读数 24/30，辅助标签 13/18；单位不再缩成任意字号。
class AggregateReadout extends StatelessWidget {
  const AggregateReadout(
      {super.key, required this.value, required this.label, this.accent});
  final String value;
  final String label;
  final Color? accent;
  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final split = value.indexOf(' ');
    final number = split < 0 ? value : value.substring(0, split);
    final unit = split < 0 ? '' : value.substring(split + 1);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: PineText.sans(
                  size: PineType.auxiliary,
                  color: palette.textSecondary,
                  height: PineLineHeight.auxiliary)),
          const SizedBox(height: PineSpacing.near),
          Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: number,
                    style: PineText.aggregate(
                        color: accent ?? palette.textPrimary)),
                if (unit.isNotEmpty)
                  TextSpan(
                      text: ' $unit',
                      style: PineText.sans(
                          size: PineType.auxiliary,
                          color: palette.textSecondary,
                          height: PineLineHeight.auxiliary)),
              ]),
              semanticsLabel: value),
        ]);
  }
}

/// 只呈现传入顺序：稳定 id 保持行身份，勾选与排序仍由现有逻辑负责。
class SettledTodoRows extends StatelessWidget {
  const SettledTodoRows(
      {super.key,
      required this.items,
      required this.itemBuilder,
      this.rowHeight,
      this.duration = PineMotion.maximum});
  final List<TodoItem> items;
  final double? rowHeight;
  final Widget Function(TodoItem item) itemBuilder;
  final Duration duration;
  @override
  Widget build(BuildContext context) {
    final minimum =
        _desktop ? PineSize.standardItemDesktop : PineSize.standardItemAndroid;
    final extent =
        rowHeight == null || rowHeight! < minimum ? minimum : rowHeight!;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final transition = reduceMotion
        ? Duration.zero
        : (duration > PineMotion.maximum ? PineMotion.maximum : duration);
    return SizedBox(
        height: extent * items.length,
        child: Stack(children: [
          for (var i = 0; i < items.length; i++)
            AnimatedPositioned(
                key: ValueKey(items[i].id),
                duration: transition,
                curve: Curves.easeOutCubic,
                top: extent * i,
                left: 0,
                right: 0,
                height: extent,
                child: itemBuilder(items[i])),
        ]));
  }
}

/// 时长统一自然语言；番茄整数计数由调用处独立呈现。
String formatMinutes(double minutes) => formatHoursMinutes(minutes);

/// 「X 小时 Y 分钟」人话时长（最近完成列表用）：
/// `3 小时 5 分钟` / `3 小时` / `45 分钟`；不足 1 分钟为 `<1 分钟`。
///
/// 2026-10-12 起不再显示 `mm:ss`（原来靠秒级精度区分 46.4 与 46.9 分钟，
/// 但对「看记录」这个场景不直观），四舍五入到分钟。
/// 时长与整数番茄计数分别呈现，不在此做番茄换算。
String formatHoursMinutes(double minutes) {
  final total = minutes.round();
  if (total <= 0) return '<1 分钟';
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '$m 分钟';
  if (m == 0) return '$h 小时';
  return '$h 小时 $m 分钟';
}

/// 紧凑时长：`185h16m` / `6h40m` / `42m`。
///
/// 侧栏、列表这类窄容器里用它 —— `185 小时 16 分钟` 那种全称会把一行撑爆，
/// 单位重复两次也不好扫读。
String formatCompactMinutes(double minutes) {
  final total = minutes.round();
  if (total <= 0) return '0m';
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h${m.toString().padLeft(2, '0')}m';
}

/// 单条记录与汇总共享自然语言时长，不隐含番茄换算。
class DurationText extends StatelessWidget {
  const DurationText(this.minutes, {super.key, this.style});
  final double minutes;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Text(formatHoursMinutes(minutes),
      style: PineText.sans(
              color: PinePalette.of(context).textPrimary,
              height: PineLineHeight.body)
          .merge(style));
}

/// V1 只读自然日差：配置入口属于 V6，不引入冲刺或考试阶段语义。
class TargetDayReadout extends StatelessWidget {
  const TargetDayReadout(
      {super.key,
      required this.countdown,
      required this.now,
      this.compact = false});
  final Countdown countdown;
  final DateTime now;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final target = countdown.target;
    final days = countdown.daysFrom(now);
    final text = !countdown.enabled || target == null
        ? '未设置目标日'
        : days <= 0
            ? '${countdown.label}已到期'
            : '距${countdown.label}还有$days天';
    return Text(text,
        style: PineText.sans(
            size: compact ? PineType.auxiliary : PineType.body,
            color: palette.textSecondary,
            height: compact ? PineLineHeight.auxiliary : PineLineHeight.body));
  }
}

/// 保留原生 Checkbox 的键盘、命中区和语义，绘制即时 20×20 视觉。
/// 不播放原生勾选的收缩动画，也不把整行染色。
class PineCheckbox extends StatelessWidget {
  const PineCheckbox({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool?>? onChanged;
  @override
  Widget build(BuildContext context) => PineFocusRing(
        radius: PineRadius.adjudication,
        child: CustomPaint(
          foregroundPainter:
              _PineCheckboxPainter(value: value, enabled: onChanged != null),
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            fillColor: const WidgetStatePropertyAll(Colors.transparent),
            checkColor: Colors.transparent,
            side: BorderSide.none,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            splashRadius: 0,
          ),
        ),
      );
}

class _PineCheckboxPainter extends CustomPainter {
  const _PineCheckboxPainter({required this.value, required this.enabled});
  final bool value, enabled;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
        center: size.center(Offset.zero), width: 20, height: 20);
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(
        shape,
        Paint()
          ..color = !enabled
              ? PineColors.presence
              : value
                  ? PineColors.accent
                  : Colors.white);
    if (!value || !enabled) {
      canvas.drawRRect(
          shape.deflate(.75),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = PineColors.line);
    }
    if (value) {
      final path = Path()
        ..moveTo(rect.left + 5, rect.top + 10)
        ..lineTo(rect.left + 8.5, rect.top + 13.5)
        ..lineTo(rect.left + 15, rect.top + 6.5);
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = enabled ? Colors.white : PineColors.textAuxiliary);
    }
  }

  @override
  bool shouldRepaint(_PineCheckboxPainter oldDelegate) =>
      value != oldDelegate.value || enabled != oldDelegate.enabled;
}
