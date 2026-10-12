import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_app/src/widgets.dart';

void main() {
  test('formatHoursMinutes：小时+分钟人话格式（最近完成列表用）', () {
    expect(formatHoursMinutes(0), '<1 分钟');
    expect(formatHoursMinutes(0.4), '<1 分钟');
    expect(formatHoursMinutes(1), '1 分钟');
    expect(formatHoursMinutes(45), '45 分钟');
    expect(formatHoursMinutes(59.6), '1 小时');
    expect(formatHoursMinutes(60), '1 小时');
    expect(formatHoursMinutes(61), '1 小时 1 分钟');
    expect(formatHoursMinutes(75), '1 小时 15 分钟');
    expect(formatHoursMinutes(125), '2 小时 5 分钟');
    expect(formatHoursMinutes(180), '3 小时');
    expect(formatHoursMinutes(180.4), '3 小时');
  });

  test('formatHoursMinutes：四舍五入到分钟，不出现小时0分钟的怪写法', () {
    expect(formatHoursMinutes(46.4), '46 分钟');
    expect(formatHoursMinutes(46.6), '47 分钟');
    expect(formatHoursMinutes(119.5), '2 小时'); // 119.5 → 120 分钟
    expect(formatHoursMinutes(119.4), '1 小时 59 分钟');
  });
}
