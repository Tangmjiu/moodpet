/// Application plugin runtime (§11): interface + registry for Application
/// plugins that override container services.
///
/// The container provides the [ApplicationPluginInterface] contract and a
/// [ApplicationRuntime] registry. Community Application plugins ([社区])
/// implement the interface; the runtime discovers enabled Application plugins
/// and routes service calls (TTS, memory, agent, renderer, UI) to the highest-
/// priority override.
///
/// This module defines the contract and registry only — actual plugin
/// execution (Dart isolate, Python subprocess, external process) is
/// [社区]-implemented. The container's role is discovery and dispatch.
library;

import '../models/plugin_manifest.dart';
import '../models/plugin_type.dart';
import 'plugin_loader.dart';

/// Service names an Application plugin can override.
enum ContainerService { tts, memory, agent, renderer }

/// The interface an Application plugin implements. Community plugins provide
/// concrete implementations; the container calls through this interface.
///
/// This is a placeholder contract — real implementations are [社区].
abstract class ApplicationPluginInterface {
  /// The plugin id.
  String get id;

  /// The plugin manifest.
  ApplicationManifest get manifest;

  /// Whether this plugin overrides [service].
  bool overrides(ContainerService service);

  /// Called when the plugin is first loaded. Return `false` to signal
  /// initialisation failure.
  Future<bool> onInit();

  /// Called when the plugin is unloaded / disabled.
  Future<void> onDispose();
}

/// The Application plugin runtime — discovers enabled Application plugins and
/// routes service overrides.
class ApplicationRuntime {
  final List<ApplicationPluginInterface> _plugins = [];

  /// Register a plugin implementation.
  void register(ApplicationPluginInterface plugin) {
    _plugins.add(plugin);
  }

  /// Unregister a plugin by id.
  void unregister(String id) {
    _plugins.removeWhere((p) => p.id == id);
  }

  /// All registered plugins.
  List<ApplicationPluginInterface> get plugins =>
      List.unmodifiable(_plugins);

  /// Find the first registered plugin that overrides [service], or `null`.
  ApplicationPluginInterface? overrideFor(ContainerService service) {
    for (final p in _plugins) {
      if (p.overrides(service)) return p;
    }
    return null;
  }

  /// Whether any registered plugin overrides [service].
  bool hasOverride(ContainerService service) =>
      overrideFor(service) != null;

  /// Initialise all registered plugins. Returns the list of ids that failed
  /// to initialise.
  Future<List<String>> initAll() async {
    final failed = <String>[];
    for (final p in _plugins) {
      final ok = await p.onInit();
      if (!ok) failed.add(p.id);
    }
    return failed;
  }

  /// Dispose all registered plugins.
  Future<void> disposeAll() async {
    for (final p in _plugins) {
      await p.onDispose();
    }
    _plugins.clear();
  }

  /// Build a runtime from a list of loaded Application plugins. The actual
  /// interface implementations are [社区] — this method creates placeholder
  /// entries that report overrides from the manifest but do nothing.
  static ApplicationRuntime fromPlugins(List<LoadedPlugin> applications) {
    final runtime = ApplicationRuntime();
    for (final plugin in applications) {
      if (plugin.type != PluginType.application) continue;
      final manifest = plugin.manifest as ApplicationManifest;
      runtime.register(_PlaceholderPlugin(manifest));
    }
    return runtime;
  }
}

/// A placeholder [ApplicationPluginInterface] that reports overrides from the
/// manifest but performs no real work. Real implementations are [社区].
class _PlaceholderPlugin implements ApplicationPluginInterface {
  @override
  final ApplicationManifest manifest;

  _PlaceholderPlugin(this.manifest);

  @override
  String get id => manifest.id;

  @override
  bool overrides(ContainerService service) {
    switch (service) {
      case ContainerService.tts:
        return manifest.overrides.overridesService('tts');
      case ContainerService.memory:
        return manifest.overrides.overridesService('memory');
      case ContainerService.agent:
        return manifest.overrides.overridesService('agent');
      case ContainerService.renderer:
        return manifest.overrides.overridesService('renderer');
    }
  }

  @override
  Future<bool> onInit() async => true;

  @override
  Future<void> onDispose() async {}
}
