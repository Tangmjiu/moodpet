import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodpet/core/agent/models_client.dart';
import 'package:moodpet/core/models/provider_config.dart';

ProviderConfig _provider({
  String id = 'openai',
  LlmProtocol protocol = LlmProtocol.openai,
  String apiKey = 'sk-test',
  String baseUrl = 'https://api.example.com',
  String? modelsEndpoint = '/v1/models',
  bool isCustom = false,
}) =>
    ProviderConfig(
      id: id,
      name: id,
      baseUrl: baseUrl,
      defaultModel: 'default-model',
      apiKey: apiKey,
      iconAsset: '',
      brandColor: '',
      modelsEndpoint: modelsEndpoint,
      protocol: protocol,
      isCustom: isCustom,
    );

/// A [MockClient] that records the request and replies with [status] and
/// [body]. Sets [called] so tests can assert whether any HTTP call happened.
MockClient _recordingClient(
  void Function(http.Request request) onRequest,
  String body,
  int status,
) =>
    MockClient((request) async {
      onRequest(request);
      return http.Response(body, status);
    });

void main() {
  group('fetchAvailableModels', () {
    test('openai protocol sends Bearer header and returns sorted ids', () async {
      http.Request? captured;
      final client = _recordingClient(
        (request) => captured = request,
        '{"data":[{"id":"m2"},{"id":"m1"}]}',
        200,
      );

      final result = await fetchAvailableModels(
        provider: _provider(),
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(result.statusCode, 200);
      expect(result.models, <String>['m1', 'm2']);
      expect(captured!.headers['Authorization'], 'Bearer sk-test');
      expect(captured!.url.toString(), 'https://api.example.com/v1/models');
    });

    test('openai protocol falls back to the models[] response shape', () async {
      final client = _recordingClient(
        (_) {},
        '{"models":[{"name":"a"},{"name":"b"}]}',
        200,
      );

      final result = await fetchAvailableModels(
        provider: _provider(),
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(result.models, <String>['a', 'b']);
    });

    test('claude protocol sends x-api-key and anthropic-version headers',
        () async {
      http.Request? captured;
      final client = _recordingClient(
        (request) => captured = request,
        '{"data":[{"id":"c1"}]}',
        200,
      );

      final result = await fetchAvailableModels(
        provider: _provider(
          id: 'claude',
          protocol: LlmProtocol.claude,
          apiKey: 'claude-key',
        ),
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(result.models, <String>['c1']);
      expect(captured!.headers['x-api-key'], 'claude-key');
      expect(captured!.headers['anthropic-version'], '2023-06-01');
      expect(captured!.headers.containsKey('Authorization'), isFalse);
      expect(captured!.url.toString(), endsWith('/v1/models'));
    });

    test('gemini protocol authenticates via key query param and strips prefix',
        () async {
      http.Request? captured;
      final client = _recordingClient(
        (request) => captured = request,
        '{"models":[{"name":"models/g1"},{"name":"models/g2"}]}',
        200,
      );

      final result = await fetchAvailableModels(
        provider: _provider(
          id: 'gemini',
          protocol: LlmProtocol.gemini,
          apiKey: 'gemini-key',
          modelsEndpoint: '/v1beta/models',
        ),
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(result.models, <String>['g1', 'g2']);
      expect(captured!.url.queryParameters['key'], 'gemini-key');
      expect(captured!.headers.containsKey('Authorization'), isFalse);
    });

    test('gemini key query param merges with an existing endpoint query',
        () async {
      http.Request? captured;
      final client = _recordingClient(
        (request) => captured = request,
        '{"models":[{"name":"models/g1"}]}',
        200,
      );

      final result = await fetchAvailableModels(
        provider: _provider(
          id: 'gemini',
          protocol: LlmProtocol.gemini,
          apiKey: 'gemini-key',
          modelsEndpoint: '/v1beta/models?alt=json',
        ),
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(captured!.url.queryParameters['key'], 'gemini-key');
      expect(captured!.url.queryParameters['alt'], 'json');
    });

    test('provider without modelsEndpoint fails without any HTTP call',
        () async {
      var called = false;
      final client = _recordingClient((_) => called = true, '{}', 200);

      final result = await fetchAvailableModels(
        provider: _provider(modelsEndpoint: null),
        client: client,
      );

      expect(result.isOk, isFalse);
      expect(result.error, '此提供商不支持在线获取模型列表');
      expect(called, isFalse);
    });

    test('keyless built-in provider fails without any HTTP call', () async {
      var called = false;
      final client = _recordingClient((_) => called = true, '{}', 200);

      final result = await fetchAvailableModels(
        provider: _provider(apiKey: ''),
        client: client,
      );

      expect(result.isOk, isFalse);
      expect(result.error, '请先填写 API Key');
      expect(called, isFalse);
    });

    test('keyless custom provider fetches without an Authorization header',
        () async {
      http.Request? captured;
      final client = _recordingClient(
        (request) => captured = request,
        '{"data":[{"id":"local-model"}]}',
        200,
      );

      final result = await fetchAvailableModels(
        provider: _provider(
          id: 'my-local',
          apiKey: '',
          baseUrl: 'http://localhost:11434/v1',
          modelsEndpoint: '/models',
          isCustom: true,
        ),
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(result.models, <String>['local-model']);
      expect(captured!.headers.containsKey('Authorization'), isFalse);
    });

    test('multi-key field sends exactly one of the keys, never the joined '
        'string', () async {
      http.Request? captured;
      final client = _recordingClient(
        (request) => captured = request,
        '{"data":[{"id":"m1"}]}',
        200,
      );

      final result = await fetchAvailableModels(
        provider: _provider(apiKey: 'k1, k2'),
        client: client,
      );

      expect(result.isOk, isTrue);
      final auth = captured!.headers['Authorization'];
      // Exactly one picked key, never the joined multi-key string.
      expect(auth, isIn(<String>['Bearer k1', 'Bearer k2']));
      expect(auth, isNot('Bearer k1, k2'));
    });

    test('keyless custom claude provider omits x-api-key and still succeeds',
        () async {
      http.Request? captured;
      final client = _recordingClient(
        (request) => captured = request,
        '{"data":[{"id":"local-claude"}]}',
        200,
      );

      final result = await fetchAvailableModels(
        provider: _provider(
          id: 'local-claude',
          protocol: LlmProtocol.claude,
          apiKey: '',
          baseUrl: 'http://localhost:8080',
          modelsEndpoint: '/v1/models',
          isCustom: true,
        ),
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(result.statusCode, 200);
      expect(captured!.headers.containsKey('x-api-key'), isFalse);
      expect(captured!.headers['anthropic-version'], '2023-06-01');
    });

    test('non-200 response fails with the HTTP status in the error', () async {
      final client = _recordingClient((_) {}, '{"error":"unauthorized"}', 401);

      final result = await fetchAvailableModels(
        provider: _provider(),
        client: client,
      );

      expect(result.isOk, isFalse);
      expect(result.statusCode, 401);
      expect(result.error, contains('HTTP 401'));
    });

    test('non-object JSON body fails instead of crashing', () async {
      final client = _recordingClient((_) {}, '[1,2,3]', 200);

      final result = await fetchAvailableModels(
        provider: _provider(),
        client: client,
      );

      expect(result.isOk, isFalse);
      expect(result.error, '响应不是 JSON 对象');
    });

    test('empty model list fails with a no-models error', () async {
      final client = _recordingClient((_) {}, '{"data":[]}', 200);

      final result = await fetchAvailableModels(
        provider: _provider(),
        client: client,
      );

      expect(result.isOk, isFalse);
      expect(result.error, '响应中没有可用的模型');
    });
  });
}
