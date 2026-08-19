import 'package:flutter_test/flutter_test.dart';
import 'package:moodpet/core/models/provider_config.dart';
import 'package:moodpet/core/provider_registry.dart';
import 'package:moodpet/core/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Raw preference keys, mirrored from SettingsStore so the tests can seed and
// inspect storage directly — these are the LEGACY keys a pre-refactor install
// would have written, and the whole point of this suite is to prove they are
// read byte-for-byte and never migrated away.
const String _kActiveIdKey = 'moodpet.provider.activeId';
const String _kApiKeyPrefix = 'moodpet.provider.apiKey.';
const String _kModelOverridePrefix = 'moodpet.provider.modelOverride.';
const String _kCustomProvidersKey = 'moodpet.provider.customProviders';
const String _kProviderOrderKey = 'moodpet.provider.order';

/// A custom provider entry shaped the way the settings UI persists one.
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

/// Fresh registry + store + prefs triple backed by an in-memory mock,
/// optionally seeded with ONLY legacy keys (simulating an existing install).
Future<(ProviderRegistry, SettingsStore, SharedPreferences)> _legacyInstall(
  Map<String, Object> legacySeed,
) async {
  SharedPreferences.setMockInitialValues(legacySeed);
  final prefs = await SharedPreferences.getInstance();
  final store = SettingsStore(prefs);
  return (ProviderRegistry(store), store, prefs);
}

const String _kDeepseek = 'deepseek';

/// The legacy seed used by cases that exercise a fully-configured deepseek
/// install: active id, API key, and a model override.
const Map<String, Object> _deepseekLegacySeed = <String, Object>{
  _kActiveIdKey: 'deepseek',
  '$_kApiKeyPrefix$_kDeepseek': 'sk-legacy',
  '$_kModelOverridePrefix$_kDeepseek': 'deepseek-reasoner',
};

