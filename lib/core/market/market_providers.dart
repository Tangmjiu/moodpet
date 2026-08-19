/// Riverpod providers for the plugin market.
///
/// Mirrors the style of `lib/core/providers.dart`: manual `FutureProvider` /
/// `Provider` declarations (no codegen), async singletons that `ref.watch`
/// their dependencies via `.future`. The UI imports this one file.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'market_config.dart';
import 'market_cache.dart';
import 'market_repository.dart';
import '../plugin/plugin_installer.dart';
import '../providers.dart';
import 'update_checker.dart';

export 'update_checker.dart' show PluginUpdate;

/// Market configuration. Defaults to the official community market; override
/// by overriding this provider before `ProviderScope` (e.g. for tests / forks).
final marketConfigProvider = Provider<MarketConfig>(
  (ref) => MarketConfig.defaultConfig,
);

/// On-disk market cache. Rooted at `<appSupportDir>/moodpet/market-cache/`.
final marketCacheProvider = FutureProvider<MarketCache>(
  (ref) async {
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/$kMarketCacheSubdir');
    return MarketCache(root);
  },
);

/// Market repository singleton (config + cache + owned http client).
final marketRepositoryProvider = FutureProvider<MarketRepository>(
  (ref) async {
    final config = ref.watch(marketConfigProvider);
    final cache = await ref.watch(marketCacheProvider.future);
    return MarketRepository(config, cache);
  },
);

/// Plugin installer singleton.
final pluginInstallerProvider = FutureProvider<PluginInstaller>(
  (ref) async {
    final repository = await ref.watch(marketRepositoryProvider.future);
    return PluginInstaller(repository);
  },
);

/// Update checker singleton — depends on the repository and the plugin manager.
final updateCheckerProvider = FutureProvider<UpdateChecker>(
  (ref) async {
    final repository = await ref.watch(marketRepositoryProvider.future);
    final manager = await ref.watch(pluginManagerProvider.future);
    return UpdateChecker(repository, manager);
  },
);

// ── directory list providers ────────────────────────────────────────────────
//
// Each is a FutureProvider so the UI renders with `.when(data/loading/error)`.
// Pull-to-refresh calls `ref.invalidate(...)` to refetch (cache TTLs still
// apply — `refreshDirectory` drops the directory listing before re-listing).

/// All Friend plugins in the market.
final marketFriendListProvider =
    FutureProvider<List<MarketPlugin>>((ref) async {
  final repo = await ref.watch(marketRepositoryProvider.future);
  return repo.listDirectory(MarketDir.friend);
});

/// All Application plugins in the market.
final marketApplicationListProvider =
    FutureProvider<List<MarketPlugin>>((ref) async {
  final repo = await ref.watch(marketRepositoryProvider.future);
  return repo.listDirectory(MarketDir.application);
});

/// All packs in the market.
final marketPacksListProvider =
    FutureProvider<List<MarketPlugin>>((ref) async {
  final repo = await ref.watch(marketRepositoryProvider.future);
  return repo.listDirectory(MarketDir.packs);
});

/// Available updates for installed plugins. Refresh by invalidating.
final marketUpdatesProvider = FutureProvider<List<PluginUpdate>>((ref) async {
  final checker = await ref.watch(updateCheckerProvider.future);
  return checker.checkAll();
});
