import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodpet/core/agent/connection_tester.dart';
import 'package:moodpet/core/models/provider_config.dart';

ProviderConfig _provider({
  String baseUrl = 'https://api.example.com',
  String apiKey = 'k1',
  String defaultModel = 'm1',
  LlmProtocol protocol = LlmProtocol.openai,
  bool isCustom = false,
}) =>
    ProviderConfig(
      id: 'test',
      name: 'Test Provider',
      baseUrl: baseUrl,
      defaultModel: defaultModel,
      apiKey: apiKey,
      iconAsset: '',
      brandColor: '',
      protocol: protocol,
      isCustom: isCustom,
    );

http.Response _openAiOk(String content) => http.Response(
      jsonEncode(<String, Object?>{
        'choices': <Map<String, Object?>>[
          <String, Object?>{
            'message': <String, String>{'role': 'assistant', 'content': content},
          },
        ],
      }),
      200,
    );

http.Response _claudeOk(String content) => http.Response(
      jsonEncode(<String, Object?>{
        'content': <Map<String, Object?>>[
          <String, Object?>{'type': 'text', 'text': content},
        ],
      }),
      200,
    );

void main() {
  group('testProviderConnection', () {
    test('200 openai shape -> ok true, status 200, latency recorded, no error',
        () async {
      final client = MockClient((request) async => _openAiOk('OK'));

      final result = await testProviderConnection(
        provider: _provider(),
        client: client,
      );

      expect(result.ok, isTrue);
      expect(result.statusCode, 200);
      expect(result.error, isNull);
      expect(result.latencyMs, greaterThanOrEqualTo(0));
    });

    test('401 -> ok false, status 401, error surfaced', () async {
      final client = MockClient(
        (request) async => http.Response('unauthorized', 401),
      );

      final result = await testProviderConnection(
        provider: _provider(),
        client: client,
      );

      expect(result.ok, isFalse);
      expect(result.statusCode, 401);
      expect(result.error, isNotNull);
    });

    test('network throw -> ok false, status 0, error mentions request failed',
        () async {
      final client = MockClient(
        (request) async => throw http.ClientException('connection refused'),
      );

      final result = await testProviderConnection(
        provider: _provider(),
        client: client,
      );

      expect(result.ok, isFalse);
      expect(result.statusCode, 0);
      expect(result.error, contains('request failed'));
    });

    test('claude protocol -> wire path is /v1/messages (protocol-aware)',
        () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return _claudeOk('OK');
      });

      final result = await testProviderConnection(
        provider: _provider(protocol: LlmProtocol.claude),
        client: client,
      );

      expect(result.ok, isTrue);
      expect(result.statusCode, 200);
      expect(result.error, isNull);
      expect(captured!.url.toString(), endsWith('/v1/messages'));
      expect(captured!.headers['x-api-key'], 'k1');
      expect(captured!.headers.containsKey('Authorization'), isFalse);
    });

    test('request body carries a tiny token budget (openai max_tokens 8)',
        () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return _openAiOk('OK');
      });

      await testProviderConnection(
        provider: _provider(),
        client: client,
      );

      final body = jsonDecode(captured!.body) as Map<String, Object?>;
      expect(body['max_tokens'], 8);
      final messages = body['messages']! as List<Object?>;
      expect(messages, hasLength(2));
      expect(
        (messages[0]! as Map<String, Object?>)['content'],
        'Reply with OK.',
      );
      expect(
        (messages[1]! as Map<String, Object?>)['content'],
        'OK',
      );
    });

    test('malformed 200 body -> ok false, error non-null, no crash', () async {
      final client = MockClient(
        (request) async => http.Response('<<garbage>>', 200),
      );

      final result = await testProviderConnection(
        provider: _provider(),
        client: client,
      );

      expect(result.ok, isFalse);
      expect(result.statusCode, 200);
      expect(result.error, isNotNull);
    });
  });
}
