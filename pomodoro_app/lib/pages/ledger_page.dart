import 'dart:async';
import 'package:flutter/material.dart';
import '../src/engine.dart';
import '../src/models.dart';
import '../src/records_view.dart';
import '../src/sheets.dart';
import '../src/theme.dart';
import '../src/widgets.dart';
import 'settings_page.dart';
import 'stats_page.dart';

/// 两个已迁移视图共用的台账语境；其他分段暂消费现有视图。
class LedgerPage extends StatefulWidget {
  const LedgerPage(
      {super.key,
      required this.data,
      required this.onChanged,
      required this.onReturnToPresent,
      this.initialSegment = PineLedgerSegment.records,
      this.onComplete,
      this.now});
  final AppData data;
  final ValueChanged<AppData> onChanged;
  final VoidCallback onReturnToPresent;
  final PineLedgerSegment initialSegment;
  final Future<void> Function()? onComplete;
  final DateTime? now;
  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  late AppData _data = widget.data;
  late PineLedgerSegment _segment = widget.initialSegment;
  Timer? _ticker;
  DateTime get _now => widget.now ?? DateTime.now();
  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _data.activeSession != null) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant LedgerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) _data = widget.data;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _apply(AppData data) {
    setState(() => _data = data);
    widget.onChanged(data);
  }

  @override
  Widget build(BuildContext context) {
    final view = SessionView.of(_data, _now);
    final active = _data.records
        .where((r) => r.id == _data.activeSession?.recordId)
        .firstOrNull;
    final day = active?.dayKey ?? dateKey(_now);
    final body = switch (_segment) {
      PineLedgerSegment.records => RecordsPanel(
          data: _data,
          onEdit: (record) => showRecordDetailSheet(context,
              data: _data,
              record: record,
              color: PinePalette.of(context).textPrimary,
              onChanged: _apply),
          onAdd: () =>
              showManualSheet(context, data: _data, onChanged: _apply)),
      PineLedgerSegment.schedule => Padding(
          padding: const EdgeInsets.all(PineSpacing.section),
          child: PlanPanel(
              data: _data,
              now: widget.now,
              onApply: (transform) =>
                  _apply(_data.copyWith(todos: transform(_data.todos))))),
      PineLedgerSegment.stats => StatsPage(data: _data, onChanged: _apply),
      PineLedgerSegment.profile => SettingsPage(data: _data, onChanged: _apply),
      PineLedgerSegment.events => Center(
          child: TextButton(
              onPressed: () => showEventArchiveSheet(context,
                  data: _data,
                  colorFor: (_) => PinePalette.of(context).taskColors.first,
                  onChanged: _apply),
              child: const Text('事件档案'))),
    };
    return Scaffold(
        body: SafeArea(
            child: Column(children: [
      TenseSwitcher(
          current: PineTense.ledger,
          onChanged: (_) => widget.onReturnToPresent()),
      LedgerSegmentSelector(
          current: _segment,
          onChanged: (value) => setState(() => _segment = value)),
      if (view != null)
        SessionPresenceBar(
            view: view,
            belongingDateText: day,
            crossDay: day != dateKey(_now),
            restingStillRunning: _data.isRestDay(_now),
            onComplete: () async {
              if (widget.onComplete != null) {
                await widget.onComplete!();
              } else {
                _apply(TimerEngine.complete(
                    TimerEngine.advance(_data, _now), _now));
              }
            },
            onReturnToPresent: widget.onReturnToPresent),
      Expanded(child: body),
    ])));
  }
}
