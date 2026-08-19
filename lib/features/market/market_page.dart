/// Plugin market page scaffold (§10 — [社区]).
///
/// The container provides only the interface and loading mechanism for a
/// plugin market. The actual market content (Friend/Application/Pack listings)
/// is filled by the community ecosystem. This page shows an inviting
/// illustration-style placeholder with the market contract description.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show kSpace4, kSpace8, kSpace12, kSpace16, kSpace32, kRadiusLg, ClayContainer, IconBadge;

class MarketPage extends ConsumerWidget {
  const MarketPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('插件市场')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(kSpace32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Illustration-style icon in a claymorphism orb.
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.3),
                ),
                child: Center(
                  child: Icon(
                    Icons.storefront_rounded,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: kSpace32),
              Text(
                '插件市场由社区生态填充',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: kSpace12),
              Text(
                'Everything is Plugin — 任何人都可以创建和分享\nFriend、Application 和整合包',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: kSpace32),
              // Feature highlights.
              _FeatureHighlights(),
              const SizedBox(height: kSpace32),
              // Local install button.
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('本地安装功能由社区 Application 插件提供 [社区]'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('从本地安装插件'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three small feature highlight chips showing the plugin ecosystem's value.
class _FeatureHighlights extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final features = <_FeatureItem>[
      _FeatureItem(
        icon: Icons.favorite_rounded,
        label: '伙伴',
        description: '情绪伙伴',
      ),
      _FeatureItem(
        icon: Icons.extension_rounded,
        label: '应用',
        description: '能力扩展',
      ),
      _FeatureItem(
        icon: Icons.inventory_2_rounded,
        label: '整合包',
        description: '一键套装',
      ),
    ];

    return Row(
      children: features.map((f) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSpace4),
            child: ClayContainer(
              padding: const EdgeInsets.symmetric(
                  vertical: kSpace16, horizontal: kSpace8),
              radius: kRadiusLg,
              shadowIntensity: 0.5,
              child: Column(
                children: [
                  IconBadge(
                    icon: f.icon,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    size: 40,
                    iconSize: 20,
                  ),
                  const SizedBox(height: kSpace8),
                  Text(
                    f.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    f.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FeatureItem {
  final IconData icon;
  final String label;
  final String description;

  const _FeatureItem({
    required this.icon,
    required this.label,
    required this.description,
  });
}
