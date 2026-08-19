/// Plugin installer: download a `.mood*` package, unzip, validate, and register
/// it into the plugins root so [PluginManager] can load it.
///
/// Flow (§9 + market integration):
///   1. Download the plugin package ZIP from the market (via [MarketRepository]
///      — the bytes are cached permanently on disk by [MarketCache]).
///   2. Unzip into a temporary directory using `package:archive`.
///   3. Validate the inner `manifest.json`: it must exist, and its `id`/`type`
///      must match the [MarketPlugin] being installed.
///   4. Copy the plugin directory into the plugins root:
///      - Friend / Application → `<safeId><suffix>/` via [copyDirectory].
///      - Pack → [installPack], which expands constituents + the pack dir.
///   5. Call [PluginManager.refresh] so the new plugin appears in the registry.
///
/// The installer reuses the existing on-disk layout from `plugin_paths.dart`
/// and the pack-expansion logic from `pack_installer.dart` — it does not
/// invent a second plugin directory or a second pack installer.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../market/market_repository.dart';
import '../models/plugin_type.dart';
import 'pack_installer.dart';
import 'plugin_paths.dart';

/// Result of an install attempt.
class PluginInstallResult {
  final bool success;
  final String? error;

  /// Plugin ids installed (one for Friend/Application; many for a Pack).
  final List<String> installedIds;

  const PluginInstallResult.ok(this.installedIds)
      : success = true,
        error = null;
  const PluginInstallResult.fail(this.error)
      : success = false,
        installedIds = const <String>[];
}

/// Downloads, unzips, validates, and registers a market plugin.
class PluginInstaller {
  final MarketRepository repository;

  PluginInstaller(this.repository);

  /// Install [plugin] (a market entry) into the plugins root and refresh the
  /// [PluginManager]. Returns a [PluginInstallResult].
  ///
  /// [onProgress] (optional) receives 0.0–1.0 during the download phase so the
  /// UI can show a progress indicator; it is not called during unzip/copy.
  Future<PluginInstallResult> install(
    MarketPlugin plugin, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = plugin.dir;
    final tmpDir = await Directory.systemTemp.createTemp('moodpet_install_');
    try {
      // 1. Download the package (cache-permanent; may hit network only once).
      //    Stream the bytes so onProgress fires during download.
      final packageFile = await repository.downloadPackage(dir, plugin.id,
          onProgress: onProgress);

      // 2. Unzip into the temp dir. The ZIP root must contain manifest.json
      //    directly (no wrapping directory) — see the market repo spec.
      final bytes = await packageFile.readAsBytes();
      try {
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final file in archive) {
          if (!file.isFile) continue;
          final name = file.name;
          // Guard against zip-slip: reject absolute or `..` paths.
          if (name.startsWith('/') || name.contains('..')) {
            return PluginInstallResult.fail('unsafe entry path in package: $name');
          }
          final outFile = File('${tmpDir.path}/$name');
          outFile.parent.createSync(recursive: true);
          outFile.writeAsBytesSync(file.content as List<int>);
        }
      } on ArchiveException catch (e) {
        return PluginInstallResult.fail('package is not a valid zip: $e');
      }

      // 3. Validate the inner manifest.json.
      final mf = manifestFile(tmpDir);
      if (!mf.existsSync()) {
        return const PluginInstallResult.fail('manifest.json not found in package');
      }
      Map<String, Object?> manifest;
      try {
        final decoded = jsonDecode(mf.readAsStringSync());
        if (decoded is! Map<String, Object?>) {
          return const PluginInstallResult.fail('manifest.json is not a JSON object');
        }
        manifest = decoded;
      } on FormatException catch (e) {
        return PluginInstallResult.fail('manifest.json invalid: ${e.message}');
      }
      final mfId = manifest['id'];
      final mfType = manifest['type'];
      if (mfId is! String || mfId != plugin.id) {
        return PluginInstallResult.fail(
            'manifest id ($mfId) does not match market id (${plugin.id})');
      }
      if (mfType is! String || PluginType.fromString(mfType) != plugin.type) {
        return PluginInstallResult.fail(
            'manifest type ($mfType) does not match market type (${plugin.type.name})');
      }

      // 4. Copy into the plugins root.
      final root = await pluginsRootDir();
      final List<String> installedIds;
      switch (plugin.type) {
        case PluginType.pack:
          final packResult = await installPack(tmpDir);
          if (!packResult.success) {
            return PluginInstallResult.fail(
                packResult.error ?? 'pack install failed');
          }
          installedIds = packResult.installedPluginIds;
          break;
        case PluginType.friend:
        case PluginType.application:
          final safeId = plugin.id.replaceAll('/', '.');
          final dest = Directory(pluginDirPath(root, '$safeId${dir.suffix}'));
          if (dest.existsSync()) {
            await dest.delete(recursive: true);
          }
          await copyDirectory(tmpDir, dest);
          installedIds = <String>[plugin.id];
          break;
      }

      return PluginInstallResult.ok(installedIds);
    } finally {
      // Clean up the temp extraction dir. The downloaded package stays in the
      // market cache (permanent) for re-install / offline use.
      if (tmpDir.existsSync()) {
        await tmpDir.delete(recursive: true);
      }
    }
  }
}
