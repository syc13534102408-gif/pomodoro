// V3「素纸书房」基础组件库（P1）。
//
// 设计权威：outputs/redesign-v3-2026-11-12/01-claude-studio.html
// 硬约束：本文件与调用方都不出现十六进制色值，全部走 `theme.dart`；
//        字号只取 `PineType` 六档；只做表现层，不持有任何业务状态。
import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// 素纸卡片：1px 裁切线 + 顶部 36×2.5 檀褐定界 + 轻纸边影。
/// [composer] 为真时换成 Composer 那一级更强的阴影与定界线。
class SuzhiCard extends StatelessWidget {
  const SuzhiCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.showRule = true,
    this.composer = false,
    this.background,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool showRule;
  final bool composer;
  final Color? background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: PineDecoration.sheet(
        color: background ?? PineColors.sheet,
        composer: composer,
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showRule) ...[
            // 外层 Column 是 stretch：直接放 Container(width:36) 会被强制拉成
            // 整卡宽的长线，必须用 Align 让短横保留 36px（2026-11-13 预览发现）。
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 36,
                height: 2.5,
                decoration: BoxDecoration(
                  color: PineColors.accent,
                  borderRadius: BorderRadius.circular(PineRadius.seal),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: onTap, child: card);
  }
}

/// 檀褐方印：1.5px 描边、圆角 3、宋体字、淡敷底。
class SectionSeal extends StatelessWidget {
  const SectionSeal({super.key, required this.text, this.color, this.onTap});

  final String text;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? PineColors.accent;
    final seal = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.withAlpha(30), PineColors.sheet),
        border: Border.all(color: c, width: 1.5),
        borderRadius: BorderRadius.circular(PineRadius.seal + 1),
      ),
      child: Text(
        text,
        style: PineText.serif(
          size: PineType.meta,
          color: c,
          weight: FontWeight.w500,
          letterSpacing: 0.08,
        ),
      ),
    );
    if (onTap == null) return seal;
    return GestureDetector(onTap: onTap, child: seal);
  }
}

/// 书眉式状态栏 48px：☰ · 日期 | 距考研 N 日 ····· ● 已同步
class FolioBar extends StatelessWidget {
  const FolioBar({
    super.key,
    required this.dateText,
    this.examText,
    this.syncText,
    this.onMenu,
    this.onExamTap,
  });

  final String dateText;
  final String? examText;
  final String? syncText;
  final VoidCallback? onMenu;

  /// 点书眉上的倒计时可进编辑面板（首页不再单独放一张倒计时卡）。
  final VoidCallback? onExamTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: PineColors.paper,
        border: Border(bottom: BorderSide(color: PineColors.line, width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onMenu,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: PineColors.sheet,
                border: Border.all(color: PineColors.lineStrong, width: 1),
                borderRadius: BorderRadius.circular(PineRadius.control - 2),
              ),
              child: const Icon(Icons.menu_rounded,
                  size: 15, color: PineColors.ink2),
            ),
          ),
          const SizedBox(width: 10),
          // 390 宽下「日期 + 倒计时 + 同步点」会挤到溢出 15px：两端文案都允许
          // 压缩省略，分隔线与同步点保持不缩。
          Flexible(
            child: Text(
              dateText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PineText.serif(size: PineType.body),
            ),
          ),
          if (examText != null) ...[
            const SizedBox(width: 10),
            Container(width: 1, height: 11, color: PineColors.lineStrong),
            const SizedBox(width: 10),
            Flexible(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onExamTap,
                child: Text(
                  examText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PineText.sans(
                      size: PineType.meta, color: PineColors.ink2),
                ),
              ),
            ),
          ],
          const Spacer(),
          if (syncText != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: PineColors.celadon,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(syncText!,
                style: PineText.mono(
                    size: PineType.caption, color: PineColors.ink3)),
          ],
        ],
      ),
    );
  }
}

/// 卷首累计铭文行 34px：全部历史累计 ···· 第 N 日 · 连续 N 日（下边虚线）。
class InscriptionRow extends StatelessWidget {
  const InscriptionRow(
      {super.key, required this.totalText, required this.rightText});

  final String totalText;
  final String rightText;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PineColors.line, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              totalText,
              overflow: TextOverflow.ellipsis,
              style:
                  PineText.serif(size: PineType.label, color: PineColors.ink2),
            ),
          ),
          const SizedBox(width: 8),
          Text(rightText,
              style: PineText.serif(
                  size: PineType.caption, color: PineColors.ink3)),
        ],
      ),
    );
  }
}