void main() {
  group('Legacy install integration', () {
    // --------------------------------------------------------------------
    // Case 1 — Legacy upgrade path: read-only overlay, NOTHING migrated.
    // --------------------------------------------------------------------
    test('case 1: legacy keys overlay the builtin deepseek and are left '
        'byte-identical in storage (no migration)', () async {
      final (registry, store, prefs) =
          await _legacyInstall(_deepseekLegacySeed);

      // Overlay applied to the builtin catalog entry.
      final deepseek = registry.byId(_kDeepseek);
      expect(deepseek, isNotNull);
      expect(deepseek!.apiKey, 'sk-legacy');
      expect(deepseek.modelOverride, 'deepseek-reasoner');
      expect(deepseek.effectiveModel, 'deepseek-reasoner');

      // Active resolution works through the overlay.
      final active = registry.activeById(_kDeepseek);
      expect(active, isNotNull);
      expect(active!.apiKey, 'sk-legacy');
      expect(active.effectiveModel, 'deepseek-reasoner');

      // No customs, no order list → exactly the 16 builtins, untouched order.
      expect(registry.all(), hasLength(16));
      expect(
        registry.all().map((p) => p.id).toList(),
        kBuiltinProviders.map((p) => p.id).toList(),
        reason: 'catalog order preserved when no order key is set',
      );
      expect(store.loadCustomProviders(), isEmpty);
      expect(store.loadProviderOrder(), isEmpty);

      // NOTHING migrated: the raw legacy keys are still on disk with the
      // exact values seeded. Read them straight back through prefs so this
      // cannot pass on derived state alone.
      expect(prefs.getString(_kActiveIdKey), 'deepseek');
      expect(prefs.getString('$_kApiKeyPrefix$_kDeepseek'), 'sk-legacy');
      expect(
        prefs.getString('$_kModelOverridePrefix$_kDeepseek'),
        'deepseek-reasoner',
      );
      // And no new-keys side effects were written.
      expect(prefs.containsKey(_kCustomProvidersKey), isFalse);
      expect(prefs.containsKey(_kProviderOrderKey), isFalse);
    });

    // --------------------------------------------------------------------
    // Case 2 — Legacy + custom coexistence: custom appended, legacy intact.
    // --------------------------------------------------------------------
    test('case 2: adding a custom provider appends after builtins and leaves '
        'the legacy deepseek overlay byte-identical', () async {
      final (registry, store, prefs) =
          await _legacyInstall(_deepseekLegacySeed);

      // Persist one custom provider the way the settings UI would.
      await store.saveCustomProviders(<ProviderConfig>[_custom('my-local')]);

      // 16 builtins + 1 custom.
      final all = registry.all();
      expect(all, hasLength(17));

      // No order key set → reconcile appends the custom after the builtins.
      expect(
        all.sublist(0, 16).map((p) => p.id).toList(),
        kBuiltinProviders.map((p) => p.id).toList(),
      );
      expect(all[16].id, 'my-local');
      expect(all[16].isCustom, isTrue);

      // The legacy deepseek overlay is still applied on top of the builtin.
      final deepseek = registry.byId(_kDeepseek);
      expect(deepseek, isNotNull);
      expect(deepseek!.apiKey, 'sk-legacy');
      expect(deepseek.modelOverride, 'deepseek-reasoner');
      expect(deepseek.effectiveModel, 'deepseek-reasoner');

      // The legacy keys themselves were not touched by the custom-provider
      // write — re-read through raw prefs.
      expect(prefs.getString(_kActiveIdKey), 'deepseek');
      expect(prefs.getString('$_kApiKeyPrefix$_kDeepseek'), 'sk-legacy');
      expect(
        prefs.getString('$_kModelOverridePrefix$_kDeepseek'),
        'deepseek-reasoner',
      );
    });

    // --------------------------------------------------------------------
    // Case 3 — Legacy active id pointing at an unknown provider: no crash.
    // --------------------------------------------------------------------
    test('case 3: a legacy activeId pointing at a removed/unknown provider '
        'resolves to null without crashing and the catalog still loads',
        () async {
      final (registry, _, _) = await _legacyInstall(const <String, Object>{
        _kActiveIdKey: 'removed-provider',
      });

      // Unknown id → null, no exception.
      expect(registry.activeById('removed-provider'), isNull);
      expect(registry.byId('removed-provider'), isNull);

      // The 16 builtins still load.
      expect(registry.all(), hasLength(16));
    });

    // --------------------------------------------------------------------
    // Case 4 — Legacy modelOverride survives an order change.
    // --------------------------------------------------------------------
    test('case 4: a legacy modelOverride is still applied after the user '
        'reorders providers', () async {
      final (registry, store, _) =
          await _legacyInstall(_deepseekLegacySeed);

      // User reorders so kimi comes first, deepseek second.
      await store.saveProviderOrder(<String>['kimi', 'deepseek']);

      final all = registry.all();
      expect(all, hasLength(16));
      expect(all.first.id, 'kimi');
      expect(all[1].id, 'deepseek');

      // The modelOverride seeded by the legacy install is still driving
      // effectiveModel — reordering must not strip overlays.
      final deepseek = registry.byId(_kDeepseek);
      expect(deepseek, isNotNull);
      expect(deepseek!.modelOverride, 'deepseek-reasoner');
      expect(deepseek.effectiveModel, 'deepseek-reasoner');
    });

    // --------------------------------------------------------------------
    // Case 5 — Regression guard: legacy byte-for-byte semantics on the
    // direct SettingsStore reads (the pre-refactor read path).
    // --------------------------------------------------------------------
    test('case 5: direct SettingsStore reads match pre-refactor legacy '
        'semantics (apiKeyFor + activeProviderId)', () async {
      final (registry, store, _) = await _legacyInstall(const <String, Object>{
        _kActiveIdKey: 'deepseek',
        '$_kApiKeyPrefix$_kDeepseek': 'sk-legacy',
      });

      // The pre-refactor code read these two directly off the store; this
      // case pins that contract so a future refactor cannot silently change
      // the legacy read semantics. (registry is constructed to prove the
      // pair composes, but the assertions are on the store itself.)
      expect(store.activeProviderId, 'deepseek');
      expect(store.apiKeyFor('deepseek'), 'sk-legacy');
      // No override seeded → null, never empty-string, for the override API.
      expect(store.modelOverrideFor('deepseek'), isNull);

      // And the registry still composes the same picture from those reads.
      expect(registry.activeById('deepseek')?.apiKey, 'sk-legacy');
    });
  });
}
