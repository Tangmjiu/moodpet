/// Plugin detail page: full metadata, platform compatibility, source URL, and
/// the install action with visible progress. Reached via `/market/plugin`;
/// `/market/pack` reuses [PluginDetailBody] with the pack note enabled.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart'
    show
        ClayContainer,
        IconBadge,
        kRadiusMd,
        kRadiusXl,
        kSpace4,
        kSpace8,
        kSpace12,
        kSpace16,
        kSpace24;
import '../../core/market/market_providers.dart';
import '../../core/market/market_repository.dart';
import '../../core/platform_info.dart';
import '../../core/providers.dart';
import 'preview_image.dart';

/// Route wrapper: reads the [MarketPlugin] argument and renders the shared
/// detail body. Shows a friendly error when the argument is missing/wrong.
class PluginDetailPage extends StatelessWidget {
  const PluginDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! MarketPlugin) {
      return Scaffold(
        appBar: AppBar(title: const Text('插件详情')),
        body: const Center(child: Text('参数错误')),
      );
    }
    return PluginDetailBody(plugin: args);
  }
}

/// The shared detail body for both plugin and pack pages: preview hero, meta,
/// platform chips, stats, source URL, and the install action with progress.
class PluginDetailBody extends ConsumerStatefulWidget {
  final MarketPlugin plugin;

  /// Whether to show the pack note — a pack installs its constituent Friend /
  /// Application plugins as one unit.
  final bool isPack;

  const PluginDetailBody({
    super.key,
    required this.plugin,
    this.isPack = false,
  });

  @override
  ConsumerState<PluginDetailBody> createState() => _PluginDetailBodyState();
}

class _PluginDetailBodyState extends ConsumerState<PluginDetailBody> {
  /// Install progress (0.0–1.0); null shows an indeterminate bar while
  /// installing. Reset to null when the install finishes.
  double? _progress;
  bool _installing = false;

  Future<void> _install() async {
    if (_installing) return;
    // An "update" is just a re-install over an existing plugin.
    final manager = ref.read(pluginManagerProvider).maybeWhen(
          data: (m) => m,
          orElse: () => null,
        );
    final isUpdate = manager?.pluginById(widget.plugin.id) != null;
    setState(() => _installing = true);
    try {
      final installer = await ref.read(pluginInstallerProvider.future);
      final result = await installer.install(
        widget.plugin,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
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
      if (mounted) {
        setState(() {
          _installing = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plugin = widget.plugin;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = ref.read(marketConfigProvider);
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

    return Scaffold(
      appBar: AppBar(title: Text(plugin.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(kSpace16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview hero.
            ClayContainer(
              padding: EdgeInsets.zero,
              radius: kRadiusXl,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(kRadiusXl),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: PreviewImage(dir: plugin.dir, id: plugin.id),
                ),
              ),
            ),
            const SizedBox(height: kSpace16),
            // Name.
            Text(
              plugin.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: kSpace4),
            // Author + version chip.
            Row(
              children: [
                Expanded(
                  child: Text(
                    plugin.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Chip(
                  label: Text('v${plugin.version}'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: kSpace16),
            // Full description.
            Text(
              plugin.description,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
            const SizedBox(height: kSpace16),
            // Platform chips, current platform highlighted.
            Text(
              '平台',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: kSpace8),
            Wrap(
              spacing: kSpace8,
              runSpacing: kSpace8,
              children: [
                for (final p in plugin.platforms)
                  Chip(
                    label: Text(p.name),
                    backgroundColor: p == currentPlatformId
                        ? colorScheme.primaryContainer
                        : null,
                    labelStyle: TextStyle(
                      color: p == currentPlatformId
                          ? colorScheme.onPrimaryContainer
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: kSpace16),
            // Stats row.
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.insert_drive_file_outlined,
                    label: '文件大小',
                    value: plugin.fileSize ?? '—',
                  ),
                ),
                const SizedBox(width: kSpace8),
                Expanded(
                  child: _StatTile(
                    icon: Icons.download_rounded,
                    label: '下载量',
                    value: '${plugin.downloads}',
                  ),
                ),
                const SizedBox(width: kSpace8),
                Expanded(
                  child: _StatTile(
                    icon: Icons.star_rounded,
                    label: '评分',
                    value: plugin.rating.toStringAsFixed(1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: kSpace16),
            // Source URL (selectable — no url_launcher dependency).
            Text(
              '源码',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: kSpace8),
            ClayContainer(
              radius: kRadiusMd,
              shadowIntensity: 0.4,
              child: SizedBox(
                width: double.infinity,
                child: SelectableText(
                  config.rawUrl(config.metaPath(plugin.dir, plugin.id)),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            if (widget.isPack) ...[
              const SizedBox(height: kSpace16),
              ClayContainer(
                radius: kRadiusMd,
                shadowIntensity: 0.4,
                child: Row(
                  children: [
                    const IconBadge(icon: Icons.inventory_2_outlined),
                    const SizedBox(width: kSpace12),
                    Expanded(
                      child: Text(
                        '整合包包含一组 Friend / Application 插件，点击安装将一并装入。',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: kSpace24),
            // Install area.
            SizedBox(
              width: double.infinity,
              child: _buildInstallButton(isInstalled, isUpdatable),
            ),
            if (_installing) ...[
              const SizedBox(height: kSpace12),
              ClipRRect(
                borderRadius: BorderRadius.circular(kRadiusMd),
                child: LinearProgressIndicator(value: _progress),
              ),
            ],
            const SizedBox(height: kSpace24),
          ],
        ),
      ),
    );
  }

  Widget _buildInstallButton(bool isInstalled, bool isUpdatable) {
    if (_installing) {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.downloading_rounded),
        label: const Text('安装中…'),
      );
    }
    if (isUpdatable) {
      return FilledButton.tonalIcon(
        onPressed: _install,
        icon: const Icon(Icons.upgrade_rounded),
        label: const Text('更新'),
      );
    }
    if (isInstalled) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_rounded),
        label: const Text('已安装'),
      );
    }
    return FilledButton.icon(
      onPressed: _install,
      icon: const Icon(Icons.download_rounded),
      label: const Text('安装'),
    );
  }
}

/// One stat cell (文件大小 / 下载量 / 评分): icon badge + label + value inside a
/// small clay surface.
class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClayContainer(
      shadowIntensity: 0.4,
      radius: kRadiusMd,
      padding: const EdgeInsets.all(kSpace12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, size: 32, iconSize: 16),
          const SizedBox(height: kSpace8),
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
