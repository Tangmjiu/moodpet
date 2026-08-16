import 'package:flutter/material.dart';

import '../widgets/emoji_display.dart';
import 'onboarding_page.dart';

/// Step 1 欢迎页。
class Step1WelcomePage extends StatefulWidget {
  const Step1WelcomePage({required this.onNext, super.key});

  final VoidCallback onNext;

  @override
  State<Step1WelcomePage> createState() => _Step1WelcomePageState();
}

class _Step1WelcomePageState extends State<Step1WelcomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _bounce = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: Column(
        children: [
          const Spacer(flex: 3),
          AnimatedBuilder(
            animation: _bounce,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, -18 * _bounce.value),
              child: child,
            ),
            child: const EmojiDisplay(emoji: '😊', fontSize: 120),
          ),
          const SizedBox(height: 32),
          Text(
            '欢迎来到 MoodPet',
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            '一个能听懂你情绪的小精灵',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            '“每一种情绪，都值得被温柔接住。”',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(flex: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: widget.onNext,
              child: const Text('开始配置'),
            ),
          ),
          const SizedBox(height: 20),
          const OnboardingDots(total: 3, current: 0),
        ],
      ),
    );
  }
}
