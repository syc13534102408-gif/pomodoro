import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/models.dart';

/// 2026-09-09 数据事故回归：统计日口径下，dateKey(日期零点) 会回退到前一天，
/// 导致「从云端恢复的历史记录整体归属日 -1、多次启动累计漂移、今日统计清零」。
/// 修复后 date 字段必须**直接采用**，禁止按零点重算。
void main() {
  test('云端恢复：date 字段直接作为归属日，不被统计日口径重算', () {
    final record = FocusRecord.fromMap({
      'name': '自控',
      'minutes': 50,
      'status': 'completed',
      'date': '2026-09-09',
      'at': '2026-09-09T20:16:07',
    });
    // 修复前：dateKey(2026-09-09 00:00) = '2026-09-08'（漂移）。
    expect(record.dayKey, '2026-09-09');
  });

  test('反复往返不产生归属日漂移', () {
    final original = FocusRecord(
      taskName: '高数',
      minutes: 48,
      dayKey: '2026-09-09',
      status: RecordStatus.completed,
      at: DateTime(2026, 9, 9, 16, 29),
    );
    var current = original;
    for (var i = 0; i < 5; i++) {
      current = FocusRecord.fromMap(current.toMap());
    }
    expect(current.dayKey, '2026-09-09');
    expect(current.minutes, 48);
  });

  test('date 缺失（旧网页端数据）：按 at 的统计日兜底', () {
    final record = FocusRecord.fromMap({
      'name': '英语',
      'minutes': 24,
      'status': 'completed',
      'at': '2026-09-09T17:14:00',
    });
    expect(record.dayKey, '2026-09-09');
  });
}
