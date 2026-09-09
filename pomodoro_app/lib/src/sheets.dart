import 'package:flutter/material.dart';

import 'engine.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

typedef DataChanged = void Function(AppData data);

/// 底部弹窗统一把手：44×4 浅色圆角条。
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 44,
          height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: PineColors.line,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// 纸面 sheet 外壳：统一内边距、把手与标题行。
class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    this.trailing,
    required this.child,
  });

  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          14,
          18,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: PineColors.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// 确认对话框：纸面样式。破坏性操作用红字按钮（R2 语义）。
Future<bool> _confirmDanger(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        SizedBox(
          height: 40,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context, true),
            style: OutlinedButton.styleFrom(
              foregroundColor: PineColors.focus,
              backgroundColor: Colors.transparent,
              side: const BorderSide(color: PineColors.focus, width: 1.5),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: Text(confirmLabel),
          ),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// 专注事件管理：选择、新增、重命名、改色、删除。
Future<void> showTaskSheet(
  BuildContext context, {
  required AppData data,
  required DataChanged onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: PineColors.paper,
    builder: (context) => _TaskSheet(data: data, onChanged: onChanged),
  );
}

class _TaskSheet extends StatefulWidget {
  const _TaskSheet({required this.data, required this.onChanged});

  final AppData data;
  final DataChanged onChanged;

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late AppData _data;

  @override
  void initState() {
    super.initState();
    _data = widget.data;
  }

  void _emit(AppData next) {
    setState(() => _data = next);
    widget.onChanged(next);
  }

  Future<void> _edit(PineTask? task) async {
    final controller = TextEditingController(text: task?.name ?? '');
    var color = task?.color ??
        kTaskPalette[_data.tasks.length % kTaskPalette.length].toARGB32();

    final result = await showDialog<(String, int)?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, local) => AlertDialog(
          title: Text(task == null ? '新增专注事件' : '编辑事件'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: '事件名称'),
              ),
              const SizedBox(height: 18),
              // 8 色任务色板：选中者外圈松绿环，未选中浅描边。
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final swatch in kTaskPalette)
                    GestureDetector(
                      onTap: () => local(() => color = swatch.toARGB32()),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: swatch,
                          border: Border.all(
                            color: color == swatch.toARGB32()
                                ? PineColors.pine
                                : PineColors.line,
                            width: color == swatch.toARGB32() ? 2.5 : 1,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            SizedBox(
              height: 40,
              child: FilledButton(
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(context, (name, color));
                },
                style: FilledButton.styleFrom(
                  backgroundColor: PineColors.ink,
                  foregroundColor: PineColors.card,
                  textStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  shape: const StadiumBorder(),
                ),
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final (name, picked) = result;

    if (task == null) {
      _emit(_data.copyWith(
          tasks: [..._data.tasks, PineTask(name: name, color: picked)]));
      return;
    }

    final oldName = task.name;
    final tasks = _data.tasks
        .map((item) => item.id == task.id
            ? item.copyWith(name: name, color: picked)
            : item)
        .toList();

    // 重命名后同步历史记录，保持统计连贯。
    final records = _data.records
        .map((record) => record.taskName == oldName
            ? record.copyWith(taskName: name)
            : record)
        .toList();
    _emit(_data.copyWith(tasks: tasks, records: records));
  }

  Future<void> _delete(PineTask task) async {
    final confirmed = await _confirmDanger(
      context,
      title: '删除事件？',
      message: '「${task.name}」会从列表移除，已产生的专注记录会保留在统计中。',
      confirmLabel: '删除',
    );
    if (!confirmed) return;

    final tasks = _data.tasks.where((item) => item.id != task.id).toList();
    final index =
        _data.selectedIndex.clamp(0, tasks.isEmpty ? 0 : tasks.length - 1);
    _emit(_data.copyWith(tasks: tasks, selectedIndex: index));
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _data.tasks;
    return _SheetScaffold(
      title: '专注事件',
      trailing: BrickButton(
        label: '新增',
        icon: Icons.add,
        height: 36,
        color: PineColors.card,
        foregroundColor: PineColors.pine,
        onPressed: () => _edit(null),
      ),
      child: Flexible(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: tasks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final task = tasks[index];
            final selected = index == _data.selectedIndex;
            return _TaskRow(
              task: task,
              selected: selected,
              onTap: () {
                _emit(_data.copyWith(selectedIndex: index));
                // 选中即视为切换完成,自动收起返回主界面;
                // 新增/重命名/改色/删除等管理操作仍在 sheet 内进行。
                Navigator.pop(context);
              },
              onEdit: () => _edit(task),
              onDelete: () => _delete(task),
            );
          },
        ),
      ),
    );
  }
}

