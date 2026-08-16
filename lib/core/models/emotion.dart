import 'package:flutter/material.dart';

/// 一次情绪分析的三重响应（Emoji + 背景色 + 震动模式）。
class Emotion {
  const Emotion({
    required this.emoji,
    required this.colorHex,
    required this.vibration,
    this.suggestion,
  });

  /// 宠物展示 Emoji，如 "😊"。
  final String emoji;

  /// 背景色，6 位十六进制，如 "#FFD93D"。
  final String colorHex;

  /// 震动毫秒数组，如 [100, 80, 100, 80, 100]。
  final List<int> vibration;

  /// 10 字以内的简短建议。
  final String? suggestion;

  Color get color {
    final hex = colorHex.replaceFirst('#', '');
    final value = int.tryParse(hex, radix: 16) ?? 0xFFD93D;
    return Color(0xFF000000 | value);
  }

  Emotion copyWith({
    String? emoji,
    String? colorHex,
    List<int>? vibration,
    String? suggestion,
  }) {
    return Emotion(
      emoji: emoji ?? this.emoji,
      colorHex: colorHex ?? this.colorHex,
      vibration: vibration ?? this.vibration,
      suggestion: suggestion ?? this.suggestion,
    );
  }

  factory Emotion.fromJson(Map<String, dynamic> json) {
    final vibrationRaw = json['vibration'];
    final vibration = <int>[];
    if (vibrationRaw is List) {
      for (final item in vibrationRaw) {
        vibration.add(item is num ? item.toInt() : 0);
      }
    }
    return Emotion(
      emoji: (json['emoji'] as String?) ?? '😊',
      colorHex: (json['color'] as String?) ?? '#FFD93D',
      vibration: vibration,
      suggestion: json['suggestion'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'emoji': emoji,
        'color': colorHex,
        'vibration': vibration,
        'suggestion': suggestion,
      };

  @override
  String toString() =>
      'Emotion(emoji: $emoji, colorHex: $colorHex, vibration: $vibration, '
      'suggestion: $suggestion)';
}
