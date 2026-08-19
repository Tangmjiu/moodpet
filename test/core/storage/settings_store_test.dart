import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodpet/core/models/provider_config.dart';
import 'package:moodpet/core/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Raw preference keys, mirrored from SettingsStore so the tests can seed and
// inspect storage directly.
const _kCustomProvidersKey = 'moodpet.provider.customProviders';
const _kEnabledPrefix = 'moodpet.provider.enabled.';
const _kModelsPrefix = 'moodpet.provider.models.';
const _kApiKeyPrefix = 'moodpet.provider.apiKey.';
const _kModelOverridePrefix = 'moodpet.provider.modelOverride.';
const _kActiveIdKey = 'moodpet.provider.activeId';

/// Build a custom provider entry. The API key is deliberately shaped like a
/// real secret so tests can prove it never reaches the persisted JSON.
ProviderConfig _custom(
  String id, {
  LlmProtocol protocol = LlmProtocol.openai,
}) =>
    ProviderConfig(
      id: id,
      name: 'Custom $id',
      baseUrl: 'https://$id.example.com/v1',
      defaultModel: '$id-model',
      apiKey: 'sk-$id-secret',
      iconAsset: '',
      brandColor: '',
      protocol: protocol,
      isCustom: true,
    );

/// Fresh store + prefs pair backed by an in-memory mock, optionally seeded.
Future<(SettingsStore, SharedPreferences)> _store([
  Map<String, Object> seed = const {},
]) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return (SettingsStore(prefs), prefs);
}

void main() {
  group('SettingsStore custom providers', () {
    test('save + load round-trips two providers without persisting API keys',
        () async {
      final (store, prefs) = await _store();
      final providers = <ProviderConfig>[
        _custom('alpha'),
        _custom('beta', protocol: LlmProtocol.gemini),
      ];

      await store.saveCustomProviders(providers);
      final loaded = store.loadCustomProviders();

      expect(loaded, hasLength(2));
      expect(loaded[0].id, 'alpha');
      expect(loaded[0].name, 'Custom alpha');
      expect(loaded[0].baseUrl, 'https://alpha.example.com/v1');
      expect(loaded[0].protocol, LlmProtocol.openai);
      expect(loaded[1].id, 'beta');
      expect(loaded[1].name, 'Custom beta');
      expect(loaded[1].baseUrl, 'https://beta.example.com/v1');
      expect(loaded[1].protocol, LlmProtocol.gemini);

      // API keys are secrets and must never reach the persisted JSON blob.
      final raw = prefs.getString(_kCustomProvidersKey);
      expect(raw, isNotNull);
      expect(raw!, isNot(contains('sk-')));
    });

    test('load returns empty list when the key is absent or empty', () async {
      final (absentStore, _) = await _store();
      expect(absentStore.loadCustomProviders(), isEmpty);

      final (emptyStore, _) = await _store({_kCustomProvidersKey: ''});
      expect(emptyStore.loadCustomProviders(), isEmpty);
    });

    test('load returns empty list for a corrupt JSON string', () async {
      final (store, _) = await _store({_kCustomProvidersKey: '{not json'});
      expect(store.loadCustomProviders(), isEmpty);
    });

    test('load skips malformed entries and keeps the valid ones', () async {
      final raw = jsonEncode(<Object?>[
        _custom('good').toJson(),
        <String, Object?>{
          'id': 'bad',
          'name': 'Bad',
          'baseUrl': 'https://bad.example.com',
          'defaultModel': 42, // wrong type — entry must be skipped
          'isCustom': true,
        },
      ]);
      final (store, _) = await _store({_kCustomProvidersKey: raw});

      final loaded = store.loadCustomProviders();
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'good');
    });
  });

  group('SettingsStore provider order', () {
    test('order round-trips and defaults to empty', () async {
      final (store, _) = await _store();
      expect(store.loadProviderOrder(), isEmpty);

      await store.saveProviderOrder(<String>['deepseek', 'my-custom', 'openai']);
      expect(store.loadProviderOrder(), <String>['deepseek', 'my-custom', 'openai']);
    });
  });

  group('SettingsStore provider enabled flags', () {
    test('defaults to true; disabling persists; re-enabling removes the key',
        () async {
      final (store, prefs) = await _store();
      expect(store.isProviderEnabled('p1'), isTrue);

      await store.setProviderEnabled('p1', false);
      expect(store.isProviderEnabled('p1'), isFalse);
      expect(prefs.containsKey('${_kEnabledPrefix}p1'), isTrue);

      await store.setProviderEnabled('p1', true);
      expect(store.isProviderEnabled('p1'), isTrue);
      expect(prefs.containsKey('${_kEnabledPrefix}p1'), isFalse);
    });
  });

  group('SettingsStore provider model lists', () {
    test('setModels round-trips and an empty list removes the key', () async {
      final (store, prefs) = await _store();
      expect(store.modelsFor('p1'), isEmpty);

      await store.setModels('p1', <String>['m-a', 'm-b']);
      expect(store.modelsFor('p1'), <String>['m-a', 'm-b']);

      await store.setModels('p1', <String>[]);
      expect(store.modelsFor('p1'), isEmpty);
      expect(prefs.containsKey('${_kModelsPrefix}p1'), isFalse);
    });
  });

  group('SettingsStore removeProviderState', () {
    test('clears every per-provider key for a custom provider id', () async {
      const id = 'my-custom';
      final (store, prefs) = await _store(<String, Object>{
        _kCustomProvidersKey: jsonEncode(<Object?>[_custom(id).toJson()]),
        '$_kApiKeyPrefix$id': 'sk-custom-secret',
        '$_kModelOverridePrefix$id': 'override-model',
        '$_kEnabledPrefix$id': false,
        '$_kModelsPrefix$id': <String>['m1', 'm2'],
      });

      await store.removeProviderState(id);

      // Re-read through the store and through raw prefs to prove removal.
      expect(store.apiKeyFor(id), isEmpty);
      expect(store.modelOverrideFor(id), isNull);
      expect(store.isProviderEnabled(id), isTrue);
      expect(store.modelsFor(id), isEmpty);
      expect(prefs.containsKey('$_kApiKeyPrefix$id'), isFalse);
      expect(prefs.containsKey('$_kModelOverridePrefix$id'), isFalse);
      expect(prefs.containsKey('$_kEnabledPrefix$id'), isFalse);
      expect(prefs.containsKey('$_kModelsPrefix$id'), isFalse);
    });

    test('never clears keys for a built-in provider id (guard)', () async {
      final (store, prefs) = await _store(<String, Object>{
        '${_kApiKeyPrefix}deepseek': 'sk-deepseek-secret',
      });

      await store.removeProviderState('deepseek');

      expect(store.apiKeyFor('deepseek'), 'sk-deepseek-secret');
      expect(prefs.containsKey('${_kApiKeyPrefix}deepseek'), isTrue);
    });
  });

  group('SettingsStore legacy coexistence', () {
    test('legacy provider keys are untouched by custom-provider storage',
        () async {
      final (store, prefs) = await _store(<String, Object>{
        '${_kApiKeyPrefix}deepseek': 'sk-legacy',
        _kActiveIdKey: 'deepseek',
      });

      expect(store.loadCustomProviders(), isEmpty);
      expect(store.activeProviderId, 'deepseek');
      expect(store.apiKeyFor('deepseek'), 'sk-legacy');
      expect(prefs.getString('${_kApiKeyPrefix}deepseek'), 'sk-legacy');
    });
  });
}