/// 事件行：纸面卡。选中 = 左侧 3px 事件色条 + 事件色浅底。
class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final PineTask task;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final swatch = task.swatch;
    return BrickPressable(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: selected ? PineColors.tint(swatch) : PineColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 48,
              color: selected ? swatch : Colors.transparent,
            ),
            const SizedBox(width: 12),
            Container(
              width: 12,
              height: 12,
              decoration:
                  BoxDecoration(color: swatch, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                task.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PineColors.ink, fontSize: 14),
              ),
            ),
            _GhostIcon(icon: Icons.edit_outlined, label: '编辑事件', onTap: onEdit),
            _GhostIcon(
                icon: Icons.delete_outline, label: '删除事件', onTap: onDelete),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// 行内小图标按钮：纸色圆钮。
class _GhostIcon extends StatelessWidget {
  const _GhostIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: BrickButton(
          label: '',
          semanticLabel: label,
          icon: icon,
          expand: false,
          height: 34,
          color: PineColors.paper,
          foregroundColor: PineColors.ink,
          onPressed: onTap,
        ),
      );
}

/// 今日清单。按当天日期保存。
Future<void> showTodoSheet(
  BuildContext context, {
  required AppData data,
  required DataChanged onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: PineColors.paper,
    builder: (context) => _TodoSheet(data: data, onChanged: onChanged),
  );
}

class _TodoSheet extends StatefulWidget {
  const _TodoSheet({required this.data, required this.onChanged});

  final AppData data;
  final DataChanged onChanged;

  @override
  State<_TodoSheet> createState() => _TodoSheetState();
}

class _TodoSheetState extends State<_TodoSheet> {
  late AppData _data;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _data = widget.data;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<TodoItem> get _items => _data.todos[dateKey(DateTime.now())] ?? [];

  void _emit(AppData next) {
    setState(() => _data = next);
    widget.onChanged(next);
  }

