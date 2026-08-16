import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/llm_provider.dart';
import '../../core/models/region_info.dart';
import '../../core/providers/settings_providers.dart';
import '../widgets/provider_logo.dart';

/// 设置页 → 切换 LLM 提供商。
class ProviderSwitchPage extends ConsumerWidget {
  const ProviderSwitchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref
            .watch(settingsControllerProvider)
            .valueOrNull
            ?.selectedProviderId;
    return Scaffold(
      appBar: AppBar(title: const Text('切换提供商')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('API Key 沿用当前加密保存值；需要换 Key 请回设置页修改。'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _regionGroup(
            context,
            ref,
            'PRC 地区（中国大陆 / 香港 / 澳门）',
            llmProvidersForRegion(AppRegion.prc),
            currentId,
          ),
          const SizedBox(height: 16),
          _regionGroup(
            context,
            ref,
            'OTHER 地区（台湾及其他所有地区）',
            llmProvidersForRegion(AppRegion.other),
            currentId,
          ),
        ],
      ),
    );
  }

  Widget _regionGroup(
    BuildContext context,
    WidgetRef ref,
    String title,
    List<LLMProvider> providers,
    String? currentId,
  ) {
    return ExpansionTile(
      initiallyExpanded: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 4),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(
        '$title（${providers.length}）',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      children: [
        for (final provider in providers)
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            leading: ProviderLogo(
              assetPath: provider.iconAsset,
              providerName: provider.name,
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    provider.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (provider.isRecommended) ...[
                  const SizedBox(width: 8),
                  const Chip(
                    label: Text('推荐'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
            subtitle: Text(
              provider.description ?? provider.officialEndpoint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(
              currentId == provider.id
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: currentId == provider.id
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
            ),
            onTap: () => _select(context, ref, provider),
          ),
      ],
    );
  }

  Future<void> _select(
      BuildContext context, WidgetRef ref, LLMProvider provider) async {
    await ref
        .read(settingsControllerProvider.notifier)
        .setSelectedProvider(provider.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }
}
