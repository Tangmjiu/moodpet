/// Persisted plugin state: enabled flags, active Friend id, first-run marker.
///
/// Thin wrapper over `shared_preferences` so the plugin manager and the UI
/// layer do not depend on the storage mechanism directly.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/provider_config.dart';

/// SharedPreferences key prefixes.
const String _kEnabledPluginsKey = 'moodpet.plugin.enabledPlugins';
const String _kActiveFriendKey = 'moodpet.plugin.activeFriendId';
const String _kFirstRunKey = 'moodpet.firstRunComplete';
const String _kOnboardingCompleteKey = 'moodpet.onboardingComplete';
const String _kActiveProviderIdKey = 'moodpet.provider.activeId';
const String _kProviderModelOverridePrefix = 'moodpet.provider.modelOverride.';
const String _kProviderApiKeyPrefix = 'moodpet.provider.apiKey.';
const String _kCustomProvidersKey = 'moodpet.provider.customProviders';
const String _kProviderOrderKey = 'moodpet.provider.order';
const String _kProviderEnabledPrefix = 'moodpet.provider.enabled.';
const String _kProviderModelsPrefix = 'moodpet.provider.models.';

/// Persisted plugin + onboarding state.
class SettingsStore {
  final SharedPreferences _prefs;
  SettingsStore(this._prefs);

  // ---- enabled plugins --------------------------------------------------

  /// Load the set of enabled plugin ids.
  Set<String> loadEnabledPlugins() {
    final list = _prefs.getStringList(_kEnabledPluginsKey);
    return list?.toSet() ?? <String>{};
  }

  /// Persist the full set of enabled plugin ids.
  Future<void> saveEnabledPlugins(Set<String> ids) =>
      _prefs.setStringList(_kEnabledPluginsKey, ids.toList());

  // ---- active friend ----------------------------------------------------

  /// Load the active Friend plugin id, or `null` when unset.
  String? loadActiveFriendId() => _prefs.getString(_kActiveFriendKey);

  /// Persist the active Friend plugin id.
  Future<void> saveActiveFriendId(String id) =>
      _prefs.setString(_kActiveFriendKey, id);

  // ---- first-run / onboarding ------------------------------------------

  /// Whether first-run bootstrap (default-Friend extraction) has completed.
  bool get isFirstRunComplete => _prefs.getBool(_kFirstRunKey) ?? false;

  /// Mark first-run bootstrap complete.
  Future<void> markFirstRunComplete() => _prefs.setBool(_kFirstRunKey, true);

  /// Whether the full onboarding flow (welcome → permissions → provider) has
  /// been completed. The app gates entry to the home page on this.
  bool get isOnboardingComplete =>
      _prefs.getBool(_kOnboardingCompleteKey) ?? false;

  /// Mark onboarding complete.
  Future<void> markOnboardingComplete() =>
      _prefs.setBool(_kOnboardingCompleteKey, true);

  // ---- LLM provider -----------------------------------------------------

  /// Active LLM provider id, or `null` when unset.
  String? get activeProviderId => _prefs.getString(_kActiveProviderIdKey);

  /// Persist the active LLM provider id.
  Future<void> setActiveProviderId(String id) =>
      _prefs.setString(_kActiveProviderIdKey, id);

  /// Clear the active LLM provider id. Used when the active custom provider
  /// is deleted so no dangling id points at a provider that no longer exists.
  Future<void> clearActiveProviderId() => _prefs.remove(_kActiveProviderIdKey);

  /// Load a model override for a provider id, or `null`.
  String? modelOverrideFor(String providerId) =>
      _prefs.getString('$_kProviderModelOverridePrefix$providerId');

  /// Load the API key for [providerId]. Empty string when unset.
  String apiKeyFor(String providerId) =>
      _prefs.getString('$_kProviderApiKeyPrefix$providerId') ?? '';

  /// Persist the API key for [providerId]. Pass an empty string to clear.
  Future<void> setApiKey(String providerId, String key) {
    final k = '$_kProviderApiKeyPrefix$providerId';
    if (key.isEmpty) return _prefs.remove(k);
    return _prefs.setString(k, key);
  }

