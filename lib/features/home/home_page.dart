/// Home page (§4.2, §7): Friend display + mic FAB + suggestion + status.
///
/// Design philosophy (§4.1): "容器是透明的，Friend 是焦点。" The home screen is
/// an immersive companion space: an ambient mood-tinted background, a soft
/// claymorphism "companion orb" holding the Friend emoji as the sole focal
/// point, a greeting speech bubble, quick-suggestion chips for low-friction
/// interaction, and a large mic FAB. An "离线陪伴模式" badge appears when no
/// LLM provider is configured.
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show kAppName, kSpace4, kSpace8, kSpace12, kSpace16, kSpace20, kSpace24, kSpace32, kRadiusLg, kRadiusXl, kTouchTarget, kMotionFast, kMotionMedium, kMotionSlow, kCurveSpring, kCurveEnter, kCurveSoft, kSpringBouncy, reducedMotionEnabled, clayShadows, ClayContainer;
import '../../core/providers.dart';
import '../../core/utils/color_hex.dart';
import '../../core/utils/haptics.dart';

/// Quick-suggestion prompts shown as tappable chips below the companion orb.
const List<String> _kQuickPrompts = <String>[
  '你好呀',
  '今天有点累',
  '好开心！',
  '有点难过',
  '晚安',
];

