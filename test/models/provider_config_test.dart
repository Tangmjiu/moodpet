import 'package:flutter_test/flutter_test.dart';
import 'package:moodpet/core/models/provider_config.dart';
import 'package:moodpet/core/models/region_info.dart';

void main() {
  group('ProviderConfig', () {
    test('builtinProviders is non-empty', () {
      expect(kBuiltinProviders, isNotEmpty);
      expect(kBuiltinProviders.length, greaterThanOrEqualTo(8));
    });

    test('builtinProviderById finds existing provider', () {
      final p = builtinProviderById('openai');
      expect(p, isNotNull);
      expect(p!.id, 'openai');
      expect(p.name, 'OpenAI');
      expect(p.baseUrl, 'https://api.openai.com');
    });

    test('builtinProviderById returns null for unknown id', () {
      expect(builtinProviderById('nonexistent'), isNull);
    });

    test('each builtin provider has required fields', () {
      for (final p in kBuiltinProviders) {
        expect(p.id, isNotEmpty);
        expect(p.name, isNotEmpty);
        expect(p.baseUrl, isNotEmpty);
        expect(p.defaultModel, isNotEmpty);
      }
    });

    test('copyWith creates a modified copy', () {
      final original = builtinProviderById('deepseek')!;
      final withKey = original.copyWith(apiKey: 'sk-test-123');
      expect(withKey.apiKey, 'sk-test-123');
      expect(withKey.id, original.id);
      expect(withKey.baseUrl, original.baseUrl);
      expect(withKey.isConfigured, true);
      expect(original.isConfigured, false); // original unchanged
    });

    test('effectiveModel uses modelOverride when set', () {
      final p = builtinProviderById('openai')!.copyWith(
        modelOverride: 'gpt-4o',
      );
      expect(p.effectiveModel, 'gpt-4o');
      expect(p.defaultModel, 'gpt-4o-mini');
    });
  });

  group('RegionInfo country names', () {
    test('countryNameFromCode returns Chinese names for known codes', () {
      expect(countryNameFromCode('CN'), '中国大陆');
      expect(countryNameFromCode('US'), '美国');
      expect(countryNameFromCode('JP'), '日本');
    });

    test('countryNameFromCode returns upper-cased code for unknown', () {
      expect(countryNameFromCode('XX'), 'XX');
    });

    test('countryNameFromCode handles null gracefully', () {
      expect(countryNameFromCode(null), '未知地区');
    });
  });
}
