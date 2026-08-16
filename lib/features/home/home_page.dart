import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/home_providers.dart';
import '../settings/settings_page.dart';
import '../widgets/emoji_display.dart';
import '../widgets/gradient_background.dart';

/// 主页：语音输入 → PocketClaw → 三重响应。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: GradientBackground(
        color: state.emotion.color,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              children: [
                _buildTopBar(context, theme, state),
                Expanded(
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      switchInCurve: Curves.elasticOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: EmojiDisplay(
                        key: ValueKey(state.emotion.emoji),
                        emoji: state.emotion.emoji,
                        fontSize: 120,
                      ),
                    ),
                  ),
                ),
                _buildSuggestion(context, state),
                const SizedBox(height: 20),
                _buildMicButton(context, state, ref),
                const SizedBox(height: 12),
                Text(
                  state.isListening
                      ? '我在听，说完会自动分析…'
                      : '轻点按钮，说说你现在的感受',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, ThemeData theme, HomeState state) {
    return Row(
      children: [
        Expanded(
          child: Chip(
            avatar: null,
            backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.72),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
            label: Text(
              '${state.emotion.emoji} ${state.statusPhrase}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: '设置',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
          ),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }

  Widget _buildSuggestion(BuildContext context, HomeState state) {
    final theme = Theme.of(context);
    if (state.isThinking) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text('正在感受你的情绪…', style: theme.textTheme.bodyLarge),
        ],
      );
    }
    final suggestion = state.suggestion;
    if (suggestion == null || suggestion.isEmpty) {
      return Text(
        '和我说句话吧',
        style: theme.textTheme.bodyLarge
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        suggestion,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildMicButton(
      BuildContext context, HomeState state, WidgetRef ref) {
    final controller = ref.read(homeControllerProvider.notifier);
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: state.isThinking ? null : controller.toggleListening,
        icon: Icon(state.isListening ? Icons.stop_circle_outlined : Icons.mic),
        label: Text(state.isListening ? '听你说…' : '说点什么...'),
      ),
    );
  }
}
