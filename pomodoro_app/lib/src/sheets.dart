import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../pages/ledger_page.dart';
import 'records_view.dart';
import 'engine.dart';
import 'models.dart';
import 'plan_import.dart';
import 'plan_remote.dart';
import 'theme.dart';
import 'widgets.dart';

typedef DataChanged = void Function(AppData data);

/// 底部弹窗统一把手：44×4 装帧线色圆角条（沿用既有尺寸，不重做几何）。
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 44,
          height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: PineColors.lineStrong,
            borderRadius: BorderRadius.circular(PineRadius.seal),
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
            // 卷首 14px 檀褐短横定界（V3 素纸弹层 anatomy）。
            Container(
              width: 14,
              height: 2,
              decoration: BoxDecoration(
                color: PineColors.accent,
                borderRadius: BorderRadius.circular(PineRadius.seal),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: PineText.serif(
                      size: PineType.body,
                      weight: FontWeight.w500,
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
              textStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
      trailing: PineButton(
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
    return PinePressable(
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
              decoration: BoxDecoration(color: swatch, shape: BoxShape.circle),
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
        child: PineButton(
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
        style: pineNumberStyle(fontSize: 12, color: PineColors.sub),
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
              PineButton(
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
    this.onFocus,
  });

  final TodoItem item;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  /// 长按「设为专注事件」。日程面板不提供该动作（会给每条待办建一个任务），传 null 即可。
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    final row = PinePressable(
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
              icon: Icons.delete_outline,
              label: '删除待办',
              onTap: onRemove,
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
    return row;
  }
}

/// 日程事实行：消费沉淀表面，保留既有编辑、删除与勾选入口。
class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.item,
    required this.onToggle,
    required this.onRemove,
    required this.onEdit,
    required this.onMenu,
  });
  final TodoItem item;
  final VoidCallback onToggle, onRemove, onEdit;
  final void Function(Offset) onMenu;
  @override
  Widget build(BuildContext context) {
    final palette = PinePalette.of(context);
    return GestureDetector(
      onSecondaryTapDown: (details) => onMenu(details.globalPosition),
      child: PinePressable(
        onTap: null,
        onLongPress: onEdit,
        semanticLabel: '编辑或长按修改：${item.text}',
        child: SettledVariantSurface(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Checkbox(value: item.done, onChanged: (_) => onToggle()),
              ),
              Expanded(
                child: Text(
                  item.text,
                  style:
                      PineText.sans(
                        height: PineLineHeight.body,
                        color: item.done
                            ? palette.textSecondary
                            : palette.textPrimary,
                      ).copyWith(
                        decoration: item.done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                ),
              ),
              IconButton(
                tooltip: '编辑内容',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                tooltip: '删除待办',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 编辑日程/待办文本。返回 null 表示取消，返回空串表示用户清空了内容（调用方应忽略）。
///
/// 独立成 StatefulWidget 是刻意的：controller 必须跟着对话框一起 dispose，
/// 在 `await showDialog` 之后立刻 dispose 会在关闭动画里抛 used-after-disposed（2026-10-23 踩过）。
Future<String?> showTodoEditDialog(
  BuildContext context, {
  required String initialText,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TodoEditDialog(initialText: initialText),
  );
}

class _TodoEditDialog extends StatefulWidget {
  const _TodoEditDialog({required this.initialText});

  final String initialText;

  @override
  State<_TodoEditDialog> createState() => _TodoEditDialogState();
}

class _TodoEditDialogState extends State<_TodoEditDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PineColors.card,
      title: const Text('编辑内容',
          style: TextStyle(
              color: PineColors.ink, fontSize: 17, fontWeight: FontWeight.w600)),
      // 对话框按内在宽度测量：给固定宽度，别让 TextField 参与无界测量（docs/07 §7）。
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(isDense: true),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消', style: TextStyle(color: PineColors.sub)),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('保存',
              style:
                  TextStyle(color: PineColors.pine, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// 日程条目的桌面右键菜单（编辑/删除）。
///
/// macOS 上"长按"是触摸屏姿势，鼠标用户不会那么操作（2026-10-26 反馈）；
/// 桌面端改用系统习惯的右键菜单，长按仍然留给手机。
Future<void> showPlanItemMenu(
  BuildContext context,
  Offset globalPosition, {
  required VoidCallback onEdit,
  required VoidCallback onRemove,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    ),
    items: const [
      PopupMenuItem<String>(value: 'edit', child: Text('编辑内容')),
      PopupMenuItem<String>(value: 'delete', child: Text('删除')),
    ],
  );
  if (action == 'edit') onEdit();
  if (action == 'delete') onRemove();
}

/// 对 todos 的一次变换。父级拿**最新** `_data` 去套，而不是用面板打开时的快照整份回写
/// （面板存活期间可能发生云端采纳，整份回写会把刚拉到的数据顶掉）。
typedef TodosTransform = Map<String, List<TodoItem>> Function(
    Map<String, List<TodoItem>> todos);

/// 日程：跨天待办的多日视图 + 文本导入。
///
/// 与「今日清单」的分工：那份只渲染 `dateKey(now)` 一天（且自 2026-09-09 起无入口），
/// 日程要一次看多天、按**目标日**落地。
///
/// **日期键用自然日 `ymdOf(目标日)`，不套凌晨 3 点的统计日口径**——否则凌晨排
/// 「明天」的任务会掉进昨天（见 plan_import.dart 的口径说明）。
/// 日程面板（2026-11-03 重构）：**日期条 + 单日清单**，不再是"一长条 8 天"。
///
/// 两端共用：手机在底部弹层里，桌面在右侧抽屉里（与统计/设置同一套机制）。
/// 需要**有界高度**（内部用 Expanded 撑列表区），调用方负责给高度。
class PlanPanel extends StatefulWidget {
  const PlanPanel({
    super.key,
    required this.data,
    required this.onApply,
    this.now,
    this.remote,
    this.showTitle = true,
  });

  final AppData data;
  final ValueChanged<TodosTransform> onApply;
  final DateTime? now;

  /// 测试注入用；为 null 时走真实的 [PlanRemote]。
  final Future<String> Function(String text)? remote;

  /// 手机弹层自带标题栏时为 false；桌面抽屉里自带标题。
  final bool showTitle;

  @override
  State<PlanPanel> createState() => _PlanPanelState();
}

class _PlanPanelState extends State<PlanPanel> {
  late final DateTime _now = widget.now ?? DateTime.now();
  late Map<String, List<TodoItem>> _todos;
  final _controller = TextEditingController();
  final _stripScroll = ScrollController();
  late String _selectedKey = _todayKey;

  /// 日期格宽与格间距，必须与 [_dateStrip] 里的 `width: _chipWidth` / `SizedBox(width: 8)`
  /// 一致——自动滚动按它们算每格的左边界。
  static const double _chipWidth = 96;
  static const double _chipGap = 8;

  /// 上一次同步过滚动位置时的「选中日 + 日期条格数」。
  ///
  /// 只在两者变化时同步：否则用户手动把日期条滚到上个月，任何一次重建
  /// （打勾、切页）都会被拽回今天。
  String? _stripSyncedKey;
  int _stripSyncedCount = -1;

  /// 是否已经做过第一次落位（第一次用直接跳，之后才用动画）。
  bool _stripJumpedOnce = false;

  String get _todayKey => ymdOf(dayStart(_now));

  @override
  void initState() {
    super.initState();
    _todos = {
      for (final entry in widget.data.todos.entries)
        entry.key: List<TodoItem>.of(entry.value),
    };
  }

  @override
  void didUpdateWidget(covariant PlanPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data.todos, widget.data.todos)) {
      _todos = {
        for (final entry in widget.data.todos.entries)
          entry.key: List<TodoItem>.of(entry.value),
      };
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _stripScroll.dispose();
    super.dispose();
  }

  void _apply(TodosTransform transform) {
    setState(() => _todos = transform(_todos));
    widget.onApply(transform);
  }

  /// 日期条只展示所有有内容的日子，空的今天也不补入。
  /// 空档期（比如只排了周五周六）不会出现一排空格子。
  ///
  /// 2026-11-06 起不再过滤 `key < 今天`：回看往期日程是刚需（核对这周到底
  /// 落了哪些），而"只有今天及以后"是当初误把日期条当"待办"而非"日历"。
  List<String> get _dayKeys {
    final keys = <String>{};
    for (final entry in _todos.entries) {
      if (entry.value.isEmpty) continue;
      keys.add(entry.key);
    }
    final list = keys.toList()..sort();
    return list;
  }

  /// 把选中的日期格滚进视野（只在它没被完整看见时才滚，避免点一下就跳）。
  ///
  /// 默认停在今天，目标位置刻意比左边缘多让 56pt：这样左边会露出前一天
  /// 的小半格——用户一眼就知道"还能往左翻"，而不会以为日期条只有今天。
  void _syncStripToSelected(List<String> keys) {
    if (_stripSyncedKey == _selectedKey && _stripSyncedCount == keys.length) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_stripScroll.hasClients) return;
      final position = _stripScroll.position;
      if (!position.hasContentDimensions) return;
      final index = keys.indexOf(_selectedKey);
      if (index < 0) return;
      // 走到这里才记账：布局还没完成就返回时，下一帧还有机会再滚一次。
      _stripSyncedKey = _selectedKey;
      _stripSyncedCount = keys.length;
      final left = index * (_chipWidth + _chipGap);
      final right = left + _chipWidth;
      final viewStart = position.pixels;
      final viewEnd = viewStart + position.viewportDimension;
      // 已完整可见就不动：否则用户点一下右边刚露头的格子，整条会突然平移。
      if (left >= viewStart && right <= viewEnd) return;
      final target = (left - 56).clamp(0.0, position.maxScrollExtent);
      if (!_stripJumpedOnce || MediaQuery.disableAnimationsOf(context)) {
        // 首次落位直接跳：有几十天往期时，从最老一天"滑"到今天会是 220ms 的拖影。
        _stripJumpedOnce = true;
        position.jumpTo(target);
        return;
      }
      _stripScroll.animateTo(
        target,
        duration: PineMotion.standard,
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// 勾选即重排：完成的按勾选顺序浮到顶部（见 toggleTodoDone）。
  void _toggle(String dayKey, TodoItem item) => _apply(
    (todos) => {
      ...todos,
      dayKey: toggleTodoDone(todos[dayKey] ?? const <TodoItem>[], item.id),
    },
  );

  void _remove(String dayKey, TodoItem item) => _apply(
    (todos) => {
      ...todos,
      dayKey: [
        for (final entry in todos[dayKey] ?? const <TodoItem>[])
          if (entry.id != item.id) entry,
      ],
    },
  );

  /// 长按编辑：只改文本，id/勾选状态/所属日期都不动。
  Future<void> _editItem(String dayKey, TodoItem item) async {
    final text = await showTodoEditDialog(context, initialText: item.text);
    if (text == null || text.isEmpty) return;
    _apply(
      (todos) => {
        ...todos,
        dayKey: [
          for (final entry in todos[dayKey] ?? const <TodoItem>[])
            entry.id == item.id ? entry.copyWith(text: text) : entry,
        ],
      },
    );
  }

  void _addToSelected() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _apply(
      (todos) => {
        ...todos,
        _selectedKey: [
          ...todos[_selectedKey] ?? const <TodoItem>[],
          TodoItem(text: text),
        ],
      },
    );
  }

  Future<void> _openImport() async {
    // 对话框自己持有 TextEditingController：如果在这里建、这里 dispose，
    // 关闭动画还在用它就会抛 "used after being disposed"。
    final plan = await showDialog<PlanParseResult>(
      context: context,
      builder: (_) => _PlanImportDialog(now: _now, remote: widget.remote),
    );
    if (plan == null || plan.isEmpty) return;

    late PlanMergeResult merged;
    _apply((todos) {
      merged = mergePlanIntoTodos(todos, plan);
      return merged.todos;
    });
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          '已导入 ${merged.added} 条'
          '${merged.duplicated == 0 ? '' : '（跳过 ${merged.duplicated} 条重复）'}',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final palette = PinePalette.of(context);
        final desktop =
            Theme.of(context).platform == TargetPlatform.macOS ||
            Theme.of(context).platform == TargetPlatform.windows ||
            Theme.of(context).platform == TargetPlatform.linux;
        final rowMinimum = desktop ? 56.0 : 64.0;
        // 长文本增加行高，不以省略号或缩字号换取固定高度。
        final textWidth = (constraints.maxWidth - 154).clamp(80.0, 800.0);
        final rowHeight = (_todos[_selectedKey] ?? const <TodoItem>[])
            .fold<double>(rowMinimum, (height, item) {
              final painter = TextPainter(
                text: TextSpan(
                  text: item.text,
                  style: PineText.sans(height: PineLineHeight.body),
                ),
                textDirection: Directionality.of(context),
              )..layout(maxWidth: textWidth);
              final needed = painter.height + 24;
              return needed > height ? needed : height;
            });
        final keys = _dayKeys;
        if (!keys.contains(_selectedKey)) _selectedKey = _todayKey;
        _syncStripToSelected(keys);
        final items = _todos[_selectedKey] ?? const <TodoItem>[];
        final totalItems = _todos.values.fold<int>(
          0,
          (sum, list) => sum + list.length,
        );
        final doneItems = _todos.values.fold<int>(
          0,
          (sum, list) => sum + list.where((item) => item.done).length,
        );
        final scheduledDays = _todos.values
            .where((list) => list.isNotEmpty)
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showTitle)
              Row(
                children: [
                  Text(
                    '日程',
                    style: PineText.sans(
                      size: PineType.body,
                      color: palette.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  PineButton(
                    label: '导入',
                    icon: Icons.file_upload_outlined,
                    expand: false,
                    height: desktop ? 32 : 48,
                    color: palette.surface,
                    foregroundColor: palette.textPrimary,
                    onPressed: _openImport,
                  ),
                ],
              ),
            if (widget.showTitle) const SizedBox(height: 10),
            _dateStrip(keys),
            const SizedBox(height: 8),
            Text(
              '所选日期：$_selectedKey',
              style: PineText.sans(
                size: PineType.auxiliary,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? _emptyDay()
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        SettledTodoRows(
                          items: items,
                          rowHeight: rowHeight + 6,
                          itemBuilder: (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _ScheduleRow(
                              item: item,
                              onToggle: () => _toggle(_selectedKey, item),
                              onRemove: () => _remove(_selectedKey, item),
                              onEdit: () => _editItem(_selectedKey, item),
                              onMenu: (position) => showPlanItemMenu(
                                context,
                                position,
                                onEdit: () => _editItem(_selectedKey, item),
                                onRemove: () => _remove(_selectedKey, item),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: PineText.sans(color: palette.textPrimary),
                    decoration: InputDecoration(
                      hintText: '加到 ${_shortLabel(_selectedKey)}',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addToSelected(),
                  ),
                ),
                const SizedBox(width: 8),
                PineButton(
                  label: '添加',
                  icon: Icons.add,
                  expand: false,
                  height: desktop ? 44 : 52,
                  color: palette.textPrimary,
                  onPressed: _addToSelected,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '已排 $scheduledDays 天 · 共 $totalItems 条 · 完成 $doneItems 条',
              style: PineText.sans(
                size: PineType.auxiliary,
                color: palette.textAuxiliary,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 日期序列仅有内容日期；键盘、触摸及鼠标均可选择。
  Widget _dateStrip(List<String> keys) {
    final palette = PinePalette.of(context);
    final desktop =
        Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.linux;
    return SizedBox(
      height: desktop ? 56 : 64,
      child: ScrollConfiguration(
        behavior: const _DragAllScrollBehavior(),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          controller: _stripScroll,
          itemCount: keys.length,
          padding: EdgeInsets.zero,
          separatorBuilder: (_, __) => const SizedBox(width: _chipGap),
          itemBuilder: (context, index) {
            final key = keys[index];
            final list = _todos[key]!;
            final selected = key == _selectedKey;
            return SizedBox(
              width: _chipWidth,
              child: PinePressable(
                onTap: () => setState(() => _selectedKey = key),
                semanticLabel: '选择日期 $key',
                child: SettledVariantSurface(
                  padding: EdgeInsets.zero,
                  borderColor: selected ? palette.textPrimary : palette.divider,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _shortLabel(key),
                        style: PineText.sans(color: palette.textPrimary),
                      ),
                      Text(
                        '${list.where((item) => item.done).length}/${list.length}',
                        style: PineText.sans(
                          size: PineType.auxiliary,
                          color: palette.textAuxiliary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _emptyDay() => Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: const EdgeInsets.only(top: PineSpacing.section),
      child: Text(
        _dayKeys.isEmpty ? '还没有日程' : '这一天没有待办',
        style: PineText.sans(color: PinePalette.of(context).textSecondary),
      ),
    ),
  );

  String _shortLabel(String key) {
    final day = DateTime.tryParse(key);
    if (day == null) return key;
    if (key == _todayKey) return '今天';
    return '${day.month}/${day.day}';
  }
}

/// 让横向日期条在桌面端也能**用鼠标拖着走**。
///
/// Flutter 的默认 `ScrollBehavior.dragDevices` 只有 touch/stylus/trackpad 之类，
/// 不含 `mouse`——桌面端于是只能靠滚轮/两指滑，按住拖是没反应的。
/// 这里只加 mouse 一项，其余沿用父类（手机端行为完全不变）。
class _DragAllScrollBehavior extends MaterialScrollBehavior {
  const _DragAllScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices =>
      {...super.dragDevices, PointerDeviceKind.mouse};
}

/// 底部弹层形态（手机）：面板 + 拖拽把手，高度按屏幕 62% 封顶。
Future<void> showPlanSheet(
  BuildContext context, {
  required AppData data,
  required ValueChanged<TodosTransform> onApply,
  DateTime? now,
  Future<String> Function(String text)? remote,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: PineColors.paper,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          10,
          18,
          14 + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHandle(),
            const SizedBox(height: 8),
            SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.62,
              child: PlanPanel(
                data: data,
                onApply: onApply,
                now: now,
                remote: remote,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 导入对话框：粘贴 → 实时预览天数/条数/跳过行 → 确认返回解析结果。
class _PlanImportDialog extends StatefulWidget {
  const _PlanImportDialog({required this.now, this.remote});

  final DateTime now;
  final Future<String> Function(String text)? remote;

  @override
  State<_PlanImportDialog> createState() => _PlanImportDialogState();
}

class _PlanImportDialogState extends State<_PlanImportDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  /// 交给服务端（`/plan/parse`）把散文/网页计划抽成标准日程文本；
  /// 成功后就地替换输入框内容，用户仍能在预览里核对后再导入。
  Future<void> _autoParse() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final parse = widget.remote ?? PlanRemote().parse;
      final result = await parse(text);
      if (!mounted) return;
      setState(() => _controller.text = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsed = parsePlan(_controller.text, now: widget.now);
    return AlertDialog(
      backgroundColor: PineColors.card,
      title: const Text('导入日程',
          style: TextStyle(
              color: PineColors.ink, fontSize: 17, fontWeight: FontWeight.w600)),
      // 固定宽高：AlertDialog 按内在尺寸测量，TextField 在里面会把高度算成天文数字
      // （实测溢出差 9 万像素），必须给它一个有界盒子（docs/07 §7 #3 同类坑）。
      content: SizedBox(
        width: 320,
        height: 372,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '一行一条，日期在前：10/24 2018 复盘（也接受 2026-10-24）',
              style: TextStyle(color: PineColors.sub, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  hintText: '10/24 2018 数一复盘 · 18(2) 重做\n10/25 现控 ch5 下半',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton.icon(
                  onPressed: (_busy || _controller.text.trim().isEmpty)
                      ? null
                      : _autoParse,
                  icon: _busy
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome, size: 14),
                  label: Text(_busy ? '解析中…' : 'AI 解析',
                      style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: PineColors.pine,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const Spacer(),
                const Text('散文/网页计划交给服务端抽取',
                    style: TextStyle(color: PineColors.faint, fontSize: 10)),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(_error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: PineColors.focus, fontSize: 10)),
              ),
            const SizedBox(height: 6),
            Text(
              '将写入 ${parsed.dayCount} 天 / ${parsed.total} 条'
              '${parsed.skipped.isEmpty ? '' : '，跳过 ${parsed.skipped.length} 行'}',
              style: const TextStyle(color: PineColors.sub, fontSize: 11),
            ),
            for (final line in parsed.skipped.take(2))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: PineColors.focus, fontSize: 10)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消', style: TextStyle(color: PineColors.sub)),
        ),
        TextButton(
          onPressed: parsed.isEmpty
              ? null
              : () => Navigator.of(context).pop(parsed),
          child: Text(
            '导入',
            style: TextStyle(
              color: parsed.isEmpty ? PineColors.faint : PineColors.pine,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// 补记与记录编辑消费同一沉淀表单；不改变引擎或持久化规则。
Future<void> showManualSheet(BuildContext context, {
  required AppData data, required DataChanged onChanged,
}) => showModalBottomSheet(context: context, isScrollControlled: true,
  builder: (context) => SafeArea(child: SizedBox(
    height: MediaQuery.sizeOf(context).height * .9,
    child: RecordEditor(data: data, onSaved: (next) { onChanged(next); Navigator.pop(context); }))));

Future<void> showRecordDetailSheet(BuildContext context, {
  required AppData data, required FocusRecord record, required Color color,
  required DataChanged onChanged,
}) => showModalBottomSheet(context: context, isScrollControlled: true,
  builder: (context) => SafeArea(child: SingleChildScrollView(
    padding: const EdgeInsets.all(PineSpacing.section), child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('记录详情', style: PineText.aggregate(color: PinePalette.of(context).textPrimary)),
        const SizedBox(height: PineSpacing.section),
        RecordFactTile(data: data, record: record),
        const SizedBox(height: PineSpacing.section),
        PineButton(label: '编辑记录', onPressed: () async {
          final next = await showDialog<AppData>(context: context,
            builder: (dialogContext) => Dialog(child: SizedBox(width: 480,
              child: RecordEditor(data: data, record: record,
                onSaved: (next) => Navigator.pop(dialogContext, next)))));
          if (next != null) { onChanged(next); if (context.mounted) Navigator.pop(context); }
        }),
        const SizedBox(height: PineSpacing.near),
        OutlinedButton.icon(icon: const Icon(Icons.delete_outline), label: const Text('删除这条记录'),
          onPressed: () async {
            final confirmed = await _confirmDanger(context, title: '删除这条记录？',
              message: '「${record.taskName}」${formatHoursMinutes(record.minutes)} 会从统计中移除。', confirmLabel: '删除');
            if (!confirmed) return;
            onChanged(data.copyWith(records: data.records.where((r) => r.id != record.id).toList()));
            if (context.mounted) Navigator.pop(context);
          }),
      ]))));

/// 考试倒计时设置：名称 + 目标日期。本地偏好，不参与云同步。
Future<void> showCountdownSheet(
  BuildContext context, {
  required AppData data,
  required DataChanged onChanged,
}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PineColors.paper,
      builder: (context) => _CountdownSheet(data: data, onChanged: onChanged),
    );

class _CountdownSheet extends StatefulWidget {
  const _CountdownSheet({required this.data, required this.onChanged});

  final AppData data;
  final DataChanged onChanged;

  @override
  State<_CountdownSheet> createState() => _CountdownSheetState();
}

class _CountdownSheetState extends State<_CountdownSheet> {
  late final TextEditingController _label;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.data.countdown.label);
    _date =
        widget.data.countdown.target ?? DateTime.parse(Countdown.defaultDate);
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _useDefault() {
    setState(() {
      _label.text = Countdown.defaultLabel;
      _date = DateTime.parse(Countdown.defaultDate);
    });
  }

  void _save() {
    final label = _label.text.trim();
    widget.onChanged(
      widget.data.copyWith(
        countdown: widget.data.countdown.copyWith(
          label: label.isEmpty ? Countdown.defaultLabel : label,
          date: ymdOf(_date),
        ),
      ),
    );
    Navigator.pop(context);
  }

  String _remainingText(int days) {
    if (days < 0) return '已结束';
    if (days == 0) return '就是今天';
    return '还剩 $days 天';
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.data.countdown.daysFrom(DateTime.now());
    return _SheetScaffold(
      title: '考试倒计时',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _label,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              labelText: '考试名称',
              hintText: '如：2027 考研初试',
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          _MiniCalendar(
            value: _date,
            onChanged: (picked) => setState(() => _date = picked),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                '距考试',
                style: TextStyle(color: PineColors.sub, fontSize: 12),
              ),
              const Spacer(),
              Text(
                _remainingText(days),
                style: pineNumberStyle(
                  fontSize: 12.5,
                  color: days >= 0 && days <= 7
                      ? PineColors.focus
                      : PineColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: PineButton(
                  label: '恢复默认',
                  color: PineColors.card,
                  foregroundColor: PineColors.ink,
                  onPressed: _useDefault,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PineButton(label: '保存', onPressed: _save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 迷你月历：单月网格，选中日松绿实心圆、今日松绿描边，非本月留空。
///
/// 自绘而非用 `showDatePicker`：应用未挂 `flutter_localizations`，系统日期
/// 选择器的月份/星期是英文；自绘可保持全中文与方案 E 的纸面视觉。
class _MiniCalendar extends StatefulWidget {
  const _MiniCalendar({required this.value, required this.onChanged});

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  State<_MiniCalendar> createState() => _MiniCalendarState();
}

class _MiniCalendarState extends State<_MiniCalendar> {
  static const List<String> _week = ['一', '二', '三', '四', '五', '六', '日'];

  /// 固定 6 行：翻月时面板高度不变，避免弹窗跳动。
  static const int _rows = 6;

  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _year = widget.value.year;
    _month = widget.value.month;
  }

  void _shiftMonth(int delta) {
    setState(() {
      final total = _year * 12 + (_month - 1) + delta;
      _year = total ~/ 12;
      _month = total % 12 + 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(_year, _month, 1).weekday; // 周一 = 1
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected =
        DateTime(widget.value.year, widget.value.month, widget.value.day);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: PineColors.card,
        borderRadius: BorderRadius.circular(Paper.chipRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _navButton(Icons.chevron_left_rounded, () => _shiftMonth(-1)),
              Expanded(
                child: Center(
                  child: Text(
                    '$_year 年 $_month 月',
                    style: const TextStyle(
                      color: PineColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              _navButton(Icons.chevron_right_rounded, () => _shiftMonth(1)),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              for (final label in _week)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: PineColors.sub,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          for (var row = 0; row < _rows; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _cell(
                      row * 7 + col - (firstWeekday - 1) + 1,
                      daysInMonth,
                      selected,
                      today,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 18, color: PineColors.sub),
        ),
      );

  Widget _cell(int day, int daysInMonth, DateTime selected, DateTime today) {
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 32);
    final date = DateTime(_year, _month, day);
    final isSelected = date == selected;
    final isToday = date == today;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onChanged(date),
      child: SizedBox(
        height: 32,
        child: Center(
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? PineColors.pine : null,
              shape: BoxShape.circle,
              border: isToday && !isSelected
                  ? Border.all(color: PineColors.pine, width: 1.2)
                  : null,
            ),
            child: Text(
              '$day',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? PineColors.card : PineColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 开启 / 编辑专注事件。
///
/// [event] 为空 = 开启模式（填名称 + 选绑定任务，同任务已有的进行中事件
/// 会被自动暂停）；非空 = 编辑模式（名称与任务预填，保存走 [TimerEngine.editEvent]，
/// 换绑任务时已归入的记录跟着更新）。
Future<void> showEventSheet(
  BuildContext context, {
  required AppData data,
  required DataChanged onChanged,
  FocusEvent? event,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: PineColors.paper,
    builder: (context) =>
        _EventSheet(data: data, onChanged: onChanged, event: event),
  );
}

class _EventSheet extends StatefulWidget {
  const _EventSheet({
    required this.data,
    required this.onChanged,
    this.event,
  });

  final AppData data;
  final DataChanged onChanged;

  /// 非空 = 编辑模式。
  final FocusEvent? event;

  @override
  State<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<_EventSheet> {
  final _name = TextEditingController();
  late String _taskName;

  bool get _editing => widget.event != null;

  @override
  void initState() {
    super.initState();
    _name.text = widget.event?.name ?? '';
    _taskName = widget.event?.taskName ?? widget.data.selectedTask.name;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (_editing) {
      widget.onChanged(TimerEngine.editEvent(
        widget.data,
        widget.event!.id,
        name: name,
        taskName: _taskName,
        now: DateTime.now(),
      ));
    } else {
      widget.onChanged(TimerEngine.startEvent(
        widget.data,
        name: name,
        taskName: _taskName,
        now: DateTime.now(),
      ));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.data.tasks;
    return _SheetScaffold(
      title: _editing ? '编辑事件' : '开启专注事件',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: !_editing,
            decoration: const InputDecoration(
                labelText: '事件名称（如「高数第六章」）', isDense: true),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _taskName,
            decoration: const InputDecoration(labelText: '绑定任务', isDense: true),
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
          const SizedBox(height: 10),
          Text(
            _editing
                ? '改名或换绑任务后，已归入这个事件的记录会跟着更新。'
                : '开启后，该任务的每一次专注（含补记）都会累计到这个事件里，'
                    '直到你暂停或完成它。',
            style: const TextStyle(color: PineColors.sub, fontSize: 11),
          ),
          const SizedBox(height: 12),
          PineButton(
            label: _editing ? '保存修改' : '开始累计',
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// 事件明细：列出该事件下的全部记录（按完成时刻倒序）。
Future<void> showEventDetailSheet(
  BuildContext context, {
  required AppData data,
  required FocusEvent event,
  required Color Function(String taskName) colorFor,
}) {
  final stats = eventStatsOf(data, event.id);
  final start = event.startedAt;
  final end = event.finishedAt ?? DateTime.now();
  String fmt(DateTime d) =>
      '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: PineColors.paper,
    builder: (context) => _SheetScaffold(
      title: event.name,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${event.statusLabel} · ${fmt(start)} → ${fmt(end)}',
            style: const TextStyle(color: PineColors.sub, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            '累计 ${formatMinutes(stats.minutes)} · ${stats.tomatoCount} 番茄 · '
            '${stats.days} 天 · ${stats.records.length} 次',
            style: pineNumberStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (stats.records.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('还没有归入的记录',
                  style: TextStyle(color: PineColors.sub, fontSize: 12)),
            )
          else
            for (final record in stats.records)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: colorFor(record.taskName),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        record.taskName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: PineColors.ink, fontSize: 12),
                      ),
                    ),
                    Text(
                      '${record.dayKey} ${record.at.hour.toString().padLeft(2, '0')}:'
                      '${record.at.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                          color: PineColors.sub, fontSize: 10.5),
                    ),
                    const SizedBox(width: 10),
                    DurationText(record.minutes,
                        style: pineNumberStyle(fontSize: 12)),
                  ],
                ),
              ),
        ],
      ),
    ),
  );
}

/// 事件操作面板（统计页只做展示，操作集中在这里/首页任务行）。
Future<void> showEventActionSheet(
  BuildContext context, {
  required AppData data,
  required FocusEvent event,
  required DataChanged onChanged,
}) {
  final stats = eventStatsOf(data, event.id);
  final now = DateTime.now();
  // 可切换的目标：除自己之外的全部**未完成**事件（切到已完成的没有意义）。
  // 进行中排前面——它们才是"另一条正在累计的"，切换动机最强。
  final others = [
    for (final e in data.events)
      if (e.id != event.id && !e.isFinished) e,
  ]..sort((a, b) {
      if (a.isRunning != b.isRunning) return a.isRunning ? -1 : 1;
      return a.startedAt.compareTo(b.startedAt);
    });
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: PineColors.paper,
    builder: (context) => _SheetScaffold(
      title: event.name,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${event.statusLabel} · 绑定「${event.taskName}」'
            ' · 累计 ${formatMinutes(stats.minutes)} · ${stats.tomatoCount} 番茄',
            style: const TextStyle(color: PineColors.sub, fontSize: 11.5),
          ),
          const SizedBox(height: 14),
          PineButton(
            label: '编辑事件（名称 / 绑定任务）',
            icon: Icons.edit,
            color: PineColors.card,
            foregroundColor: PineColors.pine,
            onPressed: () {
              Navigator.pop(context);
              showEventSheet(context,
                  data: data, onChanged: onChanged, event: event);
            },
          ),
          if (others.isNotEmpty) ...[
            const SizedBox(height: 10),
            // 2026-11-07 反馈：面板里没有"切换"入口，只能靠任务行徽标间接切。
            // 「切换」不只是换个事件名——它同时要暂停旧事件、恢复新事件、
            // 并把选中任务换成新事件绑定的任务（否则新一轮专注还记到原来那条）。
            PineButton(
              label: '切换到其他事件（${others.length} 条可选）',
              icon: Icons.swap_horiz,
              color: PineColors.card,
              foregroundColor: PineColors.pine,
              onPressed: () async {
                final picked = await _pickEventToSwitch(context, others);
                if (picked == null || !context.mounted) return;
                onChanged(TimerEngine.switchEvent(
                    data, event.id, picked.id, DateTime.now()));
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
          const SizedBox(height: 10),
          if (event.isRunning)
            PineButton(
              label: '暂停累计（暂停期间的记录不归入）',
              icon: Icons.pause,
              color: PineColors.card,
              foregroundColor: PineColors.ink,
              onPressed: () {
                onChanged(TimerEngine.pauseEvent(data, event.id, now));
                Navigator.pop(context);
              },
            )
          else
            PineButton(
              label: '继续累计',
              icon: Icons.play_arrow,
              onPressed: () {
                onChanged(TimerEngine.resumeEvent(data, event.id, now));
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 10),
          PineButton(
            label: '完成此事件（归档保留）',
            icon: Icons.check,
            onPressed: () {
              onChanged(TimerEngine.finishEvent(data, event.id, now));
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: 10),
          PineButton(
            label: '开启新事件（此事件自动暂停）',
            icon: Icons.add,
            color: PineColors.card,
            foregroundColor: PineColors.pine,
            onPressed: () {
              Navigator.pop(context);
              showEventSheet(context, data: data, onChanged: onChanged);
            },
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () async {
              final confirmed = await _confirmDanger(
                context,
                title: '删除事件？',
                message: '事件「${event.name}」会被移除，'
                    '已累计的记录保留在统计中（仅解除关联）。',
                confirmLabel: '删除',
              );
              if (!confirmed) return;
              onChanged(TimerEngine.deleteEvent(data, event.id));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('删除事件',
                style: TextStyle(color: PineColors.sub, fontSize: 12)),
          ),
        ],
      ),
    ),
  );
}

/// 选择要切换过去的事件：列出其他未完成事件（进行中排前，暂停的带状态标）。
Future<FocusEvent?> _pickEventToSwitch(
  BuildContext context,
  List<FocusEvent> options,
) {
  return showModalBottomSheet<FocusEvent>(
    context: context,
    backgroundColor: PineColors.paper,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              '切换到哪个事件？',
              style: TextStyle(
                color: PineColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              '切换 = 暂停当前这条 + 恢复所选 + 把选中任务换成它绑定的任务，'
              '之后的新专注才会记进这条。',
              style: TextStyle(color: PineColors.sub, fontSize: 10.5),
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final option in options)
                  ListTile(
                    leading: Icon(
                      option.isRunning
                          ? Icons.play_circle_outline
                          : Icons.pause_circle_outline,
                      size: 20,
                      color: option.isRunning
                          ? PineColors.pine
                          : PineColors.sub,
                    ),
                    title: Text(option.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: PineColors.ink, fontSize: 14)),
                    subtitle: Text(
                      '绑定「${option.taskName}」· ${option.statusLabel}',
                      style: const TextStyle(
                          color: PineColors.sub, fontSize: 10.5),
                    ),
                    trailing: const Icon(Icons.chevron_right,
                        size: 18, color: PineColors.faint),
                    onTap: () => Navigator.pop(sheetContext, option),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// 事件档案：全部事件的独立展示窗口（统计页「事件进展」卡的完整版）。
///
/// 2026-10-13：原「已完成事件」清单只列已完成、且统计页只露最近 5 条，
/// 事件一多既不直观也看不全。升级为完整档案：
/// - 汇总头：事件数 / 累计时长（小时分钟人话）/ 番茄当量 / 覆盖天数；
/// - 按任务构成：色点 + 任务名 + 事件数与累计时长；
/// - 分区：进行中（含已暂停）→ 已完成；
/// - 已完成支持「按最近 / 按时长」排序切换（标题栏右侧）；
/// - 行内信息：名称 + 状态/完成日期 + 覆盖天数 + 累计时长（小时分钟人话）。
Future<void> showEventArchiveSheet(
  BuildContext context, {
  required AppData data,
  required Color Function(String taskName) colorFor,
  required DataChanged onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: PineColors.paper,
    builder: (sheetContext) {
      var current = data;
      var byDuration = false;
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final statsById = {
            for (final event in current.events)
              event.id: eventStatsOf(current, event.id),
          };
          final live = current.events.where((e) => !e.isFinished).toList();
          final finished = current.events.where((e) => e.isFinished).toList()
            ..sort((a, b) => byDuration
                ? statsById[b.id]!.minutes
                    .compareTo(statsById[a.id]!.minutes)
                : (b.finishedAt ?? b.startedAt)
                    .compareTo(a.finishedAt ?? a.startedAt));

          final totalMinutes = statsById.values
              .fold<double>(0, (sum, stats) => sum + stats.minutes);
          final totalTomato = pomodoroEquiv(totalMinutes);
          final dayKeys = <String>{
            for (final stats in statsById.values)
              for (final record in stats.records) record.dayKey,
          };
          // 按任务构成：色点 + 任务名 + 事件数与累计时长，按时长降序。
          final byTask = <String, Map<String, double>>{};
          for (final event in current.events) {
            final entry = byTask.putIfAbsent(
                event.taskName, () => {'minutes': 0, 'count': 0});
            entry['minutes'] = entry['minutes']! + statsById[event.id]!.minutes;
            entry['count'] = entry['count']! + 1;
          }
          final taskRows = byTask.entries.toList()
            ..sort((a, b) =>
                b.value['minutes']!.compareTo(a.value['minutes']!));

          void apply(AppData next) {
            onChanged(next);
            setSheetState(() => current = next);
          }

          return _SheetScaffold(
            title: '事件档案',
            trailing: PineButton(
              label: byDuration ? '按时长' : '按最近',
              icon: Icons.swap_vert,
              height: 34,
              color: PineColors.card,
              foregroundColor: PineColors.pine,
              onPressed: () => setSheetState(() => byDuration = !byDuration),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.72,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  // 汇总头。
                  Text(
                    '共 ${current.events.length} 个事件 · 累计 '
                    '${formatHoursMinutes(totalMinutes)} · $totalTomato 番茄 · '
                    '覆盖 ${dayKeys.length} 天',
                    style: const TextStyle(color: PineColors.sub, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  // 按任务构成。
                  for (final row in taskRows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: colorFor(row.key),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              row.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: PineColors.ink, fontSize: 12),
                            ),
                          ),
                          Text(
                            '${row.value['count']!.toInt()} 个 · '
                            '${formatHoursMinutes(row.value['minutes']!)}',
                            style: pineNumberStyle(
                                fontSize: 11, color: PineColors.sub),
                          ),
                        ],
                      ),
                    ),
                  // 分区：进行中（含已暂停）。
                  if (live.isNotEmpty) ...[
                    const Divider(height: 18, color: PineColors.line),
                    Text(
                      '进行中 ${live.length} 个',
                      style:
                          const TextStyle(color: PineColors.sub, fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    for (final event in live)
                      _eventArchiveTile(
                        sheetContext,
                        current,
                        event,
                        colorFor,
                        apply,
                      ),
                  ],
                  // 分区：已完成。
                  const Divider(height: 18, color: PineColors.line),
                  Text(
                    '已完成 ${finished.length} 个',
                    style: const TextStyle(color: PineColors.sub, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  if (finished.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text('还没有已完成的事件',
                          style:
                              TextStyle(color: PineColors.sub, fontSize: 12)),
                    )
                  else
                    for (final event in finished)
                      _eventArchiveTile(
                        sheetContext,
                        current,
                        event,
                        colorFor,
                        apply,
                      ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// 档案行：点左侧进详情，右侧「⋯」重命名/删除。
/// 第二信息按状态给：已完成显示完成日期，进行中/已暂停显示状态；
/// 一律带覆盖天数与累计时长（小时分钟人话）。
Widget _eventArchiveTile(
  BuildContext context,
  AppData data,
  FocusEvent event,
  Color Function(String taskName) colorFor,
  void Function(AppData next) apply,
) {
  final stats = eventStatsOf(data, event.id);
  final stamp = event.finishedAt ?? event.startedAt;
  final statusText = event.isFinished
      ? '${stamp.month}/${stamp.day} 完成'
      : event.statusLabel;
  return Row(
    children: [
      Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showEventDetailSheet(
            context,
            data: data,
            event: event,
            colorFor: colorFor,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 13,
                  decoration: BoxDecoration(
                    color: colorFor(event.taskName).withAlpha(168),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PineColors.ink, fontSize: 13),
                  ),
                ),
                Text(
                  '$statusText · ${stats.days} 天',
                  style: const TextStyle(color: PineColors.sub, fontSize: 10.5),
                ),
                const SizedBox(width: 8),
                Text(
                  formatHoursMinutes(stats.minutes),
                  style: pineNumberStyle(fontSize: 12, color: PineColors.sub),
                ),
              ],
            ),
          ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.more_horiz, size: 18, color: PineColors.sub),
        tooltip: '重命名 / 删除',
        onPressed: () => _eventTileActions(context, data, event, apply),
      ),
    ],
  );
}

/// 条目操作：重命名（就地弹输入）/ 删除（二次确认，记录保留只解除关联）。
Future<void> _eventTileActions(
  BuildContext context,
  AppData data,
  FocusEvent event,
  void Function(AppData next) apply,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: PineColors.paper,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined, size: 20),
            title: const Text('重命名', style: TextStyle(fontSize: 14)),
            onTap: () => Navigator.pop(sheetContext, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline,
                size: 20, color: PineColors.focus),
            title: const Text('删除事件',
                style: TextStyle(fontSize: 14, color: PineColors.focus)),
            subtitle: const Text('事件移除，专注记录保留（只解除关联）',
                style: TextStyle(fontSize: 10.5, color: PineColors.sub)),
            onTap: () => Navigator.pop(sheetContext, 'delete'),
          ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  if (action == 'rename') {
    final controller = TextEditingController(text: event.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名事件', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '事件名称', isDense: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    apply(TimerEngine.renameEvent(data, event.id, name));
    return;
  }

  final stats = eventStatsOf(data, event.id);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('删除这个事件？', style: TextStyle(fontSize: 15)),
      content: Text(
        '「${event.name}」会被移除，它的 ${stats.records.length} 条专注记录'
        '（${formatMinutes(stats.minutes)}）保留在统计里，只是不再归属这个事件。',
        style: const TextStyle(fontSize: 12.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('删除', style: TextStyle(color: PineColors.focus)),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  apply(TimerEngine.deleteEvent(data, event.id));
}

/// 全量记录入口使用真实台账页；保留原入口签名供尚未迁移页面消费。
Future<void> showAllRecordsSheet(
  BuildContext context, {
  required AppData data,
  required Color Function(String taskName) colorFor,
  required DataChanged onChanged,
  Future<void> Function()? onComplete,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: double.infinity),
  builder: (context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .94,
    child: LedgerPage(
      data: data,
      onChanged: onChanged,
      onComplete: onComplete,
      onReturnToPresent: () => Navigator.pop(context),
    ),
  ),
);

/// 完成一轮之后的「主题归属」（2026-11-11 改版）。
///
/// 从"开始前先选主题"改成"记完再选"：开始只需要一个动作，
/// 主题在落库那一刻再补。默认选中上次用过的主题，点一下即完成；
/// 直接关掉弹层 = 保持默认，这条记录照常存在（不会丢）。
Future<PineTask?> showTopicSheet(
  BuildContext context, {
  required AppData data,
  required String timeLabel,
}) {
  if (data.tasks.isEmpty) return Future<PineTask?>.value();
  return showModalBottomSheet<PineTask>(
    context: context,
    backgroundColor: PineColors.paper,
    builder: (context) => _SheetScaffold(
      title: '这一轮记到哪个主题？',
      trailing: Text(
        timeLabel,
        style: const TextStyle(color: PineColors.sub, fontSize: 12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < data.tasks.length; i++)
                  _TopicOption(
                    task: data.tasks[i],
                    selected: i == data.selectedIndex,
                    onTap: () => Navigator.of(context).pop(data.tasks[i]),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '默认是上次用过的主题；直接关掉就保持默认，这条记录不会丢。',
            style: TextStyle(color: PineColors.sub, fontSize: 11.5),
          ),
        ],
      ),
    ),
  );
}

/// 主题选项行：色点 + 名称 + 「上次」标记。
class _TopicOption extends StatelessWidget {
  const _TopicOption({
    required this.task,
    required this.selected,
    required this.onTap,
  });

  final PineTask task;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? PineColors.line : PineColors.line,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: task.swatch,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                task.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PineColors.ink, fontSize: 14.5),
              ),
            ),
            if (selected) ...[
              const Text(
                '上次',
                style: TextStyle(color: PineColors.sub, fontSize: 11),
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: selected ? PineColors.focus : PineColors.faint,
            ),
          ],
        ),
      ),
    );
  }
}
