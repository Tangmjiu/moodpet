import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodpet/core/models/provider_config.dart';
import 'package:moodpet/core/utils/provider_share_codec.dart';

void main() {
  group('provider_share_codec round-trip', () {
    test('encode -> decode preserves fields and strips secret/local state', () {
      const original = ProviderConfig(
        id: 'original-local-id',
        name: 'My Custom Endpoint',
        baseUrl: 'https://llm.example.com/v1',
        defaultModel: 'my-model-7b',
        apiKey: 'sk-secret-123',
        iconAsset: 'assets/icons/providers/x.svg',
        brandColor: '#123456',
        protocol: LlmProtocol.claude,
        modelsEndpoint: '/v1/models',
        chatCompletionsPath: '/v2/chat/completions',
        modelOverride: 'my-model-13b',
        isCustom: true,
        enabled: false,
      );

      final encoded = encodeProviderShare(original);
      final decoded = decodeProviderShare(encoded);

      expect(decoded, isNotNull);
      final d = decoded!;
      expect(d.name, original.name);
      expect(d.baseUrl, original.baseUrl);
      expect(d.protocol, original.protocol);
      expect(d.defaultModel, original.defaultModel);
      expect(d.modelsEndpoint, original.modelsEndpoint);
      expect(d.chatCompletionsPath, original.chatCompletionsPath);
      expect(d.isCustom, isTrue);
      expect(d.apiKey, '');
      expect(d.iconAsset, '');
      expect(d.brandColor, '');
      expect(d.id, isNotEmpty);
      expect(d.id, isNot(original.id));
    });
  });

  group('provider_share_codec payload safety', () {
    test('encoded string and its decoded JSON omit apiKey and modelOverride', () {
      const provider = ProviderConfig(
        id: 'p',
        name: 'P',
        baseUrl: 'https://p.example.com',
        defaultModel: 'p-model',
        apiKey: 'sk-secret-123',
        iconAsset: '',
        brandColor: '',
        modelOverride: 'p-model-override',
      );
      final encoded = encodeProviderShare(provider);

      // The share string itself must not carry the secret or override token.
      expect(encoded.contains('sk-secret-123'), isFalse);
      expect(encoded.contains('modelOverride'), isFalse);

      // Decode the base64 segment and inspect the inner JSON for the same tokens.
      final prefixStripped = encoded.substring(kProviderSharePrefix.length);
      final jsonBytes = base64Decode(prefixStripped);
      final innerJson = utf8.decode(jsonBytes);
      expect(innerJson.contains('sk-secret-123'), isFalse);
      expect(innerJson.contains('modelOverride'), isFalse);
    });
  });

  group('provider_share_codec decode failure modes', () {
    test('wrong prefix returns null', () {
      final payload = base64Encode(
        utf8.encode(jsonEncode(<String, Object?>{
          'v': 1,
          'name': 'X',
          'baseUrl': 'https://x.example.com',
        })),
      );
      final raw = 'ai-provider:v1:$payload';
      expect(decodeProviderShare(raw), isNull);
    });

    test('corrupt base64 returns null', () {
      expect(decodeProviderShare('moodpet-provider:v1:!!!not-b64'), isNull);
    });

    test('valid base64 of non-JSON returns null', () {
      final payload = base64Encode(utf8.encode('this is not json'));
      expect(decodeProviderShare('moodpet-provider:v1:$payload'), isNull);
    });

    test('JSON missing name returns null', () {
      final payload = base64Encode(
        utf8.encode(jsonEncode(<String, Object?>{
          'v': 1,
          'baseUrl': 'https://x.example.com',
        })),
      );
      expect(decodeProviderShare('moodpet-provider:v1:$payload'), isNull);
    });

    test('JSON missing baseUrl returns null', () {
      final payload = base64Encode(
        utf8.encode(jsonEncode(<String, Object?>{
          'v': 1,
          'name': 'X',
        })),
      );
      expect(decodeProviderShare('moodpet-provider:v1:$payload'), isNull);
    });
  });

  group('provider_share_codec decode defaults', () {
    test('unknown protocol string falls back to openai', () {
      final payload = base64Encode(
        utf8.encode(jsonEncode(<String, Object?>{
          'v': 1,
          'name': 'X',
          'baseUrl': 'https://x.example.com',
          'protocol': 'weird-unknown',
        })),
      );
      final decoded = decodeProviderShare('moodpet-provider:v1:$payload');
      expect(decoded, isNotNull);
      expect(decoded!.protocol, LlmProtocol.openai);
    });

    test('missing optional fields use defaults', () {
      final payload = base64Encode(
        utf8.encode(jsonEncode(<String, Object?>{
          'v': 1,
          'name': 'X',
          'baseUrl': 'https://x.example.com',
        })),
      );
      final decoded = decodeProviderShare('moodpet-provider:v1:$payload');
      expect(decoded, isNotNull);
      final d = decoded!;
      expect(d.modelsEndpoint, isNull);
      expect(d.defaultModel, '');
      expect(d.chatCompletionsPath, '/chat/completions');
      expect(d.protocol, LlmProtocol.openai);
    });

    test('leading/trailing whitespace in raw still decodes', () {
      const provider = ProviderConfig(
        id: 'p',
        name: 'P',
        baseUrl: 'https://p.example.com',
        defaultModel: 'p-model',
        apiKey: '',
        iconAsset: '',
        brandColor: '',
      );
      final encoded = encodeProviderShare(provider);
      final padded = '  \n$encoded \t ';
      final decoded = decodeProviderShare(padded);
      expect(decoded, isNotNull);
      expect(decoded!.name, 'P');
      expect(decoded.baseUrl, 'https://p.example.com');
    });
  });
}
