import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/agent/agent_service.dart';
import '../../core/llm/llm_provider.dart';
import '../../core/models/region_info.dart';
import '../../core/providers/settings_providers.dart';
import '../../core/utils/region_detector.dart';
import '../widgets/provider_logo.dart';
import 'onboarding_page.dart';

/// Step 3 LLM 提供商配置页。
class Step3ProviderPage extends ConsumerStatefulWidget {
  const Step3ProviderPage({required this.onFinish, super.key});

  final VoidCallback onFinish;

  @override
  ConsumerState<Step3ProviderPage> createState() => _Step3ProviderPageState();
}

class _Step3ProviderPageState extends ConsumerState<Step3ProviderPage> {
  final RegionDetector _regionDetector = RegionDetector();
  final AgentConnectionTester _tester = AgentConnectionTester();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _customModelController = TextEditingController();

  RegionInfo? _regionInfo;
  AppRegion _region = AppRegion.other;
  bool _detectingRegion = true;

  String? _selectedProviderId;
  String _selectedModel = '';
  bool _codingPlanEnabled = false;
  bool _obscureKey = true;
  bool _testing = false;
  ConnectionTestResult? _testResult;

  LLMProvider? get _selectedProvider =>
      llmProviderById(_selectedProviderId);

  bool get _testPassed => _testResult?.ok == true;

