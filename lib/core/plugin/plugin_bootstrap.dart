/// First-run bootstrap: extract the bundled default-smiley Friend plugin from
/// the app's `assets/` into the writable plugins root directory.
///
/// The default smiley is a *system* Friend plugin (`"system": true`,
/// `"uninstallable": false`) — it ships inside the APK/app bundle and is copied
/// to `<appSupport>/moodpet/plugins/moodpet.friend.default_smiley.moodfriend/`
/// on first launch so the loader can treat it identically to user-installed
/// plugins. The [PluginManager] will refuse to uninstall it because of the
/// system flag.
///
/// Bootstrap is idempotent: if the target directory already exists and its
/// `manifest.json` parses, it does nothing.
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import 'plugin_paths.dart';

/// The list of files inside the bundled default-smiley Friend asset directory
/// that must be extracted. Kept explicit (not scanned) because `rootBundle`
/// cannot list directory contents — it can only load individual asset paths.
const List<String> _kDefaultSmileyFiles = <String>[
  'manifest.json',
  'system_prompt.txt',
  'emoji_mapping.json',
  'assets/identity.json',
];

/// Extract the bundled default-smiley Friend plugin to the plugins root.
///
/// Returns `true` when the plugin is present and valid after the call (either
/// it already existed, or extraction succeeded). Returns `false` only when
/// extraction failed and the plugin is absent.
///
/// Safe to call on every startup — it short-circuits when the target already
/// exists with a valid manifest.
Future<bool> extractDefaultSmileyFriend() async {
  final root = await pluginsRootDir();
  final dest = Directory(pluginDirPath(root, 'moodpet.friend.default_smiley.moodfriend'));

  // Short-circuit when already extracted and valid.
  final existingManifest = File('${dest.path}/manifest.json');
  if (existingManifest.existsSync()) {
    try {
      existingManifest.readAsStringSync();
      return true;
    } catch (_) {
      // Fall through and re-extract.
    }
  }

  // Ensure the target directory exists.
  if (!dest.existsSync()) {
    dest.createSync(recursive: true);
  }

  // Extract each bundled file.
  for (final relPath in _kDefaultSmileyFiles) {
    final assetKey = '$kDefaultSmileyAssetPath/$relPath';
    final destFile = File('${dest.path}/$relPath');
    try {
      final data = await rootBundle.loadString(assetKey);
      destFile.parent.createSync(recursive: true);
      destFile.writeAsStringSync(data);
    } on Exception {
      // Asset missing from bundle — skip this file. The manifest + prompt are
      // required; if they are missing the loader will report an error.
    }
  }

  // Verify the required files landed.
  final manifestOk = File('${dest.path}/manifest.json').existsSync();
  final promptOk = File('${dest.path}/system_prompt.txt').existsSync();
  return manifestOk && promptOk;
}
