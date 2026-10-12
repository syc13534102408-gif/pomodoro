import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_sync.dart';
import 'models.dart';
import 'storage.dart';

/// 生成云端净荷的规范化指纹。
///
/// 剔除任务/记录/待办的 id——它们由时间戳生成，每次从云端恢复都会被重新赋值，
/// 若纳入指纹会导致「什么都没变指纹却变了」的假冲突。只保留业务内容。
String cloudFingerprint(AppData data) {
  final normalized = <String, dynamic>{
    'tasks': [
      for (final task in data.tasks)
        {'name': task.name, 'color': task.color, 'count': task.count},
    ],
    'records': [
      for (final record in data.records)
        {
          'name': record.taskName,
          'minutes': record.minutes,
          'date': record.dayKey,
          'status': record.status.key,
        },
    ],
    'events': [
      for (final event in data.events)
        {
          'name': event.name,
          'task': event.taskName,
          'started': event.startedAt.toIso8601String(),
          'paused': event.pausedAt?.toIso8601String(),
          'finished': event.finishedAt?.toIso8601String(),
        },
    ],
    'todos': {
      for (final entry in data.todos.entries)
        entry.key: [
          for (final item in entry.value)
            {'text': item.text, 'done': item.done},
        ],
    },
    'settings': data.settings.toMap(),
    'selected': data.selectedIndex,
    'goalMinutes': data.goalMinutes,
    'weekGoal': data.weekGoal,
    'soundEnabled': data.soundEnabled,
    'notifyEnabled': data.notifyEnabled,
  };
  return jsonEncode(normalized);
}

/// 本机自上次同步后是否有未上传的改动。
bool hasLocalChanges(AppData data) =>
    cloudFingerprint(data) != data.sync.lastSyncedHash;

/// 自动云同步：完成专注后自动上传、App 回到前台/启动时自动拉取。
///
/// 只在「已绑定同步码」（[SyncState.deviceCode] 非空）时工作——同步码是两端
/// 互通的关键，没有它时静默创建一个网页端看不到的备份反而会造成数据分叉。
///
/// 冲突策略：本机没有未同步改动 → 直接采用云端版本（静默）；
/// 本机和云端都有改动 → 弹窗让用户决定，绝不静默覆盖。
class AutoCloudSync {
  AutoCloudSync({
    required CloudSync sync,
    required Future<void> Function(AppData data) apply,
    Duration minInterval = const Duration(seconds: 15),
    Duration pushInterval = const Duration(seconds: 20),
    DateTime Function()? clock,
  })  : _sync = sync,
        _apply = apply,
        _minInterval = minInterval,
        _pushInterval = pushInterval,
        _clock = clock ?? DateTime.now;

  final CloudSync _sync;
  final Future<void> Function(AppData data) _apply;
  final Duration _minInterval;
  final Duration _pushInterval;
  final DateTime Function() _clock;