/// The home page — the first screen after onboarding.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with TickerProviderStateMixin {
  late final AnimationController _bounceController;
  late final Animation<double> _bounceAnimation;
  late final AnimationController _breathController;
  late final Animation<double> _breathAnimation;
  bool _hasShownMicHint = false;
  bool _greetingDismissed = false;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    // Emotion-change bounce: driven by a [SpringSimulation] at trigger time
    // (see [_respond]), not a fixed curve. The controller value maps to scale.
    // Initial value = 1.0 (natural size) so the orb is visible on first render.
    // Without this the controller defaults to 0.0 → Transform.scale(0.0) makes
    // the orb invisible until the first emotion-change bounce animates it to 1.0.
    _bounceController = AnimationController(
      duration: kMotionSlow,
      vsync: this,
      value: 1.0,
    );
    // Use a curved animation as a fallback; the spring simulation overrides
    // this when animateWith() is called.
    _bounceAnimation = CurvedAnimation(
      parent: _bounceController,
      curve: kCurveSpring,
    );
    // Idle breathing: subtle, continuous life-signal.
    _breathController = AnimationController(
      duration: const Duration(milliseconds: 2800),
      vsync: this,
    );
    _breathAnimation = Tween<double>(begin: 1.0, end: 1.035).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOutSine),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = reducedMotionEnabled(context);
    if (reduced != _reducedMotion) {
      _reducedMotion = reduced;
      if (reduced) {
        _breathController.stop();
      } else {
        _breathController.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _breathController.dispose();
    super.dispose();
  }

  Future<void> _respond(String input) async {
    // agentServiceProvider is a FutureProvider — on a fresh app launch it may
    // still be initialising (loading settings, plugin manager, registry) when
    // the user sends their first message. Wait for it to resolve instead of
    // silently dropping the message (which was the bug: first send was a no-op
    // because `agent` was null, only the second send worked).
    if (!_greetingDismissed) {
      setState(() => _greetingDismissed = true);
    }
    // Show the processing indicator immediately so the user sees the partner
    // "thinking" while the agent finishes initialising.
    ref.read(isAgentProcessingProvider.notifier).state = true;
    try {
      final agent = await ref.read(agentServiceProvider.future);
      if (!mounted) return;
      final result = await agent.respond(input);
      if (result.isOk && result.response != null && mounted) {
        ref.read(activeEmotionProvider.notifier).state = result.response!;
        _triggerEmotionBounce();
        await playVibrationPattern(result.response!.vibration);
      } else if (mounted && result.error != null) {
        _showError(result.error!);
      }
    } finally {
      if (mounted) {
        ref.read(isAgentProcessingProvider.notifier).state = false;
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// Open a scrollable bottom sheet showing the partner's full message, for
  /// when the on-screen bubble truncates a long LLM reply (maxLines: 4).
  void _showFullMessage(BuildContext context, String fullText) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              kSpace24, 0, kSpace24, kSpace32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('伙伴说', style: theme.textTheme.titleLarge),
              const SizedBox(height: kSpace16),
              Flexible(
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: fullText,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: theme.textTheme.bodyLarge?.copyWith(
                        height: 1.6,
                        color: theme.colorScheme.onSurface,
                      ),
                      h2: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      h3: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      strong: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                      em: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontStyle: FontStyle.italic,
                      ),
                      code: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      ),
                      blockquote: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: kSpace16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Trigger the companion orb's emotion-change bounce using M3 Expressive
  /// spring physics. Falls back to a simple fade when reduced-motion is on.
  void _triggerEmotionBounce() {
    if (_reducedMotion) {
      // Reduced motion: gentle opacity pulse instead of spring bounce.
      _bounceController.forward(from: 0.0);
      return;
    }
    // M3 Expressive: true spring physics — overshoot and settle organically.
    final simulation = SpringSimulation(
      kSpringBouncy,
      0.3, // start slightly compressed
      1.0, // settle at natural size
      0.0, // initial velocity
    );
    _bounceController.animateWith(simulation);
  }

  void _onMicTap() {
    HapticFeedback.lightImpact();
    if (!_hasShownMicHint) {
      _hasShownMicHint = true;
      _showMicHint();
    }
    _showTextInput();
  }

  void _showMicHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('点击跟我说话'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showTextInput() async {
    final input = await showDialog<String>(
      context: context,
      builder: (context) => const _TextInputDialog(),
    );
    if (input != null && input.trim().isNotEmpty) {
      await _respond(input.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emotion = ref.watch(activeEmotionProvider);
    final isProcessing = ref.watch(isAgentProcessingProvider);
    final managerAsync = ref.watch(pluginManagerProvider);
    final providerConfigAsync = ref.watch(activeProviderConfigProvider);

    final manager = managerAsync.maybeWhen(
      data: (m) => m,
      orElse: () => null,
    );
    final friendName = manager?.activeFriendName ?? kAppName;
    final greeting = manager?.activeFriendGreeting;
    final offlineMode = providerConfigAsync.maybeWhen(
      data: (c) => c == null || !c.isConfigured,
      orElse: () => true,
    );
    final moodColor = parseHexColor(emotion.color);

    return Scaffold(
      // The home page sits behind the _TextInputDialog; letting it resize for
      // the keyboard wastes 15+ full-tree rebuilds per IME show/hide (the
      // expensive orb shadows + gradient + breathing animation repaint every
      // inset-animation frame). The Material Dialog handles its own keyboard
      // avoidance via an internal AnimatedPadding on viewInsets.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Stack(
          children: [
            // Layer 1: Ambient mood-tinted background.
            _AmbientBackground(moodColor: moodColor),
            // Layer 2: Foreground content.
            SafeArea(
              child: Column(
                children: [
                  // Top bar.
                  _TopBar(
                    friendName: friendName,
                    offlineMode: offlineMode,
                    onSettings: () =>
                        Navigator.pushNamed(context, '/settings'),
                  ),
                  // Greeting bubble — M3 enter animation (slide + fade).
                  // Shown once the active Friend's greeting is available and
                  // until the user dismisses it.
                  if (!_greetingDismissed &&
                      greeting != null &&
                      greeting.isNotEmpty)
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: kMotionMedium,
                      curve: kCurveEnter,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value.clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - value)),
                            child: child,
                          ),
                        );
                      },
                      child: _GreetingBubble(
                        text: greeting,
                        onDismiss: () =>
                            setState(() => _greetingDismissed = true),
                      ),
                    ),
                  // Partner speech bubble — sits ABOVE the orb so it always
                  // gets its natural height (no Flexible fighting the orb for
                  // space). The orb below is the only Flexible element and
                  // absorbs whatever vertical room remains. This is the fix for
                  // the bubble's last line being clipped: the bubble is no
                  // longer height-constrained by a Flexible slot.
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: kSpace8),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: Semantics(
                          label: isProcessing
                              ? '伙伴正在思考中'
                              : '伙伴说: ${emotion.displayText}',
                          liveRegion: true,
                          child: ClayContainer(
                            margin: const EdgeInsets.symmetric(
                                horizontal: kSpace16),
                            padding: const EdgeInsets.all(kSpace12),
                            radius: kRadiusLg,
                            color: moodColor.withValues(alpha: 0.08),
                            shadowIntensity: 0.5,
                            onTap: (isProcessing ||
                                    emotion.displayText.length <= 60)
                                ? null
                                : () => _showFullMessage(
                                    context, emotion.displayText),
                            child: AnimatedSwitcher(
                              duration: _reducedMotion
                                  ? Duration.zero
                                  : kMotionFast,
                              switchInCurve: kCurveEnter,
                              switchOutCurve: kCurveEnter,
                              child: isProcessing
                                  ? Text(
                                      '思考中…',
                                      key: const ValueKey<String>('processing'),
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    )
                                  : MarkdownBody(
                                      data: emotion.displayText,
                                      key: ValueKey<String>(
                                          emotion.displayText),
                                      selectable: true,
                                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                                        p: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onSurface,
                                          height: 1.5,
                                        ),
                                        textAlign: WrapAlignment.center,
                                        h2: theme.textTheme.titleSmall?.copyWith(
                                          color: theme.colorScheme.onSurface,
                                        ),
                                        h3: theme.textTheme.titleSmall?.copyWith(
                                          color: theme.colorScheme.onSurface,
                                        ),
                                        strong: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onSurface,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        em: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onSurface,
                                          fontStyle: FontStyle.italic,
                                        ),
                                        code: theme.textTheme.bodySmall?.copyWith(
                                          fontFamily: 'monospace',
                                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                        ),
                                        blockquote: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Central: companion orb (focal point). The ONLY Flexible
                  // element — absorbs remaining vertical space after all fixed
                  // siblings (top bar, identity, bubble, chips, mic) take their
                  // natural heights. Shrinks via LayoutBuilder when needed.
                  Flexible(
                    fit: FlexFit.loose,
                    child: Center(
                      child: RepaintBoundary(
                        child: _CompanionOrb(
                          emoji: emotion.emoji,
                          moodColor: moodColor,
                          bounceAnimation: _bounceAnimation,
                          breathAnimation: _breathAnimation,
                          isProcessing: isProcessing,
                        ),
                      ),
                    ),
                  ),
                  // Quick-suggestion chips — M3 enter (fade + slide up).
                  if (!isProcessing)
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: kMotionMedium,
                      curve: kCurveEnter,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value.clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(0, 16 * (1 - value)),
                            child: child,
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: kSpace16, vertical: kSpace4),
                        child: _QuickPromptChips(
                          prompts: _kQuickPrompts,
                          onTap: _respond,
                        ),
                      ),
                    ),
                  // Bottom: mic FAB + status.
                  Padding(
                    padding: const EdgeInsets.only(
                        top: kSpace12, bottom: kSpace24),
                    child: _MicButton(
                      isProcessing: isProcessing,
                      moodColor: moodColor,
                      onTap: _onMicTap,
                    ),
                  ),
                 ],
               ),
             ),
           ],
         ),
       ),
      );
  }
}

