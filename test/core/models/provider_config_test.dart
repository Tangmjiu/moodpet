import 'package:flutter_test/flutter_test.dart';
import 'package:moodpet/core/models/provider_config.dart';

void main() {
  group('ProviderConfig JSON codec', () {
    test('toJson -> fromJson round-trip preserves serialized fields', () {
      const original = ProviderConfig(
        id: 'my-custom',
        name: 'My Custom Provider',
        baseUrl: 'https://llm.example.com/v1',
        defaultModel: 'my-model-7b',
        apiKey: 'sk-secret-should-not-serialize',
        iconAsset: '',
        brandColor: '',
        protocol: LlmProtocol.claude,
        modelsEndpoint: '/models',
        chatCompletionsPath: '/v2/chat/completions',
        isCustom: true,
        enabled: false,
      );

      final json = original.toJson();
      final restored = ProviderConfig.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.baseUrl, original.baseUrl);
      expect(restored.defaultModel, original.defaultModel);
      expect(restored.protocol, original.protocol);
      expect(restored.modelsEndpoint, original.modelsEndpoint);
      expect(restored.chatCompletionsPath, original.chatCompletionsPath);
      expect(restored.isCustom, original.isCustom);
    });

    test('toJson never serializes secret or runtime-only fields', () {
      const config = ProviderConfig(
        id: 'x',
        name: 'X',
        baseUrl: 'https://x.example.com',
        defaultModel: 'x-model',
        apiKey: 'sk-secret',
        iconAsset: 'assets/icon.svg',
        brandColor: '#FFFFFF',
        modelOverride: 'override-model',
        enabled: false,
      );

      final json = config.toJson();

      expect(json.containsKey('apiKey'), isFalse);
      expect(json.containsKey('modelOverride'), isFalse);
      expect(json.containsKey('enabled'), isFalse);
      expect(json.containsKey('iconAsset'), isFalse);
      expect(json.containsKey('brandColor'), isFalse);
      expect(json.containsKey('recommended'), isFalse);
    });

    test('fromJson applies defaults for missing optional keys', () {
      final config = ProviderConfig.fromJson(<String, Object?>{
        'id': 'custom-1',
        'name': 'Custom One',
        'baseUrl': 'https://one.example.com',
        'defaultModel': 'one-model',
      });

      expect(config.protocol, LlmProtocol.openai);
      expect(config.chatCompletionsPath, '/chat/completions');
      expect(config.isCustom, isFalse);
      expect(config.modelsEndpoint, isNull);
      expect(config.apiKey, isEmpty);
      expect(config.recommended, isFalse);
      expect(config.enabled, isTrue);
    });

    test('fromJson reads isCustom from the map when present', () {
      final config = ProviderConfig.fromJson(<String, Object?>{
        'id': 'custom-2',
        'name': 'Custom Two',
        'baseUrl': 'https://two.example.com',
        'defaultModel': 'two-model',
        'isCustom': true,
      });

      expect(config.isCustom, isTrue);
    });

    test('fromJson falls back to openai for unknown protocol string', () {
      final config = ProviderConfig.fromJson(<String, Object?>{
        'id': 'custom-3',
        'name': 'Custom Three',
        'baseUrl': 'https://three.example.com',
        'defaultModel': 'three-model',
        'protocol': 'not-a-real-protocol',
      });

      expect(config.protocol, LlmProtocol.openai);
    });

    test('fromJson throws FormatException for wrong-typed values', () {
      expect(
        () => ProviderConfig.fromJson(<String, Object?>{
          'id': 42,
          'name': 'Bad',
          'baseUrl': 'https://bad.example.com',
          'defaultModel': 'bad-model',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ProviderConfig.fromJson(<String, Object?>{
          'id': 'bad',
          'name': 'Bad',
          'baseUrl': 'https://bad.example.com',
          'defaultModel': 'bad-model',
          'isCustom': 'yes',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson tolerates null values for optional keys', () {
      final config = ProviderConfig.fromJson(<String, Object?>{
        'id': 'nullable',
        'name': 'Nullable',
        'baseUrl': 'https://nullable.example.com',
        'defaultModel': 'nullable-model',
        'protocol': null,
        'modelsEndpoint': null,
        'chatCompletionsPath': null,
        'isCustom': null,
      });

      expect(config.protocol, LlmProtocol.openai);
      expect(config.modelsEndpoint, isNull);
      expect(config.chatCompletionsPath, '/chat/completions');
      expect(config.isCustom, isFalse);
    });
  });

  group('ProviderConfig.isConfigured', () {
    test('builtin provider with empty key is not configured', () {
      const config = ProviderConfig(
        id: 'openai',
        name: 'OpenAI',
        baseUrl: 'https://api.openai.com',
        defaultModel: 'gpt-4o-mini',
        apiKey: '',
        iconAsset: '',
        brandColor: '',
      );
      expect(config.isConfigured, isFalse);
    });

    test('builtin provider with key is configured', () {
      const config = ProviderConfig(
        id: 'openai',
        name: 'OpenAI',
        baseUrl: 'https://api.openai.com',
        defaultModel: 'gpt-4o-mini',
        apiKey: 'sk-test',
        iconAsset: '',
        brandColor: '',
      );
      expect(config.isConfigured, isTrue);
    });

    test('custom provider with empty key but valid baseUrl is configured', () {
      const config = ProviderConfig(
        id: 'custom',
        name: 'Custom',
        baseUrl: 'https://custom.example.com',
        defaultModel: 'custom-model',
        apiKey: '',
        iconAsset: '',
        brandColor: '',
        isCustom: true,
      );
      expect(config.isConfigured, isTrue);
    });

    test('custom provider with empty baseUrl is not configured', () {
      const config = ProviderConfig(
        id: 'custom',
        name: 'Custom',
        baseUrl: '',
        defaultModel: 'custom-model',
        apiKey: 'sk-even-with-a-key',
        iconAsset: '',
        brandColor: '',
        isCustom: true,
      );
      expect(config.isConfigured, isFalse);
    });
  });

  group('ProviderConfig copyWith and equality', () {
    const base = ProviderConfig(
      id: 'base',
      name: 'Base',
      baseUrl: 'https://base.example.com',
      defaultModel: 'base-model',
      apiKey: 'sk-base',
      iconAsset: '',
      brandColor: '',
    );

    test('copyWith updates protocol', () {
      final updated = base.copyWith(protocol: LlmProtocol.gemini);
      expect(updated.protocol, LlmProtocol.gemini);
      expect(updated.id, base.id);
      expect(updated.apiKey, base.apiKey);
    });

    test('copyWith updates enabled', () {
      final updated = base.copyWith(enabled: false);
      expect(updated.enabled, isFalse);
      expect(base.enabled, isTrue);
    });

    test('copyWith updates chatCompletionsPath', () {
      final updated = base.copyWith(chatCompletionsPath: '/v2/chat');
      expect(updated.chatCompletionsPath, '/v2/chat');
    });

    test('equality reflects protocol, isCustom, and enabled differences', () {
      final withProtocol = base.copyWith(protocol: LlmProtocol.claude);
      expect(withProtocol == base, isFalse);

      const custom = ProviderConfig(
        id: 'base',
        name: 'Base',
        baseUrl: 'https://base.example.com',
        defaultModel: 'base-model',
        apiKey: 'sk-base',
        iconAsset: '',
        brandColor: '',
        isCustom: true,
      );
      expect(custom == base, isFalse);

      final disabled = base.copyWith(enabled: false);
      expect(disabled == base, isFalse);

      expect(base.copyWith() == base, isTrue);
      expect(base.copyWith().hashCode, base.hashCode);
    });

    test('configs sharing an id but differing in baseUrl are not equal', () {
      const otherUrl = ProviderConfig(
        id: 'base',
        name: 'Base',
        baseUrl: 'https://other.example.com',
        defaultModel: 'base-model',
        apiKey: 'sk-base',
        iconAsset: '',
        brandColor: '',
      );
      expect(otherUrl == base, isFalse);
      expect(otherUrl.hashCode, isNot(base.hashCode));
    });
  });

  group('LlmProtocol', () {
    test('jsonValue round-trips through fromJsonValue', () {
      for (final protocol in LlmProtocol.values) {
        expect(LlmProtocol.fromJsonValue(protocol.jsonValue), protocol);
      }
    });

    test('fromJsonValue falls back to openai for null or unknown', () {
      expect(LlmProtocol.fromJsonValue(null), LlmProtocol.openai);
      expect(LlmProtocol.fromJsonValue(''), LlmProtocol.openai);
      expect(LlmProtocol.fromJsonValue('llama'), LlmProtocol.openai);
    });

    test('builtin claude and gemini entries declare their protocol', () {
      expect(builtinProviderById('claude')!.protocol, LlmProtocol.claude);
      expect(builtinProviderById('gemini')!.protocol, LlmProtocol.gemini);
      expect(builtinProviderById('openai')!.protocol, LlmProtocol.openai);
    });
  });
}
