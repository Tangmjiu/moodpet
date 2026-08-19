/// Provider detail page — two-tab editor for one LLM provider.
///
/// The 配置 tab holds the connection settings: built-in providers expose only
/// the API key overlay plus an enable switch (their endpoint fields are
/// read-only), while custom providers are fully editable (name, base URL,
/// protocol, models endpoint, default model, chat path). Custom providers can
/// be created ([ProviderDetailPage.isNewCustom]) and deleted here. The 模型
/// tab manages the provider's model list: manual entries, optional online
/// discovery with a multi-select picker, and the active-model override.
///
/// Saving never depends on the advisory connection test. The API key is
/// persisted separately from the provider JSON and is never serialised.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import '../../app.dart'
    show
        ClayContainer,
        kRadiusLg,
        kRadiusMd,
        kSpace4,
        kSpace8,
        kSpace12,
        kSpace16,
        kSpace20,
        kSpace24,
        kSpace32;
import '../../core/agent/connection_tester.dart';
import '../../core/agent/models_client.dart';
import '../../core/models/provider_config.dart';
import '../../core/providers.dart';
import '../../core/storage/settings_store.dart';
import '../../core/utils/color_hex.dart';
import '../../core/utils/provider_share_codec.dart';

/// Injectable seam for [fetchAvailableModels] so widget tests can stub the
/// network call.
typedef ModelFetcher = Future<ModelsResult> Function({
  required ProviderConfig provider,
  http.Client? client,
});

/// Injectable seam for [testProviderConnection] so widget tests can stub the
/// network probe.
typedef ConnectionTester = Future<ConnectionTestResult> Function({
  required ProviderConfig provider,
  http.Client? client,
});

/// Editor for a single provider. In edit modes [provider] is the overlaid
/// config (key/modelOverride/enabled applied); in create mode it is a fresh
/// custom draft whose id was minted by the caller.
class ProviderDetailPage extends ConsumerStatefulWidget {
  final ProviderConfig provider;
  final bool fromOnboarding;

  /// Whether this page is creating a new custom provider. When true,
  /// [provider] is a draft that is only persisted on save, and no delete
  /// affordance is shown.
  final bool isNewCustom;

  final ModelFetcher modelFetcher;
  final ConnectionTester connectionTester;

  const ProviderDetailPage({
    super.key,
    required this.provider,
    this.fromOnboarding = false,
    this.isNewCustom = false,
    this.modelFetcher = fetchAvailableModels,
    this.connectionTester = testProviderConnection,
  });

  @override
  ConsumerState<ProviderDetailPage> createState() =>
      _ProviderDetailPageState();
}

