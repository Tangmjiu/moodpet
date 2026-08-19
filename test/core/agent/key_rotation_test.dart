import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodpet/core/agent/llm_client.dart';
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

void main() {
  group('splitApiKeys', () {
    test(
        'splits on commas, spaces, newlines, and tabs, dropping empty segments',
        () {
      expect(splitApiKeys('a, b\nc  d'), <String>['a', 'b', 'c', 'd']);
    });

    test('whitespace-only and empty input produce no keys', () {
      expect(splitApiKeys('  '), isEmpty);
      expect(splitApiKeys(''), isEmpty);
    });

    test('duplicates are preserved (no dedupe)', () {
      expect(splitApiKeys('a,a'), <String>['a', 'a']);
    });
  });

  group('chatCompletion key rotation', () {
    test('three keys rotate through all keys on 403 and succeed', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (requests.length <= 2) {
          return http.Response('forbidden', 403);
        }
        return _openAiOk('ok');
      });

      final result = await chatCompletion(
        provider: _provider(apiKey: 'k1 k2 k3'),
        systemPrompt: 'sys',
        userInput: 'hi',
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(result.content, 'ok');
      expect(requests, hasLength(3));
      // Order is random per attempt; assert the SET of credentials used.
      final authValues = requests
          .map((request) => request.headers['Authorization'])
          .toSet();
      expect(authValues, <String?>{'Bearer k1', 'Bearer k2', 'Bearer k3'});
    });

    test('single key with 403 fails after exactly one request', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('forbidden', 403);
      });

      final result = await chatCompletion(
        provider: _provider(apiKey: 'only'),
        systemPrompt: 'sys',
        userInput: 'hi',
        client: client,
      );

      expect(result.isOk, isFalse);
      expect(result.statusCode, 403);
      expect(result.error, contains('HTTP 403'));
      expect(requests, hasLength(1));
    });

    test(
        'two keys both rate-limited at 429 terminate without infinite retry',
        () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('rate limited', 429);
      });

      final result = await chatCompletion(
        provider: _provider(apiKey: 'k1, k2'),
        systemPrompt: 'sys',
        userInput: 'hi',
        client: client,
      );

      expect(result.isOk, isFalse);
      expect(result.statusCode, 429);
      expect(result.error, contains('HTTP 429'));
      expect(requests, hasLength(2));
    });

    test(
        'keyless custom provider does not retry on 401 and sends no '
        'Authorization header', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('unauthorized', 401);
      });

      final result = await chatCompletion(
        provider: _provider(apiKey: '', isCustom: true),
        systemPrompt: 'sys',
        userInput: 'hi',
        client: client,
      );

      expect(result.isOk, isFalse);
      expect(result.statusCode, 401);
      expect(result.error, contains('HTTP 401'));
      expect(requests, hasLength(1));
      expect(requests.single.headers.containsKey('Authorization'), isFalse);
    });
  });
}
