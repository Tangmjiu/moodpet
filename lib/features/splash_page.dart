/// Splash screen — animated brand entrance with the MoodPet icon (🥳).
///
/// Shows a claymorphism orb holding the 🥳 app-icon emoji, the app name, and
/// a tagline. After a minimum display duration and once initialization
/// providers have resolved, navigates to [HomePage] or [OnboardingPage].
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/providers.dart';
import 'home/home_page.dart';
import 'onboarding_page.dart';

/// The minimum time the splash stays visible, even if providers resolve faster.
const Duration _kMinSplashDuration = Duration(seconds: 2);

/// The splash screen — shown on app launch while initialization runs.
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with TickerProviderStateMixin {
  late final AnimationController _orbController;
  late final AnimationController _contentController;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    // Orb pop-in: M3 Expressive spring physics for a playful entrance.
    _orbController = AnimationController(
      duration: kMotionSlow,
      vsync: this,
      value: 0.0,
    );
    final simulation = SpringSimulation(kSpringBouncy, 0.0, 1.0, 0.0);
    _orbController.animateWith(simulation);

    // Content (app name, tagline, loading dots) — fade + slide in after the
    // orb begins appearing, so the entrance reads as a sequence.
    _contentController = AnimationController(
      duration: kMotionMedium,
      vsync: this,
    );
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _contentController.forward();
    });

    // After the minimum display duration, wait for the onboarding state to
    // resolve, then navigate. The agent service initialises in the background;
    // _respond on the home page awaits it on first send so the first message
    // is never dropped even if the user enters the home page before the agent
    // is fully ready.
    Future.delayed(_kMinSplashDuration, () async {
      if (!mounted) return;
      try {
        final isComplete =
            await ref.read(isOnboardingCompleteProvider.future);
        if (mounted) _navigate(isComplete);
      } catch (_) {
        if (mounted) _navigate(false);
      }
    });
  }

  @override
  void dispose() {
    _orbController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _navigate(bool isOnboardingComplete) {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => isOnboardingComplete
            ? const HomePage()
            : const OnboardingPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final seedColor = kMoodPetSeed;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Warm radial-gradient background — brand-tinted ambient glow.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.1),
                    radius: 1.5,
                    colors: [
                      seedColor.withValues(alpha: isDark ? 0.12 : 0.18),
                      theme.colorScheme.surface.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SplashOrb(
                    animation: _orbController,
                    color: seedColor,
                  ),
                  const SizedBox(height: kSpace32),
                  // Use FadeTransition + SlideTransition instead of
                  // SizeTransition — SizeTransition animates layout height,
                  // which shifts the orb upward as the content expands.
                  // Fade + Slide only affect paint, keeping the layout stable.
                  FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _contentController,
                      curve: kCurveEnter,
                    ),
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.15),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: _contentController,
                          curve: kCurveEnter,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            kAppName,
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: kSpace8),
                          Text(
                            '你的情绪伙伴平台',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: kSpace32),
                          _LoadingDots(color: seedColor),
                        ],
                      ),
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

/// The splash orb — a claymorphism soft-circle holding the 🥳 app-icon emoji.
///
/// Mirrors the home screen's [_CompanionOrb] visual language: mood-tinted
/// translucent fill, clay shadows, inner ring, and the emoji as the focal
/// content.
class _SplashOrb extends StatelessWidget {
  final Animation<double> animation;
  final Color color;

  const _SplashOrb({required this.animation, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final orbSize = screenHeight * 0.22;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.scale(scale: animation.value, child: child);
      },
      child: Container(
        width: orbSize,
        height: orbSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 40,
              spreadRadius: 0,
            ),
            ...clayShadows(context, intensity: 1.2),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: orbSize * 0.82,
              height: orbSize * 0.82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surface.withValues(alpha: 0.6),
                border: Border.all(
                  color: color.withValues(alpha: 0.2),
                  width: 2,
                ),
              ),
            ),
            Text(
              '🥳',
              style: TextStyle(
                fontSize: orbSize * 0.45,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three pulsing dots — a subtle, non-intrusive loading indicator.
class _LoadingDots extends StatefulWidget {
  final Color color;
  const _LoadingDots({required this.color});

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 10,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              // Stagger each dot so they pulse in sequence.
              final t = (_controller.value + i * 0.33) % 1.0;
              final triangle = (2 * t - 1).abs();
              final scale = 0.5 + 0.5 * (1 - triangle);
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        widget.color.withValues(alpha: 0.35 + 0.45 * scale),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
