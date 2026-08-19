import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moodpet/app.dart';

void main() {
  setUp(() {
    // Mock SharedPreferences so the providers can resolve in tests.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('MoodPetApp renders onboarding on first run', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MoodPetApp()),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('你好呀'), findsOneWidget);
    expect(find.text('开始陪伴'), findsOneWidget);
  });

  testWidgets('MoodPetApp shows home page when onboarding is complete',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'moodpet.onboardingComplete': true,
      'moodpet.firstRunComplete': true,
    });

    await tester.pumpWidget(
      const ProviderScope(child: MoodPetApp()),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('点我说话'), findsOneWidget);
  });
}
