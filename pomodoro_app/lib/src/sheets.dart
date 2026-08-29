import 'package:flutter/material.dart';

import 'engine.dart';
import 'models.dart';
import 'theme.dart';

typedef DataChanged = void Function(AppData data);

/// 专注事件管理：选择、新增、重命名、改色、删除。
Future<void> showTaskSheet(
  BuildContext context, {
  required AppData data,
  required DataChanged onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: PineColors.dark,
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
    var color = task?.color ?? kTaskPalette[_data.tasks.length % kTaskPalette.length].toARGB32();

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
              const SizedBox(height: 16),
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
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == swatch.toARGB32()
                                ? PineColors.ink
                                : Colors.transparent,
                            width: 2,
                          ),
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
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(context, (name, color));
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final (name, picked) = result;

    if (task == null) {
      _emit(_data.copyWith(tasks: [..._data.tasks, PineTask(name: name, color: picked)]));
      return;
    }

    final oldName = task.name;
    final tasks = _data.tasks
        .map((item) => item.id == task.id ? item.copyWith(name: name, color: picked) : item)
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除事件？'),
        content: Text('「${task.name}」会从列表移除，已产生的专注记录会保留在统计中。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final tasks = _data.tasks.where((item) => item.id != task.id).toList();
    final index = _data.selectedIndex.clamp(0, tasks.isEmpty ? 0 : tasks.length - 1);
    _emit(_data.copyWith(tasks: tasks, selectedIndex: index));
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _data.tasks;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  '专注事件',
                  style: TextStyle(color: PineColors.ink, fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _edit(null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新增'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: tasks.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  final selected = index == _data.selectedIndex;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: task.swatch, shape: BoxShape.circle),
                    ),
                    title: Text(
                      task.name,
                      style: TextStyle(
                        color: selected ? PineColors.ink : PineColors.paper,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        fontSize: 15,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _edit(task),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(task),
                        ),
                      ],
                    ),
                    onTap: () => _emit(_data.copyWith(selectedIndex: index)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    backgroundColor: PineColors.dark,
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
        .map((entry) => entry.id == item.id ? entry.copyWith(done: !entry.done) : entry)
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
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          14,
          18,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  '今日清单',
                  style: TextStyle(color: PineColors.ink, fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  '$done / ${items.length}',
                  style: const TextStyle(color: PineColors.muted, fontSize: 13),
                ),
                const Spacer(),
                const Text('长按照项可设为专注事件',
                    style: TextStyle(color: PineColors.muted, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Checkbox(
                      value: item.done,
                      onChanged: (_) => _toggle(item),
                    ),
                    title: Text(
                      item.text,
                      style: TextStyle(
                        color: item.done ? PineColors.muted : PineColors.paper,
                        fontSize: 14,
                        decoration: item.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(item),
                    ),
                    onLongPress: () => _focusOn(item),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
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
                SizedBox(
                  height: 46,
                  child: FilledButton(onPressed: _add, child: const Text('添加')),
                ),
              ],
            ),
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
    backgroundColor: PineColors.dark,
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
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          14,
          18,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '补记已完成事件',
              style: TextStyle(color: PineColors.ink, fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 12),
            TextField(
              controller: _minutes,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '专注时长', suffixText: '分钟', isDense: true),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule, size: 18),
              label: Text(
                '完成时间 ${_at.hour.toString().padLeft(2, '0')}:${_at.minute.toString().padLeft(2, '0')}',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('添加完成记录')),
          ],
        ),
      ),
    );
  }
}
