/// Time-based cache for the plugin market.
///
/// Caches four data kinds with distinct TTLs (per the market design spec):
///
/// | data kind         | TTL        | storage   |
/// |-------------------|------------|-----------|
/// | directory listing | 5 minutes | in-memory |
/// | `.meta.json`      | 1 hour     | in-memory |
/// | preview `.png`    | 7 days     | on-disk   |
/// | plugin package    | permanent  | on-disk   |
///
/// Directory listings and metadata are small and frequently invalidated by
/// pull-to-refresh, so they live in memory only. Preview images and plugin
/// packages can be large and should survive app restarts, so they persist on
/// disk under `<appSupportDir>/moodpet/market-cache/`. A package is kept
/// permanently until the user uninstalls the plugin (handled by the installer,
/// not this cache).
///
/// The cache stores metadata as raw `Map<String, Object?>` JSON rather than a
/// typed model, so this module has no dependency on the repository layer (which
/// owns the typed [MarketPlugin] model). The repository parses on read.
///
/// Safe to call from a single isolate (the UI isolate). Memory methods are
/// synchronous; disk methods return [File]s for the caller to read.
library;

import 'dart:io';

import 'market_config.dart';

/// Cache TTLs.
const Duration kMarketDirTtl = Duration(minutes: 5);
const Duration kMarketMetaTtl = Duration(hours: 1);
const Duration kMarketImageTtl = Duration(days: 7);

/// Subdirectory under the app-support directory that holds the on-disk cache.
const String kMarketCacheSubdir = 'moodpet/market-cache';

/// One in-memory cache entry with an expiry timestamp.
class _CacheEntry<T> {
  final T value;
  final DateTime expiresAt;

  _CacheEntry(this.value, this.expiresAt);

  bool get isFresh => DateTime.now().isBefore(expiresAt);
}

/// A lightweight reference to a plugin discovered in a directory listing —
/// just the id plus which directory it came from. The GitHub Contents API
/// gives us file names; the id is the `.meta.json` filename stem.
class MarketPluginRef {
  /// Plugin id (the `.meta.json` filename stem).
  final String id;

  /// The directory this ref was discovered in.
  final MarketDir dir;

  const MarketPluginRef({required this.id, required this.dir});
}

/// The plugin market cache.
class MarketCache {
  /// Root directory for on-disk cached images and packages.
  final Directory diskRoot;

  MarketCache(this.diskRoot) {
    if (!diskRoot.existsSync()) {
      diskRoot.createSync(recursive: true);
    }
  }

  // ── directory listings (in-memory, 5 min) ────────────────────────────────
  final Map<String, _CacheEntry<List<MarketPluginRef>>> _dirs = {};

  /// Return the cached directory listing for [dir] if still fresh, else `null`.
  List<MarketPluginRef>? getDirectory(MarketDir dir) {
    final e = _dirs[dir.path];
    return (e != null && e.isFresh) ? e.value : null;
  }

  /// Store a directory listing with the directory TTL.
  void putDirectory(MarketDir dir, List<MarketPluginRef> entries) {
    _dirs[dir.path] = _CacheEntry(entries, DateTime.now().add(kMarketDirTtl));
  }

  /// Drop a cached directory listing (used by pull-to-refresh).
  void invalidateDirectory(MarketDir dir) => _dirs.remove(dir.path);

  /// Drop all cached directory listings.
  void invalidateAllDirectories() => _dirs.clear();

  // ── metadata (in-memory, 1 hour, stored as raw JSON) ──────────────────────
  final Map<String, _CacheEntry<Map<String, Object?>>> _metas = {};

  static String _metaKey(MarketDir dir, String id) => '${dir.path}/$id';

  /// Return cached metadata (raw JSON) if fresh, else `null`.
  Map<String, Object?>? getMeta(MarketDir dir, String id) {
    final e = _metas[_metaKey(dir, id)];
    return (e != null && e.isFresh) ? e.value : null;
  }

  /// Store metadata (raw JSON) with the metadata TTL.
  void putMeta(MarketDir dir, String id, Map<String, Object?> json) {
    _metas[_metaKey(dir, id)] =
        _CacheEntry(json, DateTime.now().add(kMarketMetaTtl));
  }

  /// Drop one cached meta entry.
  void invalidateMeta(MarketDir dir, String id) =>
      _metas.remove(_metaKey(dir, id));

  // ── preview images (on-disk, 7 days) ──────────────────────────────────────
  //
  // Files are stored as `<diskRoot>/image/<dir>/<id>.png`. Freshness is the
  // file's last-modified time vs [kMarketImageTtl].

  File _imageFile(MarketDir dir, String id) =>
      File('${diskRoot.path}/image/${dir.path}/$id.png');

  /// Return the cached preview image [File] if it exists and is younger than
  /// [kMarketImageTtl], else `null`.
  File? getImage(MarketDir dir, String id) {
    final f = _imageFile(dir, id);
    if (!f.existsSync()) return null;
    final age = DateTime.now().difference(f.statSync().modified);
    if (age > kMarketImageTtl) return null;
    return f;
  }

  /// Write preview [bytes] to disk and return the [File].
  File putImage(MarketDir dir, String id, List<int> bytes) {
    final f = _imageFile(dir, id);
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes, flush: true);
    return f;
  }

  // ── plugin packages (on-disk, permanent) ──────────────────────────────────
  //
  // Stored as `<diskRoot>/package/<dir>/<id>.mood*`. Never expired by TTL —
  // the installer deletes a cached package only when the plugin is uninstalled.

  File _packageFile(MarketDir dir, String id) =>
      File('${diskRoot.path}/package/${dir.path}/$id${dir.suffix}');

  /// Return the cached package [File] if it exists, else `null`. Packages are
  /// permanent — no TTL check.
  File? getPackage(MarketDir dir, String id) {
    final f = _packageFile(dir, id);
    return f.existsSync() ? f : null;
  }

  /// Write package [bytes] to disk and return the [File].
  File putPackage(MarketDir dir, String id, List<int> bytes) {
    final f = _packageFile(dir, id);
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes, flush: true);
    return f;
  }

  /// Delete a cached package (called by the installer on uninstall).
  void removePackage(MarketDir dir, String id) {
    final f = _packageFile(dir, id);
    if (f.existsSync()) f.deleteSync();
  }
}
