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
    test('splits on commas and any whitespace run, dropping empty segments', () {
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

  group('chatCompletion openai protocol', () {
    test('posts to chatCompletionsPath with Bearer key and parses content',
        () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return _openAiOk('hello there');
      });

      final result = await chatCompletion(
        provider: _provider(),
        systemPrompt: 'sys',
        userInput: 'hi',
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(result.content, 'hello there');
      expect(result.error, isNull);

      final request = captured!;
      expect(request.method, 'POST');
      expect(request.url.toString(), endsWith('/chat/completions'));
      expect(request.headers['Authorization'], 'Bearer k1');
      expect(request.headers['Content-Type'], contains('application/json'));

      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['model'], 'm1');
      expect(body['temperature'], 0.8);
      expect(body['max_tokens'], 300);
      final messages = body['messages']! as List<Object?>;
      expect(messages, hasLength(2));
      expect(messages[0], <String, String>{'role': 'system', 'content': 'sys'});
      expect(messages[1], <String, String>{'role': 'user', 'content': 'hi'});
    });

    test('custom path from chatCompletionsPath is honored', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return _openAiOk('ok');
      });

      final provider = _provider().copyWith(chatCompletionsPath: '/v2/chat');
      final result = await chatCompletion(
        provider: provider,
        systemPrompt: 'sys',
        userInput: 'hi',
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(captured!.url.toString(), endsWith('/v2/chat'));
    });

    test('200 with a non-JSON body fails with a reason instead of throwing',
        () async {
      final client = MockClient((request) async => http.Response('<<garbage>>', 200));

      final result = await chatCompletion(
        provider: _provider(),
        systemPrompt: 'sys',
        userInput: 'hi',
        client: client,
      );

      expect(result.isOk, isFalse);
      expect(result.error, isNotNull);
      expect(result.error, isNot(contains('request failed')));
    });
  });

  group('chatCompletion claude protocol', () {
    test('posts to /v1/messages with x-api-key and parses the text block',
        () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'content': <Map<String, Object?>>[
              <String, Object?>{'type': 'text', 'text': 'hi'},
            ],
          }),
          200,
        );
      });

      final result = await chatCompletion(
        provider: _provider(protocol: LlmProtocol.claude),
        systemPrompt: 'sys',
        userInput: 'hello',
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(result.content, 'hi');

      final request = captured!;
      expect(request.url.toString(), endsWith('/v1/messages'));
      expect(request.headers['x-api-key'], 'k1');
      expect(request.headers['anthropic-version'], '2023-06-01');
      expect(request.headers.containsKey('Authorization'), isFalse);

      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['model'], 'm1');
      expect(body['max_tokens'], 300);
      expect(body['system'], 'sys');
      final messages = body['messages']! as List<Object?>;
      expect(messages, hasLength(1));
      expect(messages[0], <String, String>{'role': 'user', 'content': 'hello'});
    });

    test('relay baseUrl ending in /v1 does not double the version segment',
        () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'content': <Map<String, Object?>>[
              <String, Object?>{'type': 'text', 'text': 'hi'},
            ],
          }),
          200,
        );
      });

      final result = await chatCompletion(
        provider: _provider(
          baseUrl: 'https://relay.example.com/v1',
          protocol: LlmProtocol.claude,
        ),
        systemPrompt: 'sys',
        userInput: 'hello',
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(captured!.url.toString(), 'https://relay.example.com/v1/messages');
      expect(captured!.url.path, isNot(contains('/v1/v1/')));
    });

    test('skips non-text blocks and reads the first text block', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode(<String, Object?>{
              'content': <Map<String, Object?>>[
                <String, Object?>{'type': 'thinking', 'thinking': 'hmm'},
                <String, Object?>{'type': 'text', 'text': 'real answer'},
              ],
            }),
            200,
          ));

      final result = await chatCompletion(
        provider: _provider(protocol: LlmProtocol.claude),
        systemPrompt: 'sys',
        userInput: 'hello',
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(result.content, 'real answer');
    });

    test('200 with no text content block fails with a reason', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode(<String, Object?>{'content': <Object?>[]}),
            200,
          ));

      final result = await chatCompletion(
        provider: _provider(protocol: LlmProtocol.claude),
        systemPrompt: 'sys',
        userInput: 'hello',
        client: client,
      );

      expect(result.isOk, isFalse);
      expect(result.error, isNotNull);
    });
  });

  group('chatCompletion gemini protocol', () {
    test('posts to generateContent with key query param and parses text',
        () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'candidates': <Map<String, Object?>>[
              <String, Object?>{
                'content': <String, Object?>{
                  'parts': <Map<String, String>>[
                    <String, String>{'text': 'ok'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      });

      final result = await chatCompletion(
        provider: _provider(protocol: LlmProtocol.gemini),
        systemPrompt: 'sys',
        userInput: 'hello',
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(result.content, 'ok');

      final request = captured!;
      expect(request.url.path, contains('/v1beta/models/m1:generateContent'));
      expect(request.url.queryParameters['key'], 'k1');
      expect(request.headers.containsKey('Authorization'), isFalse);

      final body = jsonDecode(request.body) as Map<String, Object?>;
      final systemInstruction =
          body['systemInstruction']! as Map<String, Object?>;
      final systemParts = systemInstruction['parts']! as List<Object?>;
      expect(
        systemParts[0],
        <String, String>{'text': 'sys'},
      );
      final contents = body['contents']! as List<Object?>;
      expect(contents, hasLength(1));
      final content = contents[0]! as Map<String, Object?>;
      expect(content['role'], 'user');
      final contentParts = content['parts']! as List<Object?>;
      expect(contentParts[0], <String, String>{'text': 'hello'});
      final generationConfig = body['generationConfig']! as Map<String, Object?>;
      expect(generationConfig['temperature'], 0.8);
      expect(generationConfig['maxOutputTokens'], 300);
    });

    test('relay baseUrl ending in /v1beta does not double the version segment',
        () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'candidates': <Map<String, Object?>>[
              <String, Object?>{
                'content': <String, Object?>{
                  'parts': <Map<String, String>>[
                    <String, String>{'text': 'ok'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      });

      final result = await chatCompletion(
        provider: _provider(
          baseUrl: 'https://relay.example.com/v1beta',
          protocol: LlmProtocol.gemini,
        ),
        systemPrompt: 'sys',
        userInput: 'hello',
        client: client,
      );

      expect(result.isOk, isTrue);
      final url = captured!.url;
      expect(url.path, contains('/models/m1:generateContent'));
      expect(url.path, isNot(contains('/v1beta/v1beta/')));
      expect(url.queryParameters['key'], 'k1');
    });

    test('200 with no candidates fails with a reason', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode(<String, Object?>{}),
            200,
          ));

      final result = await chatCompletion(
        provider: _provider(protocol: LlmProtocol.gemini),
        systemPrompt: 'sys',
        userInput: 'hello',
        client: client,
      );

      expect(result.isOk, isFalse);
      expect(result.error, isNotNull);
    });
  });

  group('chatCompletion multi-key rotation and retry', () {
    test('429 retries once with the other key and succeeds', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (requests.length == 1) {
          return http.Response('rate limited', 429);
        }
        return _openAiOk('ok');
      });

      final result = await chatCompletion(
        provider: _provider(apiKey: 'k1, k2'),
        systemPrompt: 'sys',
        userInput: 'hi',
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(result.content, 'ok');
      expect(requests, hasLength(2));
      final authValues = requests
          .map((request) => request.headers['Authorization'])
          .toSet();
      expect(authValues, <String?>{'Bearer k1', 'Bearer k2'});
    });

    test('400 never retries, even with untried keys remaining', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('bad request', 400);
      });

      final result = await chatCompletion(
        provider: _provider(apiKey: 'k1, k2'),
        systemPrompt: 'sys',
        userInput: 'hi',
        client: client,
      );

      expect(result.isOk, isFalse);
      expect(result.statusCode, 400);
      expect(result.error, contains('HTTP 400'));
      expect(requests, hasLength(1));
    });

    test('network exceptions fail immediately without retrying', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        throw http.ClientException('connection refused');
      });

      final result = await chatCompletion(
        provider: _provider(apiKey: 'k1, k2'),
        systemPrompt: 'sys',
        userInput: 'hi',
        client: client,
      );

      expect(result.isOk, isFalse);
      expect(result.error, contains('request failed'));
      expect(calls, 1);
    });
  });

  group('chatCompletion key handling', () {
    test('keyless custom provider sends no Authorization header', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return _openAiOk('local ok');
      });

      final result = await chatCompletion(
        provider: _provider(apiKey: '', isCustom: true),
        systemPrompt: 'sys',
        userInput: 'hi',
        client: client,
      );

      expect(result.isOk, isTrue);
      expect(result.content, 'local ok');
      expect(captured!.headers.containsKey('Authorization'), isFalse);
    });

    test('keyless builtin provider fails without any HTTP call', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return _openAiOk('should not happen');
      });

      final result = await chatCompletion(
        provider: _provider(apiKey: ''),
        systemPrompt: 'sys',
        userInput: 'hi',
        client: client,
      );

      expect(result.isOk, isFalse);
      expect(result.statusCode, 0);
      expect(
        result.error,
        'provider not configured (missing base URL or API key)',
      );
      expect(calls, 0);
    });
  });
}
