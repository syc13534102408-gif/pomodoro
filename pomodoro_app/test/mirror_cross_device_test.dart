// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';

const _settings = TimerSettings(focus: 25, short: 5, long: 15);

AppData _base() => AppData(
      settings: _settings,
      tasks: [PineTask(name: '高数')],
    );

/// 镜像端：任务列表含「高数」（与发起端同步过），但当前选中的是 taskName
AppData _mirrorWith(String taskName) => AppData(
      settings: _settings,
      tasks: [PineTask(name: taskName), PineTask(name: '高数'), PineTask(name: '其他任务')],
      selectedIndex: 0,
    );

void main() {
  group('镜像采纳：双端任务不同时跟随发起端', () {
    test('快照任务名在本地任务列表中 → 选中任务切换跟随', () {
      final remoteStart = DateTime(2026, 9, 10, 10);
      // 发起端（Mac）：任务「高数」、focus 50 分钟
      final remote = TimerEngine.start(
        AppData(settings: TimerSettings(focus: 50), tasks: [PineTask(name: '高数')]),
        SessionMode.focus,
        remoteStart,
      );
      final snapshot = remote.activeSession!.toMap();

      // 镜像端（手机）：当前选中「英语」，但任务列表里有「高数」
      final local = _mirrorWith('英语');
      final adopted = TimerEngine.adoptRemoteSession(
        local,
        snapshot,
        taskName: '高数',
      );

      expect(adopted.selectedTask.name, '高数'); // 跟随发起端
      // 计划时长以发起端快照为准（deadline 是绝对时刻）
      expect(adopted.activeSession!.deadline, remote.activeSession!.deadline);
    });

    test('快照任务名本地不存在 → 保持本机选择（不崩溃）', () {
      final remoteStart = DateTime(2026, 9, 10, 10);
      final remote = TimerEngine.start(_base(), SessionMode.focus, remoteStart);
      final snapshot = remote.activeSession!.toMap();

      final local = _mirrorWith('英语');
      final adopted = TimerEngine.adoptRemoteSession(
        local,
        snapshot,
        taskName: '本地没有的任务',
      );
      expect(adopted.selectedTask.name, '英语');
      expect(adopted.activeSession, isNotNull);
    });
  });

  group('镜像端完成外来会话：补建记录落统计', () {
    test('本地无 recordId 记录 → 完成时补建 completed 记录', () {
      final remoteStart = DateTime(2026, 9, 10, 10);
      // 发起端开始专注（in_progress 记录只存在于发起端）
      final remote = TimerEngine.start(
        AppData(settings: TimerSettings(focus: 50), tasks: [PineTask(name: '高数')]),
        SessionMode.focus,
        remoteStart,
      );
      final snapshot = remote.activeSession!.toMap();

      // 镜像端采纳（本地没有任何 records，选中任务已跟随为「高数」）
      final local = TimerEngine.adoptRemoteSession(
        AppData(settings: TimerSettings(focus: 50), tasks: [PineTask(name: '高数')]),
        snapshot,
        taskName: '高数',
      );

      // 镜像端点到完成（比如 30 分钟时）
      final doneAt = remoteStart.add(const Duration(minutes: 30));
      final done = TimerEngine.complete(local, doneAt);

      // 补建的记录与发起端同 id、任务名跟随、分钟=已专注时长
      final record = done.records.first;
      expect(record.id, remote.activeSession!.recordId);
      expect(record.taskName, '高数');
      expect(record.minutes, 30.0);
      expect(record.status, RecordStatus.completed);
      expect(record.dayKey, dateKey(doneAt));
      // 自动进入休息
      expect(done.activeSession!.mode.isFocus, isFalse);
    });

    test('镜像端补建记录上传后，发起端按同 id 收口自己的 in_progress 记录', () {
      final remoteStart = DateTime(2026, 9, 10, 10);
      final remote = TimerEngine.start(_base(), SessionMode.focus, remoteStart);
      final snapshot = remote.activeSession!.toMap();

      final local = TimerEngine.adoptRemoteSession(_base(), snapshot);
      final doneAt = remoteStart.add(const Duration(minutes: 25));
      final done = TimerEngine.complete(local, doneAt);
      final mirroredRecord = done.records.first;

      // 发起端把镜像端上传的记录合并进本地（模拟备份同步的拉取采用）
      final remoteLocal = remote.copyWith(records: [mirroredRecord]);
      // 发起端 tick 推进（会话已过点，targetReached）
      final advanced = TimerEngine.advance(
          remoteLocal, remoteStart.add(const Duration(minutes: 26)));
      // 再走一次 complete 收口（发起端用户也点了完成）
      final closed = TimerEngine.complete(advanced, doneAt);
      final record = closed.records.first;
      expect(record.status, RecordStatus.completed);
      expect(record.minutes, 25.0);
    });
  });
}