  /// Persist a model override for a provider id.
  Future<void> setModelOverride(String providerId, String? model) {
    final key = '$_kProviderModelOverridePrefix$providerId';
    if (model == null || model.isEmpty) {
      return _prefs.remove(key);
    }
    return _prefs.setString(key, model);
  }

  // ---- custom LLM providers ---------------------------------------------

  /// Load the user-added custom providers. Returns an empty list when nothing
  /// is stored, when the stored string is not valid JSON, or when the JSON is
  /// not a list. Individual malformed entries are skipped so one corrupt
  /// provider can never block the rest from loading.
  List<ProviderConfig> loadCustomProviders() {
    final raw = _prefs.getString(_kCustomProvidersKey);
    if (raw == null || raw.isEmpty) return <ProviderConfig>[];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object {
      return <ProviderConfig>[];
    }
    if (decoded is! List) return <ProviderConfig>[];
    final providers = <ProviderConfig>[];
    for (final entry in decoded) {
      try {
        providers.add(ProviderConfig.fromJson(entry as Map<String, Object?>));
      } on Object {
        // Malformed entry — skip it, never rethrow.
      }
    }
    return providers;
  }

  /// Persist the custom provider list as a JSON string.
  ///
  /// Safe in release builds: [ProviderConfig.toJson] serialises only durable,
  /// non-secret fields — API keys and other runtime state are never written.
  Future<void> saveCustomProviders(List<ProviderConfig> providers) {
    final json = providers.map((p) => p.toJson()).toList();
    return _prefs.setString(_kCustomProvidersKey, jsonEncode(json));
  }

  // ---- provider display order --------------------------------------------

  /// Load the user-defined provider display order (list of provider ids).
  List<String> loadProviderOrder() =>
      _prefs.getStringList(_kProviderOrderKey) ?? <String>[];

  /// Persist the provider display order.
  Future<void> saveProviderOrder(List<String> order) =>
      _prefs.setStringList(_kProviderOrderKey, order);

  // ---- provider enabled flags --------------------------------------------

  /// Whether a provider is enabled in the UI. Providers default to enabled,
  /// so a missing key means `true`.
  bool isProviderEnabled(String id) =>
      _prefs.getBool('$_kProviderEnabledPrefix$id') ?? true;

  /// Persist the enabled flag for a provider. Enabling removes the key
  /// instead of storing `true`, since enabled is the default — this keeps
  /// the preferences lean.
  Future<void> setProviderEnabled(String id, bool enabled) {
    final key = '$_kProviderEnabledPrefix$id';
    if (enabled) return _prefs.remove(key);
    return _prefs.setBool(key, false);
  }

  // ---- per-provider model lists ------------------------------------------

  /// Load the cached/discovered model list for a provider id.
  List<String> modelsFor(String id) =>
      _prefs.getStringList('$_kProviderModelsPrefix$id') ?? <String>[];

  /// Persist the model list for a provider id. An empty list removes the key.
  Future<void> setModels(String id, List<String> models) {
    final key = '$_kProviderModelsPrefix$id';
    if (models.isEmpty) return _prefs.remove(key);
    return _prefs.setStringList(key, models);
  }

  /// Remove all per-provider state (API key, model override, enabled flag,
  /// model list) for a custom provider id.
  ///
  /// Guarded: this is a no-op unless [id] appears in [loadCustomProviders],
  /// so built-in provider keys can never be cleared through this path.
  Future<void> removeProviderState(String id) async {
    final isCustom = loadCustomProviders().any((p) => p.id == id);
    if (!isCustom) return;
    await _prefs.remove('$_kProviderApiKeyPrefix$id');
    await _prefs.remove('$_kProviderModelOverridePrefix$id');
    await _prefs.remove('$_kProviderEnabledPrefix$id');
    await _prefs.remove('$_kProviderModelsPrefix$id');
  }
}