/// 手稿页的 64px 活字宋体读数 + caption + 批注。
/// 取代旧版「圆环套数字」，但沿用同样的 `timeText / caption` 语义，
/// 保证 `+MM:SS` 超时累计与「准备开始 / 专注中」等提示一字不改。
class PaperClockDigits extends StatelessWidget {
  const PaperClockDigits({
    super.key,
    required this.timeText,
    required this.caption,
    this.totalText,
    this.note,
    this.overtime = false,
    this.color,
  });

  final String timeText;
  final String caption;
  final String? totalText;
  final String? note;
  final bool overtime;

  /// 大字颜色：专注=檀褐、短休=青瓷、吃饭=赭石；不传＝浓墨。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                timeText,
                maxLines: 1,
                overflow: TextOverflow.fade,
                style: PineText.serif(
                  size: PineType.clock,
                  color:
                      overtime ? PineColors.ochre : (color ?? PineColors.ink),
                  weight: FontWeight.w500,
                  letterSpacing: -0.025,
                  features: kNumericFont,
                ),
              ),
            ),
            if (totalText != null) ...[
              const SizedBox(width: 8),
              Text(
                totalText!,
                style:
                    PineText.mono(size: PineType.meta, color: PineColors.ink3),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          style: PineText.serif(
            size: PineType.label,
            color: color == null
                ? PineColors.ink2
                : Color.alphaBlend(color!.withAlpha(210), PineColors.ink),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(note!,
              style: PineText.sans(
                  size: PineType.caption, color: PineColors.ink3)),
        ],
      ],
    );
  }
}

/// 50 分钟纸面比例尺：25 档刻度（每 2 分钟），5/10 分档加长；
/// 已历=檀褐，当前=浓墨游标，未历=极淡墨；下方 00m–50m 轴。
class RuledScale extends StatelessWidget {
  const RuledScale({
    super.key,
    required this.progress,
    this.targetMinutes = 50,
    this.meta,
    this.accent,
  });

  /// 0..1，超时会被夹到 1（超时态由 [PaperClockDigits] 的 `+MM:SS` 表达）。
  final double progress;
  final int targetMinutes;
  final String? meta;

  /// 已历刻度的颜色：专注=檀褐、短休=青瓷、吃饭=赭石。
  final Color? accent;

  /// 轴标步长：≤60 分钟每 10 分钟一个，更长的番每 15/30 分钟一个。
  int get _step => targetMinutes <= 60 ? 10 : (targetMinutes <= 90 ? 15 : 30);

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final color = accent ?? PineColors.accent;
    final labels = <int>[
      for (var m = 0; m <= targetMinutes; m += _step) m,
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
      decoration: BoxDecoration(
        color: PineColors.sunken,
        borderRadius: BorderRadius.circular(PineRadius.control),
        border: Border.all(color: PineColors.line, width: Paper.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  meta ?? '尺规进度',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PineText.sans(
                      size: PineType.caption, color: PineColors.ink2),
                ),
              ),
              Text(
                '${(p * 100).round()}%',
                style: PineText.mono(size: PineType.caption, color: color),
              ),
            ],
          ),
          const SizedBox(height: 7),
          // 尺面：基线 + 细刻度 + 已历实带 + 游标，交给一个 painter 画，
          // 比堆 25 个 Container 更稳（也不会有 1.2px 缝带来的"柱状图"错觉）。
          SizedBox(
            height: 26,
            child: CustomPaint(
              painter: _RulerPainter(
                progress: p,
                targetMinutes: targetMinutes,
                step: _step,
                accent: color,
                base: PineColors.inkFaint,
                cursor: PineColors.ink,
                axis: PineColors.lineStrong,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final m in labels)
                Text(
                  m == targetMinutes ? '${m}m' : '$m',
                  style: PineText.mono(
                      size: PineType.caption, color: PineColors.ink3),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 尺面绘制：0 处为左端，targetMinutes 处为右端。
///
/// 语言刻意做成"尺子"而不是"柱状图"：
/// 细刻度（每 2 分钟）+ 每 10 分钟加长 + 一条已历实带 + 一枚游标。
class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.progress,
    required this.targetMinutes,
    required this.step,
    required this.accent,
    required this.base,
    required this.cursor,
    required this.axis,
  });

  final double progress;
  final int targetMinutes;
  final int step;
  final Color accent;
  final Color base;
  final Color cursor;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final baselineY = h - 1;
    final total = targetMinutes <= 0 ? 1 : targetMinutes;

    // 1) 基线
    canvas.drawRect(
      Rect.fromLTWH(0, baselineY, w, 1),
      Paint()..color = axis,
    );

    // 2) 细刻度：每 2 分钟一根；每 10 分钟加长一档
    final minorCount = (total / 2).ceil();
    for (var i = 0; i <= minorCount; i++) {
      final minute = i * 2;
      if (minute > total) break;
      final x = (minute / total) * w;
      final isMajor = minute % step == 0;
      final isHalf = minute % 10 == 0;
      final tickH = isMajor ? 13.0 : (isHalf ? 9.0 : 5.0);
      final passed = minute / total <= progress;
      canvas.drawRect(
        Rect.fromLTWH(
          (x - 0.75).clamp(0.0, w - 1),
          baselineY - tickH,
          1.5,
          tickH,
        ),
        Paint()
          ..color = passed ? accent : base
          ..style = PaintingStyle.fill,
      );
    }

    // 3) 已历实带：贴着基线的 2.5pt 檀褐带，长度 = 进度
    final filled = w * progress.clamp(0.0, 1.0);
    if (filled > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, baselineY - 2.5, filled, 2.5),
        Paint()..color = accent,
      );
    }

    // 4) 游标：当前分钟处一枚全高标记（浓墨 + 上下各探出 1pt）
    final cx = (w * progress.clamp(0.0, 1.0)).clamp(0.0, w);
    canvas.drawRect(
      Rect.fromLTWH((cx - 1.25).clamp(0.0, w - 2.5), 0, 2.5, baselineY),
      Paint()..color = cursor,
    );
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.progress != progress ||
      old.targetMinutes != targetMinutes ||
      old.step != step ||
      old.accent != accent;
}

