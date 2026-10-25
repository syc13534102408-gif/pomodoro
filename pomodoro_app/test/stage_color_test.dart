import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/theme.dart';

/// 相对亮度（WCAG 2.1 定义）。
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('阶段色两档规则（2026-10-25 决策 B1）', () {
    test('gold 只作实底：长休的 color 是 gold，线条色换成 goldInk', () {
      expect(SessionMode.longBreak.color, PineColors.gold);
      expect(SessionMode.longBreak.lineColor, PineColors.goldInk);
      expect(SessionMode.longBreak.lineColor, isNot(PineColors.gold));
    });

    test('专注/短休两档不变（原本就达标，不需要第二档）', () {
      expect(SessionMode.focus.lineColor, SessionMode.focus.color);
      expect(SessionMode.shortBreak.lineColor, SessionMode.shortBreak.color);
    });
  });

  group('对比度下限（方案 E §7.1 + WCAG 1.4.11）', () {
    test('弧线/大数字 ≥ 3.0:1（goldInk、mint、focus 三色）', () {
      for (final mode in SessionMode.values) {
        final ratio = _contrast(mode.lineColor, PineColors.paper);
        expect(ratio, greaterThanOrEqualTo(3.0),
            reason: '${mode.label} 的线条色对纸面只有 ${ratio.toStringAsFixed(2)}:1');
      }
    });

    test('正文次级色 sub ≥ 4.5:1（纸面与卡片两种底）', () {
      expect(_contrast(PineColors.sub, PineColors.paper),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(PineColors.sub, PineColors.card),
          greaterThanOrEqualTo(4.5));
    });

    test('主行动 ink on gold / ink on paper 都 ≥ 4.5:1', () {
      expect(_contrast(PineColors.ink, PineColors.gold),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(PineColors.ink, PineColors.paper),
          greaterThanOrEqualTo(4.5));
    });

    test('轨道 track 比 hairline 线更显眼（1.2 – 1.8 之间，不能抢弧）', () {
      final track = _contrast(PineColors.track, PineColors.paper);
      final line = _contrast(PineColors.line, PineColors.paper);
      expect(track, greaterThan(line));
      expect(track, lessThan(1.8));
    });
  });
}
