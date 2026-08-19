/// Update checker: compare installed plugins against market versions.
///
/// On startup or on user demand, the container asks the market for the latest
/// version of each installed plugin and surfaces the ones whose market version
/// is newer. Version comparison is semver-ish: `major.minor.patch` compared
/// numerically, with a string fallback for non-numeric segments so a weird
/// version string never crashes the check.
library;

import '../models/plugin_type.dart';
import '../plugin/plugin_manager.dart';
import 'market_config.dart';
import 'market_repository.dart';

/// One available update: the installed plugin vs its newer market version.
class PluginUpdate {
  /// Plugin id (matches both the installed manifest and the market meta).
  final String pluginId;

  /// Display name (from the market entry).
  final String name;

  /// Currently installed version.
  final String installedVersion;

  /// Version available in the market.
  final String marketVersion;

  /// Which market directory the plugin lives in.
  final MarketDir dir;

  const PluginUpdate({
    required this.pluginId,
    required this.name,
    required this.installedVersion,
    required this.marketVersion,
    required this.dir,
  });
}

/// Checks installed plugins against the market for available updates.
class UpdateChecker {
  final MarketRepository repository;
  final PluginManager manager;

  UpdateChecker(this.repository, this.manager);

  /// Check every loaded plugin for a newer market version. Plugins not present
  /// in the market (e.g. the system default, or a removed entry) are skipped
  /// silently. Network failures for a single plugin do not abort the check.
  Future<List<PluginUpdate>> checkAll() async {
    final updates = <PluginUpdate>[];
    for (final plugin in manager.allPlugins) {
      final dir = _dirForType(plugin.type);
      if (dir == null) continue;
      final installed = plugin.manifest?.version;
      if (installed == null || installed.isEmpty) continue;
      try {
        final market = await repository.fetchMeta(dir, plugin.id);
        if (_isNewer(market.version, installed)) {
          updates.add(PluginUpdate(
            pluginId: plugin.id,
            name: market.name,
            installedVersion: installed,
            marketVersion: market.version,
            dir: dir,
          ));
        }
      } on MarketException {
        // Market entry missing or unreachable — no update to offer.
        continue;
      }
    }
    return updates;
  }

  /// Check a single plugin id. Returns `null` when no update is available or
  /// the plugin is not in the market.
  Future<PluginUpdate?> checkOne(String pluginId) async {
    final plugin = manager.pluginById(pluginId);
    if (plugin == null) return null;
    final dir = _dirForType(plugin.type);
    if (dir == null) return null;
    final installed = plugin.manifest?.version;
    if (installed == null || installed.isEmpty) return null;
    try {
      final market = await repository.fetchMeta(dir, plugin.id);
      if (!_isNewer(market.version, installed)) return null;
      return PluginUpdate(
        pluginId: plugin.id,
        name: market.name,
        installedVersion: installed,
        marketVersion: market.version,
        dir: dir,
      );
    } on MarketException {
      return null;
    }
  }
}

/// Map a plugin type to its market directory. Returns `null` for `null` type
/// (an unloaded/broken plugin).
MarketDir? _dirForType(PluginType? type) {
  switch (type) {
    case PluginType.friend:
      return MarketDir.friend;
    case PluginType.application:
      return MarketDir.application;
    case PluginType.pack:
      return MarketDir.packs;
    case null:
      return null;
  }
}

/// Whether [a] is a newer semver than [b].
///
/// Parses `major.minor.patch` (plus any trailing pre-release text) and compares
/// numerically segment by segment. Non-numeric segments fall back to string
/// comparison so a malformed version never throws.
bool _isNewer(String a, String b) {
  final sa = _stripPreRelease(a).split('.');
  final sb = _stripPreRelease(b).split('.');
  final len = sa.length > sb.length ? sa.length : sb.length;
  for (var i = 0; i < len; i++) {
    final va = i < sa.length ? sa[i] : '0';
    final vb = i < sb.length ? sb[i] : '0';
    final na = int.tryParse(va);
    final nb = int.tryParse(vb);
    if (na != null && nb != null) {
      if (na != nb) return na > nb;
    } else {
      // Non-numeric: compare as strings.
      final cmp = va.compareTo(vb);
      if (cmp != 0) return cmp > 0;
    }
  }
  return false;
}

String _stripPreRelease(String v) {
  final dash = v.indexOf('-');
  final plus = v.indexOf('+');
  var end = v.length;
  if (dash >= 0 && dash < end) end = dash;
  if (plus >= 0 && plus < end) end = plus;
  return v.substring(0, end);
}