/// 稿纸批注的一行数据（只含展示所需，不持有业务状态）。
class PaperCheckItem {
  const PaperCheckItem({
    required this.text,
    this.done = false,
    this.current = false,
  });

  final String text;
  final bool done;
  final bool current;
}

/// 稿纸横格线式清单：中文序号 一/二/三 + 纸勾选框 + 「此刻研读」标记。
class PaperChecklist extends StatelessWidget {
  const PaperChecklist({
    super.key,
    required this.items,
    this.title,
    this.trailing,
    this.onTrailing,
    this.onToggle,
    this.onTapItem,
  });

  final List<PaperCheckItem> items;
  final String? title;
  final String? trailing;
  final VoidCallback? onTrailing;
  final void Function(int index)? onToggle;
  final void Function(int index)? onTapItem;

  static const List<String> _numerals = <String>[
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '七',
    '八',
    '九',
    '十',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  title!,
                  style: PineText.serif(
                      size: PineType.meta, color: PineColors.ink2),
                ),
              ),
              if (trailing != null)
                GestureDetector(
                  onTap: onTrailing,
                  child: Text(
                    trailing!,
                    style: PineText.serif(
                        size: PineType.meta, color: PineColors.accent),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 6),
        for (var i = 0; i < items.length; i++) _row(i, items[i]),
      ],
    );
  }

  Widget _row(int index, PaperCheckItem item) {
    final numeral =
        index < _numerals.length ? _numerals[index] : '${index + 1}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTapItem == null ? null : () => onTapItem!(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PineColors.line, width: 1)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$numeral、',
                style: PineText.serif(
                  size: PineType.meta,
                  color: item.current ? PineColors.accent : PineColors.ink3,
                  weight: FontWeight.w500,
                ),
              ),
            ),
            GestureDetector(
              onTap: onToggle == null ? null : () => onToggle!(index),
              child: Container(
                width: 15,
                height: 15,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: item.done ? PineColors.accentSoft : PineColors.sheet,
                  border: Border.all(
                    color:
                        item.done ? PineColors.accent : PineColors.lineStrong,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(PineRadius.seal),
                ),
                child: item.done
                    ? Text(
                        '✓',
                        style: PineText.serif(
                            size: PineType.caption, color: PineColors.accent),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PineText.sans(
                  size: PineType.meta,
                  color: item.done ? PineColors.ink3 : PineColors.ink,
                ),
              ),
            ),
            if (item.current)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: PineColors.accentSoft,
                  borderRadius: BorderRadius.circular(PineRadius.seal),
                ),
                child: Text(
                  '此刻研读',
                  style: PineText.serif(
                      size: PineType.caption, color: PineColors.accent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 今日达成条：目标 / 已完成 / 百分比 / 细进度条 / 落账详单。
class LedgerBar extends StatelessWidget {
  const LedgerBar({
    super.key,
    required this.kicker,
    required this.value,
    required this.percent,
    required this.detail,
    required this.progress,
    this.footLeft,
    this.footRight,
    this.onDetail,
  });

  final String kicker;
  final String value;
  final String percent;
  final String detail;
  final double progress;
  final String? footLeft;
  final String? footRight;
  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context) {
    return SuzhiCard(
      showRule: false,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  kicker,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PineText.serif(
                      size: PineType.meta, color: PineColors.ink2),
                ),
              ),
              const SizedBox(width: 6),
              Text(percent,
                  style: PineText.mono(
                      size: PineType.label, color: PineColors.accent)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  style: PineText.serif(
                      size: PineType.num, weight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: PineText.sans(
                      size: PineType.caption, color: PineColors.ink3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(PineRadius.seal),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: PineColors.sunken,
              color: PineColors.accent,
            ),
          ),
          if (footLeft != null || footRight != null) ...[
            const SizedBox(height: 7),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    footLeft ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PineText.sans(
                        size: PineType.caption, color: PineColors.ink3),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: GestureDetector(
                    onTap: onDetail,
                    child: Text(
                      footRight ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: PineText.serif(
                          size: PineType.caption, color: PineColors.accent),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 主行动按钮：檀褐实底纸字（定稿全屏只允许 3–4 处檀褐实底）。
class CinnabarButton extends StatelessWidget {
  const CinnabarButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.semanticLabel,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// 图标按钮（label 为空）的可访问性文案，读屏与测试靠它定位。
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final bg = enabled ? PineColors.accent : PineColors.lineStrong;
    final fg = enabled ? PineColors.sheet : PineColors.ink3;
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(PineRadius.control),
            boxShadow: enabled ? PineShadow.card : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: PineText.serif(size: PineType.label, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 次行动按钮：笺纸底 + 定界线描边 + 浓墨字。
class PaperButton extends StatelessWidget {
  const PaperButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.selected = false,
    this.semanticLabel,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool selected;

  /// 图标按钮（label 为空）的可访问性文案。
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: selected ? PineColors.accentSoft : PineColors.sheet,
            border: Border.all(
              color: selected ? PineColors.accent : PineColors.lineStrong,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(PineRadius.control),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 16,
                    color: selected ? PineColors.accent : PineColors.ink2),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: PineText.serif(
                  size: PineType.label,
                  color: selected ? PineColors.accent : PineColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部笺纸 Composer：上层提示 + 方印按钮，下层阶段段选 + 三键。
class PaperComposer extends StatelessWidget {
  const PaperComposer({
    super.key,
    required this.hintText,
    required this.sealText,
    required this.onSeal,
    required this.phases,
    required this.actions,
  });

  final String hintText;
  final String sealText;
  final VoidCallback onSeal;
  final Widget phases;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: PineDecoration.sheet(composer: true),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hintText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PineText.sans(
                      size: PineType.meta, color: PineColors.ink3),
                ),
              ),
              const SizedBox(width: 8),
              SectionSeal(text: sealText, onTap: onSeal),
            ],
          ),
          const SizedBox(height: 9),
          // 390 宽的手机上，阶段段选与三键同行会互相挤压；设计稿桌面宽屏
          // 是同一行，这里按响应式规则收成两行，语义与回调完全不变。
          Row(children: [Expanded(child: phases)]),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: actions),
        ],
      ),
    );
  }
}

/// 素纸拨子：取代 iOS 胶囊开关。无状态，值由调用方持有。
class PaperToggle extends StatelessWidget {
  const PaperToggle(
      {super.key, required this.value, required this.onChanged, this.label});

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final knob = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: value ? PineColors.accent : PineColors.ink3,
        border: Border.all(color: PineColors.lineStrong, width: 1),
        borderRadius: BorderRadius.circular(PineRadius.seal),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Text(label!,
                style:
                    PineText.sans(size: PineType.meta, color: PineColors.ink2)),
            const SizedBox(width: 8),
          ],
          Container(
            width: 34,
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: value ? PineColors.accentSoft : PineColors.sunken,
              border: Border.all(color: PineColors.lineStrong, width: 1),
              borderRadius: BorderRadius.circular(PineRadius.control),
            ),
            child: knob,
          ),
        ],
      ),
    );
  }
}