class _ProviderDetailPageState extends ConsumerState<ProviderDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  late final TextEditingController _apiKeyController;
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelsEndpointController;
  late final TextEditingController _defaultModelController;
  late final TextEditingController _chatPathController;
  late final TextEditingController _manualModelController;

  SettingsStore? _settings;
  bool _settingsLoaded = false;

  bool _obscureApiKey = true;
  bool _enabled = true;
  LlmProtocol _protocol = LlmProtocol.openai;
  bool _isSaving = false;

  bool _isTesting = false;
  ConnectionTestResult? _testResult;
  bool _testErrorExpanded = false;

  String? _nameError;
  String? _baseUrlError;
  String? _defaultModelError;

  List<String> _models = <String>[];
  String? _modelOverride;
  bool _isFetchingModels = false;
  String? _fetchError;
  bool _autoFetchAttempted = false;

  bool get _isCustom => widget.provider.isCustom;

  @override
  void initState() {
    super.initState();
    final provider = widget.provider;
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _apiKeyController = TextEditingController(text: provider.apiKey);
    _nameController = TextEditingController(text: provider.name);
    _baseUrlController = TextEditingController(text: provider.baseUrl);
    _modelsEndpointController =
        TextEditingController(text: provider.modelsEndpoint ?? '');
    _defaultModelController = TextEditingController(text: provider.defaultModel);
    _chatPathController =
        TextEditingController(text: provider.chatCompletionsPath);
    _manualModelController = TextEditingController();
    _protocol = provider.protocol;
    _enabled = provider.enabled;
    _loadPersistedState();
  }

  /// Read the persisted overlay state (key, enabled flag, model list, model
  /// override) from storage — the source of truth even when the caller passed
  /// a non-overlaid catalog entry.
  void _loadPersistedState() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final settings = await ref.read(settingsStoreProvider.future);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _settingsLoaded = true;
        _apiKeyController.text = settings.apiKeyFor(widget.provider.id);
        _enabled = settings.isProviderEnabled(widget.provider.id);
        _models = settings.modelsFor(widget.provider.id);
        _modelOverride = settings.modelOverrideFor(widget.provider.id);
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _apiKeyController.dispose();
    _nameController.dispose();
    _baseUrlController.dispose();
    _modelsEndpointController.dispose();
    _defaultModelController.dispose();
    _chatPathController.dispose();
    _manualModelController.dispose();
    super.dispose();
  }

  // ---- helpers -------------------------------------------------------------

  /// The default model the models tab keys off: the (possibly edited) field
  /// value for customs, the catalog value for builtins.
  String get _currentDefaultModel => _isCustom
      ? _defaultModelController.text.trim()
      : widget.provider.defaultModel;

  /// Strip all trailing slashes so a user-entered URL never doubles path
  /// segments when the agent appends the chat path.
  static String _normalizeBaseUrl(String raw) {
    var url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static bool _isValidHttpUrl(String url) {
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// The loaded settings store, reading it from the provider when the
  /// post-frame load has not completed yet.
  Future<SettingsStore> _requireSettings() async {
    final cached = _settings;
    if (cached != null) return cached;
    return ref.read(settingsStoreProvider.future);
  }

  /// Snapshot of the provider as currently described by the form fields.
  ProviderConfig _draftConfig() {
    final provider = widget.provider;
    if (!_isCustom) {
      return provider.copyWith(
        apiKey: _apiKeyController.text.trim(),
        enabled: _enabled,
      );
    }
    final endpoint = _modelsEndpointController.text.trim();
    final chatPath = _chatPathController.text.trim();
    return ProviderConfig(
      id: provider.id,
      name: _nameController.text.trim(),
      baseUrl: _normalizeBaseUrl(_baseUrlController.text),
      defaultModel: _defaultModelController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      iconAsset: '',
      brandColor: '',
      modelsEndpoint: endpoint.isEmpty ? null : endpoint,
      protocol: _protocol,
      isCustom: true,
      chatCompletionsPath:
          chatPath.isEmpty ? '/chat/completions' : chatPath,
      enabled: _enabled,
    );
  }

  /// Validate the custom form and surface inline errors. Returns whether the
  /// form is saveable.
  bool _validateCustomForm() {
    final nameOk = _nameController.text.trim().isNotEmpty;
    final urlOk = _isValidHttpUrl(_normalizeBaseUrl(_baseUrlController.text));
    final modelOk = _defaultModelController.text.trim().isNotEmpty;
    setState(() {
      _nameError = nameOk ? null : '请输入名称';
      _baseUrlError = urlOk ? null : '请输入合法的 http(s) 地址';
      _defaultModelError = modelOk ? null : '请输入默认模型';
    });
    return nameOk && urlOk && modelOk;
  }

  // ---- save / delete -------------------------------------------------------

  bool get _saveEnabled {
    if (_isSaving) return false;
    // Builtins require a key to enable, but saving must stay possible when
    // the intent is to disable: a keyless builtin can be saved once the
    // switch is toggled off. Customs validate on press so the inline errors
    // can surface (the save button stays tappable).
    if (!_isCustom) {
      return _apiKeyController.text.trim().isNotEmpty || !_enabled;
    }
    return true;
  }

  Future<void> _save() async {
    if (_isCustom && !_validateCustomForm()) return;
    setState(() => _isSaving = true);
    try {
      final settings = await _requireSettings();
      final id = widget.provider.id;
      if (_isCustom) {
        await _saveCustom(settings, id);
      } else {
        // Built-in overlay save: key + enabled + active. The model override
        // is managed on the models tab and is intentionally untouched here.
        await settings.setApiKey(id, _apiKeyController.text.trim());
        await settings.setProviderEnabled(id, _enabled);
        await settings.setActiveProviderId(id);
      }
      // WidgetRef.invalidate throws after dispose, so it must be guarded.
      if (!mounted) return;
      ref.invalidate(providerListProvider);
      ref.invalidate(activeProviderConfigProvider);
      // The settings page row watches the registry directly.
      ref.invalidate(providerRegistryProvider);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveCustom(SettingsStore settings, String id) async {
    // The API key is persisted separately; it never enters the provider JSON.
    final config = _draftConfig().copyWith(apiKey: '');
    final customs = settings.loadCustomProviders();
    final index = customs.indexWhere((p) => p.id == id);
    if (index >= 0) {
      customs[index] = config;
    } else {
      customs.add(config);
    }
    await settings.saveCustomProviders(customs);
    if (widget.isNewCustom) {
      final order = settings.loadProviderOrder();
      if (!order.contains(id)) {
        await settings.saveProviderOrder(<String>[...order, id]);
      }
    }
    await settings.setApiKey(id, _apiKeyController.text.trim());
    await settings.setProviderEnabled(id, _enabled);
    await settings.setActiveProviderId(id);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除此提供商'),
        content: const Text('删除后其 Key 与模型配置将一并清除'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final settings = await _requireSettings();
    final id = widget.provider.id;
    // removeProviderState is guarded on the id still being in the custom
    // list, so it must run before the entry is removed below.
    await settings.removeProviderState(id);
    final customs = settings.loadCustomProviders()
      ..removeWhere((p) => p.id == id);
    await settings.saveCustomProviders(customs);
    final order = settings.loadProviderOrder()..remove(id);
    await settings.saveProviderOrder(order);
    if (settings.activeProviderId == id) {
      await settings.clearActiveProviderId();
    }
    // WidgetRef.invalidate throws after dispose, so it must be guarded.
    if (!mounted) return;
    ref.invalidate(providerListProvider);
    ref.invalidate(activeProviderConfigProvider);
    // The settings page row watches the registry directly.
    ref.invalidate(providerRegistryProvider);
    if (mounted) Navigator.of(context).pop(true);
  }

  // ---- share ---------------------------------------------------------------

  /// Open the QR share sheet. The payload is encoded from [provider] as
  /// passed to this page, at tap time; the codec never writes the API key or
  /// the model list into it. The action is hidden in create mode because a
  /// draft has nothing saved to share yet.
  Future<void> _showShareSheet() async {
    final provider = widget.provider;
    final payload = encodeProviderShare(provider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) =>
          _ShareSheet(provider: provider, payload: payload),
    );
  }

  // ---- connection test -----------------------------------------------------

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
      _testErrorExpanded = false;
    });
    final result = await widget.connectionTester(provider: _draftConfig());
    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testResult = result;
    });
  }

  // ---- models tab ----------------------------------------------------------

  void _onTabChanged() {
    if (_tabController.index == 1) _maybeAutoFetchModels();
  }

  /// Auto-fetch once when the models tab is first viewed with a key present
  /// and no models cached yet. Best-effort: any failure leaves manual add
  /// usable.
  Future<void> _maybeAutoFetchModels() async {
    if (_autoFetchAttempted || !_settingsLoaded) return;
    final draft = _draftConfig();
    if (!draft.supportsModelDiscovery) return;
    if (_apiKeyController.text.trim().isEmpty) return;
    if (_models.isNotEmpty) return;
    _autoFetchAttempted = true;
    await _fetchModels();
  }

  Future<void> _selectModel(String? model) async {
    final settings = _settings;
    if (settings == null) return;
    await settings.setModelOverride(widget.provider.id, model);
    if (!mounted) return;
    setState(() => _modelOverride = model);
  }

  Future<void> _removeModel(String model) async {
    final settings = _settings;
    if (settings == null) return;
    final previousModels = _models;
    final previousOverride = _modelOverride;
    final updated = previousModels.where((m) => m != model).toList();
    // Optimistic update: remove from the UI first. Persisting before the
    // setState lets two rapid dismissals each compute from a stale list and
    // clobber one another; the dismissed override is cleared in the same
    // setState so the active model never dangles.
    setState(() {
      _models = updated;
      if (_modelOverride == model) _modelOverride = null;
    });
    try {
      await settings.setModels(widget.provider.id, updated);
      if (previousOverride == model) {
        await settings.setModelOverride(widget.provider.id, null);
      }
    } on Object {
      // Revert the optimistic removal when persistence fails.
      if (!mounted) return;
      setState(() {
        _models = previousModels;
        _modelOverride = previousOverride;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败')),
      );
    }
  }

  Future<void> _addManualModel() async {
    final model = _manualModelController.text.trim();
    if (model.isEmpty) return;
    if (model == _currentDefaultModel || _models.contains(model)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已存在')),
      );
      return;
    }
    final settings = _settings;
    if (settings == null) return;
    final previousModels = _models;
    // Optimistic update: show the new model first, then persist.
    setState(() {
      _models = <String>[...previousModels, model];
      _manualModelController.clear();
    });
    try {
      await settings.setModels(widget.provider.id, _models);
    } on Object {
      // Revert the optimistic addition when persistence fails.
      if (!mounted) return;
      setState(() => _models = previousModels);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('添加失败')),
      );
    }
  }

  Future<void> _fetchModels() async {
    setState(() {
      _isFetchingModels = true;
      _fetchError = null;
    });
    final result = await widget.modelFetcher(provider: _draftConfig());
    if (!mounted) return;
    setState(() => _isFetchingModels = false);
    if (!result.isOk) {
      setState(() => _fetchError = result.error ?? '拉取失败');
      return;
    }
    final defaultModel = _currentDefaultModel;
    final candidates = result.models
        .where((m) => m != defaultModel && !_models.contains(m))
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可添加的新模型')),
      );
      return;
    }
    await _showModelPicker(candidates);
  }

  Future<void> _showModelPicker(List<String> candidates) async {
    final selected = <String>{};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final allSelected =
                candidates.isNotEmpty && selected.length == candidates.length;
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: kSpace8),
                  Text(
                    '选择要添加的模型',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  CheckboxListTile(
                    value: allSelected,
                    onChanged: (v) => setSheetState(() {
                      if (v ?? false) {
                        selected.addAll(candidates);
                      } else {
                        selected.clear();
                      }
                    }),
                    title: const Text('全选'),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final m in candidates)
                          CheckboxListTile(
                            value: selected.contains(m),
                            onChanged: (v) => setSheetState(() {
                              if (v ?? false) {
                                selected.add(m);
                              } else {
                                selected.remove(m);
                              }
                            }),
                            title: Text(m),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(kSpace16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.of(sheetContext).pop(),
                        child: Text('添加所选 (${selected.length})'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (!mounted || selected.isEmpty) return;
    final settings = _settings;
    if (settings == null) return;
    // Merge: existing entries first, then the new selection sorted.
    final newOnes = selected.where((m) => !_models.contains(m)).toList()
      ..sort();
    final merged = <String>[..._models];
    for (final m in newOnes) {
      if (!merged.contains(m)) merged.add(m);
    }
    await settings.setModels(widget.provider.id, merged);
    if (!mounted) return;
    setState(() => _models = merged);
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    return Scaffold(
      appBar: AppBar(
        title: Text(provider.name.isEmpty ? '新建提供商' : provider.name),
        actions: [
          if (!widget.isNewCustom)
            IconButton(
              key: const ValueKey('shareProviderButton'),
              icon: const Icon(Icons.ios_share_rounded),
              tooltip: '分享提供商',
              onPressed: _showShareSheet,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '配置'),
            Tab(text: '模型'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildConfigTab(),
          _buildModelsTab(),
        ],
      ),
    );
  }

  Widget _buildConfigTab() {
    final theme = Theme.of(context);
    final provider = widget.provider;
    return SingleChildScrollView(
      padding:
          const EdgeInsets.symmetric(horizontal: kSpace20, vertical: kSpace16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProviderHeader(provider: provider),
          const SizedBox(height: kSpace24),
          if (_isCustom)
            ..._buildCustomFields(theme)
          else
            _buildBuiltinInfo(theme),
          const SizedBox(height: kSpace24),
          const _SectionLabel(text: 'API Key'),
          const SizedBox(height: kSpace8),
          TextField(
            key: const ValueKey('apiKeyField'),
            controller: _apiKeyController,
            // The framework asserts obscured fields are single-line, so the
            // multiline paste area only exists while the key is visible.
            obscureText: _obscureApiKey,
            maxLines: _obscureApiKey ? 1 : 3,
            minLines: 1,
            decoration: InputDecoration(
              hintText: _isCustom
                  ? '粘贴 API Key；可粘贴多个，逗号或空格分隔；本地服务可留空'
                  : '粘贴 API Key；可粘贴多个，逗号或空格分隔',
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscureApiKey
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _obscureApiKey = !_obscureApiKey),
              ),
            ),
            onChanged: (_) => setState(() => _testResult = null),
          ),
          const SizedBox(height: kSpace16),
          _buildTestConnectionSection(theme),
          const SizedBox(height: kSpace8),
          SwitchListTile(
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
            title: const Text('启用此提供商'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: kSpace16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('saveButton'),
              onPressed: _saveEnabled ? _save : null,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: const Text('保存并使用'),
            ),
          ),
          if (_isCustom && !widget.isNewCustom) ...[
            const SizedBox(height: kSpace8),
            Center(
              child: TextButton.icon(
                key: const ValueKey('deleteProviderButton'),
                onPressed: _confirmDelete,
                icon: Icon(Icons.delete_outline_rounded,
                    color: theme.colorScheme.error),
                label: Text(
                  '删除此提供商',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ),
          ],
          const SizedBox(height: kSpace32),
        ],
      ),
    );
  }

  List<Widget> _buildCustomFields(ThemeData theme) {
    return [
      const _SectionLabel(text: '基本信息'),
      const SizedBox(height: kSpace8),
      TextField(
        key: const ValueKey('customNameField'),
        controller: _nameController,
        decoration: InputDecoration(
          labelText: '名称',
          hintText: '例如：本地 Ollama',
          errorText: _nameError,
        ),
        onChanged: (_) => setState(() => _nameError = null),
      ),
      const SizedBox(height: kSpace12),
      TextField(
        key: const ValueKey('customBaseUrlField'),
        controller: _baseUrlController,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: '接口地址',
          hintText: 'https://api.example.com/v1',
          errorText: _baseUrlError,
        ),
        onChanged: (_) => setState(() => _baseUrlError = null),
      ),
      const SizedBox(height: kSpace16),
      const _SectionLabel(text: '协议'),
      const SizedBox(height: kSpace8),
      SegmentedButton<LlmProtocol>(
        segments: const [
          ButtonSegment(value: LlmProtocol.openai, label: Text('OpenAI 兼容')),
          ButtonSegment(value: LlmProtocol.claude, label: Text('Claude')),
          ButtonSegment(value: LlmProtocol.gemini, label: Text('Gemini')),
        ],
        selected: {_protocol},
        onSelectionChanged: (selection) =>
            setState(() => _protocol = selection.first),
      ),
      const SizedBox(height: kSpace8),
      Text(
        '自定义 Claude/Gemini 提供商需使用标准接口路径（/v1/messages、/v1beta/models/…:generateContent）',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
      const SizedBox(height: kSpace16),
      TextField(
        key: const ValueKey('customModelsEndpointField'),
        controller: _modelsEndpointController,
        decoration: const InputDecoration(
          labelText: '模型列表端点',
          hintText: '留空表示不支持在线拉取模型列表',
        ),
      ),
      const SizedBox(height: kSpace12),
      TextField(
        key: const ValueKey('customDefaultModelField'),
        controller: _defaultModelController,
        decoration: InputDecoration(
          labelText: '默认模型',
          hintText: '例如：llama3',
          errorText: _defaultModelError,
        ),
        onChanged: (_) => setState(() => _defaultModelError = null),
      ),
      if (_protocol == LlmProtocol.openai) ...[
        const SizedBox(height: kSpace12),
        TextField(
          key: const ValueKey('customChatPathField'),
          controller: _chatPathController,
          decoration: const InputDecoration(
            labelText: '聊天路径',
            hintText: '/chat/completions',
          ),
        ),
      ],
    ];
  }

  Widget _buildBuiltinInfo(ThemeData theme) {
    final provider = widget.provider;
    return ClayContainer(
      padding: const EdgeInsets.symmetric(
          horizontal: kSpace16, vertical: kSpace12),
      radius: kRadiusLg,
      shadowIntensity: 0.4,
      child: Column(
        children: [
          _InfoRow(label: '名称', value: provider.name),
          _InfoRow(label: '接口地址', value: provider.baseUrl),
          _InfoRow(label: '协议', value: _protocolLabel(provider.protocol)),
          _InfoRow(
              label: '模型列表端点', value: provider.modelsEndpoint ?? '不支持'),
          _InfoRow(label: '默认模型', value: provider.defaultModel),
          _InfoRow(label: '聊天路径', value: provider.chatCompletionsPath),
        ],
      ),
    );
  }

  static String _protocolLabel(LlmProtocol protocol) => switch (protocol) {
        LlmProtocol.openai => 'OpenAI 兼容',
        LlmProtocol.claude => 'Claude',
        LlmProtocol.gemini => 'Gemini',
      };

  Widget _buildTestConnectionSection(ThemeData theme) {
    final result = _testResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('testConnectionButton'),
          onPressed: _isTesting ? null : _testConnection,
          icon: _isTesting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_tethering_rounded),
          label: const Text('测试连接'),
        ),
        if (result != null) ...[
          const SizedBox(height: kSpace8),
          if (result.ok)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 18, color: Color(0xFF4CAF50)),
                const SizedBox(width: kSpace4),
                Text(
                  '连接成功 · ${result.latencyMs}ms',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF2E7D32),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            )
          else
            Material(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(kRadiusMd),
              child: InkWell(
                onTap: () =>
                    setState(() => _testErrorExpanded = !_testErrorExpanded),
                borderRadius: BorderRadius.circular(kRadiusMd),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: kSpace12, vertical: kSpace8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error_outline_rounded,
                              size: 18, color: theme.colorScheme.error),
                          const SizedBox(width: kSpace8),
                          Expanded(
                            child: Text(
                              result.statusCode > 0
                                  ? '连接失败 · HTTP ${result.statusCode}，点击查看详情'
                                  : '连接失败，点击查看详情',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            _testErrorExpanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18,
                            color: theme.colorScheme.error,
                          ),
                        ],
                      ),
                      if (_testErrorExpanded) ...[
                        const SizedBox(height: kSpace8),
                        Text(
                          result.error ?? '未知错误',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildModelsTab() {
    final theme = Theme.of(context);
    if (!_settingsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final defaultModel = _currentDefaultModel;
    final extraModels = _models.where((m) => m != defaultModel).toList();
    final draft = _draftConfig();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(
                horizontal: kSpace20, vertical: kSpace16),
            children: [
              _buildModelRow(theme, defaultModel, isDefault: true),
              for (final m in extraModels)
                Padding(
                  key: ValueKey('model-row-wrap-$m'),
                  padding: const EdgeInsets.only(bottom: kSpace8),
                  child: Dismissible(
                    key: ValueKey('model-row-$m'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: kSpace20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        borderRadius: BorderRadius.circular(kRadiusMd),
                      ),
                      child: Icon(Icons.delete_outline_rounded,
                          color: theme.colorScheme.onError),
                    ),
                    onDismissed: (_) => _removeModel(m),
                    child: _buildModelRow(theme, m, isDefault: false),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              kSpace20, kSpace8, kSpace20, kSpace24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_fetchError != null) ...[
                Text(
                  _fetchError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: kSpace8),
              ],
              if (draft.supportsModelDiscovery)
                FilledButton.tonalIcon(
                  key: const ValueKey('fetchModelsButton'),
                  onPressed: _isFetchingModels ? null : _fetchModels,
                  icon: _isFetchingModels
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined),
                  label: const Text('拉取模型列表'),
                )
              else
                Text(
                  '此提供商不支持在线拉取，请手动添加模型',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: kSpace8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('manualModelField'),
                      controller: _manualModelController,
                      decoration: const InputDecoration(
                        hintText: '模型 ID，例如 gpt-4o-mini',
                        prefixIcon: Icon(Icons.memory_rounded),
                      ),
                      onSubmitted: (_) => _addManualModel(),
                    ),
                  ),
                  const SizedBox(width: kSpace8),
                  IconButton(
                    key: const ValueKey('manualModelAddButton'),
                    onPressed: _addManualModel,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    tooltip: '添加模型',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModelRow(ThemeData theme, String model,
      {required bool isDefault}) {
    final isActive =
        isDefault ? _modelOverride == null : _modelOverride == model;
    return ClayContainer(
      padding: const EdgeInsets.symmetric(
          horizontal: kSpace16, vertical: kSpace12),
      radius: kRadiusMd,
      shadowIntensity: 0.4,
      onTap: () => _selectModel(isDefault ? null : model),
      child: Row(
        children: [
          Expanded(
            child: Text(
              model.isEmpty ? '（未设置默认模型）' : model,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (isDefault) ...[
            _MiniChip(
              label: '默认',
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              foregroundColor: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: kSpace8),
          ],
          if (isActive)
            _MiniChip(
              label: '当前',
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
            ),
        ],
      ),
    );
  }
}

/// A small section label.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// A read-only label/value row used for built-in provider details.
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kSpace4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small status chip with a coloured background (默认 / 当前).
class _MiniChip extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const _MiniChip({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: kSpace8, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: foregroundColor,
        ),
      ),
    );
  }
}

/// Provider header — logo in a brand-tinted claymorphism card. Custom
/// providers (no bundled icon) render a letter avatar instead of an SVG.
class _ProviderHeader extends StatelessWidget {
  final ProviderConfig provider;

  const _ProviderHeader({required this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCustom = provider.isCustom;
    final brandColor = provider.brandColor.isEmpty
        ? theme.colorScheme.primary
        : parseHexColor(provider.brandColor);
    final isChinaFriendly =
        kChinaRecommendedProviderIds.contains(provider.id);

    return ClayContainer(
      padding: const EdgeInsets.all(kSpace20),
      radius: kRadiusLg,
      color: brandColor.withValues(alpha: 0.08),
      shadowIntensity: 0.5,
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: brandColor.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: provider.iconAsset.isEmpty
                  ? _LetterAvatar(
                      name: provider.name, brandColor: brandColor)
                  : SvgPicture.asset(
                      provider.iconAsset,
                      width: 64,
                      height: 64,
                      placeholderBuilder: (_) => _LetterAvatar(
                          name: provider.name, brandColor: brandColor),
                    ),
            ),
          ),
          const SizedBox(width: kSpace16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.name.isEmpty ? '自定义提供商' : provider.name,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: kSpace4),
                Row(
                  children: [
                    Icon(
                      isCustom
                          ? Icons.tune_rounded
                          : isChinaFriendly
                              ? Icons.signal_cellular_alt_rounded
                              : Icons.vpn_lock_rounded,
                      size: 14,
                      color: !isCustom && isChinaFriendly
                          ? const Color(0xFF4CAF50)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: kSpace4),
                    Text(
                      isCustom
                          ? '自定义提供商'
                          : isChinaFriendly
                              ? '国内可直连'
                              : '需网络代理',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: !isCustom && isChinaFriendly
                            ? const Color(0xFF4CAF50)
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Brand-coloured square with the provider's first letter — the fallback for
/// custom providers, which have no bundled SVG icon.
class _LetterAvatar extends StatelessWidget {
  final String name;
  final Color brandColor;

  const _LetterAvatar({required this.name, required this.brandColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      color: brandColor,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.characters.first,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// QR share sheet — renders the share payload as a scannable QR code with a
/// copyable text fallback. The QR always sits on a white surface regardless
/// of theme so scanners see a light background. [payload] is encoded by the
/// caller at tap time from the page's provider.
class _ShareSheet extends StatelessWidget {
  final ProviderConfig provider;
  final String payload;

  const _ShareSheet({required this.provider, required this.payload});

  Future<void> _copyPayload(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: payload));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制，发送给对方粘贴导入')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          kSpace24,
          kSpace8,
          kSpace24,
          MediaQuery.viewInsetsOf(context).bottom + kSpace24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle.
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: kSpace16),
            Text('分享提供商', style: theme.textTheme.titleLarge),
            const SizedBox(height: kSpace16),
            ClayContainer(
              padding: const EdgeInsets.all(kSpace16),
              radius: kRadiusLg,
              color: Colors.white,
              shadowIntensity: 0.4,
              child: QrImageView(
                data: payload,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: kSpace16),
            Text(provider.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: kSpace4),
            Text(provider.baseUrl, style: theme.textTheme.bodySmall),
            if (!provider.isCustom) ...[
              const SizedBox(height: kSpace8),
              Text(
                '将以自定义提供商形式分享',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
            const SizedBox(height: kSpace16),
            // Caption-high window (~3 lines) onto the full payload string;
            // the inner scroll keeps long payloads readable and selectable.
            Container(
              height: 72,
              width: double.infinity,
              padding: const EdgeInsets.all(kSpace12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(kRadiusMd),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  payload,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ),
            const SizedBox(height: kSpace16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                key: const ValueKey('copySharePayloadButton'),
                onPressed: () => _copyPayload(context),
                icon: const Icon(Icons.copy_rounded),
                label: const Text('复制口令'),
              ),
            ),
            const SizedBox(height: kSpace12),
            Text(
              '口令不包含 API Key 和模型列表，接收方导入后需自行填写 Key',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
