import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 提供商 SVG Logo（36dp）。
class ProviderLogo extends StatelessWidget {
  const ProviderLogo({
    required this.assetPath,
    required this.providerName,
    this.size = 36,
    super.key,
  });

  final String assetPath;
  final String providerName;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: SvgPicture.asset(
        assetPath,
        width: size,
        height: size,
        placeholderBuilder: (_) => _fallback(context),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          providerName.characters.first.toUpperCase(),
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.38,
          ),
        ),
      ),
    );
  }
}
