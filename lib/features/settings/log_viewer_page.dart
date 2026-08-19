/// Log viewer page: inspects the in-memory [AgentLogger] buffer.
///
/// Diagnostic surface for LLM/agent failures — when the agent silently falls
/// back to keyword matching, the user can open this page (settings → 日志查看器)
/// to see HTTP status codes, response bodies and parse errors, then export the
/// whole buffer for a bug report.
///
/// Design language: claymorphism cards (ClayContainer) + M3 Expressive colour
/// roles. Level tinting uses colour-scheme roles only, never raw hex.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart'
    show
        ClayContainer,
        IconBadge,
        kCurveEnter,
        kMotionMedium,
        kRadiusLg,
        kRadiusSm,
        kSpace4,
        kSpace8,
        kSpace12,
        kSpace16,
        kSpace24,
        reducedMotionEnabled;
import '../../core/agent/agent_logger.dart';

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  /// Active level filter. `null` means 全部 (All).
  LogLevel? _levelFilter;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// Identity-based set of expanded entries (LogEntry has no value equality).
  final Set<LogEntry> _expanded = <LogEntry>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<LogEntry> _applyFilters(List<LogEntry> entries) {
    final q = _searchQuery.trim().toLowerCase();
    return entries.where((e) {
      if (_levelFilter != null && e.level != _levelFilter) return false;
      if (q.isEmpty) return true;
      return e.message.toLowerCase().contains(q) ||
          e.category.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _exportLogs() async {
    // share_plus is not a dependency — copy to clipboard instead of adding one.
    await Clipboard.setData(
      ClipboardData(text: AgentLogger.instance.exportAsText()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制日志到剪贴板')),
    );
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('清空日志'),
          content: const Text('确定要清空所有日志吗？此操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      AgentLogger.instance.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志查看器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: '导出日志',
            onPressed: _exportLogs,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: '清空日志',
            onPressed: _confirmClear,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search box.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  kSpace16, kSpace8, kSpace16, kSpace8),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索日志内容或分类',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          tooltip: '清除搜索',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                ),
              ),
            ),
            // Level filter chips (single-select, 全部 default). Wrap avoids
            // any horizontal scroll on narrow screens.
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: kSpace16),
              child: Wrap(
                spacing: kSpace8,
                runSpacing: kSpace8,
                children: [
                  _LevelChip(
                    label: '全部',
                    selected: _levelFilter == null,
                    onSelected: () =>
                        setState(() => _levelFilter = null),
                  ),
                  _LevelChip(
                    label: '错误',
                    selected: _levelFilter == LogLevel.error,
                    onSelected: () =>
                        setState(() => _levelFilter = LogLevel.error),
                  ),
                  _LevelChip(
                    label: '警告',
                    selected: _levelFilter == LogLevel.warn,
                    onSelected: () =>
                        setState(() => _levelFilter = LogLevel.warn),
                  ),
                  _LevelChip(
                    label: '信息',
                    selected: _levelFilter == LogLevel.info,
                    onSelected: () =>
                        setState(() => _levelFilter = LogLevel.info),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kSpace8),
            // Log list — rebuilds on every add/clear via the changes stream.
            Expanded(
              child: StreamBuilder<List<LogEntry>>(
                stream: AgentLogger.instance.changes,
                initialData: AgentLogger.instance.entries,
                builder: (context, snapshot) {
                  final all = snapshot.data ?? const <LogEntry>[];
                  final entries = _applyFilters(all);

                  if (entries.isEmpty) {
                    return _EmptyState(
                      message: all.isEmpty ? '暂无日志' : '无匹配的日志',
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        kSpace16, kSpace8, kSpace16, kSpace24),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: kSpace8),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _LogEntryTile(
                        entry: entry,
                        expanded: _expanded.contains(entry),
                        onToggle: () => setState(() {
                          if (!_expanded.remove(entry)) {
                            _expanded.add(entry);
                          }
                        }),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single-select filter chip with a padded 48px touch target.
class _LevelChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _LevelChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      showCheckmark: false,
    );
  }
}

/// One log entry — collapsed shows badge + message + timestamp, tap expands
/// inline to show category, full timestamp and the raw payload (monospace).
class _LogEntryTile extends StatelessWidget {
  final LogEntry entry;
  final bool expanded;
  final VoidCallback onToggle;

  const _LogEntryTile({
    required this.entry,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reducedMotion = reducedMotionEnabled(context);

    return ClayContainer(
      radius: kRadiusLg,
      shadowIntensity: 0.6,
      color: _levelTint(cs, entry.level),
      onTap: onToggle,
      padding: const EdgeInsets.all(kSpace12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: _levelIcon(entry.level),
                backgroundColor: _levelBadgeBg(cs, entry.level),
                foregroundColor: _levelBadgeFg(cs, entry.level),
                size: 36,
                iconSize: 18,
              ),
              const SizedBox(width: kSpace12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.message,
                      maxLines: expanded ? null : 2,
                      overflow: expanded ? null : TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: kSpace4),
                    Text(
                      '${_formatTime(entry.timestamp)} · ${entry.category}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: kSpace8),
              Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
          // Expansion: minimal motion — one AnimatedSize, M3 enter curve,
          // skipped entirely under reduced-motion.
          AnimatedSize(
            duration: reducedMotion ? Duration.zero : kMotionMedium,
            curve: kCurveEnter,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.hardEdge,
            child: expanded
                ? _ExpandedDetails(entry: entry)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  static Color _levelTint(ColorScheme cs, LogLevel level) => switch (level) {
        LogLevel.error => cs.error.withValues(alpha: 0.10),
        LogLevel.warn => cs.tertiary.withValues(alpha: 0.14),
        LogLevel.info => cs.surfaceContainerHighest,
      };

  static IconData _levelIcon(LogLevel level) => switch (level) {
        LogLevel.error => Icons.error_rounded,
        LogLevel.warn => Icons.warning_amber_rounded,
        LogLevel.info => Icons.info_outline_rounded,
      };

  static Color _levelBadgeBg(ColorScheme cs, LogLevel level) =>
      switch (level) {
        LogLevel.error => cs.errorContainer,
        LogLevel.warn => cs.tertiaryContainer,
        LogLevel.info => cs.surfaceContainerHigh,
      };

  static Color _levelBadgeFg(ColorScheme cs, LogLevel level) =>
      switch (level) {
        LogLevel.error => cs.onErrorContainer,
        LogLevel.warn => cs.onTertiaryContainer,
        LogLevel.info => cs.onSurfaceVariant,
      };
}

/// Inline detail block shown when an entry is expanded.
class _ExpandedDetails extends StatelessWidget {
  final LogEntry entry;

  const _ExpandedDetails({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: kSpace12),
        Divider(
          height: 1,
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
        const SizedBox(height: kSpace12),
        _DetailRow(label: '级别', value: _levelLabel(entry.level)),
        const SizedBox(height: kSpace4),
        _DetailRow(label: '分类', value: entry.category),
        const SizedBox(height: kSpace4),
        _DetailRow(label: '时间', value: _formatFull(entry.timestamp)),
        if (entry.rawPayload != null && entry.rawPayload!.isNotEmpty) ...[
          const SizedBox(height: kSpace12),
          Text('原始数据', style: theme.textTheme.labelMedium),
          const SizedBox(height: kSpace4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(kSpace12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(kRadiusSm),
            ),
            child: SelectableText(
              entry.rawPayload!,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _levelLabel(LogLevel level) => switch (level) {
        LogLevel.error => '错误',
        LogLevel.warn => '警告',
        LogLevel.info => '信息',
      };
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: theme.textTheme.labelMedium),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.article_outlined,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: kSpace12),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// `HH:mm:ss.SSS` — intl is not a dependency, so format manually.
String _formatTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  String three(int v) => v.toString().padLeft(3, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
}

/// `yyyy-MM-dd HH:mm:ss.SSS` for the expanded detail view.
String _formatFull(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${_formatTime(t)}';
}