/// 底部书签栏 40px：选中项顶部 2px 檀褐短线，宋体页签名。
class PaperTabs extends StatelessWidget {
  const PaperTabs({
    super.key,
    required this.index,
    required this.labels,
    required this.onChanged,
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: PineColors.sheet,
        border: Border(top: BorderSide(color: PineColors.lineStrong, width: 1)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 28,
                      height: 2,
                      decoration: BoxDecoration(
                        color:
                            i == index ? PineColors.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(PineRadius.seal),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[i],
                      style: PineText.serif(
                        size: PineType.meta,
                        color: i == index ? PineColors.accent : PineColors.ink2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 近七日科目堆叠墨柱的一天。[minutes] 固定 4 档顺序：
/// 高数 / 408 / 英语 / 政治（跨天比较不可换序）。
class InkStackDay {
  const InkStackDay({
    required this.label,
    required this.minutes,
    this.valueLabel,
    this.today = false,
  });

  final String label;
  final List<double> minutes;
  final String? valueLabel;
  final bool today;
}

/// 水墨四阶堆叠柱：檀褐 / 浓墨 82% / 中墨 46% / 淡墨 22%。
/// 不引入第三方图表库，用 `Column + Expanded(flex: 分钟)` 自绘。
class InkStackChart extends StatelessWidget {
  const InkStackChart({
    super.key,
    required this.days,
    this.height = 118,
    this.legend = const <String>['高数', '408', '英语', '政治'],
  });

  final List<InkStackDay> days;
  final double height;
  final List<String> legend;

  static const List<Color> _colors = <Color>[
    PineColors.accent,
    PineColors.ink,
    PineColors.ink2,
    PineColors.ink3,
  ];

  @override
  Widget build(BuildContext context) {
    final maxTotal = days.fold<double>(
      1,
      (m, d) => m > d.minutes.fold<double>(0, (s, v) => s + v)
          ? m
          : d.minutes.fold<double>(0, (s, v) => s + v),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final day in days) Expanded(child: _column(day, maxTotal)),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            for (final day in days)
              Expanded(
                child: Text(
                  day.label,
                  textAlign: TextAlign.center,
                  style: PineText.mono(
                    size: PineType.caption,
                    color: day.today ? PineColors.accent : PineColors.ink3,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (var i = 0; i < legend.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, color: _colors[i]),
                  const SizedBox(width: 4),
                  Text(
                    legend[i],
                    style: PineText.sans(
                        size: PineType.caption, color: PineColors.ink2),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static Widget _segment({required double minutes, required Color color}) {
    final flex = minutes.round();
    return Expanded(
      flex: flex < 1 ? 1 : flex,
      child: ColoredBox(color: color),
    );
  }

  Widget _column(InkStackDay day, double maxTotal) {
    final total = day.minutes.fold<double>(0, (s, v) => s + v);
    final fill = (total / maxTotal).clamp(0.0, 1.0);
    // 数值标签要占掉柱顶的一段高度，否则满格柱 + 标签会撑破外层固定高度。
    final labelReserve = day.valueLabel != null ? 20.0 : 0.0;
    final barHeight = (height - labelReserve) * fill;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        // 关键：Column 默认 crossAxisAlignment.center，柱子会按 child 内在宽度
        // 塌成 0 宽（只有今日柱的描边显出一条细线）。必须拉伸到 Expanded 给的宽度。
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (day.valueLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                day.valueLabel!,
                maxLines: 1,
                overflow: TextOverflow.fade,
                textAlign: TextAlign.center,
                style: PineText.mono(
                  size: PineType.caption,
                  color: day.today ? PineColors.accent : PineColors.ink3,
                ),
              ),
            ),
          SizedBox(
            key: ValueKey('ink-bar-${day.label}'),
            width: double.infinity,
            height: barHeight,
            child: Container(
              decoration: BoxDecoration(
                border: day.today
                    ? Border.all(color: PineColors.accent, width: 1.5)
                    : null,
                borderRadius: BorderRadius.circular(PineRadius.seal),
              ),
              clipBehavior: Clip.antiAlias,
              child: total <= 0
                  ? const SizedBox.shrink()
                  : Column(
                      // 内外两层 Column 都要 stretch：`ColoredBox` 没有 child，
                      // 不拉伸时内在宽度为 0，柱子会只剩描边、看不到色段。
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      // 自下而上按科目堆叠：列表头（高数）落在柱底。
                      children: [
                        for (var i = day.minutes.length - 1; i >= 0; i--)
                          if (day.minutes[i] > 0)
                            _segment(
                              minutes: day.minutes[i],
                              color: _colors[i < 4 ? i : 0],
                            ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 双线框藏书票：外 1px 定界线 + 内 1px 裁切线。
class ExLibrisCard extends StatelessWidget {
  const ExLibrisCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: PineColors.sheet,
        border: Border.all(color: PineColors.lineStrong, width: 1),
        borderRadius: BorderRadius.circular(PineRadius.card),
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: PineColors.sheet,
          border: Border.all(color: PineColors.line, width: 1),
          borderRadius: BorderRadius.circular(PineRadius.card - 2),
        ),
        child: child,
      ),
    );
  }
}

/// 钤印日历的一格：打卡=檀褐淡敷，今日=檀褐实底，空格=纸面。
class SealCalendar extends StatelessWidget {
  const SealCalendar({
    super.key,
    required this.daysInMonth,
    required this.firstWeekday,
    required this.dayMinutes,
    required this.today,
    this.columns = 10,
  });

  final int daysInMonth;
  final int firstWeekday; // 1=周一 … 7=周日
  final Map<int, double> dayMinutes;
  final int today;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    for (var i = 1; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final minutes = dayMinutes[d] ?? 0;
      final isToday = d == today;
      cells.add(Container(
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isToday
              ? PineColors.accent
              : minutes > 0
                  ? PineColors.accentSoft
                  : PineColors.sheet,
          border: Border.all(
            color: isToday ? PineColors.accent : PineColors.line,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(PineRadius.seal),
        ),
        child: Text(
          '$d',
          style: PineText.mono(
            size: PineType.caption,
            color: isToday
                ? PineColors.sheet
                : minutes > 0
                    ? PineColors.accent
                    : PineColors.inkFaint,
          ),
        ),
      ));
    }
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: columns,
      mainAxisSpacing: 3,
      crossAxisSpacing: 3,
      childAspectRatio: 1.35,
      children: cells,
    );
  }
}

/// 阶段段选（定稿 anatomy）：宋体字 + 分钟小字 + 选中项底部 2px 檀褐短横。
/// 语义与 [PhaseSwitcher] 完全一致（`current` 为 null = 今日已收工，全不选中），
/// 只换视觉载体：不再用胶囊底块。
class PhaseTabs extends StatelessWidget {
  const PhaseTabs({
    super.key,
    required this.current,
    required this.minutesFor,
    required this.onChanged,
  });

  /// 当前阶段；null = 已收工，三段全部留白（刻意的，不在收工态高亮「专注」）。
  final SessionMode? current;
  final int Function(SessionMode mode) minutesFor;
  final ValueChanged<SessionMode> onChanged;

  static String shortLabel(SessionMode mode) => switch (mode) {
        SessionMode.focus => '专注',
        SessionMode.shortBreak => '短休',
        SessionMode.longBreak => '吃饭',
      };

  @override
  Widget build(BuildContext context) {
    // 间距随宽度收：三栏重排后中栏更窄（左栏 216→236），
    // 单列专注舱（<720）里 16pt 间距会让三段并排溢出 3.6pt，收到 12。
    final gap = MediaQuery.sizeOf(context).width < 720 ? 12.0 : 16.0;
    // 再兜一层：极窄时（440×600 舱内的 Composer 只有 198pt）整组等比缩一点，
    // 而不是让 RenderFlex 报溢出——这几个百分点肉眼不可见。
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < SessionMode.values.length; i++) ...<Widget>[
            if (i > 0) SizedBox(width: gap),
            _tab(SessionMode.values[i]),
          ],
        ],
      ),
    );
  }

  Widget _tab(SessionMode mode) {
    final selected = mode == current;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(mode),
      child: Padding(
        padding: const EdgeInsets.only(top: 3, bottom: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  shortLabel(mode),
                  style: PineText.serif(
                    size: PineType.body,
                    weight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? PineColors.ink : PineColors.ink3,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${minutesFor(mode)}',
                  style: PineText.mono(
                    size: PineType.caption,
                    color: selected ? PineColors.ink2 : PineColors.ink3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              width: 16,
              height: 2,
              decoration: BoxDecoration(
                color: selected ? PineColors.accent : const Color(0x00000000),
                borderRadius: BorderRadius.circular(PineRadius.seal),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
