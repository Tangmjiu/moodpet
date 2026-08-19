/// Pack installer (§9): install `.moodpack` bundles by expanding them into
/// their constituent Friend + Application plugins.
///
/// A pack is a directory containing a `manifest.json` (type: "pack") plus
/// `friend/` and `application/` subdirectories. Installing a pack:
///   1. Parse the pack manifest to get the plugin reference list.
///   2. Copy each referenced plugin into the plugins root.
///   3. Optionally set the recommended default Friend / Applications as active.
///
/// Uninstalling a pack removes all its constituent plugins (unless they are
/// system plugins). Individual plugins within an installed pack can be
/// replaced or uninstalled independently.
library;

import 'dart:convert';
import 'dart:io';

import '../models/plugin_manifest.dart';
import 'plugin_paths.dart';

/// Result of a pack installation attempt.
class PackInstallResult {
  final bool success;
  final String? error;
  final List<String> installedPluginIds;

  const PackInstallResult.ok(this.installedPluginIds)
      : success = true,
        error = null;
  const PackInstallResult.fail(this.error)
      : success = false,
        installedPluginIds = const <String>[];
}

/// Install a pack from a source directory.
///
/// The source directory must contain a valid `manifest.json` with
/// `"type": "pack"`. Each referenced plugin directory is copied into the
/// plugins root. Returns the list of installed plugin ids on success.
Future<PackInstallResult> installPack(Directory sourceDir) async {
  // Parse the pack manifest.
  final mf = manifestFile(sourceDir);
  if (!mf.existsSync()) {
    return const PackInstallResult.fail('pack manifest.json not found');
  }

  PackManifest manifest;
  try {
    final raw = mf.readAsStringSync();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      return const PackInstallResult.fail('pack manifest is not a JSON object');
    }
    manifest = PackManifest.fromJson(decoded);
  } on FormatException catch (e) {
    return PackInstallResult.fail('pack manifest invalid: ${e.message}');
  }

  final root = await pluginsRootDir();
  final installedIds = <String>[];

  // Install each referenced Friend plugin.
  for (final ref in manifest.plugins.friend) {
    final pluginDir = Directory('${sourceDir.path}/${ref.path}');
    if (!pluginDir.existsSync()) {
      continue; // skip missing
    }
    final id = await _copyPlugin(pluginDir, root, kFriendDirSuffix);
    if (id != null) installedIds.add(id);
  }

  // Install each referenced Application plugin.
  for (final ref in manifest.plugins.application) {
    final pluginDir = Directory('${sourceDir.path}/${ref.path}');
    if (!pluginDir.existsSync()) {
      continue;
    }
    final id = await _copyPlugin(pluginDir, root, kApplicationDirSuffix);
    if (id != null) installedIds.add(id);
  }

  // Also copy the pack itself into the pack directory.
  final packDirName =
      manifest.id.replaceAll('/', '.') + kPackDirSuffix;
  final packDest = Directory(pluginDirPath(root, packDirName));
  if (packDest.existsSync()) {
    await packDest.delete(recursive: true);
  }
  await copyDirectory(sourceDir, packDest);

  return PackInstallResult.ok(installedIds);
}

/// Copy a plugin directory into the plugins root, reading its id from its
/// manifest. Returns the plugin id, or `null` when the manifest is missing or
/// invalid.
Future<String?> _copyPlugin(
    Directory source, Directory root, String suffix) async {
  final mf = manifestFile(source);
  if (!mf.existsSync()) return null;
  try {
    final raw = mf.readAsStringSync();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) return null;
    final id = decoded['id'];
    if (id is! String) return null;
    final safeId = id.replaceAll('/', '.');
    final dest = Directory(pluginDirPath(root, '$safeId$suffix'));
    if (dest.existsSync()) {
      await dest.delete(recursive: true);
    }
    await copyDirectory(source, dest);
    return id;
  } catch (_) {
    return null;
  }
}

/// Recursively copy a directory.
Future<void> copyDirectory(Directory source, Directory destination) async {
  if (!destination.existsSync()) {
    await destination.create(recursive: true);
  }
  for (final entity in source.listSync(followLinks: false)) {
    final name = entity.path.split('/').last;
    final destPath = '${destination.path}/$name';
    if (entity is File) {
      await entity.copy(destPath);
    } else if (entity is Directory) {
      await copyDirectory(entity, Directory(destPath));
    }
  }
}
