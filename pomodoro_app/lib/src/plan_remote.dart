import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_sync.dart';

/// 智能解析失败：带上服务端给的原因，UI 直接显示这一句。
class PlanRemoteException implements Exception {
  PlanRemoteException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 「自然语言计划 → 标准日程文本」的服务端解析客户端。
///
/// 为什么要绕服务端：模型密钥不能进客户端（APK 可反编译），而且提示词要能随时改、
/// 不该逼用户装新包。客户端只发文本、收文本，落库仍走本地的 `parsePlan()`。
class PlanRemote {
  PlanRemote({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 25),
  })  : _client = client ?? http.Client(),
        _base = (baseUrl == null || baseUrl.trim().isEmpty)
            ? CloudSync.defaultBaseUrl
            : baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  final http.Client _client;
  final String _base;
  final Duration timeout;

  /// 把 [text]（一段计划/散文）或 [url]（网页）交给服务端解析，
  /// 返回 `MM/DD<TAB>条目` 形态的文本，可直接喂给 `parsePlan()`。
  Future<String> parse(String text, {String? url}) async {
    final res = await _client
        .post(
          Uri.parse('$_base/plan/parse'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            if (url != null && url.trim().isNotEmpty) 'url': url.trim() else 'text': text,
          }),
        )
        .timeout(timeout);

    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      body = null;
    }

    if (res.statusCode == 200) {
      final plan = body?['plan'];
      if (plan is String && plan.trim().isNotEmpty) return plan;
      throw PlanRemoteException('服务端返回了空日程');
    }
    if (res.statusCode == 501) {
      throw PlanRemoteException('服务端未配置智能解析（缺少 PINE_LLM_API_KEY）');
    }
    final reason = body?['error'];
    throw PlanRemoteException(
      reason is String && reason.isNotEmpty ? reason : 'HTTP ${res.statusCode}',
    );
  }
}
