/// Settings page (§12): LLM provider entry, plugin management, about.
///
/// Clean mobile settings with grouped claymorphism cards, coloured icon
/// badges, and clear visual hierarchy. The provider configuration is a
/// dedicated full-page selection (ProviderSelectionPage).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show kSpace4, kSpace8, kSpace12, kSpace16, kSpace24, kSpace32, kRadiusLg, ClayContainer, IconBadge;
import '../../core/provider_registry.dart';
import '../../core/providers.dart';
import 'conversation_page.dart';
import 'log_viewer_page.dart';
import 'provider_selection_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsStoreProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: settingsAsync.when(
        data: (settings) => _SettingsBody(settings: settings),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  final dynamic settings;
  const _SettingsBody({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeProviderId = settings.activeProviderId as String?;
    // Resolve through the registry so custom providers show their display
    // name, not their id. The registry future is one async hop past the
    // already-loaded settings; fall back to the raw id while it resolves.
    final registryAsync = ref.watch(providerRegistryProvider);
    final providerName = activeProviderId != null
        ? registryAsync.maybeWhen(
            data: (registry) =>
                _providerDisplayName(registry, activeProviderId),
            orElse: () => activeProviderId,
          )
        : null;

    return ListView(
      padding: const EdgeInsets.symmetric(
          horizontal: kSpace16, vertical: kSpace8),
      children: [
        // Provider section.
        _SectionTitle('LLM 提供商'),
        ClayContainer(
          padding: EdgeInsets.zero,
          radius: kRadiusLg,
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.psychology_rounded,
                iconBg: theme.colorScheme.primaryContainer,
                iconFg: theme.colorScheme.onPrimaryContainer,
                title: '提供商',
                subtitle: Text(
                  providerName ?? '未配置 — 点击选择',
                  style: TextStyle(
                    color: providerName == null
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                    fontWeight:
                        providerName == null ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const ProviderSelectionPage(fromOnboarding: false),
                    ),
                  );
                },
                showDivider: true,
              ),
              _SettingsTile(
                icon: Icons.forum_outlined,
                iconBg: theme.colorScheme.secondaryContainer,
                iconFg: theme.colorScheme.onSecondaryContainer,
                title: '对话历史',
                subtitle: const Text(
                  '伙伴记得你说过的内容',
                  style: TextStyle(fontWeight: FontWeight.w400),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ConversationPage(),
                    ),
                  );
                },
                showDivider: true,
              ),
              _SettingsTile(
                icon: Icons.article_outlined,
                iconBg: theme.colorScheme.surfaceContainerHighest,
                iconFg: theme.colorScheme.onSurface,
                title: '日志查看器',
                subtitle: const Text(
                  '查看 Agent / LLM 调用日志，导出诊断信息',
                  style: TextStyle(fontWeight: FontWeight.w400),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LogViewerPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: kSpace24),
        // Plugin management section.
        _SectionTitle('插件'),
        ClayContainer(
          padding: EdgeInsets.zero,
          radius: kRadiusLg,
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.extension_rounded,
                iconBg: theme.colorScheme.tertiaryContainer,
                iconFg: theme.colorScheme.onTertiaryContainer,
                title: '插件管理',
                subtitle: const Text(
                  '管理已安装的伙伴、应用和整合包',
                  style: TextStyle(fontWeight: FontWeight.w400),
                ),
                onTap: () => Navigator.pushNamed(context, '/plugins'),
                showDivider: true,
              ),
              _SettingsTile(
                icon: Icons.store_outlined,
                iconBg: theme.colorScheme.secondaryContainer,
                iconFg: theme.colorScheme.onSecondaryContainer,
                title: '插件市场',
                subtitle: const Text(
                  '浏览和安装社区插件 [社区]',
                  style: TextStyle(fontWeight: FontWeight.w400),
                ),
                onTap: () => Navigator.pushNamed(context, '/market'),
              ),
            ],
          ),
        ),
        const SizedBox(height: kSpace24),
        // About section.
        _SectionTitle('关于'),
        ClayContainer(
          padding: EdgeInsets.zero,
          radius: kRadiusLg,
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.info_outline,
                iconBg: theme.colorScheme.primaryContainer,
                iconFg: theme.colorScheme.onPrimaryContainer,
                title: '关于 MoodPet',
                subtitle: const Text(
                  '版本、贡献者、开源信息',
                  style: TextStyle(fontWeight: FontWeight.w400),
                ),
                onTap: () => Navigator.pushNamed(context, '/about'),
              ),
            ],
          ),
        ),
        const SizedBox(height: kSpace32),
      ],
    );
  }

  /// Display name for the provider with [id], resolved through the merged
  /// registry (builtins + customs). Falls back to the raw id when unknown.
  String _providerDisplayName(ProviderRegistry registry, String id) =>
      registry.byId(id)?.name ?? id;
}

/// A single settings list tile with an icon badge, title, subtitle, and
/// optional divider.
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final Widget? subtitle;
  final VoidCallback? onTap;
  final bool showDivider;

  const _SettingsTile({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    this.subtitle,
    this.onTap,
    this.showDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: showDivider
            ? const BorderRadius.vertical(top: Radius.circular(kRadiusLg))
            : null,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: kSpace16, vertical: kSpace12),
              child: Row(
                children: [
                  IconBadge(
                    icon: icon,
                    backgroundColor: iconBg,
                    foregroundColor: iconFg,
                    size: 40,
                    iconSize: 20,
                  ),
                  const SizedBox(width: kSpace16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleSmall),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          DefaultTextStyle(
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            child: subtitle!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: kSpace8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
                  ],
                ],
              ),
            ),
            if (showDivider)
              Padding(
                padding: const EdgeInsets.only(left: kSpace16 + 40 + kSpace16),
                child: Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant
                      .withValues(alpha: 0.4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpace4, kSpace12, kSpace4, kSpace8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
