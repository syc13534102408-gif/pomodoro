import 'dart:convert';

import 'package:flutter/material.dart';

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
    'todos': {
      for (final entry in data.todos.entries)
        entry.key: [
          for (final item in entry.value)
            {'text': item.text, 'done': item.done},
        ],
    },
    'settings': data.settings.toMap(),
    'selected': data.selectedIndex,
    'goalTarget': data.goalTarget,
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
    DateTime Function()? clock,
  })  : _sync = sync,
        _apply = apply,
        _minInterval = minInterval,
        _clock = clock ?? DateTime.now;

  final CloudSync _sync;
  final Future<void> Function(AppData data) _apply;
  final Duration _minInterval;
  final DateTime Function() _clock;

  bool _busy = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);

  bool _canRun(AppData data) =>
      !_busy &&
      data.sync.deviceCode.isNotEmpty &&
      _clock().difference(_lastRun) >= _minInterval;

  /// 完成一次专注后调用：把本机新数据推上云端。
  ///
  /// 网络失败静默跳过——数据仍在本地，下次同步会补上。
  /// 云端已被网页端更新（409）时改为拉取，本机有改动则弹窗询问。
  /// [context] 仅在有冲突需要弹窗时使用，可为 null。
  Future<void> afterFocus(BuildContext? context, AppData data) async {
    if (!_canRun(data)) return;
    final fingerprint = cloudFingerprint(data);
    if (!hasLocalChanges(data)) return; // 没有新记录，无需上传
    _busy = true;
    _lastRun = _clock();
    try {
      final updatedAt = await _sync.upload(
        deviceCode: data.sync.deviceCode,
        payload: data.toCloudMap(),
        baseUpdatedAt: data.sync.lastSyncedAt,
      );
      await _apply(data.copyWith(
        sync: data.sync.copyWith(
          lastUploadedAt: updatedAt,
          lastSyncedAt: updatedAt,
          lastSyncedHash: fingerprint,
        ),
      ));
    } on CloudSyncException catch (error) {
      // 409：网页端刚更新过云端。本机数据不丢，转去拉取并让用户决定。
      if (error.conflict) {
        if (context == null || !context.mounted) return;
        await _pull(context, data, askOnConflict: true);
      }
    } catch (_) {
      // 网络不可用等：静默跳过。
    } finally {
      _busy = false;
    }
  }

  /// App 启动 / 回到前台时调用：拉取云端更新。
  Future<void> onResume(BuildContext? context, AppData data) =>
      _pull(context, data, askOnConflict: true);

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
        // 本机自上次同步后没有改动：直接采用云端版本。
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
          '本机也有未同步的改动。\n\n恢复云端版本会覆盖本机改动，请确认。',
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
