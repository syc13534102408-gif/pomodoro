import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// 云端同步异常。[conflict] 为 true 表示云端已被其他设备更新。
class CloudSyncException implements Exception {
  CloudSyncException(this.message, {this.conflict = false});

  final String message;
  final bool conflict;

  @override
  String toString() => message;
}

/// 云端返回的备份内容。
class CloudBackup {
  const CloudBackup({required this.payload, required this.updatedAt});

  final Map<String, dynamic> payload;
  final DateTime updatedAt;

  int get recordCount {
    final records = payload['records'];
    return records is List ? records.length : 0;
  }
}

/// 与网页端共用的 Cloudflare Worker 同步接口。
class CloudSync {
  CloudSync({String? baseUrl})
      : baseUrl = (baseUrl == null || baseUrl.trim().isEmpty)
            ? defaultBaseUrl
            : baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  static const String defaultBaseUrl =
      'https://pine-pomodoro-reminders.pine-pomodoro-reminders.workers.dev';

  static const Duration timeout = Duration(seconds: 20);

  final String baseUrl;

  /// 生成本机同步码，需满足服务端的 `[A-Za-z0-9_-]{16,128}`。
  static String generateDeviceCode() {
    const alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789_-';
    final random = Random.secure();
    return List.generate(
      28,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  static bool isValidCode(String code) =>
      RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(code.trim());

  Future<DateTime> upload({
    required String deviceCode,
    required Map<String, dynamic> payload,
    DateTime? baseUpdatedAt,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/sync/upload'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'deviceCode': deviceCode.trim(),
            'payload': payload,
            if (baseUpdatedAt != null)
              'baseUpdatedAt': baseUpdatedAt.toIso8601String(),
          }),
        )
        .timeout(timeout);

    final body = _decode(response.body);
    if (response.statusCode == 409) {
      throw CloudSyncException(
        (body?['error'] ?? '云端数据已在另一台设备更新').toString(),
        conflict: true,
      );
    }
    if (response.statusCode != 200) {
      throw CloudSyncException((body?['error'] ?? '上传失败').toString());
    }
    final updatedAt = DateTime.tryParse((body?['updatedAt'] ?? '').toString());
    return updatedAt ?? DateTime.now();
  }

  Future<CloudBackup> download(String deviceCode) async {
    final uri = Uri.parse('$baseUrl/sync/download')
        .replace(queryParameters: {'deviceCode': deviceCode.trim()});
    final response = await http.get(uri).timeout(timeout);
    final body = _decode(response.body);
    if (response.statusCode == 404) {
      throw CloudSyncException('没有找到云端备份，请先在原设备上传一次');
    }
    if (response.statusCode != 200) {
      throw CloudSyncException((body?['error'] ?? '下载失败').toString());
    }
    final payload = body?['payload'];
    if (payload is! Map) throw CloudSyncException('云端备份格式不正确');
    return CloudBackup(
      payload: Map<String, dynamic>.from(payload),
      updatedAt:
          DateTime.tryParse((body?['updatedAt'] ?? '').toString()) ??
              DateTime.now(),
    );
  }

  Map<String, dynamic>? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }
}
