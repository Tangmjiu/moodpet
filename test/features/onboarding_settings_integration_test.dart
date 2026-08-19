import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodpet/core/models/provider_config.dart';
import 'package:moodpet/core/providers.dart';
import 'package:moodpet/core/storage/settings_store.dart';
import 'package:moodpet/features/settings/provider_selection_page.dart';
import 'package:moodpet/features/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The custom provider seeded by the tests below, in persisted form. The id
/// is uuid-shaped so the settings test can tell a raw-id fallback apart from
/// a resolved display name.
const ProviderConfig _custom = ProviderConfig(
  id: 'b3f1c2a4-7e2d-4f19-9c8a-0d1e2f3a4b5c',
  name: 'Home Server LLM',
  baseUrl: 'http://192.168.1.20:8080/v1',
  defaultModel: 'home-7b',
  apiKey: '',
  iconAsset: '',
  brandColor: '',
  isCustom: true,
);

Map<String, Object> _seedValues({required bool active}) => <String, Object>{
      'moodpet.provider.customProviders':
          jsonEncode(<Map<String, Object?>>[_custom.toJson()]),
      'moodpet.provider.order': <String>[_custom.id],
      if (active) 'moodpet.provider.activeId': _custom.id,
    };

Future<void> _pump(WidgetTester tester, Widget home,
    {required Map<String, Object> seed, required Size surface}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPrefsProvider.overrideWith((ref) async => prefs),
      ],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'onboarding selection lists the custom provider above the '
      'offline-skip section', (tester) async {
    await _pump(
      tester,
      const ProviderSelectionPage(fromOnboarding: true),
      seed: _seedValues(active: false),
      // Tall surface so the list, the add-custom card and the offline-skip
      // section all lay out within the viewport.
      surface: const Size(1080, 3200),
    );

    // Custom card from the merged list: name plus its 自定义 chip.
    expect(find.text('Home Server LLM'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);

    // The offline-skip section is intact in onboarding mode, below the card:
    // both the entry button and its advisory copy render.
    expect(find.text('进入离线陪伴模式'), findsOneWidget);
    expect(find.textContaining('不配置 LLM 也能用'), findsOneWidget);
    final nameY = tester.getTopLeft(find.text('Home Server LLM')).dy;
    final skipY = tester.getTopLeft(find.text('进入离线陪伴模式')).dy;
    expect(nameY, lessThan(skipY));
  });

  testWidgets(
      'settings provider row shows the custom provider name, not its id',
      (tester) async {
    await _pump(
      tester,
      const SettingsPage(),
      seed: _seedValues(active: true),
      surface: const Size(1080, 2400),
    );

    // The provider row resolves the custom provider through the registry…
    expect(find.text('Home Server LLM'), findsOneWidget);
    // …and never falls back to the raw uuid.
    expect(find.text(_custom.id), findsNothing);
  });

  testWidgets(
      'settings name refreshes when the custom provider is created after '
      'the page was opened', (tester) async {
    // Seed only the active id: the settings page is opened before the custom
    // provider it points at has been created.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'moodpet.provider.activeId': _custom.id,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPrefsProvider.overrideWith((ref) async => prefs),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    // The id resolves to nothing yet, so the row falls back to the raw uuid.
    expect(find.text(_custom.id), findsOneWidget);
    expect(find.text('Home Server LLM'), findsNothing);

    // Persist the new provider (as the creation flow does), then invalidate
    // the registry the row watches; the registry re-reads storage on every
    // resolution.
    await SettingsStore(prefs).saveCustomProviders(<ProviderConfig>[_custom]);
    container.invalidate(providerRegistryProvider);
    await tester.pumpAndSettle();

    // The row now shows the resolved display name; the raw uuid is gone.
    expect(find.text('Home Server LLM'), findsOneWidget);
    expect(find.text(_custom.id), findsNothing);
  });
}
