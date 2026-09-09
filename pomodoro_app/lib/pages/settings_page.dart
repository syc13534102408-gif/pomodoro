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
          BrickButton(
            label: '恢复',
            height: 40,
            expand: false,
            onPressed: () => Navigator.pop(context, controller.text.trim()),
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
    final first = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空全部专注记录？'),
        content: const Text('专注记录与统计会全部删除，事件、今日清单与设置会保留。此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          BrickButton(
            label: '继续',
            height: 40,
            expand: false,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final second = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('最后确认'),
        content: const Text('真的要清空全部专注记录吗？云端备份不受影响，但本机记录删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          BrickButton(
            label: '清空',
            height: 40,
            expand: false,
            color: PineColors.focus,
            foregroundColor: PineColors.card,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (second != true) return;
    _emit(widget.data.copyWith(records: []));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清空全部专注记录')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final code = data.sync.deviceCode;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        children: [
          const SectionHeader(title: '计时与目标'),
          const SizedBox(height: 10),
          BrickCard(
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
                const SizedBox(height: 16),
                BrickButton(
                  label: '保存计时设置',
                  onPressed: _saveTimer,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: '提醒'),
          const SizedBox(height: 10),
          BrickCard(
            child: Column(
              children: [
                _switchRow(
                  title: '结束通知',
                  subtitle: '计划时长到达时发送系统通知',
                  value: data.notifyEnabled,
                  onChanged: (value) async {
                    if (value) {
                      await Notifier.requestPermission();
                      // 精确闹钟授权：开启后到点可精确触发（只尝试一次，被拒降级）。
                      unawaited(Notifier.maybeRequestExactAlarmPermission());
                    } else {
                      // 全链路静默：撤掉已预排的 911 系统闹钟，并清掉可能残留的 910。
                      await Notifier.cancelEndAlarm();
                      await Notifier.cancel();
                    }
                    _emit(data.copyWith(notifyEnabled: value));
                  },
                ),
                const Divider(height: 1.5),
                _switchRow(
                  title: '完成提示音',
                  subtitle: '三音提示，打开时试听一次',
                  value: data.soundEnabled,
                  onChanged: (value) {
                    if (value) unawaited(Notifier.chime());
                    _emit(data.copyWith(soundEnabled: value));
                  },
                ),
                const Divider(height: 1.5),
                _tapRow(
                  title: '测试提醒',
                  subtitle: '立即发送一条通知并播放提示音',
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
                  const Divider(height: 1.5),
                  _tapRow(
                    title: '锁屏剩余时间',
                    subtitle: '计时运行时显示；OPPO 需允许锁屏通知与后台运行',
                    onTap: () => ForegroundRunner.requestBatteryExemption(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: '云端同步'),
          const SizedBox(height: 10),
          BrickCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        code.isEmpty ? '尚未生成同步码' : code,
                        style: brickNumberStyle(
                          fontSize: 13,
                          color: code.isEmpty ? PineColors.sub : PineColors.ink,
                        ),
                      ),
                    ),
                    BrickButton(
                      label: '',
                      semanticLabel: '复制同步码',
                      icon: Icons.copy,
                      expand: false,
                      height: 38,
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
                const SizedBox(height: 8),
                Text(
                  '最近上传：${_formatStamp(data.sync.lastUploadedAt)}',
                  style: const TextStyle(color: PineColors.sub, fontSize: 11),
                ),
                const SizedBox(height: 4),
                const Text(
                  '绑定同步码后：完成专注自动上传，回到 App 自动拉取',
                  style: TextStyle(color: PineColors.sub, fontSize: 11),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: BrickButton(
                        label: '上传本机数据',
                        height: 44,
                        onPressed: _syncBusy ? null : () => _runSync(_upload),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BrickButton(
                        label: '从云端恢复',
                        height: 44,
                        color: PineColors.card,
                        foregroundColor: PineColors.ink,
                        onPressed: _syncBusy ? null : () => _runSync(_restore),
                      ),
                    ),
                  ],
                ),
                if (_syncBusy) ...[
                  const SizedBox(height: 14),
                  const BrickProgress(value: 0.35, color: PineColors.gold),
                ],
                if (_syncMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: PineColors.tint(PineColors.gold),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _syncMessage,
                      style:
                          const TextStyle(color: PineColors.ink, fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _worker,
                  enabled: false,
                  style: const TextStyle(color: PineColors.sub, fontSize: 11),
                  decoration: const InputDecoration(
                    labelText: '同步服务地址',
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: '关于'),
          const SizedBox(height: 10),
          const BrickCard(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Text('版本',
                          style: TextStyle(color: PineColors.sub, fontSize: 13)),
                      Spacer(),
                      Text('v1.2.0 · 松林手帐',
                          style: TextStyle(
                              color: PineColors.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Divider(height: 1),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Text('数据',
                          style: TextStyle(color: PineColors.sub, fontSize: 13)),
                      Spacer(),
                      Text('本地优先 · 云端仅备份',
                          style: TextStyle(color: PineColors.ink, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: '本机数据'),
          const SizedBox(height: 10),
          BrickCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PineColors.tint(PineColors.focus),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '清空后将删除全部专注记录与统计；事件、今日清单、设置与云端备份不受影响。此操作不可撤销。',
                    style: TextStyle(color: PineColors.ink, fontSize: 13, height: 1.5),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _clearRecords,
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: PineColors.focus),
                    label: const Text(
                      '清空全部记录',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: PineColors.focus,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PineColors.focus,
                      backgroundColor: Colors.transparent,
                      side: const BorderSide(
                          color: PineColors.focus, width: 1.5),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 描边开关行。
  Widget _switchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        const TextStyle(color: PineColors.ink, fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        const TextStyle(color: PineColors.sub, fontSize: 11)),
              ],
            ),
          ),
          BrickSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  /// 可点的设置行，右侧箭头。
  Widget _tapRow({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return BrickPressable(
      onTap: onTap,
      shadowed: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          const TextStyle(color: PineColors.ink, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          const TextStyle(color: PineColors.sub, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: PineColors.sub),
          ],
        ),
      ),
    );
  }

  Widget _numberField(String label, TextEditingController controller) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: brickNumberStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixText: label.contains('次') ? null : '分',
        ),
      );
}