  @override
  void initState() {
    super.initState();
    _detectRegion();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  Future<void> _detectRegion() async {
    try {
      final info = await _regionDetector.detect();
      if (!mounted) return;
      setState(() {
        _regionInfo = info;
        _region = info.regionClass;
        _detectingRegion = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _regionInfo = null;
        _region = AppRegion.other;
        _detectingRegion = false;
      });
    }
  }

  Future<void> _switchRegion() async {
    final selected = await showModalBottomSheet<AppRegion>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('切换地区',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                _region == AppRegion.prc
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              onTap: () => Navigator.of(context).pop(AppRegion.prc),
              title: const Text('PRC（中国大陆 / 香港 / 澳门）'),
              subtitle: const Text('推荐 DeepSeek、Kimi、GLM、MiniMax'),
            ),
            ListTile(
              leading: Icon(
                _region == AppRegion.other
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              onTap: () => Navigator.of(context).pop(AppRegion.other),
              title: const Text('OTHER（台湾及其他所有地区）'),
              subtitle: const Text('推荐 OpenAI、Claude、DeepSeek'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final available =
        llmProvidersForRegion(selected).map((p) => p.id).toSet();
    final resetSelection = _selectedProviderId != null &&
        !available.contains(_selectedProviderId);
    setState(() {
      _region = selected;
      if (resetSelection) {
        _selectedProviderId = null;
        _codingPlanEnabled = false;
        _selectedModel = '';
        _customModelController.text = '';
        _testResult = null;
      }
    });
  }

  void _selectProvider(String? id) {
    final provider = llmProviderById(id);
    setState(() {
      _selectedProviderId = id;
      _codingPlanEnabled = false;
      _selectedModel = provider?.defaultModel ?? '';
      _customModelController.text = _selectedModel;
      _testResult = null;
    });
  }

  void _onCodingChanged(bool value) {
    final provider = _selectedProvider;
    if (provider == null) return;
    setState(() {
      _codingPlanEnabled = value;
      final models = provider.modelsFor(codingPlanEnabled: value);
      _selectedModel = models.isNotEmpty ? models.first : '';
      _customModelController.text = _selectedModel;
      _testResult = null;
    });
  }

  Future<void> _testConnection() async {
    final provider = _selectedProvider;
    if (provider == null) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final result = await _tester.test(
      provider: provider,
      apiKey: _apiKeyController.text,
      model: _selectedModel,
      codingPlanEnabled: _codingPlanEnabled,
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  Future<void> _launch() async {
    final provider = _selectedProvider;
    if (provider == null || !_testPassed) return;
    try {
      await ref.read(settingsControllerProvider.notifier).completeOnboarding(
            providerId: provider.id,
            apiKey: _apiKeyController.text.trim(),
            model: _selectedModel,
            codingPlanEnabled: _codingPlanEnabled,
          );
      if (!mounted) return;
      widget.onFinish();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存配置失败，请重试')),
      );
    }
  }

  Future<void> _openDocs() async {
    final docsUrl = _selectedProvider?.docsUrl;
    if (docsUrl == null) return;
    final uri = Uri.tryParse(docsUrl);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开浏览器')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              children: [
                _buildHeader(context),
                const SizedBox(height: 16),
                _RegionBar(
                  info: _regionInfo,
                  region: _region,
                  detecting: _detectingRegion,
                  onSwitch: _switchRegion,
                ),
                const SizedBox(height: 16),
                _buildProviderList(context),
                if (_selectedProvider != null) ...[
                  const SizedBox(height: 16),
                  _buildConfigSection(context),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _selectedProvider != null && _testPassed
                        ? _launch
                        : null,
                    child: const Text('启动 MoodPet'),
                  ),
                ),
                const SizedBox(height: 14),
                const OnboardingDots(total: 3, current: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '连接大脑',
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '选择一个 LLM 提供商，MoodPet 将通过 PocketClaw 调用它',
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildProviderList(BuildContext context) {
    final recommended = recommendedProvidersForRegion(_region);
    final backup = backupProvidersForRegion(_region);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final provider in recommended) ...[
          _ProviderTile(
            provider: provider,
            selected: provider.id == _selectedProviderId,
            onTap: () => _selectProvider(provider.id),
          ),
          const SizedBox(height: 8),
        ],
        if (backup.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              '更多提供商（${backup.length}）',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            children: [
              for (final provider in backup)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ProviderTile(
                    provider: provider,
                    selected: provider.id == _selectedProviderId,
                    onTap: () => _selectProvider(provider.id),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildConfigSection(BuildContext context) {
    final provider = _selectedProvider!;
    final models = provider.modelsFor(codingPlanEnabled: _codingPlanEnabled);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('已选: ${provider.name}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (provider.hasCodingPlan)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用 Coding Plan'),
                subtitle: Text('使用 ${provider.codingModels!.join(' / ')}'),
                value: _codingPlanEnabled,
                onChanged: _onCodingChanged,
              ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _apiKeyController,
              obscureText: _obscureKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: _apiKeyHint(provider),
                helperText: provider.requiresSecretKey
                    ? '特殊鉴权：APIKey:APISecret'
                    : null,
                suffixIcon: IconButton(
                  tooltip: _obscureKey ? '显示' : '隐藏',
                  icon: Icon(
                    _obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
              onChanged: (_) => setState(() => _testResult = null),
            ),
            const SizedBox(height: 16),
            if (provider.requiresCustomModelId)
              TextFormField(
                controller: _customModelController,
                decoration: InputDecoration(
                  labelText: '模型 ID',
                  hintText: provider.modelHint ?? '填写推理接入点 ID',
                ),
                onChanged: (value) => setState(() {
                  _selectedModel = value.trim();
                  _testResult = null;
                }),
              )
            else if (models.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey(
                    '${provider.id}-$_codingPlanEnabled-$_selectedModel'),
                initialValue: models.contains(_selectedModel)
                    ? _selectedModel
                    : models.first,
                decoration: const InputDecoration(labelText: '模型'),
                items: [
                  for (final model in models)
                    DropdownMenuItem(value: model, child: Text(model)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedModel = value;
                    _testResult = null;
                  });
                },
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _testing ? null : _testConnection,
              icon: _testing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: Text(_testing ? '测试中…' : '测试连接'),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 10),
              _TestResultIndicator(result: _testResult!),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _openDocs,
                icon: const Icon(Icons.open_in_new),
                label: const Text('如何获取 Key？'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _apiKeyHint(LLMProvider provider) {
    if (provider.authType == AuthType.apiKeyHeader) return 'x-api-key';
    if (provider.authType == AuthType.queryParam) return '?key=...';
    return '粘贴你的 API Key';
  }
}

class _RegionBar extends StatelessWidget {
  const _RegionBar({
    required this.info,
    required this.region,
    required this.detecting,
    required this.onSwitch,
  });

  final RegionInfo? info;
  final AppRegion region;
  final bool detecting;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.public, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: detecting
                  ? const Text('正在检测地区…')
                  : Text(
                      info?.displayText ?? '未检测到地区，使用 OTHER 分组',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
            ),
            TextButton(onPressed: onSwitch, child: const Text('切换地区')),
          ],
        ),
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    required this.selected,
    required this.onTap,
  });

  final LLMProvider provider;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: selected ? 2 : 1,
      color: selected ? scheme.secondaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: selected
            ? BorderSide(color: scheme.primary, width: 1.4)
            : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (provider.isRecommended) ...[
              const SizedBox(width: 8),
              Chip(
                label: const Text('推荐'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                labelStyle: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        ),
        subtitle: Text(
          provider.description ?? provider.officialEndpoint,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          selected
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked,
          color: selected ? scheme.primary : scheme.outline,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _TestResultIndicator extends StatelessWidget {
  const _TestResultIndicator({required this.result});

  final ConnectionTestResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.ok ? Colors.green : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            result.ok ? Icons.check_circle : Icons.cancel_outlined,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              result.message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
