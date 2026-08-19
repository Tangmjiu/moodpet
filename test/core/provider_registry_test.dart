import 'package:flutter_test/flutter_test.dart';
import 'package:moodpet/core/models/provider_config.dart';
import 'package:moodpet/core/provider_registry.dart';
import 'package:moodpet/core/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Build a custom provider entry the way the settings UI would.
ProviderConfig _custom(String id) => ProviderConfig(
      id: id,
      name: 'Custom $id',
      baseUrl: 'https://$id.example.com/v1',
      defaultModel: '$id-model',
      apiKey: '',
      iconAsset: '',
      brandColor: '',
      isCustom: true,
    );

/// Fresh registry + store pair backed by an in-memory mock, optionally seeded.
Future<(ProviderRegistry, SettingsStore)> _registry([
  Map<String, Object> seed = const {},
]) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  final store = SettingsStore(prefs);
  return (ProviderRegistry(store), store);
}

void main() {
  group('ProviderRegistry.all', () {
    test('empty prefs returns the 16 builtins in catalog order, all enabled '
        'with empty apiKey', () async {
      final (registry, _) = await _registry();

      final all = registry.all();

      expect(all, hasLength(16));
      expect(
        all.map((p) => p.id).toList(),
        kBuiltinProviders.map((p) => p.id).toList(),
      );
      for (final provider in all) {
        expect(provider.enabled, isTrue, reason: '${provider.id} enabled');
        expect(provider.apiKey, isEmpty, reason: '${provider.id} apiKey');
        expect(provider.isCustom, isFalse, reason: '${provider.id} isCustom');
      }
    });

    test('apiKey + enabled overlays apply to builtins; activeById hides a '
        'disabled provider while byId still finds it', () async {
      final (registry, store) = await _registry();
      await store.setApiKey('deepseek', 'sk-deepseek-test');

      // Enabled by default → resolvable as active, key injected.
      expect(registry.activeById('deepseek')?.apiKey, 'sk-deepseek-test');

      await store.setProviderEnabled('deepseek', false);

      final deepseek =
          registry.all().firstWhere((p) => p.id == 'deepseek');
      expect(deepseek.apiKey, 'sk-deepseek-test');
      expect(deepseek.enabled, isFalse);

      // Disabled-as-absent lives in activeById only; byId still resolves.
      expect(registry.activeById('deepseek'), isNull);
      final byId = registry.byId('deepseek');
      expect(byId, isNotNull);
      expect(byId!.enabled, isFalse);
      expect(byId.apiKey, 'sk-deepseek-test');
    });

    test('custom providers merge after the builtins by default', () async {
      final (registry, store) = await _registry();
      await store.saveCustomProviders(<ProviderConfig>[
        _custom('custom-a'),
        _custom('custom-b'),
      ]);

      final all = registry.all();

      expect(all, hasLength(18));
      expect(
        all.sublist(0, 16).map((p) => p.id).toList(),
        kBuiltinProviders.map((p) => p.id).toList(),
      );
      expect(all[16].id, 'custom-a');
      expect(all[17].id, 'custom-b');
      expect(all[16].isCustom, isTrue);
      expect(all[17].isCustom, isTrue);
      // Overlays apply to customs too: enabled defaults to true, key empty.
      expect(all[16].enabled, isTrue);
      expect(all[16].apiKey, isEmpty);
    });

    test('persisted order is reconciled: known ids first, stale ids dropped, '
        'the rest appended in catalog-then-customs order', () async {
      final (registry, store) = await _registry();
      await store.saveCustomProviders(<ProviderConfig>[
        _custom('custom-a'),
        _custom('custom-b'),
      ]);
      await store.saveProviderOrder(<String>['custom-b', 'deepseek', 'ghost-id']);

      final ids = registry.all().map((p) => p.id).toList();

      expect(ids, hasLength(18));
      expect(ids[0], 'custom-b');
      expect(ids[1], 'deepseek');
      expect(ids, isNot(contains('ghost-id')));
      final expectedTail = <String>[
        for (final p in kBuiltinProviders)
          if (p.id != 'deepseek') p.id,
        'custom-a',
      ];
      expect(ids.sublist(2), expectedTail);
    });

    test('modelOverride overlay applies and drives effectiveModel', () async {
      final (registry, store) = await _registry();
      await store.setModelOverride('kimi', 'moonshot-v1-32k');

      final kimi = registry.all().firstWhere((p) => p.id == 'kimi');

      expect(kimi.modelOverride, 'moonshot-v1-32k');
      expect(kimi.effectiveModel, 'moonshot-v1-32k');
    });
  });

  group('ProviderRegistry.byId / activeById', () {
    test('byId resolves builtins and customs; unknown ids return null',
        () async {
      final (registry, store) = await _registry();
      await store.saveCustomProviders(<ProviderConfig>[_custom('custom-a')]);

      expect(registry.byId('openai')?.name, 'OpenAI');
      expect(registry.byId('custom-a')?.isCustom, isTrue);
      expect(registry.byId('no-such-provider'), isNull);
      expect(registry.activeById('no-such-provider'), isNull);
    });

    test('activeById returns the overlaid provider when enabled', () async {
      final (registry, store) = await _registry();
      await store.saveCustomProviders(<ProviderConfig>[_custom('custom-a')]);
      await store.setApiKey('custom-a', 'sk-custom-a');

      final active = registry.activeById('custom-a');

      expect(active, isNotNull);
      expect(active!.apiKey, 'sk-custom-a');
      expect(active.enabled, isTrue);
    });
  });

  group('ProviderRegistry equality sensitivity', () {
    test('toggling enabled changes the overlaid config (== includes enabled, '
        'so Riverpod invalidation repaints)', () async {
      final (registry, store) = await _registry();

      final before = registry.byId('deepseek');
      expect(before, isNotNull);
      expect(before!.enabled, isTrue);

      await store.setProviderEnabled('deepseek', false);
      final after = registry.byId('deepseek');

      expect(after, isNotNull);
      expect(after!.enabled, isFalse);
      expect(after, isNot(equals(before)));
      // Only the enabled flag changed between the two snapshots.
      expect(after.apiKey, before.apiKey);
      expect(after.modelOverride, before.modelOverride);
      expect(after.id, before.id);
    });
  });
}
