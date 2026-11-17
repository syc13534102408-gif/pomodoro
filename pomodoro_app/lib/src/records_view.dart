import 'package:flutter/material.dart';

import 'engine.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

String recordTimestamp(DateTime value) {
  final at = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${ymdOf(at)} ${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
}

/// 双时间字段是独立事实：dayKey 不从完成时刻重新推导。
class RecordFactTile extends StatelessWidget {
  const RecordFactTile(
      {super.key, required this.data, required this.record, this.onTap});
  final AppData data;
  final FocusRecord record;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final event = data.events.where((e) => e.id == record.eventId).firstOrNull;
    final task = data.tasks.where((t) => t.name == record.taskName).firstOrNull;
    final crossDay = ymdOf(record.at.toLocal()) != record.dayKey;
    return SettledCard(
        onTap: onTap,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                  spacing: PineSpacing.section,
                  runSpacing: PineSpacing.near,
                  alignment: WrapAlignment.start,
                  children: [
                    Text(formatHoursMinutes(record.minutes),
                        style: PineText.sans(
                            color: palette.textPrimary,
                            weight: FontWeight.w600,
                            height: PineLineHeight.body)),
                    if (record.taskName.isNotEmpty)
                      TaskIdentityBadge(
                          taskName: record.taskName,
                          color: task == null
                              ? palette.taskColors.first
                              : Color(task.color))
                    else
                      Text('无任务',
                          style: PineText.sans(color: palette.textSecondary)),
                  ]),
              const SizedBox(height: PineSpacing.near),
              Text('归属事件：${event?.name ?? '无事件'}',
                  style: PineText.sans(
                      size: PineType.auxiliary,
                      color: palette.textSecondary,
                      height: PineLineHeight.auxiliary)),
              const SizedBox(height: PineSpacing.section),
              Text('所属日期：${record.dayKey}',
                  style: PineText.sans(
                      size: PineType.auxiliary,
                      color: palette.textAuxiliary,
                      height: PineLineHeight.auxiliary)),
              Text('完成时刻：${recordTimestamp(record.at)}',
                  style: PineText.mono(
                      size: PineType.auxiliary,
                      color: palette.textAuxiliary,
                      height: PineLineHeight.auxiliary)),
              if (crossDay) ...[
                const SizedBox(height: PineSpacing.near),
                Text('完成时刻已跨日，所属日期仍按本段开始时刻计算',
                    style: PineText.sans(
                        size: PineType.auxiliary,
                        color: palette.textAuxiliary,
                        height: PineLineHeight.auxiliary)),
              ],
            ]));
  }
}

class RecordsPanel extends StatelessWidget {
  const RecordsPanel(
      {super.key,
      required this.data,
      required this.onEdit,
      required this.onAdd});
  final AppData data;
  final ValueChanged<FocusRecord> onEdit;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final records = data.records.where((r) => r.counted).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    final groups = <String, List<FocusRecord>>{};
    for (final record in records) {
      groups.putIfAbsent(record.dayKey, () => []).add(record);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(PineSpacing.section,
              PineSpacing.section, PineSpacing.section, PineSpacing.near),
          child: Row(children: [
            Expanded(
                child: Text('全部记录',
                    style: PineText.serif(
                        size: PineType.aggregate,
                        color: palette.textPrimary,
                        weight: FontWeight.w600,
                        height: PineLineHeight.aggregate))),
            TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: PineSize.stateGraphic),
                label: const Text('补记')),
          ])),
      Expanded(
          child: ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: PineSpacing.section),
              children: [
            Text(
                '${records.length} 条 · 合计 ${formatHoursMinutes(records.fold<double>(0, (sum, r) => sum + r.minutes))}',
                style: PineText.sans(
                    size: PineType.auxiliary, color: palette.textSecondary)),
            const SizedBox(height: PineSpacing.section),
            if (records.isEmpty)
              const SettledVariantSurface(child: Text('还没有记录'))
            else ...[
              const FactSectionHeader(title: '最近完成'),
              const SizedBox(height: PineSpacing.near),
              RecordFactTile(
                  data: data,
                  record: records.first,
                  onTap: () => onEdit(records.first)),
              const SizedBox(height: PineSpacing.far),
              for (final day in days) ...[
                LogicalDayDivider(
                    dateLabel: '所属日期 $day',
                    auxiliaryLabel: '${groups[day]!.length} 条'),
                const SizedBox(height: PineSpacing.near),
                for (final record in groups[day]!) ...[
                  RecordFactTile(
                      key: ValueKey('record-${record.id}'),
                      data: data,
                      record: record,
                      onTap: () => onEdit(record)),
                  if (record != groups[day]!.last)
                    const SizedBox(height: PineSpacing.near),
                ],
                const SizedBox(height: PineSpacing.far),
              ],
            ],
          ])),
    ]);
  }
}

