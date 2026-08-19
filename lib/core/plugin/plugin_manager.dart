/// Plugin manager: the in-memory registry plus the enable/disable and
/// active-Friend state.
///
/// Responsibilities:
///   - Hold the loaded [PluginScanResult] (refreshed on demand / on FS change).
///   - Persist per-plugin enabled flags and the active Friend id in
///     `shared_preferences`.
///   - Refuse to enable a plugin on an incompatible platform or to uninstall a
///     system plugin.
///   - Expose the active Friend's manifest + lazily-read system prompt /
///     emoji mapping for the agent runtime.
///
/// The manager is a plain class — Riverpod providers in
/// `lib/core/providers/plugin_providers.dart` wrap it for the UI.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/emotion.dart';
import '../models/plugin_manifest.dart';
import '../models/plugin_type.dart';
import 'plugin_loader.dart';
import 'plugin_paths.dart';

/// Keys used in `shared_preferences`.
const String _kEnabledKeyPrefix = 'moodpet.plugin.enabled.';
const String _kActiveFriendKey = 'moodpet.plugin.activeFriend';
const String _kFirstRunKey = 'moodpet.firstRunComplete';

/// The plugin manager. One instance per app process.
class PluginManager {
  final SharedPreferences _prefs;

  /// Last scan result. `null` until [refresh] is called.
  PluginScanResult? _scan;

  PluginManager(this._prefs);

  /// Reload every plugin from disk.
  ///
  /// Call after bootstrap (default-Friend extraction) or after
  /// installing/uninstalling a plugin.
  Future<PluginScanResult> refresh() async {
    final result = await loadAllPlugins();
    _scan = result;
    return result;
  }

  /// The last scan result. Throws [StateError] if [refresh] has not been called.
  PluginScanResult get scan {
    final s = _scan;
    if (s == null) {
      throw StateError('PluginManager.refresh() must be called before access');
    }
    return s;
  }

  /// All successfully-loaded plugins (ok list).
  List<LoadedPlugin> get allPlugins => scan.ok;

  /// All loaded Friend plugins.
  List<LoadedPlugin> get friends => scan.friends;

  /// All loaded Application plugins.
  List<LoadedPlugin> get applications => scan.applications;

  /// All loaded Pack bundles.
  List<LoadedPlugin> get packs => scan.packs;

  /// Plugins that failed to load (for the management UI error list).
  List<LoadedPlugin> get failedPlugins => scan.failed;

