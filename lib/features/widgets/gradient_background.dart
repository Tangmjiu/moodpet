import 'package:flutter/material.dart';

/// 情绪背景：基于当前情绪色的柔和渐变，随情绪平滑过渡。
class GradientBackground extends StatelessWidget {
  const GradientBackground({
    required this.color,
    required this.child,
    this.duration = const Duration(milliseconds: 800),
    super.key,
  });

  final Color color;
  final Widget child;
  final Duration duration;

  Color _lighten(Color source, [double amount = 0.35]) =>
      Color.lerp(source, Colors.white, amount)!;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _lighten(color, 0.55),
            _lighten(color, 0.12),
            color.withValues(alpha: 0.85),
          ],
        ),
      ),
      child: child,
    );
  }
}
