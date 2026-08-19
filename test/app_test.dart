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
    // Pump past the splash screen's 2s minimum display duration + the
    // navigation transition. pumpAndSettle will keep pumping through the
    // splash's loading-dots animation until the splash is replaced by
    // the onboarding page (which has no continuous animations).
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // On first run (no onboarding-complete flag), the onboarding page shows
    // the welcome step with the default smiley emoji and a "开始陪伴" button.
    expect(find.text('你好呀'), findsOneWidget);
    expect(find.text('开始陪伴'), findsOneWidget);
  });

  testWidgets('MoodPetApp shows home page when onboarding is complete',
      (tester) async {
    // Pre-set the onboarding-complete flag.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'moodpet.onboardingComplete': true,
      'moodpet.firstRunComplete': true,
    });

    await tester.pumpWidget(
      const ProviderScope(child: MoodPetApp()),
    );
    // Pump past the splash screen's 2s minimum display duration, then pump
    // an extra frame for the post-frame navigation callback to fire and the
    // route transition to render. Use pump() instead of pumpAndSettle()
    // because the home page has a continuous breathing animation that never
    // settles.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));

    // After onboarding, the home page shows the friend name in the top bar
    // and a "点我说话" status label under the mic FAB.
    expect(find.text('点我说话'), findsOneWidget);
  });
}
