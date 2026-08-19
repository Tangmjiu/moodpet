/// Conversation history page: inspects the persistent [ConversationStore].
///
/// Shows the user ↔ partner dialogue log (newest first) as chat bubbles so
/// the user can see what the partner "remembers" across restarts. The AppBar
/// clear action wipes the whole history after a confirmation dialog.
///
/// Design language: claymorphism bubbles (ClayContainer) + M3 Expressive
/// colour roles — the user bubble sits on `primaryContainer`, the partner
/// bubble on `surfaceContainerHighest`. Colour-scheme roles only, never raw
/// hex.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart'
    show
        ClayContainer,
        kRadiusMd,
        kSpace8,
        kSpace12,
        kSpace16,
        kSpace24;
import '../../core/providers.dart';
import '../../core/storage/conversation_store.dart';

class ConversationPage extends ConsumerStatefulWidget {
  const ConversationPage({super.key});

  @override
  ConsumerState<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends ConsumerState<ConversationPage> {
  Future<void> _confirmClear(ConversationStore store) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('清空对话历史'),
          content: const Text('确定要清空所有对话记录吗？此操作不可撤销。'),
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
      await store.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(conversationStoreProvider);
    final store = storeAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('对话历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: '清空对话历史',
            onPressed: store == null ? null : () => _confirmClear(store),
          ),
        ],
      ),
      body: SafeArea(
        child: storeAsync.when(
          data: (store) => StreamBuilder<List<ConversationTurn>>(
            // Rebuilds on every append/clear via the changes stream.
            stream: store.changes,
            initialData: store.turns,
            builder: (context, snapshot) {
              final turns = snapshot.data ?? const <ConversationTurn>[];
              if (turns.isEmpty) {
                return const _EmptyState();
              }
              // The store is oldest-first; the viewer shows newest first.
              final newestFirst = turns.reversed.toList(growable: false);
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                    kSpace16, kSpace8, kSpace16, kSpace24),
                itemCount: newestFirst.length,
                separatorBuilder: (_, _) => const SizedBox(height: kSpace8),
                itemBuilder: (context, index) =>
                    _TurnTile(turn: newestFirst[index]),
              );
            },
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败: $e')),
        ),
      ),
    );
  }
}

/// One conversation turn — user bubble (right), centred timestamp, partner
/// bubble (left).
class _TurnTile extends StatelessWidget {
  final ConversationTurn turn;

  const _TurnTile({required this.turn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bubble(
          alignment: Alignment.centerRight,
          color: cs.primaryContainer,
          textColor: cs.onPrimaryContainer,
          text: turn.userInput,
        ),
        const SizedBox(height: kSpace8),
        Text(
          _formatTimestamp(turn.timestamp),
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: kSpace8),
        _Bubble(
          alignment: Alignment.centerLeft,
          color: cs.surfaceContainerHighest,
          textColor: cs.onSurface,
          text: turn.partnerReply,
        ),
      ],
    );
  }
}

/// A clay chat bubble, capped at 80% of the screen width so long messages
/// still read as a bubble rather than a full-width card.
class _Bubble extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final Color textColor;
  final String text;

  const _Bubble({
    required this.alignment,
    required this.color,
    required this.textColor,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: ClayContainer(
          color: color,
          radius: kRadiusMd,
          shadowIntensity: 0.6,
          padding: const EdgeInsets.all(kSpace12),
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.forum_outlined,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: kSpace12),
          Text(
            '还没有对话记录',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// `MM/dd HH:mm` — intl is not a dependency, so format manually.
String _formatTimestamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
