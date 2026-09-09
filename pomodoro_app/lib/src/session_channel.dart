import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_sync.dart';

/// 会话实时镜像的传输层（方案 A：SCF 会话通道 + 短轮询）。
///
/// 与备份净荷（`/sync/*`）完全分离：会话是瞬态，只保留**最新一份快照**，
/// 发布即覆盖，不做历史也不做冲突检测——冲突由「seq 单调递增，后写者胜」裁决。
/// 传输失败一律静默降级：镜像能力不影响本地计时。
class SessionChannel {
  SessionChannel({String? baseUrl, http.Client? client})
      : baseUrl = (baseUrl == null || baseUrl.trim().isEmpty)
            ? CloudSync.defaultBaseUrl
            : baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  /// 复用同步后端地址；改其一必改其二（见 docs/05）。
  final String baseUrl;

  /// 轮询高频调用，超时比备份同步短：镜像失败不该拖住任何 UI。
  static const Duration timeout = Duration(seconds: 8);

  final http.Client _client;

  /// 发布最新会话快照。[session] 为 null 表示对端应回到空闲。
  Future<void> publish({
    required String deviceCode,
    required String deviceId,
    required int seq,
    required Map<String, dynamic>? session,
    String? taskName,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/session/publish'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'deviceCode': deviceCode,
            'deviceId': deviceId,
            'seq': seq,
            'session': session,
            'taskName': taskName,
          }),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw SessionChannelException('会话发布失败（${response.statusCode}）');
    }
  }

  /// 拉取最新会话快照。云端无记录时返回 seq=0 的空态（非异常）。
  Future<RemoteSessionState> poll(String deviceCode) async {
    final uri = Uri.parse('$baseUrl/session/poll')
        .replace(queryParameters: {'deviceCode': deviceCode});
    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw SessionChannelException('会话拉取失败（${response.statusCode}）');
    }
    final body = _decode(response.body);
    if (body == null) throw SessionChannelException('会话拉取响应格式不正确');
    return RemoteSessionState(
      seq: (body['seq'] as num?)?.toInt() ?? 0,
      deviceId: (body['deviceId'] ?? '') as String,
      session: body['session'] is Map
          ? Map<String, dynamic>.from(body['session'] as Map)
          : null,
      taskName: body['taskName'] as String?,
    );
  }

  Map<String, dynamic>? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }
}

/// 云端最新会话快照。
class RemoteSessionState {
  const RemoteSessionState({
    required this.seq,
    required this.deviceId,
    required this.session,
    required this.taskName,
  });

  /// 单调递增序号；0 表示云端无记录。
  final int seq;

  /// 发布者设备标识；空表示云端无记录。
  final String deviceId;

  /// `ActiveSession.toMap()` 快照；null 表示对端已无会话。
  final Map<String, dynamic>? session;

  /// 发布者当时的任务名（仅供 UI 提示用）。
  final String? taskName;
}

class SessionChannelException implements Exception {
  SessionChannelException(this.message);

  final String message;

  @override
  String toString() => message;
}
