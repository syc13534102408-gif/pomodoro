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

/// 从云端净荷恢复本机数据，保留推送订阅、进行中会话与本地偏好。
///
/// records 按**记录 id 并集**合并（2026-09-15 数据事故的根治）：
/// - 云端独有的记录 → 补入本机；
/// - 本机独有的记录（云端备份之后本机又新学的）→ **保留**，不再被整体
///   替换清空——此前「恢复一次、今天的数据两端同时消失」即源于此；
/// - 同 id 冲突 → 云端版本优先（恢复场景云端是权威快照）。
/// 其余字段（任务/清单/设置）仍以云端为准。
AppData mergeFromCloud(AppData local, Map<String, dynamic> payload) {
  final restored = AppData.fromMap(payload);
  final cloudIds = {for (final r in restored.records) r.id};
  final localOnly =
      local.records.where((r) => !cloudIds.contains(r.id)).toList();
  final merged = [...restored.records, ...localOnly]
    ..sort((a, b) => b.at.compareTo(a.at));
  return restored.copyWith(
    records: merged,
    activeSession: local.activeSession,
    sync: local.sync,
    // 倒计时属本地偏好（不进云端净荷），恢复云端数据时必须保留本机设置，
    // 否则每同步一次就被重置回默认的考试名称与日期。
    countdown: local.countdown,
  );
}
