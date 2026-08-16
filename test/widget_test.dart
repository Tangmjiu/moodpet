import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodpet/app.dart';
import 'package:moodpet/core/agent/emotion_rules.dart';

void main() {
  testWidgets('Material 3 主题生效', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMoodPetTheme(),
        home: const Scaffold(body: Text('MoodPet')),
      ),
    );
    final context = tester.element(find.text('MoodPet'));
    expect(Theme.of(context).useMaterial3, isTrue);
    expect(
      Theme.of(context).colorScheme.primary,
      isNot(Colors.transparent),
    );
  });

  test('13 个本地情绪规则齐备', () {
    expect(kLocalEmotionRules.length, 13);
    for (final rule in kLocalEmotionRules) {
      expect(rule.emotion.emoji.isNotEmpty, isTrue);
      expect(
        RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(rule.emotion.colorHex),
        isTrue,
      );
      expect(rule.emotion.vibration, isNotEmpty);
      expect(rule.emotion.suggestion!.runes.length <= 10, isTrue);
    }
  });

  test('本地兜底规则可命中', () {
    final rule = resolveLocalEmotion('今天真的好累，完全没力气');
    expect(rule.name, '累了');
    expect(rule.emotion.emoji, '😩');
  });
}
