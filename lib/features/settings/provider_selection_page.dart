/// Provider selection page — merged provider-management list.
///
/// Shows the built-in catalog plus the user's custom providers as one
/// reorderable card list; the order is persisted via
/// `SettingsStore.saveProviderOrder`. Each card carries an icon (SVG for
/// built-ins, a letter avatar for customs), name, status badges
/// (推荐 / 自定义 / 已停用), the effective model and the cached model count.
/// Tapping a card navigates to [ProviderDetailPage]; the trailing dashed card
/// starts the custom-provider creation flow. The page also shows the detected
/// region with its emoji in a claymorphism banner.
library;

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uuid/uuid.dart';

import '../../app.dart' show kSpace4, kSpace8, kSpace12, kSpace16, kSpace24, kRadiusLg, ClayContainer;
import '../../core/models/provider_config.dart';
import '../../core/models/region_info.dart';
import '../../core/providers.dart';
import '../../core/region/region_detector.dart';
import '../../core/utils/provider_share_codec.dart';
import 'provider_detail_page.dart';
import 'provider_scan_page.dart';

/// Full-page provider selection — launched from onboarding Step 3 or settings.
class ProviderSelectionPage extends ConsumerStatefulWidget {
  final bool fromOnboarding;

  const ProviderSelectionPage({super.key, this.fromOnboarding = false});

  @override
  ConsumerState<ProviderSelectionPage> createState() =>
      _ProviderSelectionPageState();
}

