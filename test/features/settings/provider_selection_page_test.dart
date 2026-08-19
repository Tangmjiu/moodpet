import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodpet/core/models/provider_config.dart';
import 'package:moodpet/core/providers.dart';
import 'package:moodpet/features/settings/provider_selection_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The custom provider seeded by the tests below, in persisted form.
const ProviderConfig _custom = ProviderConfig(
  id: 'test-custom',
  name: 'Test Custom LLM',
  baseUrl: 'http://localhost:11434/v1',
  defaultModel: 'llama3',
  apiKey: '',
  iconAsset: '',
  brandColor: '',
  isCustom: true,
);

/// Seed mock SharedPreferences the way the settings UI persists state: one
/// custom provider, a display order putting the custom first, deepseek
/// disabled, and a cached two-model list for kimi.
Map<String, Object> _seedValues() => <String, Object>{
      'moodpet.provider.customProviders':
          jsonEncode(<Map<String, Object?>>[_custom.toJson()]),
      'moodpet.provider.order': <String>['test-custom'],
      'moodpet.provider.enabled.deepseek': false,
      'moodpet.provider.models.kimi': <String>['m1', 'm2'],
    };

Future<SharedPreferences> _pumpPage(WidgetTester tester) async {
  // Tall surface so every card in the lazy list is built (17 providers).
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(_seedValues());
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPrefsProvider.overrideWith((ref) async => prefs),
      ],
      child: const MaterialApp(home: ProviderSelectionPage()),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  testWidgets('merged list shows custom, disabled, model-count and add entry',
      (tester) async {
    await _pumpPage(tester);

    // Custom provider is merged into the list (ordered first per seeded
    // order) with its 自定义 chip and letter avatar.
    expect(find.text('Test Custom LLM'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);
    expect(find.text('T'), findsWidgets); // letter-avatar initials

    // Disabled builtin is greyed out and chips 已停用.
    expect(find.text('DeepSeek'), findsOneWidget);
    expect(find.text('已停用'), findsOneWidget);

    // Cached model list surfaces as an "N 个模型" caption.
    expect(find.text('Moonshot Kimi'), findsOneWidget);
    expect(find.text('2 个模型'), findsOneWidget);

    // The add-custom entry renders below the list.
    expect(find.text('添加自定义提供商'), findsOneWidget);
    expect(find.text('自定义接口地址与协议'), findsOneWidget);

    // fromOnboarding=false: no offline-mode section.
    expect(find.text('进入离线陪伴模式'), findsNothing);
  });

  testWidgets('reorder persists the new id order', (tester) async {
    final prefs = await _pumpPage(tester);

    // Card order per seeded prefs: custom first, then the builtin catalog.
    final customTop = tester.getTopLeft(find.text('Test Custom LLM'));
    final openAiTop = tester.getTopLeft(find.text('OpenAI'));
    expect(customTop.dy, lessThan(openAiTop.dy));

    // Drag the first card's handle past the midpoint of the next card —
    // far enough to swap, not far enough to skip the card after it.
    final handle = find.byIcon(Icons.drag_handle_rounded).first;
    final pitch = openAiTop.dy - customTop.dy;
    await tester.drag(handle, Offset(0, pitch + 60));
    await tester.pumpAndSettle();

    // The full id order (not a subset) is persisted: the custom moved below
    // OpenAI (the exact landing index depends on drag physics).
    final order = prefs.getStringList('moodpet.provider.order');
    expect(order, isNotNull);
    expect(order!.length, kBuiltinProviders.length + 1);
    expect(order.first, 'openai');
    expect(order.indexOf('test-custom'),
        greaterThan(order.indexOf('openai')));

    // The list rebuilt from the persisted order after the invalidation.
    expect(tester.getTopLeft(find.text('OpenAI')).dy,
        lessThan(tester.getTopLeft(find.text('Test Custom LLM')).dy));
  });

  testWidgets('drag is a no-op while a search filter is active',
      (tester) async {
    final prefs = await _pumpPage(tester);

    // Activate the search filter: the drag affordance must disappear.
    await tester.enterText(find.byType(TextField), 'test');
    await tester.pumpAndSettle();
    expect(find.text('Test Custom LLM'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle_rounded), findsNothing);

    // Attempting to drag the card changes nothing in the persisted order.
    await tester.drag(find.text('Test Custom LLM'), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(
      prefs.getStringList('moodpet.provider.order'),
      <String>['test-custom'],
    );
  });
}
