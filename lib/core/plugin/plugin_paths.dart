/// Plugin directory layout and path helpers (§6.1, §7.1, §8.1).
///
/// The container stores plugins under a single user-writable root:
///
/// ```text
/// <appSupportDir>/plugins/
///   moodpet.friend.default_smiley.moodfriend/   ← system, bundled
///   <plugin_id>.moodfriend/                     ← installed Friend
///   <plugin_id>.moodapp/                        ← installed Application
///   <pack_id>.moodpack/                         ← expanded pack
/// ```
///
/// The default smiley Friend is bundled in the app's `assets/` and extracted
/// into the root on first run by `PluginBootstrap` (see `plugin_bootstrap.dart`).
/// System plugins always live alongside user-installed ones — there is no
/// separate system directory — but their manifest carries `"system": true` so
/// the manager refuses to uninstall them.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Extension suffixes for the three plugin kinds on disk.
const String kFriendDirSuffix = '.moodfriend';
const String kApplicationDirSuffix = '.moodapp';
const String kPackDirSuffix = '.moodpack';

/// Subdirectory name under the application support directory that holds all
/// plugins.
const String kPluginsSubdir = 'moodpet/plugins';

/// Resolve the absolute path to the plugins root directory, creating it if it
/// does not yet exist.
Future<Directory> pluginsRootDir() async {
  final support = await getApplicationSupportDirectory();
  final root = Directory('${support.path}/$kPluginsSubdir');
  if (!root.existsSync()) {
    await root.create(recursive: true);
  }
  return root;
}

/// Absolute path to the bundled default-smiley Friend asset directory.
const String kDefaultSmileyAssetPath =
    'assets/plugins/moodpet.friend.default_smiley.moodfriend';

/// Plugin id of the bundled default-smiley Friend.
const String kDefaultSmileyPluginId = 'moodpet.friend.default_smiley';

/// Absolute path to a plugin directory inside the plugins root, given its
/// folder name (e.g. `moodpet.friend.default_smiley.moodfriend`).
String pluginDirPath(Directory root, String folderName) =>
    '${root.path}/$folderName';

/// Whether a directory name ends with one of the plugin suffixes.
bool isPluginDirName(String name) =>
    name.endsWith(kFriendDirSuffix) ||
    name.endsWith(kApplicationDirSuffix) ||
    name.endsWith(kPackDirSuffix);

/// The manifest.json path inside a plugin directory.
File manifestFile(Directory pluginDir) =>
    File('${pluginDir.path}/manifest.json');

/// Resolve a relative interface path (from a Friend manifest's `interfaces`
/// block) against a plugin directory, returning an absolute [File] or
/// [Directory]. Returns `null` when the path is not set.
FileSystemEntity? resolveInterfacePath(Directory pluginDir, String? relative) {
  if (relative == null || relative.isEmpty) return null;
  final absolute = '${pluginDir.path}/$relative';
  // We do not stat here; callers decide file vs dir.
  return File(absolute);
}
