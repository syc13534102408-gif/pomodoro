import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/cloud_auto.dart';
import '../src/cloud_sync.dart';
import '../src/models.dart';
import '../src/notifications.dart';
import '../src/storage.dart';
import '../src/theme.dart';
import '../src/widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.data, required this.onChanged});

  final AppData data;
  final ValueChanged<AppData> onChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _focus;
  late final TextEditingController _short;
  late final TextEditingController _long;
  late final TextEditingController _goal;
  late final TextEditingController _weekGoal;
  late final TextEditingController _worker;

  final CloudSync _sync = CloudSync();
  String _syncMessage = '';
  bool _syncBusy = false;

  @override
  void initState() {
    super.initState();
    _focus = TextEditingController(text: widget.data.settings.focus.toString());
    _short = TextEditingController(text: widget.data.settings.short.toString());
    _long = TextEditingController(text: widget.data.settings.long.toString());
    _goal = TextEditingController(text: widget.data.goalMinutes.toString());
    _weekGoal = TextEditingController(text: widget.data.weekGoal.toString());
    _worker = TextEditingController(text: CloudSync.defaultBaseUrl);
  }

  @override
  void dispose() {
    _focus.dispose();
    _short.dispose();
    _long.dispose();
    _goal.dispose();
    _weekGoal.dispose();
    _worker.dispose();
    super.dispose();
  }

  void _emit(AppData next) {
    widget.onChanged(next);
    setState(() {});
  }

  Future<void> _saveTimer() async {
    int read(TextEditingController controller, int fallback, int min, int max) {
      final value = int.tryParse(controller.text) ?? fallback;
      return value.clamp(min, max);
    }

    final next = widget.data.copyWith(
      settings: TimerSettings(
        focus: read(_focus, 50, 1, 600),
        short: read(_short, 10, 1, 120),
        long: read(_long, 25, 1, 180),
      ),
      goalMinutes: read(_goal, 200, 1, 999),
      weekGoal: read(_weekGoal, 20, 1, 999),
    );
    _emit(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('设置已保存')),
    );
  }

  Future<void> _runSync(Future<void> Function() action) async {
    if (_syncBusy) return;
    setState(() {
      _syncBusy = true;
      _syncMessage = '';
    });
    try {
      await action();
    } on CloudSyncException catch (error) {
      setState(() => _syncMessage = error.message);
    } catch (_) {
      setState(() => _syncMessage = '网络不可用，请稍后重试');
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Future<void> _upload() async {
    var data = widget.data;
    if (data.sync.deviceCode.isEmpty) {
      data = data.copyWith(
        sync: data.sync.copyWith(deviceCode: CloudSync.generateDeviceCode()),
      );
      _emit(data);
    }
    final updatedAt = await _sync.upload(
      deviceCode: data.sync.deviceCode,
      payload: data.toCloudMap(),
      baseUpdatedAt: data.sync.lastSyncedAt,
    );
    _emit(data.copyWith(
      sync: data.sync.copyWith(
        lastUploadedAt: updatedAt,
        lastSyncedAt: updatedAt,
        lastSyncedHash: cloudFingerprint(data),
      ),
    ));
    setState(() => _syncMessage = '已上传到云端');
  }

  Future<void> _restore() async {
    final code = await _askCode();
    if (code == null) return;
    final backup = await _sync.download(code);
    final mergedBase = mergeFromCloud(widget.data, backup.payload);
    final merged = mergedBase.copyWith(
      sync: widget.data.sync.copyWith(
        deviceCode: code,
        lastSyncedAt: backup.updatedAt,
        lastSyncedHash: cloudFingerprint(mergedBase),
      ),
    );
    _emit(merged);
    setState(
      () => _syncMessage =
          '已恢复 ${backup.recordCount} 条记录 · ${_formatStamp(backup.updatedAt)}',
    );
  }

  Future<String?> _askCode() async {
    final controller = TextEditingController(text: widget.data.sync.deviceCode);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入同步码'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '同步码',
            helperText: '在原设备的设置页复制同步码',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
  }

  String _formatStamp(DateTime? time) {
    if (time == null) return '尚未同步';
    final local = time.toLocal();
    return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _clearRecords() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空全部专注记录？'),
        content: const Text('事件、待办和设置会保留，专注记录不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _emit(widget.data.copyWith(records: []));
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final code = data.sync.deviceCode;

    return Scaffold(
      appBar: AppBar(title: const Text('偏好设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          const _SettingsHeading(
            icon: Icons.timer_outlined,
            title: '计时与目标',
          ),
          const SizedBox(height: 8),
          PanelCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _numberField('专注', _focus)),
                    const SizedBox(width: 10),
                    Expanded(child: _numberField('短休息', _short)),
                    const SizedBox(width: 10),
                    Expanded(child: _numberField('长休息', _long)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _numberField('今日目标（分钟）', _goal)),
                    const SizedBox(width: 10),
                    Expanded(child: _numberField('本周目标（次）', _weekGoal)),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saveTimer,
                    child: const Text('保存计时设置'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SettingsHeading(
            icon: Icons.notifications_none_rounded,
            title: '提醒',
          ),
          const SizedBox(height: 8),
          PanelCard(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('结束通知',
                      style: TextStyle(color: PineColors.paper, fontSize: 14)),
                  subtitle: const Text('计划时长到达时发送系统通知',
                      style: TextStyle(color: PineColors.muted, fontSize: 11)),
                  value: data.notifyEnabled,
                  onChanged: (value) async {
                    if (value) await Notifier.requestPermission();
                    _emit(data.copyWith(notifyEnabled: value));
                  },
                ),
                const Divider(),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('完成提示音',
                      style: TextStyle(color: PineColors.paper, fontSize: 14)),
                  subtitle: const Text('三音提示，打开时试听一次',
                      style: TextStyle(color: PineColors.muted, fontSize: 11)),
                  value: data.soundEnabled,
                  onChanged: (value) {
                    if (value) unawaited(Notifier.chime());
                    _emit(data.copyWith(soundEnabled: value));
                  },
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('测试提醒',
                      style: TextStyle(color: PineColors.paper, fontSize: 14)),
                  subtitle: const Text('立即发送一条通知并播放提示音',
                      style: TextStyle(color: PineColors.muted, fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () async {
                    await Notifier.requestPermission();
                    await Notifier.alert(
                      title: '松果 · 测试提醒',
                      body: '这是专注结束时的提醒效果。',
                    );
                    if (data.soundEnabled) await Notifier.chime();
                  },
                ),
                if (ForegroundRunner.supported) ...[
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('锁屏剩余时间',
                        style:
                            TextStyle(color: PineColors.paper, fontSize: 14)),
                    subtitle: const Text('计时运行时显示；OPPO 需允许锁屏通知与后台运行',
                        style:
                            TextStyle(color: PineColors.muted, fontSize: 11)),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => ForegroundRunner.requestBatteryExemption(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SettingsHeading(
            icon: Icons.cloud_outlined,
            title: '云端同步',
          ),
          const SizedBox(height: 8),
          PanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        code.isEmpty ? '尚未生成同步码' : code,
                        style: const TextStyle(
                          color: PineColors.ink,
                          fontSize: 13,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '复制同步码',
                      icon: const Icon(Icons.copy, size: 17),
                      onPressed: code.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                  ClipboardData(text: code));
                              if (!context.mounted) return;
                              if (!mounted) return;
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('同步码已复制')),
                                );
                              }
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '最近上传：${_formatStamp(data.sync.lastUploadedAt)}',
                  style: const TextStyle(color: PineColors.muted, fontSize: 11),
                ),
                const SizedBox(height: 4),
                const Text(
                  '绑定同步码后：完成专注自动上传，回到 App 自动拉取',
                  style: TextStyle(color: PineColors.muted, fontSize: 11),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _syncBusy ? null : () => _runSync(_upload),
                        child: const Text('上传本机数据'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _syncBusy ? null : () => _runSync(_restore),
                        child: const Text('从云端恢复'),
                      ),
                    ),
                  ],
                ),
                if (_syncBusy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 3),
                ],
                if (_syncMessage.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _syncMessage,
                    style:
                        const TextStyle(color: PineColors.gold, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: _worker,
                  enabled: false,
                  style: const TextStyle(color: PineColors.muted, fontSize: 11),
                  decoration: const InputDecoration(
                    labelText: '同步服务地址',
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SettingsHeading(
            icon: Icons.storage_outlined,
            title: '本机数据',
          ),
          const SizedBox(height: 8),
          PanelCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('清空全部专注记录',
                  style: TextStyle(color: PineColors.tomato, fontSize: 14)),
              subtitle: const Text('事件、待办与设置会保留',
                  style: TextStyle(color: PineColors.muted, fontSize: 11)),
              trailing: const Icon(Icons.delete_outline, size: 18),
              onTap: _clearRecords,
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField(String label, TextEditingController controller) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: PineColors.ink, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixText: label.contains('次') ? null : '分',
        ),
      );
}

class _SettingsHeading extends StatelessWidget {
  const _SettingsHeading({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 17, color: PineColors.gold),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: PineColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}
