import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodpet/core/models/emotion.dart';

void main() {
  group('EmotionResponse', () {
    test('fromJson parses all fields correctly', () {
      final json = <String, Object?>{
        'emoji': '😢',
        'color': '#6C9BCF',
        'vibration': [500],
        'suggestion': '我在呢，想聊聊吗？',
        'message': '看你不太开心，发生什么事了？如果想说说，我都在这里听着。',
      };
      final resp = EmotionResponse.fromJson(json);
      expect(resp.emoji, '😢');
      expect(resp.color, '#6C9BCF');
      expect(resp.vibration, [500]);
      expect(resp.suggestion, '我在呢，想聊聊吗？');
      expect(resp.message, '看你不太开心，发生什么事了？如果想说说，我都在这里听着。');
      expect(resp.displayText, resp.message);
    });

    test('fromJson handles missing vibration gracefully', () {
      final json = <String, Object?>{
        'emoji': '😊',
        'color': '#FFD93D',
        'suggestion': '开心',
      };
      final resp = EmotionResponse.fromJson(json);
      expect(resp.vibration, isEmpty);
      expect(resp.message, isNull);
      expect(resp.displayText, '开心');
    });

    test('fromJson treats non-string message as null', () {
      final resp = EmotionResponse.fromJson(<String, Object?>{
        'emoji': '😊',
        'color': '#FFD93D',
        'suggestion': '开心',
        'message': 123,
      });
      expect(resp.message, isNull);
    });

    test('fromJson throws on missing required string fields', () {
      expect(
        () => EmotionResponse.fromJson(<String, Object?>{
          'emoji': '😊',
          // missing color and suggestion
        }),
        throwsFormatException,
      );
    });

    test('idle is a valid default response', () {
      expect(EmotionResponse.idle.emoji, '😊');
      expect(EmotionResponse.idle.color, '#E8A87C');
      expect(EmotionResponse.idle.vibration, isEmpty);
      expect(EmotionResponse.idle.message, isNotNull);
      expect(EmotionResponse.idle.displayText, EmotionResponse.idle.message);
    });

    test('toJson round-trips correctly with message', () {
      const original = EmotionResponse(
        emoji: '🤩',
        color: '#FFD700',
        vibration: [100, 50, 100],
        suggestion: '为你开心！',
        message: '太棒了！看到你这么开心我也跟着高兴起来了。',
      );
      final json = original.toJson();
      expect(json.containsKey('message'), isTrue);
      final restored = EmotionResponse.fromJson(json);
      expect(restored.emoji, original.emoji);
      expect(restored.color, original.color);
      expect(restored.vibration, original.vibration);
      expect(restored.suggestion, original.suggestion);
      expect(restored.message, original.message);
    });

    test('toJson omits message when null', () {
      const original = EmotionResponse(
        emoji: '🤩',
        color: '#FFD700',
        vibration: [100],
        suggestion: '为你开心！',
      );
      expect(original.toJson().containsKey('message'), isFalse);
    });

    test('copyWith attaches message to keyword-fallback response', () {
      const fallback = EmotionResponse(
        emoji: '😢',
        color: '#6C9BCF',
        vibration: [500],
        suggestion: '我在呢',
      );
      final withMessage = fallback.copyWith(message: fallback.suggestion);
      expect(withMessage.message, '我在呢');
      expect(withMessage.displayText, '我在呢');
      expect(withMessage.emoji, fallback.emoji);
      // copyWith without message arg preserves original (null) message.
      final unchanged = fallback.copyWith();
      expect(unchanged.message, isNull);
    });
  });

  group('EmojiMapping', () {
    test('resolve matches first keyword hit', () {
      final mapping = EmojiMapping.fromJson({
        'rules': [
          {
            'keywords': ['开心', '高兴'],
            'response': {
              'emoji': '😊',
              'color': '#FFD93D',
              'vibration': [100],
              'suggestion': '开心',
            },
          },
          {
            'keywords': ['难过'],
            'response': {
              'emoji': '😢',
              'color': '#6C9BCF',
              'vibration': [500],
              'suggestion': '难过',
            },
          },
        ],
        'default': {
          'emoji': '😊',
          'color': '#9E9E9E',
          'vibration': [200],
          'suggestion': '默认',
        },
      });
      expect(mapping.resolve('我今天很开心').emoji, '😊');
      expect(mapping.resolve('有点难过').emoji, '😢');
      expect(mapping.resolve('随便说点什么').emoji, '😊');
      expect(mapping.resolve('随便说点什么').suggestion, '默认');
    });

    test('parseEmojiMapping parses valid JSON string', () {
      final raw = jsonEncode({
        'rules': [],
        'default': {
          'emoji': '😊',
          'color': '#9E9E9E',
          'vibration': [],
          'suggestion': '我在这里',
        },
      });
      final mapping = parseEmojiMapping(raw);
      expect(mapping.rules, isEmpty);
      expect(mapping.defaultResponse.emoji, '😊');
    });

    test('parseEmojiMapping throws on invalid JSON', () {
      expect(() => parseEmojiMapping('not json'), throwsFormatException);
      expect(() => parseEmojiMapping('[]'), throwsFormatException);
    });
  });
}
