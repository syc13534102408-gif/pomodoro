import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 本地持久化。键名与网页端 localStorage 保持一致，便于对照排查。
class Storage {
  Storage._();

  static const String currentKey = 'pine-pomodoro';

  /// 旧版安卓端使用的键，用于一次性迁移。
  static const String legacyKey = 'pomodoro_data';

  static Future<AppData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(currentKey) ?? prefs.getString(legacyKey);
    if (raw == null || raw.isEmpty) return AppData();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return AppData();
      return AppData.fromMap(decoded);
    } catch (_) {
      return AppData();
    }
  }

  static Future<void> save(AppData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(currentKey, jsonEncode(data.toMap()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(currentKey);
    await prefs.remove(legacyKey);
  }
}

/// 从云端净荷恢复本机数据，保留推送订阅与进行中会话。
AppData mergeFromCloud(AppData local, Map<String, dynamic> payload) {
  final restored = AppData.fromMap(payload);
  return restored.copyWith(
    activeSession: local.activeSession,
    sync: local.sync,
  );
}
