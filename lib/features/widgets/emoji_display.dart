import 'package:flutter/material.dart';

/// 宠物 Emoji 展示（仅用于宠物本体区域）。
class EmojiDisplay extends StatelessWidget {
  const EmojiDisplay({
    required this.emoji,
    this.fontSize = 120,
    this.semanticsLabel,
    super.key,
  });

  final String emoji;
  final double fontSize;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel ?? '宠物表情',
      child: Text(
        emoji,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.15,
          fontFamilyFallback: const ['Noto Color Emoji', 'Apple Color Emoji'],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
