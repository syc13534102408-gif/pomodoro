import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/engine.dart';
import 'package:pomodoro_app/src/models.dart';

void main() {
  test('自然完成：记录 at 推进到完成时刻（而非停留在开始时刻）', () {
    final t0 = DateTime(2026, 9, 8, 14, 0); // 开始计时
    final t1 = DateTime(2026, 9, 8, 14, 50); // 确认完成
    final afterStart = TimerEngine.start(AppData(), SessionMode.focus, t0);
    final started = afterStart.records.first;

    expect(started.status, RecordStatus.inProgress);
    expect(started.at, t0);

    final afterDone = TimerEngine.complete(afterStart, t1);
    final done =
        afterDone.records.firstWhere((record) => record.id == started.id);

    expect(done.status, RecordStatus.completed);
    expect(done.at, t1);
    expect(done.dayKey, '2026-09-08');
    expect(done.minutes, greaterThan(0));
  });

  test('跨午夜完成：dayKey 保持开始日，at 为完成时刻且往返一致', () {
    final t0 = DateTime(2026, 9, 7, 23, 50); // 前一天深夜开始
    final t1 = DateTime(2026, 9, 8, 0, 20); // 次日凌晨完成
    final afterStart = TimerEngine.start(AppData(), SessionMode.focus, t0);
    final afterDone = TimerEngine.complete(afterStart, t1);
    final done = afterDone.records
        .firstWhere((record) => record.status == RecordStatus.completed);

    expect(done.dayKey, '2026-09-07');
    expect(done.at, t1);

    // 落盘/上云再读回，归属日与完成时刻各自不漂移。
    final restored = FocusRecord.fromMap(
      Map<dynamic, dynamic>.from(done.toMap()),
    );
    expect(restored.dayKey, '2026-09-07');
    expect(restored.at, t1);
  });

  test('手动补记：at 为用户填写的完成时刻', () {
    final at = DateTime(2026, 9, 8, 18, 30);
    final next = TimerEngine.addManual(
      AppData(),
      taskName: '数学真题',
      minutes: 25,
      at: at,
    );
    final added = next.records.first;

    expect(added.status, RecordStatus.manual);
    expect(added.at, at);
    expect(added.dayKey, '2026-09-08');
  });
}
