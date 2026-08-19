/// Onboarding flow (§5): welcome → permissions → provider config → home.
///
/// Design philosophy (§5.1): "首次启动是建立信任，不是填表。" Each step is
/// minimal, emotional, and gets the user closer to seeing the Friend respond.
/// Dot indicators show progress; a Skip button lets users enter offline mode
/// at any point. Permission cards use claymorphism containers with icon badges.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show kSpace8, kSpace12, kSpace16, kSpace20, kSpace24, kSpace32, kRadiusLg, kMotionMedium, kMotionSlow, kCurveEmphasised, kCurveSpring, kCurveEnter, reducedMotionEnabled, clayShadows, ClayContainer, IconBadge;
import '../core/models/region_info.dart';
import '../core/providers.dart';
import '../core/region/region_detector.dart';
import 'home/home_page.dart';
import 'settings/provider_selection_page.dart';

/// The onboarding flow — a [PageView] with three steps.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _currentStep = 0;
  RegionInfo? _region;

  static const _stepCount = 3;

  @override
  void initState() {
    super.initState();
    _region = detectRegion();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_currentStep < _stepCount - 1) {
      _controller.nextPage(
        duration: kMotionMedium,
        curve: kCurveEmphasised,
      );
    } else {
      _complete();
    }
  }

  void _skip() {
    HapticFeedback.selectionClick();
    _complete();
  }

  Future<void> _complete() async {
    final settings = await ref.read(settingsStoreProvider.future);
    await settings.markOnboardingComplete();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top row: dot indicators + skip button.
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: kSpace24, vertical: kSpace16),
              child: Row(
                children: [
                  // Dot indicators.
                  Expanded(
                    child: Row(
                      children: List.generate(_stepCount, (i) {
                        final active = i <= _currentStep;
                        final isCurrent = i == _currentStep;
                        return AnimatedContainer(
                          duration: kMotionMedium,
                          curve: kCurveEmphasised,
                          margin: const EdgeInsets.only(right: kSpace8),
                          width: isCurrent ? 28 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: active
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                          ),
                        );
                      }),
                    ),
                  ),
                  // Skip button (hidden on the last step).
                  if (_currentStep < _stepCount - 1)
                    TextButton(
                      onPressed: _skip,
                      child: const Text('跳过'),
                    ),
                ],
              ),
            ),
            // Step content.
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _currentStep = i),
                children: [
                  _WelcomeStep(),
                  _PermissionsStep(),
                  _ProviderStep(
                    region: _region,
                    onComplete: _complete,
                  ),
                ],
              ),
            ),
            // Bottom navigation button (hidden on the provider step which has
            // its own complete button).
            if (_currentStep < 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    kSpace24, kSpace8, kSpace24, kSpace32),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _next,
                    child: Text(_currentStep == 0 ? '开始陪伴' : '下一步'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Step 1: Welcome — big emoji, emotional copy.
class _WelcomeStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kSpace32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The default smiley emoji as the visual focal point, in a soft orb.
          // M3 Expressive: spring entrance, but fade-only when reduced-motion.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: kMotionSlow,
            curve: reducedMotionEnabled(context) ? kCurveEnter : kCurveSpring,
            builder: (context, value, child) {
              if (reducedMotionEnabled(context)) {
                return Opacity(opacity: value, child: child);
              }
              final scale = 0.6 + 0.4 * value;
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                boxShadow: clayShadows(context, intensity: 1.2),
              ),
              child: Center(
                child: const Text('😊', style: TextStyle(fontSize: 88)),
              ),
            ),
          ),
          const SizedBox(height: kSpace32),
          Text(
            '你好呀',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: kSpace12),
          Text(
            '我是你的情绪伙伴\n我会陪你度过每一天',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 2: Permissions — claymorphism card-based, user taps to grant.
class _PermissionsStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kSpace24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: kSpace24),
          Text('让我感知你的世界',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: kSpace8),
          Text('授予以下权限，让我更好地陪伴你',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: kSpace24),
          _PermissionCard(
            icon: Icons.mic_rounded,
            title: '麦克风',
            subtitle: '让我听到你的声音',
          ),
          const SizedBox(height: kSpace12),
          _PermissionCard(
            icon: Icons.vibration_rounded,
            title: '震动反馈',
            subtitle: '让我用触觉回应你的情绪',
          ),
          const SizedBox(height: kSpace12),
          _PermissionCard(
            icon: Icons.storage_rounded,
            title: '本地存储',
            subtitle: '记住你的伙伴和偏好',
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClayContainer(
      padding:
          const EdgeInsets.symmetric(horizontal: kSpace16, vertical: kSpace12),
      radius: kRadiusLg,
      child: Row(
        children: [
          IconBadge(
            icon: icon,
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: kSpace16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle_rounded,
            color: theme.colorScheme.primary,
            size: 22,
          ),
        ],
      ),
    );
  }
}

/// Step 3: Provider config — shows detected region with emoji, launches the
/// full-page provider selection page.
class _ProviderStep extends ConsumerWidget {
  final RegionInfo? region;
  final VoidCallback onComplete;

  const _ProviderStep({
    required this.region,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: kSpace24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: kSpace24),
          Text('注入大脑',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: kSpace8),
          Text(
            '选择一个 LLM 提供商，让你的伙伴能思考和回应',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: kSpace24),
          // Region detection card with emoji.
          if (region != null && region!.countryCode != null) ...[
            ClayContainer(
              padding: const EdgeInsets.all(kSpace20),
              radius: kRadiusLg,
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.15),
              shadowIntensity: 0.5,
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primaryContainer,
                    ),
                    child: Center(
                      child: Text(region!.emoji ?? '🌍',
                          style: const TextStyle(fontSize: 28)),
                    ),
                  ),
                  const SizedBox(width: kSpace16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('检测到地区',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            )),
                        const SizedBox(height: 2),
                        Text(
                          region!.displayText,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kSpace16),
          ],
          // "选择提供商" button → full-page provider selection.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final configured = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const ProviderSelectionPage(
                        fromOnboarding: true),
                  ),
                );
                if (configured == true) {
                  onComplete();
                }
              },
              icon: const Icon(Icons.psychology_rounded),
              label: const Text('选择提供商'),
            ),
          ),
          const SizedBox(height: kSpace12),
          // Offline-companion entry — explicit, with explanation.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onComplete,
              icon: const Icon(Icons.cloud_off_rounded),
              label: const Text('进入离线陪伴模式'),
            ),
          ),
          const SizedBox(height: kSpace16),
          Text(
            '离线陪伴模式：不配置 LLM，伙伴用本地情绪词库回应你（约 12 种情绪），没有 AI 思考能力。随时可在设置里补配提供商让伙伴"活过来"。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: kSpace24),
        ],
      ),
    );
  }
}
