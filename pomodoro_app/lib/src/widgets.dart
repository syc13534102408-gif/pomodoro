import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'engine.dart';
import 'models.dart';
import 'theme.dart';

/// 环形计时器。超时后进度环转为金色并继续显示累计时长。
class RingTimer extends StatelessWidget {
  const RingTimer({
    super.key,
    required this.view,
    required this.caption,
  });

  final SessionView view;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final accent = view.targetReached ? PineColors.gold : view.mode.color;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              progress: view.progress,
              accent: accent,
              overtime: view.targetReached,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    view.clockText,
                    style: TextStyle(
                      color: PineColors.ink,
                      fontSize: size * 0.20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  SizedBox(height: size * 0.035),
                  Text(
                    caption,
                    style: TextStyle(
                      color: PineColors.muted,
                      fontSize: size * 0.062,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.accent,
    required this.overtime,
  });

  final double progress;
  final Color accent;
  final bool overtime;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    const start = -math.pi / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = PineColors.ink.withValues(alpha: 0.10),
    );

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = accent;

    if (overtime) {
      // 超时后用虚线弧表示「已超出计划时长」。
      const dash = 0.10;
      const gap = 0.07;
      for (var angle = 0.0; angle < math.pi * 2; angle += dash + gap) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          start + angle,
          dash,
          false,
          arcPaint,
        );
      }
      return;
    }

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.accent != accent ||
      old.overtime != overtime;
}

/// 专注 / 短休息 / 长休息 切换。
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
        for (final mode in SessionMode.values) ...[
          Expanded(
            child: _ModeChip(
              label: mode.label,
              minutes: minutesFor(mode),
              selected: mode == current,
              accent: mode.color,
              onTap: () => onChanged(mode),
            ),
          ),
          if (mode != SessionMode.longBreak) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.minutes,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final int minutes;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.16) : PineColors.dark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.75) : PineColors.line,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? PineColors.ink : PineColors.muted,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$minutes 分',
              style: TextStyle(
                color: selected ? accent : PineColors.muted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分区标题。
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: PineColors.muted,
              fontSize: 12,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      );
}

/// 数值指标块。
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
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: accent ?? PineColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: PineColors.muted, fontSize: 11)),
        ],
      );
}

/// 通用分组卡片。
class PanelCard extends StatelessWidget {
  const PanelCard({super.key, required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: PineColors.dark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PineColors.line),
        ),
        child: child,
      );
}

/// 分钟数格式化：整数显示整数，否则保留一位。
String formatMinutes(double minutes) {
  if (minutes >= 60) {
    final hours = minutes ~/ 60;
    final rest = minutes - hours * 60;
    final restText = rest == 0 ? '' : ' ${formatMinutes(rest)}分';
    return '$hours 小时$restText';
  }
  final rounded = (minutes * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) {
    return '${rounded.toStringAsFixed(0)} 分钟';
  }
  return '${rounded.toStringAsFixed(1)} 分钟';
}
