/// Plugin management page (§8): list all plugins, toggle enable/disable,
/// switch active Friend, expand packs, uninstall non-system plugins.
///
/// Claymorphism list layout with icon-badge avatars, clear active/inactive
/// states, and grouped section headers (§4.2 "后台页面").
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show kSpace4, kSpace8, kSpace12, kSpace16, kSpace32, kRadiusLg, ClayContainer, IconBadge;
import '../../core/models/plugin_type.dart';
import '../../core/plugin/plugin_loader.dart';
import '../../core/plugin/plugin_manager.dart';
import '../../core/providers.dart';

class PluginManagementPage extends ConsumerStatefulWidget {
  const PluginManagementPage({super.key});

  @override
  ConsumerState<PluginManagementPage> createState() =>
      _PluginManagementPageState();
}

class _PluginManagementPageState extends ConsumerState<PluginManagementPage> {
  @override
  Widget build(BuildContext context) {
    final managerAsync = ref.watch(pluginManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('插件管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.store_outlined),
            tooltip: '插件市场',
            onPressed: () => Navigator.pushNamed(context, '/market'),
          ),
        ],
      ),
      body: managerAsync.when(
        data: (manager) => _PluginList(manager: manager),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }
}

class _PluginList extends ConsumerWidget {
  final PluginManager manager;
  const _PluginList({required this.manager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = manager.friends;
    final applications = manager.applications;
    final packs = manager.packs;
    final failed = manager.failedPlugins;

    return ListView(
      padding: const EdgeInsets.symmetric(
          horizontal: kSpace16, vertical: kSpace8),
      children: [
        if (friends.isNotEmpty) ...[
          _SectionHeader(title: '伙伴 (Friend)', count: friends.length),
          ...friends.map((p) => _FriendTile(
                manager: manager,
                plugin: p,
                isActive: manager.activeFriendId == p.id,
                onActivate: () => _activateFriend(ref, p.id),
                onToggle: () => _toggle(ref, p.id, manager.isEnabled(p.id)),
              )),
        ],
        if (applications.isNotEmpty) ...[
          const SizedBox(height: kSpace16),
          _SectionHeader(
              title: '应用 (Application)', count: applications.length),
          ...applications.map((p) => _PluginTile(
                manager: manager,
                plugin: p,
                onToggle: () => _toggle(ref, p.id, manager.isEnabled(p.id)),
              )),
        ],
        if (packs.isNotEmpty) ...[
          const SizedBox(height: kSpace16),
          _SectionHeader(title: '整合包 (Pack)', count: packs.length),
          ...packs.map((p) => _PluginTile(
                manager: manager,
                plugin: p,
                onToggle: () => _toggle(ref, p.id, manager.isEnabled(p.id)),
              )),
        ],
        if (failed.isNotEmpty) ...[
          const SizedBox(height: kSpace16),
          _SectionHeader(
              title: '加载失败', count: failed.length, isError: true),
          ...failed.map((p) => _ErrorTile(plugin: p)),
        ],
        const SizedBox(height: kSpace32),
      ],
    );
  }

  void _activateFriend(WidgetRef ref, String id) {
    manager.setActiveFriend(id);
    ref.invalidate(pluginManagerProvider);
  }

  void _toggle(WidgetRef ref, String id, bool currentlyEnabled) {
    if (currentlyEnabled) {
      manager.disable(id);
    } else {
      manager.enable(id);
    }
    ref.invalidate(pluginManagerProvider);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool isError;
  const _SectionHeader({
    required this.title,
    required this.count,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpace4, kSpace12, kSpace4, kSpace8),
      child: Text(
        '$title ($count)',
        style: theme.textTheme.labelLarge?.copyWith(
          color: isError
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// A Friend plugin tile — shows emoji avatar, name, description, active badge,
/// and enable/disable switch.
class _FriendTile extends StatelessWidget {
  final PluginManager manager;
  final LoadedPlugin plugin;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onToggle;

  const _FriendTile({
    required this.manager,
    required this.plugin,
    required this.isActive,
    required this.onActivate,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manifest = plugin.manifest;
    final isEnabled = manager.isEnabled(plugin.id);
    final isSystem = plugin.isSystem;

    return Padding(
      padding: const EdgeInsets.only(bottom: kSpace8),
      child: ClayContainer(
        padding: EdgeInsets.zero,
        radius: kRadiusLg,
        borderColor: isActive ? theme.colorScheme.primary : null,
        shadowIntensity: isActive ? 1.2 : 0.6,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: kSpace16, vertical: kSpace12),
          child: Row(
            children: [
              // Friend emoji avatar in a soft circle.
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.4),
                ),
                child: Center(
                  child: Text('😊', style: const TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(width: kSpace16),
              // Name + description.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      manifest?.name ?? plugin.folderName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (manifest?.description != null &&
                        manifest!.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        manifest.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: kSpace8),
              // Active badge / switch button.
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: kSpace12, vertical: kSpace4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '当前',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (isEnabled)
                TextButton(
                  onPressed: onActivate,
                  child: const Text('切换'),
                ),
              // Enable/disable switch (disabled for system plugins).
              Switch(
                value: isEnabled,
                onChanged: isSystem ? null : (_) => onToggle(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An Application or Pack plugin tile — icon badge, name, description, switch.
class _PluginTile extends StatelessWidget {
  final PluginManager manager;
  final LoadedPlugin plugin;
  final VoidCallback onToggle;

  const _PluginTile({
    required this.manager,
    required this.plugin,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manifest = plugin.manifest;
    final isEnabled = manager.isEnabled(plugin.id);
    final isSystem = plugin.isSystem;
    final isApplication = plugin.type == PluginType.application;

    return Padding(
      padding: const EdgeInsets.only(bottom: kSpace8),
      child: ClayContainer(
        padding: EdgeInsets.zero,
        radius: kRadiusLg,
        shadowIntensity: 0.6,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: kSpace16, vertical: kSpace12),
          child: Row(
            children: [
              IconBadge(
                icon: isApplication
                    ? Icons.extension_outlined
                    : Icons.inventory_2_outlined,
                backgroundColor: isApplication
                    ? theme.colorScheme.tertiaryContainer
                    : theme.colorScheme.secondaryContainer,
                foregroundColor: isApplication
                    ? theme.colorScheme.onTertiaryContainer
                    : theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: kSpace16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      manifest?.name ?? plugin.folderName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (manifest?.description != null &&
                        manifest!.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        manifest.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Switch(
                value: isEnabled,
                onChanged: isSystem ? null : (_) => onToggle(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An error tile for plugins that failed to load.
class _ErrorTile extends StatelessWidget {
  final LoadedPlugin plugin;
  const _ErrorTile({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: kSpace8),
      child: ClayContainer(
        padding: const EdgeInsets.symmetric(
            horizontal: kSpace16, vertical: kSpace12),
        radius: kRadiusLg,
        borderColor: theme.colorScheme.error.withValues(alpha: 0.3),
        shadowIntensity: 0.4,
        child: Row(
          children: [
            IconBadge(
              icon: Icons.error_outline,
              backgroundColor:
                  theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: kSpace16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plugin.folderName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    plugin.error ?? '未知错误',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
