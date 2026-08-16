import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app.dart';
import '../../core/llm/llm_provider.dart';
import '../../core/providers/settings_providers.dart';
import 'history_page.dart';
import 'provider_switch_page.dart';

/// 设置页（全 Material Icons，无 Emoji）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('设置加载失败：$error'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(settingsControllerProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (settings) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const _SectionHeader('大脑配置'),
            _ProviderTile(ref: ref),
            _ApiKeyTile(ref: ref),
            _ModelTile(ref: ref, settings: settings),
            _codingSwitch(ref, settings),
            const Divider(height: 32),
            const _SectionHeader('宠物设置'),
            SwitchListTile(
              title: const Text('震动反馈'),
              subtitle: const Text('情绪变化时震动'),
              value: settings.vibrationEnabled,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setVibrationEnabled(value),
            ),
            SwitchListTile(
              title: const Text('主动推送'),
              subtitle: const Text('定期送来陪伴提醒'),
              value: settings.proactivePushEnabled,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setProactivePushEnabled(value),
            ),
            const Divider(height: 32),
            const _SectionHeader('数据与隐私'),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('情绪历史'),
              subtitle: const Text('查看全部情绪记忆'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const HistoryPage(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: const Text('清除所有记忆'),
              subtitle: const Text('不可恢复'),
              onTap: () => _confirmClearMemories(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('导出数据'),
              subtitle: const Text('导出为 JSON 文件'),
              onTap: () => _exportData(context, ref),
            ),
            const Divider(height: 32),
            const _SectionHeader('关于'),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('版本'),
              subtitle: Text(kMoodPetVersion),
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('GitHub'),
              subtitle: const Text('查看 MoodPet 源码'),
              onTap: () => _openUrl('https://github.com/moodpet/moodpet'),
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('致谢'),
              subtitle: const Text('感谢开源社区与 LLM 服务商'),
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('致谢'),
                  content: const Text(
                    'MoodPet 基于 Flutter、Riverpod 与 PocketClaw 构建。'
                    '感谢所有开源项目维护者，以及提供 API 的 LLM 服务商。',
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('知道啦'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _codingSwitch(WidgetRef ref, AppSettings settings) {
    final provider = ref.watch(selectedProviderProvider);
    final available = provider?.hasCodingPlan == true;
    return SwitchListTile(
      title: const Text('Coding Plan'),
      subtitle: Text(
        available
            ? '当前提供商支持 Coding Plan'
            : '当前提供商不支持 Coding Plan',
      ),
      value: settings.codingPlanEnabled,
      onChanged: available
          ? (value) async {
              final controller =
                  ref.read(settingsControllerProvider.notifier);
              await controller.setCodingPlanEnabled(value);
              if (value) {
                final codingModels = provider!.codingModels!;
                if (codingModels.isNotEmpty) {
                  await controller.setSelectedModel(codingModels.first);
                }
              }
            }
          : null,
    );
  }

  Future<void> _confirmClearMemories(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除所有记忆？'),
        content: const Text('此操作将永久删除全部情绪历史，且不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(settingsControllerProvider.notifier).deleteAllMemories();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('所有记忆已清除')),
    );
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    try {
      final json = await ref.read(memoryRepositoryProvider).exportJson();
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/moodpet_export_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(json);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导出成功'),
          content: SelectableText('文件已保存到：\n${file.path}'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('好的'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _ProviderTile extends ConsumerWidget {
  const _ProviderTile({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(selectedProviderProvider);
    return ListTile(
      leading: const Icon(Icons.memory),
      title: const Text('提供商'),
      subtitle: Text(provider?.name ?? '未配置'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ProviderSwitchPage(),
        ),
      ),
    );
  }
}

class _ApiKeyTile extends ConsumerWidget {
  const _ApiKeyTile({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.key),
      title: const Text('API Key'),
      subtitle: const Text('点击修改（加密存储）'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _editApiKey(context, ref),
    );
  }

  Future<void> _editApiKey(BuildContext context, WidgetRef ref) async {
    final current = await ref.read(apiKeyProvider.future);
    if (!context.mounted) return;
    final controller = TextEditingController(text: current ?? '');
    var obscure = true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('修改 API Key'),
          content: TextField(
            controller: controller,
            obscureText: obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API Key',
              suffixIcon: IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => obscure = !obscure),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await ref
          .read(settingsControllerProvider.notifier)
          .updateApiKey(controller.text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API Key 已更新')),
        );
      }
    }
    controller.dispose();
  }
}

class _ModelTile extends ConsumerWidget {
  const _ModelTile({required this.ref, required this.settings});

  final WidgetRef ref;
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(selectedProviderProvider);
    return ListTile(
      leading: const Icon(Icons.tune),
      title: const Text('模型'),
      subtitle: Text(settings.selectedModel ?? '未配置'),
      trailing: const Icon(Icons.chevron_right),
      onTap: provider == null
          ? null
          : () => _editModel(context, ref, provider),
    );
  }

  Future<void> _editModel(
      BuildContext context, WidgetRef ref, LLMProvider provider) async {
    final models = provider.modelsFor(
      codingPlanEnabled: settings.codingPlanEnabled,
    );
    var selected = models.contains(settings.selectedModel)
        ? settings.selectedModel!
        : (models.isNotEmpty ? models.first : settings.selectedModel ?? '');
    if (provider.requiresCustomModelId) {
      final controller = TextEditingController(text: selected);
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('修改模型'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: '模型 ID',
              hintText: provider.modelHint ?? '填写接入点 ID',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (saved == true && controller.text.trim().isNotEmpty) {
        await ref
            .read(settingsControllerProvider.notifier)
            .setSelectedModel(controller.text.trim());
      }
      controller.dispose();
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改模型'),
        content: DropdownButtonFormField<String>(
          initialValue: selected,
          decoration: const InputDecoration(labelText: '模型'),
          items: [
            for (final model in models)
              DropdownMenuItem(value: model, child: Text(model)),
          ],
          onChanged: (value) {
            if (value != null) selected = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await ref
                  .read(settingsControllerProvider.notifier)
                  .setSelectedModel(selected);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