  /// Look up a loaded plugin by id. Returns `null` when not found.
  LoadedPlugin? pluginById(String id) {
    for (final p in scan.ok) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ---- enable / disable -------------------------------------------------

  /// Whether a plugin is enabled. A plugin is enabled when its persisted flag
  /// is `true`; default is the manifest's `defaultEnabled`.
  bool isEnabled(String pluginId) {
    final plugin = pluginById(pluginId);
    if (plugin == null) return false;
    final key = _kEnabledKeyPrefix + pluginId;
    if (_prefs.containsKey(key)) {
      return _prefs.getBool(key) ?? false;
    }
    return plugin.manifest?.defaultEnabled ?? false;
  }

  /// Enable a plugin. Refuses (returns `false`) when the plugin is not
  /// compatible with the current platform.
  bool enable(String pluginId) {
    final plugin = pluginById(pluginId);
    if (plugin == null) return false;
    if (!isPluginCompatible(plugin)) return false;
    _prefs.setBool(_kEnabledKeyPrefix + pluginId, true);
    return true;
  }

  /// Disable a plugin. System plugins can be disabled (they just stop
  /// contributing) but cannot be uninstalled — see [uninstall].
  void disable(String pluginId) {
    _prefs.setBool(_kEnabledKeyPrefix + pluginId, false);
  }

  // ---- active Friend ----------------------------------------------------

  /// The id of the active Friend plugin, or `null` when none is active.
  ///
  /// Falls back to the default smiley Friend when the persisted value is empty
  /// or points to a missing/disabled plugin.
  String? get activeFriendId {
    final stored = _prefs.getString(_kActiveFriendKey);
    if (stored != null && stored.isNotEmpty) {
      final plugin = pluginById(stored);
      if (plugin != null &&
          plugin.type == PluginType.friend &&
          isEnabled(stored)) {
        return stored;
      }
    }
    // Fallback: the default smiley Friend, if present and enabled.
    final defaultPlugin = pluginById(kDefaultSmileyPluginId);
    if (defaultPlugin != null && defaultPlugin.type == PluginType.friend) {
      final key = _kEnabledKeyPrefix + kDefaultSmileyPluginId;
      if (!_prefs.containsKey(key)) {
        _prefs.setBool(key, true);
      }
      return kDefaultSmileyPluginId;
    }
    return null;
  }

  /// Set the active Friend plugin. [pluginId] must be a loaded, enabled Friend.
  /// Returns `false` when the id is not a valid enabled Friend.
  bool setActiveFriend(String pluginId) {
    final plugin = pluginById(pluginId);
    if (plugin == null || plugin.type != PluginType.friend) return false;
    if (!isEnabled(pluginId)) {
      final ok = enable(pluginId);
      if (!ok) return false;
    }
    _prefs.setString(_kActiveFriendKey, pluginId);
    return true;
  }

  /// The active Friend's [LoadedPlugin], or `null` when no active Friend.
  LoadedPlugin? get activeFriend {
    final id = activeFriendId;
    if (id == null) return null;
    return pluginById(id);
  }

  /// The active Friend's manifest, or `null`.
  FriendManifest? get activeFriendManifest {
    final plugin = activeFriend;
    if (plugin == null || plugin.manifest is! FriendManifest) return null;
    return plugin.manifest as FriendManifest;
  }

  /// The active Friend's display name.
  String get activeFriendName => activeFriend?.manifest?.name ?? 'MoodPet';

  // ---- Friend content (lazy) -------------------------------------------

  /// Read the active Friend's `system_prompt.txt`. Returns a fallback prompt
  /// when the active Friend is missing or the file cannot be read.
  Future<String> activeFriendSystemPrompt() async {
    final plugin = activeFriend;
    final manifest = activeFriendManifest;
    if (plugin == null || manifest == null) {
      return _kFallbackSystemPrompt;
    }
    try {
      return await readFriendSystemPrompt(manifest, pluginDir: plugin.dir);
    } catch (_) {
      return _kFallbackSystemPrompt;
    }
  }

  /// Read the active Friend's `emoji_mapping.json` and parse it. Returns `null`
  /// when the Friend has no mapping file.
  Future<EmojiMapping?> activeFriendEmojiMapping() async {
    final plugin = activeFriend;
    final manifest = activeFriendManifest;
    if (plugin == null || manifest == null) return null;
    final raw = await readFriendEmojiMappingRaw(manifest, pluginDir: plugin.dir);
    if (raw == null) return null;
    try {
      return parseEmojiMapping(raw);
    } catch (_) {
      return null;
    }
  }

  /// Read and parse the active Friend's `identity.json`. Returns
  /// [FriendIdentity.empty] when the Friend declares no identity file or the
  /// file is missing; never throws — a malformed identity degrades to empty.
  Future<FriendIdentity> activeFriendIdentity() async {
    final plugin = activeFriend;
    final manifest = activeFriendManifest;
    if (plugin == null || manifest == null) return FriendIdentity.empty;
    try {
      return await readFriendIdentity(manifest, pluginDir: plugin.dir);
    } catch (_) {
      return FriendIdentity.empty;
    }
  }

  /// The active Friend's greeting string from its `configSchema.greeting`
  /// field default, or `null` when the Friend declares no greeting.
  String? get activeFriendGreeting {
    final manifest = activeFriendManifest;
    if (manifest == null) return null;
    final field = manifest.configSchema['greeting'];
    return field?.defaultValue is String
        ? field!.defaultValue as String
        : null;
  }

  /// The active Friend's manifest description, or `null` when no active Friend.
  String? get activeFriendDescription => activeFriendManifest?.description;

  // ---- uninstall --------------------------------------------------------

  /// Uninstall a plugin by deleting its directory. Refuses system plugins.
  ///
  /// Returns `false` when the plugin is system-protected or not loaded.
  /// After a successful uninstall the caller should call [refresh].
  Future<bool> uninstall(String pluginId) async {
    final plugin = pluginById(pluginId);
    if (plugin == null) return false;
    if (plugin.isSystem) return false;
    final dir = plugin.dir;
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
    _prefs.remove(_kEnabledKeyPrefix + pluginId);
    if (activeFriendId == pluginId) {
      _prefs.remove(_kActiveFriendKey);
    }
    return true;
  }

  // ---- first-run gate ---------------------------------------------------

  /// Whether first-run bootstrap (default-Friend extraction) has completed.
  bool get isFirstRunComplete => _prefs.getBool(_kFirstRunKey) ?? false;

  /// Mark first-run bootstrap as complete.
  Future<void> markFirstRunComplete() =>
      _prefs.setBool(_kFirstRunKey, true);
}

/// Fallback system prompt used when the active Friend has no readable
/// `system_prompt.txt`. Keeps the agent functional even with a broken Friend.
const String _kFallbackSystemPrompt = '''你是 MoodPet 默认伙伴，一个住在用户设备里的情绪伙伴。

【你的性格】
温暖、共情、善于倾听。

【你的说话风格】
温柔、真诚、简洁。

【响应规则】
收到用户输入后，分析用户情绪，返回 JSON：
{
  "emoji": "😊",
  "color": "#FFD93D",
  "vibration": [100, 80, 100, 80, 100],
  "suggestion": "简短建议（不超过10个字）"
}

【可选 Emoji】
😊 😢 😩 😤 🤩 😌 🤔 😨 😲 😰 🥺 🥹 🧐
''';