  bool _busy = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);

  /// 「本地改动即上传」的独立节流时钟：与 [minInterval] 分开，
  /// 这样周期同步里连续「先上传、再拉取」时，后者不会被前者的节流吃掉。
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);

  /// 「完成专注」尚未成功上传的积压条数。完成一次专注是**必达事件**：
  /// 上传被占用/失败时只排队、不丢弃，等下一次同步机会（回前台/巡检/启动）
  /// 由 [flushPending] 补传，避免用户"点了完成但一直没上去"。
  ///
  /// 用计数而非布尔：本次上传只消化「它开始时已积压」的那些，
  /// 上传期间新产生的完成事件会留在计数里等下一轮。
  int _pendingPushes = 0;

  /// 本次上传开始时就积压的条数——成功/冲突时恰好消化这么多。
  void _consumePendingPushes(int count) {
    if (count <= 0) return;
    _pendingPushes = _pendingPushes > count ? _pendingPushes - count : 0;
  }

  /// 上传失败：保证至少留 1 条待补传（本次没传上去）。
  void _markPendingPush() {
    if (_pendingPushes < 1) _pendingPushes = 1;
  }

  bool _canRun(AppData data) =>
      !_busy &&
      data.sync.deviceCode.isNotEmpty &&
      _clock().difference(_lastRun) >= _minInterval;

  /// 采用/恢复云端前，把本机数据存一份安全副本（保留最近 3 份）。
  /// 误恢复后可按时间戳找回本机当时的数据（2026-09-15 事故教训：
  /// 「恢复云端」曾整体替换本机 records，今天的数据两端同时清空）。
  Future<void> _saveSafetyCopy(AppData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stamp =
          _clock().toIso8601String().replaceAll(':', '-').split('.').first;
      await prefs.setString(
          'pine-safety-copy-$stamp', jsonEncode(data.toMap()));
      final keys = prefs
          .getKeys()
          .where((k) => k.startsWith('flutter.pine-safety-copy-') ||
              k.startsWith('pine-safety-copy-'))
          .toList()
        ..sort();
      for (final k in keys.take(keys.length - 3)) {
        await prefs.remove(k);
      }
    } catch (_) {
      // 副本失败不阻断恢复主流程。
    }
  }

  /// 完成一次专注后调用：把本机新数据推上云端。
  ///
  /// **必达语义**（2026-10-12 修）：完成专注不该被节流或竞争吞掉——
  /// - 不参与 [minInterval]/[pushInterval] 节流（该事件本身低频，节流只会漏传）；
  /// - 若此刻正有拉取/上传在跑（[AutoCloudSync] 单通道），只把 [_pendingPushes]
  ///   加一排队，等下一次同步机会由 [flushPending] 用**最新数据**补传，不再直接丢弃；
  /// - 网络失败同样留待补传（数据始终在本机，不会丢）。
  ///
  /// 云端已被另一端更新（409）时改为拉取，本机有改动则弹窗询问。
  /// [context] 仅在有冲突需要弹窗时使用，可为 null。
  Future<void> afterFocus(BuildContext? context, AppData data) async {
    if (data.sync.deviceCode.isEmpty) return;
    if (!hasLocalChanges(data)) return; // 没有新记录，无需上传
    if (_busy) {
      _pendingPushes++; // 有同步在跑：排队，等下一次机会补传
      return;
    }
    await _pushNow(context, data);
  }

  /// 下一次同步机会的补传（回前台/巡检/启动时调用）：把被占用或失败的那次
  /// 「完成专注」补上去。用 [current]（调用方的最新数据）而不是当时的快照，
  /// 避免用旧快照覆盖云端在本机之后产生的新改动。
  Future<void> flushPending(BuildContext? context, AppData current) async {
    if (_pendingPushes <= 0 || _busy) return;
    if (current.sync.deviceCode.isEmpty || !hasLocalChanges(current)) {
      _pendingPushes = 0; // 未绑码 / 已由其它路径同步上去了
      return;
    }
    await _pushNow(context, current);
  }

  /// 真正的单次上传。[_busy] 由此方法统一持有与释放。
  Future<void> _pushNow(BuildContext? context, AppData data) async {
    final fingerprint = cloudFingerprint(data);
    final pendingAtStart = _pendingPushes; // 本次上传能消化掉的积压
    var askOnConflict = false;
    _busy = true;
    try {
      final updatedAt = await _sync.upload(
        deviceCode: data.sync.deviceCode,
        payload: data.toCloudMap(),
        baseUpdatedAt: data.sync.lastSyncedAt,
      );
      _consumePendingPushes(pendingAtStart);
      await _apply(data.copyWith(
        sync: data.sync.copyWith(
          lastUploadedAt: updatedAt,
          lastSyncedAt: updatedAt,
          lastSyncedHash: fingerprint,
        ),
      ));
    } on CloudSyncException catch (error) {
      if (error.conflict) {
        // 409：云端刚被另一端更新。本机数据不丢，交给拉取链路询问；
        // 开始时积压的那些不再计入待补传（否则会立即再撞一次同一冲突）。
        _consumePendingPushes(pendingAtStart);
        askOnConflict = true;
      } else {
        _markPendingPush();
      }
    } catch (_) {
      // 网络不可用等：留待下一次同步机会补传。
      _markPendingPush();
    } finally {
      _busy = false;
    }
    // 必须在 [_busy] 释放之后再拉取：[_pull] 自身带 `!_busy` 前置检查，
    // 原先在 _busy 未释放时调用会静默 return——409 的询问从未真正执行过。
    if (askOnConflict && context != null && context.mounted) {
      await _pull(context, data, askOnConflict: true);
    }
  }

  /// App 启动 / 回到前台时调用：拉取云端更新。
  Future<void> onResume(BuildContext? context, AppData data) =>
      _pull(context, data, askOnConflict: true);

  /// 本地数据改动后调用（补记、删除记录、改目标/清单/设置/编辑记录等）：
  /// 节流上传，让云端尽快跟上本机，而不是只等「完成一次专注」。
  ///
  /// 与 [afterFocus] 的两点差异：
  /// - 不需要 context：遇 409（云端已被另一端更新）时**静默跳过**，本机改动
  ///   原样保留，交给 [onResume]/周期同步的拉取链路去询问，避免高频弹窗打断操作；
  /// - 会话进行中不上传：`activeSession` 会把 in-progress 记录写进净荷，
  ///   这种半截记录不该落到云端，统一等 [afterFocus] 在完成时上传。
  Future<void> afterLocalChange(AppData data) async {
    if (data.sync.deviceCode.isEmpty) return; // 未绑定同步码：不创建孤立备份
    if (data.activeSession != null) return; // 会话进行中：等完成后统一上传
    if (!hasLocalChanges(data)) return; // 没有新改动
    if (_busy) return;
    if (_clock().difference(_lastPush) < _pushInterval) return; // 节流
    final fingerprint = cloudFingerprint(data);
    final pendingAtStart = _pendingPushes;
    _busy = true;
    _lastPush = _clock();
    try {
      final updatedAt = await _sync.upload(
        deviceCode: data.sync.deviceCode,
        payload: data.toCloudMap(),
        baseUpdatedAt: data.sync.lastSyncedAt,
      );
      // 这次传的是最新数据，开始时积压的完成事件已包含在内。
      _consumePendingPushes(pendingAtStart);
      await _apply(data.copyWith(
        sync: data.sync.copyWith(
          lastUploadedAt: updatedAt,
          lastSyncedAt: updatedAt,
          lastSyncedHash: fingerprint,
        ),
      ));
    } on CloudSyncException catch (error) {
      // 409 冲突：交给拉取链路询问，不计入待补传；
      // 其它错误留待下一次同步机会补传。
      if (!error.conflict) _markPendingPush();
    } catch (_) {
      // 网络不可用等：静默跳过，但要记住这次没传上去。
      _markPendingPush();
    } finally {
      _busy = false;
    }
  }

  Future<void> _pull(
    BuildContext? context,
    AppData data, {
    required bool askOnConflict,
  }) async {
    if (!_canRun(data)) return;
    _busy = true;
    _lastRun = _clock();
    try {
      final backup = await _sync.download(data.sync.deviceCode);
      final lastSyncedAt = data.sync.lastSyncedAt;
      if (lastSyncedAt != null && !backup.updatedAt.isAfter(lastSyncedAt)) {
        return; // 云端没有比上次同步更新的内容
      }
      if (!hasLocalChanges(data)) {
        // 本机自上次同步后没有改动：直接采用云端版本（先存安全副本）。
        // 副本异步落盘，不阻塞恢复主流程。
        unawaited(_saveSafetyCopy(data));
        final merged = mergeFromCloud(data, backup.payload);
        await _apply(merged.copyWith(
          sync: data.sync.copyWith(
            lastSyncedAt: backup.updatedAt,
            lastSyncedHash: cloudFingerprint(merged),
          ),
        ));
        return;
      }
      // 本机和云端都有改动。
      if (!askOnConflict || context == null || !context.mounted) return;
      final restore = await _askRestore(context, backup);
      if (restore != true) return;
      unawaited(_saveSafetyCopy(data));
      final merged = mergeFromCloud(data, backup.payload);
      await _apply(merged.copyWith(
        sync: data.sync.copyWith(
          lastSyncedAt: backup.updatedAt,
          lastSyncedHash: cloudFingerprint(merged),
        ),
      ));
    } on CloudSyncException catch (_) {
      // 404：这份同步码在云端还没有备份（网页端还没上传过）。跳过。
    } catch (_) {
      // 网络错误：静默跳过。
    } finally {
      _busy = false;
    }
  }

  Future<bool?> _askRestore(BuildContext context, CloudBackup backup) {
    final stamp = backup.updatedAt.toLocal();
    final time = '${stamp.month.toString().padLeft(2, '0')}-'
        '${stamp.day.toString().padLeft(2, '0')} '
        '${stamp.hour.toString().padLeft(2, '0')}:'
        '${stamp.minute.toString().padLeft(2, '0')}';
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('云端有更新'),
        content: Text(
          '另一台设备在 $time 更新了云端数据（${backup.recordCount} 条记录），'
          '本机也有未同步的改动。\n\n恢复云端会与本机数据**合并**'
          '（本机独有的记录会保留，不会丢失），请确认。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留本机'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复云端'),
          ),
        ],
      ),
    );
  }
}
