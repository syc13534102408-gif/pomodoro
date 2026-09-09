import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/models.dart';

FocusRecord _fromJson(Map<String, dynamic> map) =>
    FocusRecord.fromMap(Map<dynamic, dynamic>.from(map));

void main() {
  test('toMap -> fromMap 往返后保留时分秒（修复 00:00 回归）', () {
    final at = DateTime(2026, 9, 8, 14, 35, 7);
    final record = FocusRecord(
      taskName: '数学真题',
      minutes: 25,
      dayKey: '2026-09-08',
      status: RecordStatus.completed,
      at: at,
    );

    final restored = FocusRecord.fromMap(
      Map<dynamic, dynamic>.from(record.toMap()),
    );

    expect(restored.at.hour, 14);
    expect(restored.at.minute, 35);
    expect(restored.at.second, 7);
    expect(restored.at.millisecondsSinceEpoch, at.millisecondsSinceEpoch);
    expect(restored.dayKey, '2026-09-08');
    expect(restored.minutes, 25);
    expect(restored.status, RecordStatus.completed);
  });

  test('旧数据只有 date 时退化为当天 00:00，不抛异常', () {
    final restored = _fromJson({
      'id': 'old-1',
      'name': '数学真题',
      'minutes': 50,
      'date': '2026-09-08',
      'status': 'completed',
    });

    expect(restored.dayKey, '2026-09-08');
    expect(restored.at.hour, 0);
    expect(restored.at.minute, 0);
  });

  test('at 为脏数据时安全回退到 date，不抛异常', () {
    final restored = _fromJson({
      'id': 'dirty-1',
      'name': '数学真题',
      'minutes': 25,
      'date': '2026-09-08',
      'at': 'not-a-datetime',
      'status': 'completed',
    });

    expect(restored.dayKey, '2026-09-08');
    expect(restored.at.hour, 0);
    expect(restored.at.minute, 0);
  });

  test('dayKey 仍以 date 字段为准，不因 at 的日期不同而漂移', () {
    // 记录归属 date（09-07），但 at 落在次日凌晨（跨午夜场景）。
    final restored = _fromJson({
      'id': 'midnight-1',
      'name': '数学真题',
      'minutes': 25,
      'date': '2026-09-07',
      'at': '2026-09-08T00:30:00.000',
      'status': 'completed',
    });

    expect(restored.dayKey, '2026-09-07');
    expect(restored.at.hour, 0);
    expect(restored.at.minute, 30);
  });

  test('云端 UTC at 解析后转本地时区（isUtc=false，时刻等价）', () {
    final restored = _fromJson({
      'id': 'cloud-1',
      'name': '数学真题',
      'minutes': 25,
      'date': '2026-09-08',
      'at': '2026-09-08T06:35:00.000Z',
      'status': 'completed',
    });

    expect(restored.at.isUtc, isFalse);
    expect(
      restored.at.millisecondsSinceEpoch,
      DateTime.utc(2026, 9, 8, 6, 35).millisecondsSinceEpoch,
    );
    expect(restored.dayKey, '2026-09-08');
  });
}