/// 编辑语境调用现有引擎；控制器归组件所有，关闭过渡期间不提前释放。
class RecordEditor extends StatefulWidget {
  const RecordEditor(
      {super.key,
      required this.data,
      required this.onSaved,
      this.record,
      this.now});
  final AppData data;
  final ValueChanged<AppData> onSaved;
  final FocusRecord? record;
  final DateTime? now;
  @override
  State<RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<RecordEditor> {
  late final _minutes = TextEditingController(
      text:
          widget.record?.minutes.toString() ?? '${widget.data.settings.focus}');
  late final _timestamp = TextEditingController(
      text: recordTimestamp(widget.record?.at ?? widget.now ?? DateTime.now()));
  late String _task = widget.record?.taskName ?? widget.data.selectedTask.name;
  late String _event = widget.record?.eventId ?? '';
  String? get _durationError {
    final minutes = num.tryParse(_minutes.text.trim());
    return minutes == null ||
            !minutes.isFinite ||
            minutes <= 0 ||
            minutes != minutes.roundToDouble()
        ? '时长需为大于零的整数分钟'
        : null;
  }

  DateTime? get _at {
    final text = _timestamp.text.trim();
    final parsed = DateTime.tryParse(text);
    // tryParse 会把 2 月 30 日进位；表单必须拒绝不存在的日历时刻。
    return parsed != null && recordTimestamp(parsed) == text ? parsed : null;
  }

  String? get _timeError => _at == null
      ? '请填写时刻'
      : _at!.isAfter(widget.now ?? DateTime.now())
          ? '时刻不得晚于当前时刻'
          : null;
  @override
  void dispose() {
    _minutes.dispose();
    _timestamp.dispose();
    super.dispose();
  }

  void _save() {
    if (_durationError != null || _timeError != null) return;
    final minutes = double.parse(_minutes.text.trim());
    var next = widget.record == null
        ? TimerEngine.addManual(widget.data,
            taskName: _task, minutes: minutes, at: _at!)
        : TimerEngine.updateRecord(widget.data, widget.record!.id,
            taskName: _task,
            minutes: minutes,
            at: _timestamp.text == recordTimestamp(widget.record!.at)
                ? null
                : _at);
    next = TimerEngine.setRecordEvent(
        next,
        widget.record?.id ?? next.records.first.id,
        _event.isEmpty ? null : _event);
    widget.onSaved(next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    final taskNames = <String>{
      '',
      _task,
      for (final task in widget.data.tasks) task.name
    };
    final events = <String, String>{
      '': '不归属事件',
      for (final event in widget.data.events
          .where((e) => e.taskName == _task || e.taskName.isEmpty))
        event.id: event.name
    };
    if (!events.containsKey(_event)) events[_event] = '与当前任务不匹配的旧事件';
    return SingleChildScrollView(
        padding: const EdgeInsets.all(PineSpacing.section),
        child: SettledVariantSurface(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Text(widget.record == null ? '补记记录' : '编辑记录',
                  style: PineText.serif(
                      size: PineType.aggregate,
                      color: palette.textPrimary,
                      height: PineLineHeight.aggregate)),
              const SizedBox(height: PineSpacing.section),
              TextField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      labelText: '时长',
                      suffixText: '分钟',
                      errorText: _durationError)),
              const SizedBox(height: PineSpacing.section),
              TextField(
                  controller: _timestamp,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      labelText: widget.record == null ? '时刻' : '完成时刻',
                      helperText: 'YYYY-MM-DD HH:mm:ss',
                      errorText: _timeError)),
              const SizedBox(height: PineSpacing.near),
              Text(
                  widget.record == null
                      ? '所属日期按该时刻所属的逻辑日确定，无需另选日期。'
                      : '所属日期：${_timestamp.text == recordTimestamp(widget.record!.at) ? widget.record!.dayKey : _at == null ? '—' : dateKey(_at!)}',
                  style: PineText.sans(
                      size: PineType.auxiliary,
                      color: palette.textSecondary,
                      height: PineLineHeight.auxiliary)),
              const SizedBox(height: PineSpacing.section),
              DropdownButtonFormField<String>(
                  initialValue: _task,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '归属任务'),
                  items: [
                    for (final name in taskNames)
                      DropdownMenuItem(
                          value: name, child: Text(name.isEmpty ? '无任务' : name))
                  ],
                  onChanged: (value) => setState(() {
                        _task = value ?? '';
                        _event = '';
                      })),
              const SizedBox(height: PineSpacing.section),
              DropdownButtonFormField<String>(
                  key: ValueKey('event-$_task-$_event'),
                  initialValue: _event,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '归属事件'),
                  items: [
                    for (final entry in events.entries)
                      DropdownMenuItem(
                          value: entry.key, child: Text(entry.value))
                  ],
                  onChanged: (value) => setState(() => _event = value ?? '')),
              const SizedBox(height: PineSpacing.section),
              PineButton(
                  label: widget.record == null ? '保存补记' : '保存',
                  onPressed: _durationError == null && _timeError == null
                      ? _save
                      : null),
            ])));
  }
}
