import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/menu_bar_timer.dart';
import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/theme.dart';

const _settings = TimerSettings(focus: 25, short: 5, long: 15);

AppData _base() => AppData(settings: _settings);

void main() {
  test('空闲：只显示品牌名，配色中性，无可重置会话', () {
    final state = menuBarStateOf(_base(), DateTime(2026, 9, 6, 10));

    expect(state.title, '松果');
    expect(state.tint, PineColors.sub.toARGB32());
    expect(state.primary, '开始');
    expect(state.canReset, false);
    // 空闲时菜单里补一句今日进度，抬眼就能看到还差多少。
    expect(state.detail, contains('/ 200 分钟'));
    // 空闲时悬浮窗自动隐藏，进度归零。
    expect(state.active, false);
    expect(state.progress, 0);
    expect(state.elapsed, '00:00');
  });

  test('专注中：番茄红 + 已专注时长（剩余挪到下拉菜单）', () {
    final now = DateTime(2026, 9, 6, 10);
    var data = TimerEngine.start(_base(), SessionMode.focus, now);

    final state = menuBarStateOf(data, now.add(const Duration(seconds: 1)));

    // 常驻显示的是「已经专注了多久」，不是剩余。
    expect(state.title, '专注 00:01');
    expect(state.elapsed, '00:01');
    expect(state.detail, contains('剩余 24:59'));
    expect(state.tint, PineColors.focus.toARGB32());
    expect(state.primary, '暂停');
    expect(state.confirm, '完成并开始休息');
    expect(state.canReset, true);
    expect(state.head, contains('专注中'));
    // 悬浮窗靠这两个字段渲染：进度条 + 是否显示。
    expect(state.active, true);
    expect(state.progress, closeTo(1 / 1500, 1e-9));
  });

  test('到点后：转金色，已专注继续累计，菜单里给出超出量', () {
    final now = DateTime(2026, 9, 6, 10);
    var data = TimerEngine.start(_base(), SessionMode.focus, now);
    // 跨过截止点：advance 会把超时锚点设在计划结束时刻。
    final after = now.add(const Duration(minutes: 25, seconds: 90));
    data = TimerEngine.advance(data, after);

    final state = menuBarStateOf(data, after);

    // 25:00 计划 + 1:30 超时 = 26:30 已专注。
    expect(state.title, '专注 26:30');
    expect(state.elapsed, '26:30');
    expect(state.tint, PineColors.gold.toARGB32());
    expect(state.detail, contains('超出计划 +01:30'));
    // 超时也不自动结束，仍可暂停/重置。
    expect(state.primary, '暂停');
    expect(state.progress, 1);
  });

  test('暂停：冻结在暂停时刻的已专注时长，配色转灰，主按钮变「继续」', () {
    final now = DateTime(2026, 9, 6, 10);
    var data = TimerEngine.start(_base(), SessionMode.focus, now);
    data = TimerEngine.pause(data, now.add(const Duration(minutes: 13)));

    final state = menuBarStateOf(data, now.add(const Duration(minutes: 40)));

    // 暂停期间时间不流逝：过了 27 分钟，显示仍是暂停那一刻的已专注 13:00。
    expect(state.title, '暂停 13:00');
    expect(state.elapsed, '13:00');
    expect(state.tint, PineColors.sub.toARGB32());
    expect(state.primary, '继续');
    expect(state.detail, contains('12:00'));
    // 暂停时悬浮窗仍然显示（用户需要知道停在哪）。
    expect(state.active, true);
  });

  test('休息中：薄荷绿，确认按钮为「结束休息」', () {
    final now = DateTime(2026, 9, 6, 10);
    var data = TimerEngine.start(_base(), SessionMode.shortBreak, now);

    final state = menuBarStateOf(data, now.add(const Duration(seconds: 2)));

    expect(state.title, '短休 00:02');
    expect(state.tint, PineColors.mint.toARGB32());
    expect(state.confirm, '结束休息');
  });

  test('长休息：标题区分长短休息', () {
    final now = DateTime(2026, 9, 6, 10);
    var data = TimerEngine.start(_base(), SessionMode.longBreak, now);

    final state = menuBarStateOf(data, now);

    expect(state.title, '长休 00:00');
    expect(state.head, contains('长休息'));
  });

  test('已专注满 1 小时：elapsed 转 h:mm:ss', () {
    final now = DateTime(2026, 9, 6, 10);
    var data = TimerEngine.start(_base(), SessionMode.focus, now);
    final after = now.add(const Duration(minutes: 65));
    data = TimerEngine.advance(data, after);

    final state = menuBarStateOf(data, after);

    expect(state.elapsed, '1:05:00');
    expect(state.title, '专注 1:05:00');
  });
}