class _ProviderSelectionPageState
    extends ConsumerState<ProviderSelectionPage> {
  RegionInfo? _region;
  String? _selectedProviderId;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _region = detectRegion();
  }

  List<ProviderConfig> _filterProviders(List<ProviderConfig> providers) {
    if (_searchQuery.isEmpty) return providers;
    final q = _searchQuery.toLowerCase();
    return providers
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.id.toLowerCase().contains(q))
        .toList();
  }

  bool _isRecommendedForRegion(ProviderConfig provider) {
    final code = _region?.countryCode?.toUpperCase();
    if (code == 'CN' || code == 'HK' || code == 'MO' || code == 'TW') {
      return kChinaRecommendedProviderIds.contains(provider.id);
    }
    return kGlobalRecommendedProviderIds.contains(provider.id);
  }

  Future<void> _onProviderTap(ProviderConfig provider) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProviderDetailPage(
          provider: provider,
          fromOnboarding: widget.fromOnboarding,
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      setState(() => _selectedProviderId = provider.id);
      if (widget.fromOnboarding) {
        Navigator.of(context).pop(true);
      }
    }
  }

  /// Start the custom-provider creation flow with a fresh blank draft.
  void _onAddCustomProvider() {
    final draft = ProviderConfig(
      id: const Uuid().v4(),
      name: '',
      baseUrl: '',
      defaultModel: '',
      apiKey: '',
      iconAsset: '',
      brandColor: '',
      isCustom: true,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProviderDetailPage(
          provider: draft,
          fromOnboarding: widget.fromOnboarding,
          isNewCustom: true,
        ),
      ),
    );
  }

  /// Import chooser: scan a QR code (Android only) or paste a share payload.
  void _showImportChooser() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入提供商'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Camera scanning only exists on Android; the desktop build
            // (Linux) has no camera path, so the entry is hidden there.
            if (!kIsWeb && Platform.isAndroid)
              ListTile(
                leading: const Icon(Icons.qr_code_scanner_rounded),
                title: const Text('扫码导入'),
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _onScanImport();
                },
              ),
            ListTile(
              leading: const Icon(Icons.content_paste_rounded),
              title: const Text('粘贴导入'),
              onTap: () {
                Navigator.of(dialogContext).pop();
                _onPasteImport();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Push the full-screen scanner; a decoded config flows into the preview.
  Future<void> _onScanImport() async {
    final decoded = await Navigator.of(context).push<ProviderConfig>(
      MaterialPageRoute(builder: (_) => const ProviderScanPage()),
    );
    if (!mounted || decoded == null) return;
    await _showImportPreview(decoded);
  }

  /// Paste a share payload into a dialog; decode failures keep it open.
  Future<void> _onPasteImport() async {
    final decoded = await showDialog<ProviderConfig>(
      context: context,
      builder: (_) => const _PasteImportDialog(),
    );
    if (!mounted || decoded == null) return;
    await _showImportPreview(decoded);
  }

  /// Shared confirm-and-persist flow for both scan and paste imports.
  ///
  /// Warns first when a custom provider with the same name and base URL
  /// already exists, then shows a preview sheet; only 确认导入 persists.
  Future<void> _showImportPreview(ProviderConfig config) async {
    final settings = await ref.read(settingsStoreProvider.future);
    if (!mounted) return;
    final isDuplicate = settings.loadCustomProviders().any(
        (p) => p.name == config.name && p.baseUrl == config.baseUrl);
    if (isDuplicate) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('已存在相同提供商，仍要导入吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('仍要导入'),
            ),
          ],
        ),
      );
      if (!mounted || proceed != true) return;
    }
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                kSpace24, 0, kSpace24, kSpace24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('确认导入提供商', style: theme.textTheme.titleLarge),
                const SizedBox(height: kSpace16),
                _ImportPreviewRow(label: '名称', value: config.name),
                _ImportPreviewRow(label: '接口地址', value: config.baseUrl),
                _ImportPreviewRow(
                    label: '协议', value: _protocolLabel(config.protocol)),
                const SizedBox(height: kSpace12),
                Text(
                  '口令不含 API Key，导入后请自行填写',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: kSpace16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.of(sheetContext).pop(false),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: kSpace12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.of(sheetContext).pop(true),
                        child: const Text('确认导入'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || confirmed != true) return;
    final customs = settings.loadCustomProviders();
    await settings.saveCustomProviders([...customs, config]);
    await settings.saveProviderOrder(
        [...settings.loadProviderOrder(), config.id]);
    // WidgetRef.invalidate throws after dispose, so it must be guarded.
    if (!mounted) return;
    ref.invalidate(providerListProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已导入「${config.name}」')),
    );
  }

  /// Human-readable protocol name for the import preview.
  static String _protocolLabel(LlmProtocol protocol) => switch (protocol) {
        LlmProtocol.openai => 'OpenAI 兼容',
        LlmProtocol.claude => 'Claude',
        LlmProtocol.gemini => 'Gemini',
      };

  /// Persist the new display order after a drag-and-drop reorder.
  ///
  /// [newIndex] arrives pre-adjusted by `onReorderItem` (no manual
  /// downward-move fix-up). A no-op while a search filter is active: a
  /// filtered subset's indices cannot be mapped back onto the full list (the
  /// drag affordance is hidden in that state, so this is only a defensive
  /// guard).
  Future<void> _onReorder(
      List<ProviderConfig> displayed, int oldIndex, int newIndex) async {
    if (_searchQuery.isNotEmpty) return;
    final ids = <String>[for (final p in displayed) p.id];
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    try {
      final settings = await ref.read(settingsStoreProvider.future);
      await settings.saveProviderOrder(ids);
    } on Object {
      // Keep the UI responsive; a failed persist leaves the old order.
      return;
    }
    // WidgetRef.invalidate throws after dispose, so it must be guarded.
    if (!mounted) return;
    ref.invalidate(providerListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providersAsync = ref.watch(providerListProvider);
    final settingsAsync = ref.watch(settingsStoreProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择提供商'),
        automaticallyImplyLeading: !widget.fromOnboarding,
        actions: [
          IconButton(
            tooltip: '导入提供商',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: _showImportChooser,
          ),
        ],
      ),
      body: Column(
        children: [
          // Region detection banner.
          if (_region != null && _region!.countryCode != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(
                  kSpace16, kSpace8, kSpace16, kSpace4),
              padding: const EdgeInsets.symmetric(
                  horizontal: kSpace16, vertical: kSpace12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(kRadiusLg),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primaryContainer,
                    ),
                    child: Center(
                      child: Text(_region!.emoji ?? '🌍',
                          style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                  const SizedBox(width: kSpace12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '检测到地区',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _region!.displayText,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_region!.confident)
                    TextButton(
                      onPressed: () => _showRegionOverrideDialog(),
                      child: const Text('更改'),
                    ),
                ],
              ),
            ),
          // Search bar.
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: kSpace16, vertical: kSpace8),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索提供商…',
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // Provider card list (reorderable when no search filter is active).
          Expanded(
            child: providersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(kSpace24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('提供商列表加载失败',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: kSpace8),
                      Text(
                        '$error',
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: kSpace16),
                      FilledButton.icon(
                        onPressed: () =>
                            ref.invalidate(providerListProvider),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (providers) {
                final displayed = _filterProviders(providers);
                final settings = settingsAsync.valueOrNull;
                final reorderEnabled = _searchQuery.isEmpty;
                return ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: kSpace16, vertical: kSpace4),
                  buildDefaultDragHandles: false,
                  itemCount: displayed.length,
                  onReorderItem: (oldIndex, newIndex) =>
                      _onReorder(displayed, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final provider = displayed[index];
                    final isRecommended = _isRecommendedForRegion(provider);
                    final isSelected = _selectedProviderId == provider.id;
                    final isChinaFriendly =
                        kChinaRecommendedProviderIds.contains(provider.id);
                    return _ProviderCard(
                      key: ValueKey(provider.id),
                      provider: provider,
                      isRecommended: isRecommended,
                      isSelected: isSelected,
                      isChinaFriendly: isChinaFriendly,
                      modelCount:
                          settings?.modelsFor(provider.id).length ?? 0,
                      dragIndex: reorderEnabled ? index : null,
                      onTap: () => _onProviderTap(provider),
                    );
                  },
                );
              },
            ),
          ),
          // Trailing add-custom entry — a sibling of the list, never an item.
          _AddCustomProviderCard(onTap: _onAddCustomProvider),
          // Bottom: offline-companion entry (onboarding only).
          if (widget.fromOnboarding)
            Padding(
              padding: const EdgeInsets.all(kSpace24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text(
                        '进入离线陪伴模式', style: TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(height: kSpace8),
                  Text(
                    '不配置 LLM 也能用：伙伴会用本地情绪词库回应你（约 12 种情绪），但没有 AI 思考能力。随时可在设置里补配提供商。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showRegionOverrideDialog() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('地区手动选择功能由社区生态提供 [社区]'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// A single provider card in the selection list.
class _ProviderCard extends StatelessWidget {
  final ProviderConfig provider;
  final bool isRecommended;
  final bool isSelected;
  final bool isChinaFriendly;
  final int modelCount;

  /// Index handed to the drag-start listener, or `null` to hide the drag
  /// affordance (search filter active — reordering is disabled).
  final int? dragIndex;
  final VoidCallback onTap;

  const _ProviderCard({
    super.key,
    required this.provider,
    required this.isRecommended,
    required this.isSelected,
    required this.isChinaFriendly,
    required this.modelCount,
    required this.dragIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: kSpace8),
      child: ClayContainer(
        padding: EdgeInsets.zero,
        radius: kRadiusLg,
        onTap: onTap,
        shadowIntensity: isSelected ? 1.3 : 0.7,
        borderColor: isSelected ? theme.colorScheme.primary : null,
        child: Padding(
          padding: const EdgeInsets.all(kSpace16),
          child: Opacity(
            // Disabled providers stay manageable but read as inactive.
            opacity: provider.enabled ? 1.0 : 0.5,
            child: Row(
              children: [
                _buildIcon(theme),
                const SizedBox(width: kSpace16),
                // Name + status + model.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              provider.name,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isRecommended) ...[
                            const SizedBox(width: kSpace8),
                            _StatusChip(
                              label: '推荐',
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onPrimaryContainer,
                            ),
                          ],
                          if (provider.isCustom) ...[
                            const SizedBox(width: kSpace8),
                            _StatusChip(
                              label: '自定义',
                              backgroundColor:
                                  theme.colorScheme.secondaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onSecondaryContainer,
                            ),
                          ],
                          if (!provider.enabled) ...[
                            const SizedBox(width: kSpace8),
                            _StatusChip(
                              label: '已停用',
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              foregroundColor:
                                  theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: kSpace4),
                      // Reachability is only known for the built-in catalog;
                      // a custom endpoint's reachability is unknown.
                      if (!provider.isCustom)
                        Row(
                          children: [
                            Icon(
                              isChinaFriendly
                                  ? Icons.signal_cellular_alt_rounded
                                  : Icons.vpn_lock_rounded,
                              size: 13,
                              color: isChinaFriendly
                                  ? const Color(0xFF4CAF50)
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: kSpace4),
                            Text(
                              isChinaFriendly ? '国内可直连' : '需网络代理',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isChinaFriendly
                                    ? const Color(0xFF4CAF50)
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 2),
                      Text(
                        provider.effectiveModel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                      if (modelCount > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '$modelCount 个模型',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Selected check or chevron.
                if (isSelected)
                  Icon(Icons.check_circle_rounded,
                      size: 24, color: theme.colorScheme.primary)
                else
                  Icon(Icons.chevron_right_rounded,
                      size: 24, color: theme.colorScheme.onSurfaceVariant),
                if (dragIndex != null) ...[
                  const SizedBox(width: kSpace8),
                  ReorderableDragStartListener(
                    index: dragIndex!,
                    child: Icon(
                      Icons.drag_handle_rounded,
                      size: 22,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Provider logo: SVG asset for built-ins, a letter avatar for customs
  /// (customs have no bundled asset; an empty asset path would throw).
  Widget _buildIcon(ThemeData theme) {
    final initial =
        provider.name.isEmpty ? '?' : provider.name.characters.first;
    final avatar = Container(
      width: 52,
      height: 52,
      color: theme.colorScheme.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: provider.iconAsset.isEmpty
            ? avatar
            : SvgPicture.asset(
                provider.iconAsset,
                width: 52,
                height: 52,
                placeholderBuilder: (_) => avatar,
              ),
      ),
    );
  }
}

/// Trailing entry below the list that starts the custom-provider creation
/// flow. Styled like a provider card but dashed/subtle to read as an action,
/// not an existing provider.
class _AddCustomProviderCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddCustomProviderCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpace16, kSpace8, kSpace16, kSpace16),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kRadiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kRadiusLg),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: theme.colorScheme.outlineVariant,
              radius: kRadiusLg,
            ),
            child: Padding(
              padding: const EdgeInsets.all(kSpace16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: 26,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: kSpace16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '添加自定义提供商',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: kSpace4),
                        Text(
                          '自定义接口地址与协议',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded dashed border for the add-custom-provider card.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  static const double _dashLength = 6;
  static const double _gapLength = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    final outline = Path()..addRRect(rrect);
    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final len = math.min(_dashLength, metric.length - distance);
        canvas.drawPath(metric.extractPath(distance, distance + len), paint);
        distance += _dashLength + _gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// Paste-import dialog. Stateful so the text controller's disposal is tied
/// to the dialog's own lifecycle (disposing it from the caller races the
/// dialog's exit animation, which still rebuilds the field).
class _PasteImportDialog extends StatefulWidget {
  const _PasteImportDialog();

  @override
  State<_PasteImportDialog> createState() => _PasteImportDialogState();
}

class _PasteImportDialogState extends State<_PasteImportDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('粘贴导入'),
      content: TextField(
        controller: _controller,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          hintText: '粘贴 moodpet-provider:v1: 开头的口令',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final config = decodeProviderShare(_controller.text);
            if (config == null) {
              // Stay open so the user can fix or re-paste the payload.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('口令无效')),
              );
              return;
            }
            Navigator.of(context).pop(config);
          },
          child: const Text('导入'),
        ),
      ],
    );
  }
}

/// One label/value row in the import-preview bottom sheet.
class _ImportPreviewRow extends StatelessWidget {
  final String label;
  final String value;

  const _ImportPreviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: kSpace8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: theme.textTheme.labelMedium),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// A small status chip with a coloured background.
class _StatusChip extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const _StatusChip({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: kSpace8, vertical: 2),
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
