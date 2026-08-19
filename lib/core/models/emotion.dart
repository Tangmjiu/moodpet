/// Emotion response contract shared between Friend plugins, the PocketClaw
/// agent and the UI layer.
///
/// A Friend responds to user input with exactly this shape (§6.3): an emoji,
/// a mood colour, an optional haptic pattern and a ≤10-char suggestion. The
/// agent parses an LLM reply into [EmotionResponse]; the keyword fallback in
/// [EmojiMapping] produces the same shape without an LLM.
library;

import 'dart:convert';

/// A single Friend response: emoji + mood colour + haptic pattern + suggestion.
///
/// Immutable and JSON-serialisable. [color] is a `#RRGGBB` hex string as
/// emitted by the agent; parsing to a [dart:ui] [Color] is the UI layer's job
/// (see `color_hex.dart`).
class EmotionResponse {
  final String emoji;
  final String color;
  final List<int> vibration;
  final String suggestion;

  const EmotionResponse({
    required this.emoji,
    required this.color,
    required this.vibration,
    required this.suggestion,
  });

  /// Default idle response used before the first interaction and on errors.
  ///
  /// The colour is the MoodPet brand seed (#E8A87C, warm sand/peach) so the
  /// companion orb is warmly visible on the home screen from first launch —
  /// not an near-invisible grey that makes the partner seem absent until the
  /// user interacts.
  static const EmotionResponse idle = EmotionResponse(
    emoji: '😊',
    color: '#E8A87C',
    vibration: <int>[],
    suggestion: '我在这里陪着你',
  );

  factory EmotionResponse.fromJson(Map<String, Object?> json) {
    final emoji = json['emoji'];
    final color = json['color'];
    final suggestion = json['suggestion'];
    final vib = json['vibration'];
    if (emoji is! String || color is! String || suggestion is! String) {
      throw const FormatException(
          'EmotionResponse requires string emoji/color/suggestion');
    }
    final vibration = (vib is List)
        ? vib.whereType<int>().toList(growable: false)
        : const <int>[];
    return EmotionResponse(
      emoji: emoji,
      color: color,
      vibration: vibration,
      suggestion: suggestion,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'emoji': emoji,
        'color': color,
        'vibration': vibration,
        'suggestion': suggestion,
      };

  @override
  bool operator ==(Object other) =>
      other is EmotionResponse &&
      other.emoji == emoji &&
      other.color == color &&
      _listEq(other.vibration, vibration) &&
      other.suggestion == suggestion;

  @override
  int get hashCode => Object.hash(emoji, color, Object.hashAll(vibration), suggestion);

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// One keyword → response rule inside an [EmojiMapping] (§6.4).
class EmojiRule {
  final List<String> keywords;
  final EmotionResponse response;

  const EmojiRule({required this.keywords, required this.response});

  factory EmojiRule.fromJson(Map<String, Object?> json) {
    final kw = json['keywords'];
    final resp = json['response'];
    if (kw is! List || resp is! Map<String, Object?>) {
      throw const FormatException('EmojiRule requires keywords[] and response{}');
    }
    return EmojiRule(
      keywords: kw.whereType<String>().toList(growable: false),
      response: EmotionResponse.fromJson(resp),
    );
  }
}

/// Optional keyword-based emotion mapping shipped with a Friend plugin (§6.4).
/// Used as a zero-LLM fallback when no provider is configured and as a local
/// fast path the agent may consult before calling the LLM.
class EmojiMapping {
  final List<EmojiRule> rules;
  final EmotionResponse defaultResponse;

  const EmojiMapping({required this.rules, required this.defaultResponse});

  factory EmojiMapping.fromJson(Map<String, Object?> json) {
    final rules = json['rules'];
    final def = json['default'];
    if (rules is! List || def is! Map<String, Object?>) {
      throw const FormatException(
          'EmojiMapping requires rules[] and default{}');
    }
    return EmojiMapping(
      rules: rules
          .whereType<Map<String, Object?>>()
          .map(EmojiRule.fromJson)
          .toList(growable: false),
      defaultResponse: EmotionResponse.fromJson(def),
    );
  }

  /// Resolve a response for [input] by first-keyword match, else [defaultResponse].
  EmotionResponse resolve(String input) {
    for (final rule in rules) {
      for (final kw in rule.keywords) {
        if (input.contains(kw)) return rule.response;
      }
    }
    return defaultResponse;
  }
}

/// Parse an [EmojiMapping] from a raw JSON string (the `emoji_mapping.json`
/// file inside a Friend plugin directory).
EmojiMapping parseEmojiMapping(String jsonSource) {
  final decoded = jsonDecode(jsonSource);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('emoji_mapping.json must be a JSON object');
  }
  return EmojiMapping.fromJson(decoded);
}