  void _add() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final key = dateKey(DateTime.now());
    final items = [..._items, TodoItem(text: text)];
    final todos = Map<String, List<TodoItem>>.from(_data.todos)..[key] = items;
    _controller.clear();
    _emit(_data.copyWith(todos: todos));
  }

  void _toggle(TodoItem item) {
    final key = dateKey(DateTime.now());
    final items = _items
        .map((entry) =>
            entry.id == item.id ? entry.copyWith(done: !entry.done) : entry)
        .toList();
    final todos = Map<String, List<TodoItem>>.from(_data.todos)..[key] = items;
    _emit(_data.copyWith(todos: todos));
  }

  void _remove(TodoItem item) {
    final key = dateKey(DateTime.now());
    final items = _items.where((entry) => entry.id != item.id).toList();
    final todos = Map<String, List<TodoItem>>.from(_data.todos)..[key] = items;
    _emit(_data.copyWith(todos: todos));
  }

  void _focusOn(TodoItem item) {
    final name = item.text;
    final index = _data.tasks.indexWhere((task) => task.name == name);
    if (index >= 0) {
      _emit(_data.copyWith(selectedIndex: index));
      Navigator.pop(context);
      return;
    }
    _emit(_data.copyWith(
      tasks: [..._data.tasks, PineTask(name: name)],
      selectedIndex: _data.tasks.length,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final done = items.where((item) => item.done).length;
    return _SheetScaffold(
      title: '今日清单',
      trailing: Text(
        '$done / ${items.length}',
        style: brickNumberStyle(fontSize: 12, color: PineColors.sub),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isNotEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('长按照项可设为专注事件',
                  style: TextStyle(color: PineColors.sub, fontSize: 11)),
            ),
          const SizedBox(height: 10),
          if (items.isNotEmpty)
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _TodoRow(
                    item: item,
                    onToggle: () => _toggle(item),
                    onRemove: () => _remove(item),
                    onFocus: () => _focusOn(item),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: '添加一项待办',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 10),
              BrickButton(
                label: '添加',
                height: 46,
                color: PineColors.pine,
                foregroundColor: PineColors.card,
                onPressed: _add,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({
    required this.item,
    required this.onToggle,
    required this.onRemove,
    required this.onFocus,
  });

  final TodoItem item;
  final VoidCallback onToggle;
  final VoidCallback onRemove;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    return BrickPressable(
      onTap: null,
      onLongPress: onFocus,
      semanticLabel: '设为专注事件 ${item.text}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: item.done ? PineColors.tint(PineColors.pine) : PineColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Checkbox(
                value: item.done,
                onChanged: (_) => onToggle(),
                visualDensity: VisualDensity.compact,
              ),
            ),
            Expanded(
              child: Text(
                item.text,
                style: TextStyle(
                  color: item.done ? PineColors.sub : PineColors.ink,
                  fontSize: 14,
                  decoration: item.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            _GhostIcon(
                icon: Icons.delete_outline, label: '删除待办', onTap: onRemove),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

/// 补记已完成事件。
Future<void> showManualSheet(
  BuildContext context, {
  required AppData data,
  required DataChanged onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: PineColors.paper,
    builder: (context) => _ManualSheet(data: data, onChanged: onChanged),
  );
}

class _ManualSheet extends StatefulWidget {
  const _ManualSheet({required this.data, required this.onChanged});

  final AppData data;
  final DataChanged onChanged;

  @override
  State<_ManualSheet> createState() => _ManualSheetState();
}

class _ManualSheetState extends State<_ManualSheet> {
  final _minutes = TextEditingController();
  late String _taskName;
  late DateTime _at;

  @override
  void initState() {
    super.initState();
    _minutes.text = widget.data.settings.focus.toString();
    _taskName = widget.data.selectedTask.name;
    _at = DateTime.now();
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (time == null) return;
    setState(() {
      _at = DateTime(_at.year, _at.month, _at.day, time.hour, time.minute);
    });
  }

  void _save() {
    final minutes = double.tryParse(_minutes.text);
    if (minutes == null || minutes <= 0) return;
    final next = TimerEngine.addManual(
      widget.data,
      taskName: _taskName,
      minutes: minutes,
      at: _at,
    );
    widget.onChanged(next);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.data.tasks;
    return _SheetScaffold(
      title: '补记已完成事件',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _taskName,
            decoration: const InputDecoration(labelText: '专注事件', isDense: true),
            items: [
              for (final task in tasks)
                DropdownMenuItem<String>(
                  value: task.name,
                  child: Text(task.name),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _taskName = value);
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _minutes,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: brickNumberStyle(fontSize: 14),
            decoration: const InputDecoration(
                labelText: '专注时长', suffixText: '分钟', isDense: true),
          ),
          const SizedBox(height: 14),
          BrickButton(
            label:
                '完成时间 ${_at.hour.toString().padLeft(2, '0')}:${_at.minute.toString().padLeft(2, '0')}',
            icon: Icons.schedule,
            color: PineColors.card,
            foregroundColor: PineColors.ink,
            onPressed: _pickTime,
          ),
          const SizedBox(height: 10),
          BrickButton(
            label: '添加完成记录',
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// 状态徽章（记录详情用）。
Color _badgeColor(RecordStatus status) {
  switch (status) {
    case RecordStatus.completed:
    case RecordStatus.manual:
      return PineColors.tint(PineColors.pine);
    case RecordStatus.paused:
      return PineColors.tint(PineColors.gold);
    case RecordStatus.interrupted:
      return PineColors.tint(PineColors.faint);
    case RecordStatus.inProgress:
      return PineColors.tint(PineColors.focus);
  }
}

/// 记录详情：只读展示一条专注记录（D2），可删除。
Future<void> showRecordDetailSheet(
  BuildContext context, {
  required AppData data,
  required FocusRecord record,
  required Color color,
  required DataChanged onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: PineColors.paper,
    builder: (context) => _RecordDetailSheet(
      data: data,
      record: record,
      color: color,
      onChanged: onChanged,
    ),
  );
}

class _RecordDetailSheet extends StatelessWidget {
  const _RecordDetailSheet({
    required this.data,
    required this.record,
    required this.color,
    required this.onChanged,
  });

  final AppData data;
  final FocusRecord record;
  final Color color;
  final DataChanged onChanged;

  @override
  Widget build(BuildContext context) {
    final at = record.at.toLocal();
    return _SheetScaffold(
      title: '记录详情',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: _badgeColor(record.status),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          record.status.label,
          style: const TextStyle(
            color: PineColors.ink,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailRow(
            label: '专注事件',
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    record.taskName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: PineColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          _DetailRow(
            label: '时长',
            child: Text(formatMinutes(record.minutes),
                style: brickNumberStyle(fontSize: 14)),
          ),
          _DetailRow(
            label: '完成于',
            child: Text(
              '${at.month}月${at.day}日 ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
              style: brickNumberStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () => _delete(context),
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: PineColors.focus),
              label: const Text(
                '删除这条记录',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: PineColors.focus,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: PineColors.focus,
                backgroundColor: Colors.transparent,
                side: const BorderSide(color: PineColors.focus, width: 1.5),
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await _confirmDanger(
      context,
      title: '删除这条记录？',
      message: '「${record.taskName}」${formatMinutes(record.minutes)} 会从统计中移除。',
      confirmLabel: '删除',
    );
    if (!confirmed) return;
    final next = data.copyWith(
      records: data.records.where((item) => item.id != record.id).toList(),
    );
    onChanged(next);
    if (context.mounted) Navigator.pop(context);
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                label,
                style:
                    const TextStyle(color: PineColors.sub, fontSize: 13),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      );
}