/// A soft radial-gradient background tinted by the current mood colour.
class _AmbientBackground extends StatelessWidget {
  final Color moodColor;
  const _AmbientBackground({required this.moodColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.15),
            radius: 1.2,
            colors: [
              moodColor.withValues(alpha: isDark ? 0.08 : 0.12),
              theme.colorScheme.surface.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.7],
          ),
        ),
      ),
    );
  }
}

/// Top bar: friend name (centred) + offline badge + settings icon.
class _TopBar extends StatelessWidget {
  final String friendName;
  final bool offlineMode;
  final VoidCallback onSettings;

  const _TopBar({
    required this.friendName,
    required this.offlineMode,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: kSpace12, vertical: kSpace8),
      child: Row(
        children: [
          // Balance the settings icon on the right.
          const SizedBox(width: kTouchTarget),
          Expanded(
            child: Column(
              children: [
                Text(
                  friendName,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (offlineMode)
                  Padding(
                    padding: const EdgeInsets.only(top: kSpace4),
                    child: _OfflineBadge(),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            iconSize: 24,
            tooltip: '设置',
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

/// The companion orb — a claymorphism soft-circle holding the Friend emoji.
/// Combines a bounce animation (on emotion change) with a continuous breathing
/// animation (idle life-signal).
class _CompanionOrb extends StatelessWidget {
  final String emoji;
  final Color moodColor;
  final Animation<double> bounceAnimation;
  final Animation<double> breathAnimation;
  final bool isProcessing;

  const _CompanionOrb({
    required this.emoji,
    required this.moodColor,
    required this.bounceAnimation,
    required this.breathAnimation,
    required this.isProcessing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Use LayoutBuilder so the orb shrinks to fit whatever space the Column
    // gives it after the fixed-height siblings (greeting, identity, bubble,
    // chips, mic) take their share. A fixed `screenHeight * 0.32` would overflow
    // its Expanded box when those siblings already fill most of the screen.
    return LayoutBuilder(
      builder: (context, constraints) {
        // The orb must be a perfect square. Use the SMALLER of the available
        // width and height — if we only used height, a portrait screen would
        // give an orbSize larger than the available width, and the parent would
        // clamp the Container's width while leaving height untouched, turning
        // the circle into an ellipse and stretching the emoji + processing
        // ring with it.
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height * 0.32;
        // Leave 10% headroom so the orb never kisses the bubble/identity edges.
        final orbSize = (maxW < maxH ? maxW : maxH) * 0.9;
    return AnimatedBuilder(
      animation: Listenable.merge([bounceAnimation, breathAnimation]),
      builder: (context, child) {
        final scale = bounceAnimation.value * breathAnimation.value;
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        width: orbSize,
        height: orbSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: moodColor.withValues(alpha: 0.10),
          boxShadow: [
            BoxShadow(
              color: moodColor.withValues(alpha: 0.12),
              blurRadius: 40,
              spreadRadius: 0,
            ),
            ...clayShadows(context, intensity: 1.2),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Inner ring — subtle claymorphism inset.
            Container(
              width: orbSize * 0.82,
              height: orbSize * 0.82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surface.withValues(alpha: 0.6),
                border: Border.all(
                  color: moodColor.withValues(alpha: 0.15),
                  width: 2,
                ),
              ),
            ),
            // The emoji — the Friend's visual identity (content, not icon).
            Text(
              emoji,
              style: TextStyle(
                fontSize: orbSize * 0.42,
                height: 1.0,
              ),
            ),
            // Processing ring — rotating arc when the agent is thinking.
            if (isProcessing)
              SizedBox(
                width: orbSize * 0.95,
                height: orbSize * 0.95,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: moodColor.withValues(alpha: 0.5),
                  backgroundColor: Colors.transparent,
                ),
              ),
          ],
        ),
      ),
    );
      },
    );
  }
}

/// Quick-suggestion tappable chips — low-friction prompts for the user.
class _QuickPromptChips extends StatelessWidget {
  final List<String> prompts;
  final ValueChanged<String> onTap;

  const _QuickPromptChips({required this.prompts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kSpace12),
        itemCount: prompts.length,
        separatorBuilder: (_, _) => const SizedBox(width: kSpace8),
        itemBuilder: (context, index) {
          final prompt = prompts[index];
          return Material(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap(prompt);
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                alignment: Alignment.center,
                child: Text(
                  prompt,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The mic FAB — large circular claymorphism button with press feedback.
class _MicButton extends StatefulWidget {
  final bool isProcessing;
  final Color moodColor;
  final VoidCallback onTap;

  const _MicButton({
    required this.isProcessing,
    required this.moodColor,
    required this.onTap,
  });

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _pressAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: kMotionFast,
      vsync: this,
    );
    _pressAnimation = Tween<double>(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _pressController, curve: kCurveSoft),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: _pressAnimation,
          child: GestureDetector(
            onTapDown: (_) => _pressController.forward(),
            onTapUp: (_) {
              _pressController.reverse();
              widget.onTap();
            },
            onTapCancel: () => _pressController.reverse(),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.moodColor,
                boxShadow: [
                  BoxShadow(
                    color: widget.moodColor.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                widget.isProcessing
                    ? Icons.hourglass_top_rounded
                    : Icons.mic_rounded,
                size: 34,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: kSpace12),
        Text(
          widget.isProcessing ? '思考中…' : '点我说话',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// A dismissable speech-bubble showing the Friend's first-launch greeting.
class _GreetingBubble extends StatelessWidget {
  final String text;
  final VoidCallback onDismiss;

  const _GreetingBubble({required this.text, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: kSpace16, vertical: kSpace4),
      child: ClayContainer(
        padding:
            const EdgeInsets.symmetric(horizontal: kSpace16, vertical: kSpace12),
        radius: kRadiusLg,
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
        shadowIntensity: 0.5,
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: kSpace8),
            InkWell(
              onTap: onDismiss,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(kSpace4),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small chip signalling that no LLM provider is configured and the partner
/// is running on the local keyword-based emotion engine.
class _OfflineBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: kSpace8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 13,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: kSpace4),
          Text(
            '离线陪伴模式',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A bottom-sheet-style text input dialog for when speech-to-text is not
/// available (it's a [社区] Application plugin).
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog();

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  final _controller = TextEditingController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final canSend = _controller.text.trim().isNotEmpty;
      if (canSend != _canSend) setState(() => _canSend = canSend);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusXl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(kSpace24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '跟伙伴说点什么',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: kSpace16),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '今天怎么样？',
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) Navigator.pop(context, v);
              },
            ),
            const SizedBox(height: kSpace20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: kSpace8),
                FilledButton(
                  onPressed: _canSend
                      ? () => Navigator.pop(context, _controller.text)
                      : null,
                  child: const Text('发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
