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
      };
      final resp = EmotionResponse.fromJson(json);
      expect(resp.emoji, '😢');
      expect(resp.color, '#6C9BCF');
      expect(resp.vibration, [500]);
      expect(resp.suggestion, '我在呢，想聊聊吗？');
    });

    test('fromJson handles missing vibration gracefully', () {
      final json = <String, Object?>{
        'emoji': '😊',
        'color': '#FFD93D',
        'suggestion': '开心',
      };
      final resp = EmotionResponse.fromJson(json);
      expect(resp.vibration, isEmpty);
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
    });

    test('toJson round-trips correctly', () {
      const original = EmotionResponse(
        emoji: '🤩',
        color: '#FFD700',
        vibration: [100, 50, 100],
        suggestion: '为你开心！',
      );
      final json = original.toJson();
      final restored = EmotionResponse.fromJson(json);
      expect(restored.emoji, original.emoji);
      expect(restored.color, original.color);
      expect(restored.vibration, original.vibration);
      expect(restored.suggestion, original.suggestion);
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
