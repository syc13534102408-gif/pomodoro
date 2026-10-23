import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:pomodoro_app/src/plan_remote.dart';

PlanRemote _with(MockClient client) =>
    PlanRemote(client: client, baseUrl: 'https://example.test/');

/// 服务端返回的是 UTF-8 JSON；`http.Response(String)` 默认按 latin1 编码，中文会直接抛，
/// 所以这里统一走 `Response.bytes`。
http.Response _json(Map<String, dynamic> body, int status) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('成功：返回服务端清洗好的日程文本', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return _json({'plan': '10/24\t2018 复盘\n10/25\t现控 ch6', 'lines': 2}, 200);
    });

    final plan = await _with(client).parse('下周一二做复盘和现控');
    expect(plan, '10/24\t2018 复盘\n10/25\t现控 ch6');
    expect(captured.url.toString(), 'https://example.test/plan/parse');
    expect(jsonDecode(captured.body)['text'], '下周一二做复盘和现控');
  });

  test('url 模式发的是 url 字段而不是 text', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return _json({'plan': '10/24\t复盘'}, 200);
    });

    await _with(client).parse('', url: 'https://example.com/plan.html');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['url'], 'https://example.com/plan.html');
    expect(body.containsKey('text'), isFalse);
  });

  test('服务端未配置密钥（501）给出可操作提示', () async {
    final client = MockClient(
        (_) async => _json({'error': '服务端未配置 PINE_LLM_API_KEY'}, 501));
    expect(
      () => _with(client).parse('随便'),
      throwsA(isA<PlanRemoteException>().having(
          (e) => e.message, 'message', contains('PINE_LLM_API_KEY'))),
    );
  });

  test('200 但 plan 为空也算失败，不静默返回空串', () async {
    final client = MockClient((_) async => _json({'plan': '  '}, 200));
    expect(() => _with(client).parse('随便'), throwsA(isA<PlanRemoteException>()));
  });

  test('其它错误码透传服务端原因', () async {
    final client = MockClient(
        (_) async => _json({'error': '调用模型失败：timeout'}, 502));
    expect(
      () => _with(client).parse('随便'),
      throwsA(isA<PlanRemoteException>()
          .having((e) => e.message, 'message', contains('timeout'))),
    );
  });
}
