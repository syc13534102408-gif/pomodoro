import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/models.dart';
import 'package:pomodoro_app/src/notification_policy.dart';

void main() {
  group('endAlarmCopyFor 到点文案', () {
    test('专注到点：标题与正文（无任务名）', () {
      final copy = endAlarmCopyFor(mode: SessionMode.focus);
      expect(copy.title, '松果 · 计划时长已到');
      expect(copy.body, '这一轮计划时长已到，继续专注会累计更多时长。');
    });

    test('专注到点：正文拼接任务名', () {
      final copy = endAlarmCopyFor(mode: SessionMode.focus, taskName: '数学真题');
      expect(copy.title, '松果 · 计划时长已到');
      expect(copy.body, contains('数学真题'));
      expect(copy.body, '「数学真题」计划时长已到，继续专注会累计更多时长。');
    });

    test('短休息/长休息到点：同一套休息文案', () {
      for (final mode in [SessionMode.shortBreak, SessionMode.longBreak]) {
        final copy = endAlarmCopyFor(mode: mode, taskName: '数学真题');
        expect(copy.title, '松果 · 休息结束');
        expect(copy.body, '休息结束，可以开始下一轮专注。');
      }
    });
  });

  group('lockTimerTitle 锁屏常驻标题', () {
    test('专注中：标题含任务名（锁屏与通知栏完整可见）', () {
      expect(
        lockTimerTitle(targetReached: false, taskName: '数学真题'),
        '松果 · 专注：数学真题',
      );
    });

    test('已超时：标题含任务名', () {
      expect(
        lockTimerTitle(targetReached: true, taskName: '错题整理'),
        '松果 · 已超时：错题整理',
      );
    });

    test('无任务名（休息/取不到）：维持原文案', () {
      expect(lockTimerTitle(targetReached: false), '松果 · 计时中');
      expect(lockTimerTitle(targetReached: true), '松果 · 已超时');
      expect(lockTimerTitle(targetReached: false, taskName: ''),
          '松果 · 计时中');
    });
  });

  group('shouldScheduleSystemAlarm 911 排程决策', () {
    bool schedule({
      NotifyPlatform platform = NotifyPlatform.android,
      bool notifyEnabled = true,
      bool running = true,
      bool targetReached = false,
      bool hasDeadline = true,
      bool granted = true,
    }) =>
        shouldScheduleSystemAlarm(
          platform: platform,
          notifyEnabled: notifyEnabled,
          running: running,
          targetReached: targetReached,
          hasDeadline: hasDeadline,
          notificationsGranted: granted,
        );

    test('运行中未到点且有截止时刻：需要排', () {
      expect(schedule(), isTrue);
    });

    test('桌面/其他平台不排系统闹钟', () {
      expect(schedule(platform: NotifyPlatform.other), isFalse);
    });

    test('notifyEnabled=false 静默：不排', () {
      expect(schedule(notifyEnabled: false), isFalse);
    });

    test('暂停/非运行不排', () {
      expect(schedule(running: false), isFalse);
    });

    test('已到点（targetReached）不再排新闹钟', () {
      expect(schedule(targetReached: true), isFalse);
    });

    test('没有截止时刻（暂停残留状态）不排', () {
      expect(schedule(hasDeadline: false), isFalse);
    });

    test('系统通知权限未授予不排', () {
      expect(schedule(granted: false), isFalse);
    });
  });

  group('decideEndRing 到点响铃去重策略', () {
    EndRingDecision decide({
      SessionMode mode = SessionMode.focus,
      String? taskName,
      bool notifyEnabled = true,
      bool soundEnabled = true,
      NotifyPlatform platform = NotifyPlatform.android,
      bool restoreCompensation = false,
      bool granted = true,
    }) =>
        decideEndRing(
          mode: mode,
          taskName: taskName,
          notifyEnabled: notifyEnabled,
          soundEnabled: soundEnabled,
          platform: platform,
          restoreCompensation: restoreCompensation,
          notificationsGranted: granted,
        );

    test('Android 正常到点翻转：不弹 910、不 chime（交给系统 911，防双响）', () {
      final decision = decide();
      expect(decision.showLocalAlert, isFalse);
      expect(decision.playChime, isFalse);
    });

    test('Android restore 补偿：才弹 910，仍不 chime', () {
      final decision = decide(restoreCompensation: true);
      expect(decision.showLocalAlert, isTrue);
      expect(decision.playChime, isFalse);
      expect(decision.copy.title, '松果 · 计划时长已到');
    });

    test('Android 补偿但 notifyEnabled=false：静默', () {
      final decision = decide(restoreCompensation: true, notifyEnabled: false);
      expect(decision.showLocalAlert, isFalse);
      expect(decision.playChime, isFalse);
    });

    test('Android 补偿但系统权限未授予：静默', () {
      final decision =
          decide(restoreCompensation: true, granted: false);
      expect(decision.showLocalAlert, isFalse);
    });

    test('桌面正常到点：alert 910 + chime（维持旧行为）', () {
      final decision = decide(platform: NotifyPlatform.other);
      expect(decision.showLocalAlert, isTrue);
      expect(decision.playChime, isTrue);
    });

    test('桌面到点但关闭通知/声音：各自静默', () {
      final silent = decide(
          platform: NotifyPlatform.other,
          notifyEnabled: false,
          soundEnabled: false);
      expect(silent.showLocalAlert, isFalse);
      expect(silent.playChime, isFalse);

      final onlySound = decide(
          platform: NotifyPlatform.other,
          notifyEnabled: false,
          soundEnabled: true);
      expect(onlySound.showLocalAlert, isFalse);
      expect(onlySound.playChime, isTrue);
    });

    test('Android 关闭提示音也不影响系统闹钟文案（文案由 911 负责）', () {
      final decision = decide(soundEnabled: false, restoreCompensation: true);
      expect(decision.showLocalAlert, isTrue);
      expect(decision.copy.body, contains('这一轮'));
    });

    test('休息到点（Android 补偿）文案用休息文案', () {
      final decision = decide(
        mode: SessionMode.shortBreak,
        restoreCompensation: true,
      );
      expect(decision.copy.title, '松果 · 休息结束');
    });

    test('桌面到点带任务名：正文拼接任务名', () {
      final decision = decide(
        platform: NotifyPlatform.other,
        taskName: '看网课',
      );
      expect(decision.copy.body, contains('看网课'));
    });
  });
}
