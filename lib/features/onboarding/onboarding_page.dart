import 'package:flutter/material.dart';

import '../home/home_page.dart';
import 'step1_welcome.dart';
import 'step2_permissions.dart';
import 'step3_provider.dart';

/// 首次启动三步配置流程。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  int _current = 0;

  void _goNext() {
    if (_current >= 2) return;
    setState(() => _current++);
    _controller.animateToPage(
      _current,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  void _finish() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomePage()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _controller,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            Step1WelcomePage(onNext: _goNext),
            Step2PermissionsPage(onNext: _goNext),
            Step3ProviderPage(onFinish: _finish),
          ],
        ),
      ),
    );
  }
}

/// ● ● ○ 圆点指示器。
class OnboardingDots extends StatelessWidget {
  const OnboardingDots({required this.total, required this.current, super.key});

  final int total;
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (index) {
        final selected = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: selected ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.outlineVariant,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
