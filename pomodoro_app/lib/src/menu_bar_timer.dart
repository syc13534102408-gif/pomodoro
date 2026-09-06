import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// macOS 菜单栏（屏幕右上角状态栏）剩余时间显示。
///
/// Flutter 侧每秒推送一次文本，原生 `NSStatusItem` 负责渲染；
/// App 窗口最小化或在后台时，Dart 计时器仍持续运行，菜单栏倒计时照常走表。
/// 非 macOS 平台为空操作，不影响安卓/网页。
class MenuBarTimer {
  MenuBarTimer._();

  static const MethodChannel _channel = MethodChannel('pine/menu_bar');

  static bool get _supported => !kIsWeb && Platform.isMacOS;

  /// [title] 即菜单栏文本：
  /// - 未计时建议传 "专注 待"（始终可见，避免图标被一堆状态项淹没）
  /// - 计时中传 "专注 MM:SS" / "+MM:SS"
  static void show({required String title}) {
    if (!_supported) return;
    _channel
        .invokeMethod<void>('update', {'title': title})
        .catchError((Object _) {});
  }
}
