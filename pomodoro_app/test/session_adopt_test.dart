import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';

const _settings = TimerSettings(focus: 25, short: 5, long: 15);

AppData _started(DateTime at) => TimerEngine.start(
      AppData(settings: _settings),
      SessionMode.focus,
      at,
    );

void main() {
  group('TimerEngine.adoptRemoteSession', () {
    test('远端无会话 → 清除本机进行中的会话（不写统计）', () {
      final data = _started(DateTime(2026, 9, 9, 10));

      final next = TimerEngine.adoptRemoteSession(data, null);

      expect(next.activeSession, isNull);
      // discard 语义：start 落下的 inProgress 占位记录被删除（重置不记录）；
      // 无任何 counted 记录产生（这轮不进统计，已专注部分由发起端负责）。
      expect(next.records.length, data.records.length - 1);
      expect(next.records.where((r) => r.counted), isEmpty);
    });

    test('远端无会话 + 本机本就空闲 → 原样返回', () {
      final data = AppData(settings: _settings);
      expect(TimerEngine.adoptRemoteSession(data, null), same(data));
    });

    test('采纳运行中的远端会话：deadline 直接采用，本机随时间正确走表', () {
      final remoteStart = DateTime(2026, 9, 9, 10);
      final remote = _started(remoteStart);
      final snapshot = remote.activeSession!.toMap();

      final local = AppData(settings: _settings);
      final adopted = TimerEngine.adoptRemoteSession(local, snapshot);

      expect(adopted.activeSession, isNotNull);
      expect(adopted.activeSession!.mode, SessionMode.focus);
      expect(adopted.activeSession!.deadline, remote.activeSession!.deadline);
      expect(adopted.activeSession!.running, isTrue);

      // 采纳 10 分钟后：镜像端显示剩余 15:00，与发起端一致。
      final view =
          SessionView.of(adopted, remoteStart.add(const Duration(minutes: 10)));
      expect(view, isNotNull);
      expect(view!.remainingSeconds, 15 * 60);
      expect(view.clockText, '15:00');
    });

    test('采纳暂停中的远端会话：冻结在 remaining', () {
      final remoteStart = DateTime(2026, 9, 9, 10);
      var remote = _started(remoteStart);
      remote = TimerEngine.pause(remote, remoteStart.add(const Duration(minutes: 13)));
      final snapshot = remote.activeSession!.toMap();

      final adopted = TimerEngine.adoptRemoteSession(
          AppData(settings: _settings), snapshot);
      // 暂停后 27 分钟再查看：仍冻结在剩余 12:00。
      final view = SessionView.of(
          adopted, remoteStart.add(const Duration(minutes: 40)));

      expect(view!.running, isFalse);
      expect(view.clockText, '12:00');
    });

    test('快照损坏 → 原样返回，不抛异常', () {
      final data = _started(DateTime(2026, 9, 9, 10));
      // mode 给非法值，fromMap 应安全回退返回 null 或合法会话，不得崩溃。
      expect(
        () => TimerEngine.adoptRemoteSession(data, {
          'recordId': 'x',
          'mode': 'not-a-mode',
          'running': true,
          'remaining': 0,
          'targetReached': false,
          'overtimeElapsed': 0,
        }),
        returnsNormally,
      );
    });
  });

  group('shouldAdoptRemoteSession', () {
    test('空态（seq=0）不采纳', () {
      expect(
        shouldAdoptRemoteSession(
            lastSeenSeq: 0, remoteSeq: 0, selfDeviceId: 'A', remoteDeviceId: 'B'),
        isFalse,
      );
    });

    test('更小的 seq（乱序/重放）不采纳', () {
      expect(
        shouldAdoptRemoteSession(
            lastSeenSeq: 7, remoteSeq: 6, selfDeviceId: 'A', remoteDeviceId: 'B'),
        isFalse,
      );
    });

    test('自己发布的回声不采纳', () {
      expect(
        shouldAdoptRemoteSession(
            lastSeenSeq: 0, remoteSeq: 5, selfDeviceId: 'A', remoteDeviceId: 'A'),
        isFalse,
      );
    });

    test('他人更大 seq 采纳', () {
      expect(
        shouldAdoptRemoteSession(
            lastSeenSeq: 5, remoteSeq: 6, selfDeviceId: 'A', remoteDeviceId: 'B'),
        isTrue,
      );
    });

    test('deviceId 缺失（云端记录损坏）不采纳', () {
      expect(
        shouldAdoptRemoteSession(
            lastSeenSeq: 0, remoteSeq: 5, selfDeviceId: 'A', remoteDeviceId: ''),
        isFalse,
      );
    });
  });
}
