/// Unified view over the built-in provider catalog and the user's custom
/// providers.
///
/// The registry merges both sources, applies the user's persisted overlays
/// (API key, model override, enabled flag) to every entry, and reconciles the
/// persisted display order. It is the single read path the UI and the agent
/// use to resolve providers — consumers never touch the catalog or the
/// settings keys directly.
library;

import 'models/provider_config.dart';
import 'storage/settings_store.dart';

/// Merges the built-in catalog with persisted custom providers and applies
/// per-provider user overlays.
class ProviderRegistry {
  ProviderRegistry(this._settings);

  final SettingsStore _settings;

  /// All providers — builtin catalog plus persisted customs — with the user
  /// overlays (apiKey, modelOverride, enabled) applied, ordered by the
  /// persisted order list.
  ///
  /// Ordering is reconciled on every read: ids in the persisted order list
  /// come first (ids that no longer resolve to a provider are silently
  /// dropped), then the remaining providers follow in builtin-catalog order
  /// and finally customs-storage order.
  List<ProviderConfig> all() {
    final merged = <ProviderConfig>[
      for (final builtin in kBuiltinProviders) _overlay(builtin),
      for (final custom in _settings.loadCustomProviders()) _overlay(custom),
    ];
    final order = _settings.loadProviderOrder();
    if (order.isEmpty) return merged;

    // LinkedHashMap preserves insertion order, so the leftovers below keep
    // the builtin-catalog-then-customs sequence.
    final remaining = <String, ProviderConfig>{
      for (final provider in merged) provider.id: provider,
    };
    final ordered = <ProviderConfig>[];
    for (final id in order) {
      final provider = remaining.remove(id);
      if (provider != null) ordered.add(provider);
    }
    ordered.addAll(remaining.values);
    return ordered;
  }

  /// The provider with [id] (overlaid), or `null` when unknown.
  ProviderConfig? byId(String id) {
    for (final provider in all()) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  /// The provider with [id] when it exists AND is enabled, else `null`.
  ///
  /// This is the only place the disabled-as-absent semantic lives: a disabled
  /// provider is treated exactly like an unknown one here, while [byId] still
  /// resolves it for management UI.
  ProviderConfig? activeById(String id) {
    final provider = byId(id);
    if (provider == null || !provider.enabled) return null;
    return provider;
  }

  /// Apply the persisted user overlays for [provider]'s id.
  ///
  /// The API key and enabled flag live outside any serialised provider JSON,
  /// so they must be re-attached on every read. A `null` model override keeps
  /// the provider's own value (always `null` for builtins) via [copyWith].
  ProviderConfig _overlay(ProviderConfig provider) => provider.copyWith(
        apiKey: _settings.apiKeyFor(provider.id),
        modelOverride: _settings.modelOverrideFor(provider.id),
        enabled: _settings.isProviderEnabled(provider.id),
      );
}
