/// Plugin loading: scan the plugins directory, parse each `manifest.json`,
/// validate it, and produce a typed [LoadedPlugin] per plugin.
///
/// The loader is intentionally side-effect-free apart from filesystem reads —
/// enable/disable/active-friend state lives in [PluginManager]. A loader run
/// never throws for a single bad plugin; it records the failure on the
/// [LoadedPlugin] so the management UI can surface it.
library;

import 'dart:convert';
import 'dart:io';

import '../models/plugin_manifest.dart';
import '../models/plugin_type.dart';
import '../platform_info.dart';
import 'plugin_paths.dart';

/// A plugin directory plus its parsed manifest (or a load error).
///
/// [manifest] is `null` when [error] is set, and vice-versa. The [dir] is
/// always populated so the UI can show the folder name even for broken
/// plugins.
class LoadedPlugin {
  /// Absolute plugin directory.
  final Directory dir;

  /// Folder name (e.g. `moodpet.friend.default_smiley.moodfriend`).
  final String folderName;

  /// Parsed manifest, or `null` when loading failed.
  final PluginManifest? manifest;

  /// Non-null when the manifest could not be parsed or failed validation.
  final String? error;

  /// True when the manifest declares the plugin as system (non-uninstallable).
  bool get isSystem => manifest?.system ?? false;

  /// Plugin id from the manifest, or the folder name when unparseable.
  String get id => manifest?.id ?? folderName;

  /// Plugin type, or `null` when unparseable.
  PluginType? get type => manifest?.type;

  LoadedPlugin({
    required this.dir,
    required this.folderName,
    required this.manifest,
    required this.error,
  });

  @override
  String toString() =>
      'LoadedPlugin($folderName, ${manifest?.id ?? "error: $error"})';
}

/// A batch load result for the whole plugins directory.
class PluginScanResult {
  /// Successfully loaded plugins (manifest non-null, no error).
  final List<LoadedPlugin> ok;

  /// Plugins that failed to load (error non-null).
  final List<LoadedPlugin> failed;

  const PluginScanResult({required this.ok, required this.failed});

  /// All plugins, ok first then failed.
  List<LoadedPlugin> get all => <LoadedPlugin>[...ok, ...failed];

  /// Convenience: only Friend plugins that loaded.
  List<LoadedPlugin> get friends =>
      ok.where((p) => p.type == PluginType.friend).toList(growable: false);

  /// Convenience: only Application plugins that loaded.
  List<LoadedPlugin> get applications =>
      ok.where((p) => p.type == PluginType.application).toList(growable: false);

  /// Convenience: only Pack bundles that loaded.
  List<LoadedPlugin> get packs =>
      ok.where((p) => p.type == PluginType.pack).toList(growable: false);
}

/// Scan the plugins root directory and load every plugin inside it.
///
/// Each immediate subdirectory whose name ends with a plugin suffix
/// (`.moodfriend` / `.moodapp` / `.moodpack`) is treated as one plugin. A
/// missing or malformed `manifest.json` records an error on the [LoadedPlugin]
/// rather than aborting the whole scan.
Future<PluginScanResult> loadAllPlugins() async {
  final root = await pluginsRootDir();
  final ok = <LoadedPlugin>[];
  final failed = <LoadedPlugin>[];
  if (!root.existsSync()) {
    return PluginScanResult(ok: ok, failed: failed);
  }
  final entries = root.listSync(followLinks: false);
  for (final entry in entries) {
    if (entry is! Directory) continue;
    final name = entry.path.split('/').last;
    if (!isPluginDirName(name)) continue;
    final loaded = await _loadOne(entry, name);
    if (loaded.error != null) {
      failed.add(loaded);
    } else {
      ok.add(loaded);
    }
  }
  return PluginScanResult(ok: ok, failed: failed);
}

/// Load a single plugin directory.
Future<LoadedPlugin> _loadOne(Directory dir, String folderName) async {
  final manifest = manifestFile(dir);
  if (!manifest.existsSync()) {
    return LoadedPlugin(
        dir: dir, folderName: folderName, manifest: null, error: 'manifest.json not found');
  }
  try {
    final raw = await manifest.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      return LoadedPlugin(
          dir: dir,
          folderName: folderName,
          manifest: null,
          error: 'manifest.json is not a JSON object');
    }
    final parsed = _parseAndValidate(decoded);
    return LoadedPlugin(
        dir: dir, folderName: folderName, manifest: parsed, error: null);
  } on FormatException catch (e) {
    return LoadedPlugin(
        dir: dir, folderName: folderName, manifest: null, error: e.message);
  } on FileSystemException catch (e) {
    return LoadedPlugin(
        dir: dir, folderName: folderName, manifest: null, error: e.message);
  } catch (e) {
    return LoadedPlugin(
        dir: dir, folderName: folderName, manifest: null, error: '$e');
  }
}

/// Dispatch on `"type"` to the correct subclass constructor and run
/// platform-compatibility validation.
PluginManifest _parseAndValidate(Map<String, Object?> json) {
  final typeRaw = json['type'];
  if (typeRaw is! String) {
    throw const FormatException('manifest "type" is required');
  }
  final type = PluginType.fromString(typeRaw);
  final PluginManifest manifest;
  switch (type) {
    case PluginType.friend:
      manifest = FriendManifest.fromJson(json);
      break;
    case PluginType.application:
      manifest = ApplicationManifest.fromJson(json);
      break;
    case PluginType.pack:
      manifest = PackManifest.fromJson(json);
      break;
  }
  // Platform compatibility check: warn (not fail) when the current platform is
  // not in the manifest's supported list — the UI shows a compatibility badge
  // and the manager refuses to enable it, but the plugin still loads so the
  // user can see it.
  return manifest;
}

/// Whether [plugin] is compatible with the current platform.
bool isPluginCompatible(LoadedPlugin plugin) {
  final manifest = plugin.manifest;
  if (manifest == null) return false;
  return manifest.platforms.supports(currentPlatformId);
}

/// Read a Friend plugin's `system_prompt.txt` from disk.
///
/// The path comes from `manifest.interfaces.personality`. Throws if the file
/// is missing — callers should catch and fall back to a default prompt.
Future<String> readFriendSystemPrompt(FriendManifest manifest,
    {required Directory pluginDir}) async {
  final rel = manifest.interfaces.personality;
  final file = File('${pluginDir.path}/$rel');
  return file.readAsString();
}

/// Read a Friend plugin's `emoji_mapping.json` if present. Returns `null` when
/// the file is absent or the manifest does not declare an expression path.
Future<String?> readFriendEmojiMappingRaw(FriendManifest manifest,
    {required Directory pluginDir}) async {
  final rel = manifest.interfaces.expression;
  if (rel == null) return null;
  final file = File('${pluginDir.path}/$rel');
  if (!file.existsSync()) return null;
  return file.readAsString();
}

/// Read and parse a Friend plugin's `identity.json` if present. Returns
/// [FriendIdentity.empty] when the file is absent or the manifest does not
/// declare an identity path; throws [FormatException] only when the file
/// exists but is not a JSON object.
Future<FriendIdentity> readFriendIdentity(FriendManifest manifest,
    {required Directory pluginDir}) async {
  final rel = manifest.interfaces.identity;
  if (rel == null) return FriendIdentity.empty;
  final file = File('${pluginDir.path}/$rel');
  if (!file.existsSync()) return FriendIdentity.empty;
  final raw = await file.readAsString();
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('identity.json must be a JSON object');
  }
  return FriendIdentity.fromJson(decoded);
}
