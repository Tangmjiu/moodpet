/// Riverpod providers for the plugin system, agent, and settings.
///
/// Centralised here so the UI layer imports one file. All providers are
/// `FutureProvider` or `Provider` — no `StateNotifier` complexity needed for
/// the container's synchronous registry access.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'agent/agent_service.dart';
import 'agent/pocketclaw_agent.dart';
import 'models/emotion.dart';
import 'models/provider_config.dart';
import 'plugin/plugin_bootstrap.dart';
import 'plugin/plugin_manager.dart';
import 'provider_registry.dart';
import 'storage/settings_store.dart';

/// SharedPreferences singleton.
final sharedPrefsProvider = FutureProvider<SharedPreferences>(
  (ref) => SharedPreferences.getInstance(),
);

/// SettingsStore singleton, derived from SharedPreferences.
final settingsStoreProvider = FutureProvider<SettingsStore>(
  (ref) async => SettingsStore(await ref.watch(sharedPrefsProvider.future)),
);

/// PluginManager singleton. Initialised after first-run bootstrap.
final pluginManagerProvider = FutureProvider<PluginManager>(
  (ref) async {
    final settings = await ref.watch(settingsStoreProvider.future);

    // First-run: extract the default smiley Friend.
    if (!settings.isFirstRunComplete) {
      await extractDefaultSmileyFriend();
      await settings.markFirstRunComplete();
    }

    // Create the manager with a SharedPreferences-backed manager.
    final prefs = await ref.watch(sharedPrefsProvider.future);
    final manager = PluginManager(prefs);
    await manager.refresh();
    return manager;
  },
);

/// The active agent service (PocketClaw by default; replaceable by Application
/// plugins [社区]).
final agentServiceProvider = FutureProvider<AgentService>(
  (ref) async {
    final settings = await ref.watch(settingsStoreProvider.future);
    final manager = await ref.watch(pluginManagerProvider.future);
    final registry = await ref.watch(providerRegistryProvider.future);

    // PocketClawAgent reads the active Friend's prompt and emoji mapping lazily
    // per respond() call via the PluginManager — no need to inject here.
    final agent = PocketClawAgent(manager, settings, registry);
    return agent;
  },
);

/// Whether onboarding has been completed. The app gates entry to the home page
/// on this.
final isOnboardingCompleteProvider = FutureProvider<bool>(
  (ref) async {
    final settings = await ref.watch(settingsStoreProvider.future);
    return settings.isOnboardingComplete;
  },
);

/// The active Friend's current emotion response (UI state).
final activeEmotionProvider = StateProvider<EmotionResponse>(
  (ref) => EmotionResponse.idle,
);

/// Whether the agent is currently processing a request.
final isAgentProcessingProvider = StateProvider<bool>(
  (ref) => false,
);

/// The active LLM provider config (with API key injected). A disabled
/// provider resolves to `null` — disabled-as-absent lives in the registry.
final activeProviderConfigProvider = FutureProvider<ProviderConfig?>(
  (ref) async {
    final settings = await ref.watch(settingsStoreProvider.future);
    final registry = await ref.watch(providerRegistryProvider.future);
    final id = settings.activeProviderId;
    if (id == null) return null;
    return registry.activeById(id);
  },
);

/// ProviderRegistry singleton, derived from the settings store.
final providerRegistryProvider = FutureProvider<ProviderRegistry>(
  (ref) async => ProviderRegistry(await ref.watch(settingsStoreProvider.future)),
);

/// The merged, ordered provider list (builtins + customs with overlays).
final providerListProvider = FutureProvider<List<ProviderConfig>>(
  (ref) async => (await ref.watch(providerRegistryProvider.future)).all(),
);
