/// Plugin market home (§10 — [社区]): three tabbed directories (伙伴 / 应用 /
/// 整合包) backed by the GitHub directory-as-index repository. Cards lead with
/// the preview image (content-first claymorphism), offer quick-install with a
/// visible in-flight state, and tap through to the detail pages.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart'
    show
        ClayContainer,
        kRadiusLg,
        kSpace4,
        kSpace8,
        kSpace12,
        kSpace16,
        kSpace32;
import '../../core/market/market_providers.dart';
import '../../core/market/market_repository.dart';
import '../../core/models/plugin_type.dart';
import '../../core/providers.dart';
import 'preview_image.dart';

class MarketPage extends ConsumerStatefulWidget {
  const MarketPage({super.key});

  @override
  ConsumerState<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends ConsumerState<MarketPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Ids of plugins with an install currently in flight.
  final Set<String> _installing = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshAll() {
    ref.invalidate(marketFriendListProvider);
    ref.invalidate(marketApplicationListProvider);
    ref.invalidate(marketPacksListProvider);
    ref.invalidate(marketUpdatesProvider);
  }

  Future<void> _install(MarketPlugin plugin) async {
    if (_installing.contains(plugin.id)) return;
    // An "update" is just a re-install over an existing plugin.
    final manager = ref.read(pluginManagerProvider).maybeWhen(
          data: (m) => m,
          orElse: () => null,
        );
    final isUpdate = manager?.pluginById(plugin.id) != null;
    setState(() => _installing.add(plugin.id));
    try {
      final installer = await ref.read(pluginInstallerProvider.future);
      final result = await installer.install(plugin);
      if (!mounted) return;
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isUpdate ? '更新成功' : '安装成功')),
        );
        ref.invalidate(pluginManagerProvider);
        ref.invalidate(marketUpdatesProvider);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('安装失败: ${result.error}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('安装失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _installing.remove(plugin.id));
    }
  }

  void _openDetail(MarketPlugin plugin) {
    Navigator.pushNamed(
      context,
      plugin.type == PluginType.pack ? '/market/pack' : '/market/plugin',
      arguments: plugin,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch available updates so the refresh badge can show a red dot when any
    // installed plugin has a newer market version. Errors / loading hide it.
    final hasUpdates = ref.watch(marketUpdatesProvider).maybeWhen(
          data: (updates) => updates.isNotEmpty,
          orElse: () => false,
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件市场'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refreshAll,
            icon: Badge(
              isLabelVisible: hasUpdates,
              backgroundColor: Theme.of(context).colorScheme.error,
              child: const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '伙伴'),
            Tab(text: '应用'),
            Tab(text: '整合包'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MarketTab(
            provider: marketFriendListProvider,
            installing: _installing,
            onInstall: _install,
            onOpen: _openDetail,
          ),
          _MarketTab(
            provider: marketApplicationListProvider,
            installing: _installing,
            onInstall: _install,
            onOpen: _openDetail,
          ),
          _MarketTab(
            provider: marketPacksListProvider,
            installing: _installing,
            onInstall: _install,
            onOpen: _openDetail,
          ),
        ],
      ),
    );
  }
}

/// One directory tab: pull-to-refresh + async grid of [_MarketPluginCard]s.
class _MarketTab extends ConsumerWidget {
  final FutureProvider<List<MarketPlugin>> provider;
  final Set<String> installing;
  final void Function(MarketPlugin) onInstall;
  final void Function(MarketPlugin) onOpen;

  const _MarketTab({
    required this.provider,
    required this.installing,
    required this.onInstall,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(provider.future).then((_) {}),
      child: ref.watch(provider).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _MarketError(error: e),
        data: (plugins) => GridView.builder(
          padding: const EdgeInsets.all(kSpace16),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 500,
            childAspectRatio: 0.82,
            crossAxisSpacing: kSpace12,
            mainAxisSpacing: kSpace12,
          ),
          itemCount: plugins.length,
          itemBuilder: (context, index) {
            final plugin = plugins[index];
            return _MarketPluginCard(
              plugin: plugin,
              isInstalling: installing.contains(plugin.id),
              onInstall: () => onInstall(plugin),
              onOpen: () => onOpen(plugin),
            );
          },
        ),
      ),
    );
  }
}

class _MarketError extends StatelessWidget {
  final Object error;
  const _MarketError({required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: kSpace12),
          Text(
            '加载失败',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: kSpace4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSpace32),
            child: Text(
              '$error',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A market plugin card: preview image first (the content focus), meta below,
/// and a compact install button with a visible in-flight spinner.
class _MarketPluginCard extends ConsumerWidget {
  final MarketPlugin plugin;
  final bool isInstalling;
  final VoidCallback onInstall;
  final VoidCallback onOpen;

  const _MarketPluginCard({
    required this.plugin,
    required this.isInstalling,
    required this.onInstall,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final manager = ref.watch(pluginManagerProvider).maybeWhen(
          data: (m) => m,
          orElse: () => null,
        );
    final isInstalled = manager?.pluginById(plugin.id) != null;
    // Updatable = installed AND present in the available-updates list.
    final updatableIds = ref.watch(marketUpdatesProvider).maybeWhen(
          data: (updates) => updates.map((u) => u.pluginId).toSet(),
          orElse: () => const <String>{},
        );
    final isUpdatable = isInstalled && updatableIds.contains(plugin.id);

    return ClayContainer(
      padding: EdgeInsets.zero,
      radius: kRadiusLg,
      shadowIntensity: 0.6,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The preview takes the card's flexible space and stays the focus.
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(kRadiusLg),
              ),
              child: PreviewImage(dir: plugin.dir, id: plugin.id),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(kSpace12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  plugin.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  plugin.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  plugin.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: kSpace8),
                Row(
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      plugin.rating.toStringAsFixed(1),
                      style: theme.textTheme.labelMedium,
                    ),
                    const Spacer(),
                    _buildInstallButton(isInstalled, isUpdatable),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallButton(bool isInstalled, bool isUpdatable) {
    if (isInstalling) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (isUpdatable) {
      // Installed but a newer version exists in the market.
      return FilledButton.tonal(
        onPressed: onInstall,
        child: const Text('更新'),
      );
    }
    if (isInstalled) {
      return const OutlinedButton(onPressed: null, child: Text('已安装'));
    }
    return FilledButton(onPressed: onInstall, child: const Text('安装'));
  }
}
