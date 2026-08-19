import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodpet/core/models/provider_config.dart';
import 'package:moodpet/core/providers.dart';
import 'package:moodpet/core/storage/settings_store.dart';
import 'package:moodpet/features/settings/provider_detail_page.dart';
import 'package:moodpet/features/settings/provider_selection_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pump the selection page over mock prefs with a hand-held container, so a
/// test can invalidate providers after seeding storage directly. Returns the
/// container, a SettingsStore over the same prefs, and the raw prefs.
Future<({ProviderContainer container, SettingsStore store, SharedPreferences prefs})>
    _pumpSelectionPage(
  WidgetTester tester, {
  Map<String, Object> seed = const <String, Object>{},
}) async {
  // Tall surface so the full builtin list, the trailing add-custom card and
  // the detail page's config form all lay out within the viewport.
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(seed);
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
      child: const MaterialApp(home: ProviderSelectionPage()),
    ),
  );
  await tester.pumpAndSettle();
  return (container: container, store: SettingsStore(prefs), prefs: prefs);
}

/// Drive the full create flow from the selection page: add card → detail
/// page in create mode → fill the form → save → back at the selection page.
/// Returns the new provider's id read back from persisted state.
Future<String> _createCustomViaUi(
  WidgetTester tester,
  SettingsStore store, {
  required String name,
  required String baseUrl,
  required String defaultModel,
  String? apiKey,
}) async {
  await tester.tap(find.text('添加自定义提供商'));
  await tester.pumpAndSettle();
  // Create mode: editable custom fields, no delete or share affordances.
  expect(find.byType(ProviderDetailPage), findsOneWidget);
  expect(find.byKey(const ValueKey('deleteProviderButton')), findsNothing);
  expect(find.byKey(const ValueKey('shareProviderButton')), findsNothing);

  await tester.enterText(find.byKey(const ValueKey('customNameField')), name);
  await tester.enterText(
      find.byKey(const ValueKey('customBaseUrlField')), baseUrl);
  await tester.enterText(
      find.byKey(const ValueKey('customDefaultModelField')), defaultModel);
  if (apiKey != null) {
    await tester.enterText(find.byKey(const ValueKey('apiKeyField')), apiKey);
  }
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('saveButton')));
  await tester.pumpAndSettle();
  // Save pops true → back at the selection page.
  expect(find.byType(ProviderSelectionPage), findsOneWidget);
  return store.loadCustomProviders().singleWhere((p) => p.name == name).id;
}

/// Tap a provider card on the selection page and wait for the detail page.
Future<void> _openProviderCard(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
  expect(find.byType(ProviderDetailPage), findsOneWidget);
}

/// The current text of a detail-page field.
String _fieldValue(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

/// End-to-end create/edit/delete wiring of custom providers across the
/// selection page and the detail page, driven entirely through the UI.
/// Persistence is asserted on raw prefs and the SettingsStore, never just
/// on UI text.
void main() {
  testWidgets(
      'create flow persists the custom provider, appends it to the order '
      'and lists it with the custom chip', (tester) async {
    final h = await _pumpSelectionPage(
      tester,
      // Seed a partial order so "appended last" is observable.
      seed: const <String, Object>{
        'moodpet.provider.order': <String>['openai', 'deepseek'],
      },
    );

    final id = await _createCustomViaUi(
      tester,
      h.store,
      name: 'Flow LLM',
      baseUrl: 'http://192.168.1.10:8080/v1',
      defaultModel: 'flow-7b',
      apiKey: 'sk-flow',
    );

    // UI: the new card is listed with its 自定义 chip.
    expect(find.text('Flow LLM'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);

    // Persisted state: customs JSON, order appended last, active id, key.
    final customs = h.store.loadCustomProviders();
    expect(customs, hasLength(1));
    expect(customs.single.id, id);
    expect(customs.single.baseUrl, 'http://192.168.1.10:8080/v1');
    expect(customs.single.defaultModel, 'flow-7b');
    expect(customs.single.isCustom, isTrue);
    expect(h.store.loadProviderOrder(), <String>['openai', 'deepseek', id]);
    expect(h.store.activeProviderId, id);
    expect(h.store.apiKeyFor(id), 'sk-flow');
    // Raw prefs: the API key never enters the provider JSON.
    final rawCustoms = h.prefs.getString('moodpet.provider.customProviders');
    expect(rawCustoms, contains('Flow LLM'));
    expect(rawCustoms, isNot(contains('sk-flow')));
    expect(h.prefs.getStringList('moodpet.provider.order'),
        <String>['openai', 'deepseek', id]);

    // providerListProvider merges the custom and honours the order.
    final listed = await h.container.read(providerListProvider.future);
    expect(listed.map((p) => p.id).take(3),
        <String>['openai', 'deepseek', id]);
    expect(listed[2].name, 'Flow LLM');
    expect(listed[2].isCustom, isTrue);
  });

  testWidgets(
      'edit flow pre-populates the fields from the overlaid config and '
      'persists the update', (tester) async {
    final h = await _pumpSelectionPage(tester);
    final id = await _createCustomViaUi(
      tester,
      h.store,
      name: 'Flow LLM',
      baseUrl: 'http://192.168.1.10:8080/v1',
      defaultModel: 'flow-7b',
      apiKey: 'sk-flow',
    );

    // Tap the custom card → edit mode with every field pre-populated.
    await _openProviderCard(tester, 'Flow LLM');
    expect(_fieldValue(tester, 'customNameField'), 'Flow LLM');
    expect(_fieldValue(tester, 'customBaseUrlField'),
        'http://192.168.1.10:8080/v1');
    expect(_fieldValue(tester, 'customDefaultModelField'), 'flow-7b');
    expect(_fieldValue(tester, 'customModelsEndpointField'), '/models');
    expect(_fieldValue(tester, 'customChatPathField'), '/chat/completions');
    expect(_fieldValue(tester, 'apiKeyField'), 'sk-flow');
    // Edit mode (not create): the delete affordance is present.
    expect(find.byKey(const ValueKey('deleteProviderButton')), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('customDefaultModelField')), 'flow-13b');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('saveButton')));
    await tester.pumpAndSettle();
    expect(find.byType(ProviderSelectionPage), findsOneWidget);

    // Reload: the update landed; still exactly one custom provider.
    final customs = h.store.loadCustomProviders();
    expect(customs, hasLength(1));
    expect(customs.single.id, id);
    expect(customs.single.defaultModel, 'flow-13b');
    expect(h.prefs.getString('moodpet.provider.customProviders'),
        contains('flow-13b'));
    // The selection card shows the new effective model.
    expect(find.text('flow-13b'), findsOneWidget);
  });

  testWidgets(
      'deleting the ACTIVE custom provider clears its per-provider state, '
      'prunes the order and clears the active id', (tester) async {
    final h = await _pumpSelectionPage(tester);
    final id = await _createCustomViaUi(
      tester,
      h.store,
      name: 'Flow LLM',
      baseUrl: 'http://192.168.1.10:8080/v1',
      defaultModel: 'flow-7b',
    );
    expect(h.store.activeProviderId, id);

    // Seed per-provider state so the removal is observable, not vacuous.
    await h.store.setApiKey(id, 'sk-flow-secret');
    await h.store.setModels(id, <String>['flow-7b-32k']);

    await _openProviderCard(tester, 'Flow LLM');
    await tester.tap(find.byKey(const ValueKey('deleteProviderButton')));
    await tester.pumpAndSettle();
    expect(find.text('删除后其 Key 与模型配置将一并清除'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // Back at the selection page; the card is gone.
    expect(find.byType(ProviderSelectionPage), findsOneWidget);
    expect(find.text('Flow LLM'), findsNothing);

    // Persisted: customs JSON shrinks, order pruned, per-id keys removed,
    // active id cleared because the deleted provider was the active one.
    expect(h.store.loadCustomProviders(), isEmpty);
    expect(h.store.loadProviderOrder(), isEmpty);
    expect(h.store.activeProviderId, isNull);
    expect(h.store.apiKeyFor(id), isEmpty);
    expect(h.store.modelsFor(id), isEmpty);
    // Raw prefs: the per-id keys are physically removed.
    expect(h.prefs.getString('moodpet.provider.apiKey.$id'), isNull);
    expect(h.prefs.getStringList('moodpet.provider.models.$id'), isNull);
    expect(h.prefs.getString('moodpet.provider.activeId'), isNull);

    // The active config resolves to null → home falls back to offline mode.
    final active = await h.container.read(activeProviderConfigProvider.future);
    expect(active, isNull);
  });

  testWidgets('backing out of create mode without saving persists nothing',
      (tester) async {
    final h = await _pumpSelectionPage(tester);

    await tester.tap(find.text('添加自定义提供商'));
    await tester.pumpAndSettle();
    expect(find.byType(ProviderDetailPage), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('customNameField')), 'Ghost LLM');
    await tester.pump();
    // Back via the AppBar back button — never saved.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ProviderSelectionPage), findsOneWidget);

    expect(h.store.loadCustomProviders(), isEmpty);
    expect(h.store.loadProviderOrder(), isEmpty);
    expect(h.store.activeProviderId, isNull);
    expect(h.prefs.getString('moodpet.provider.customProviders'), isNull);
  });

  testWidgets(
      'deleting a NON-active custom provider keeps the active id on the '
      'remaining provider', (tester) async {
    final h = await _pumpSelectionPage(tester);
    final idA = await _createCustomViaUi(
      tester,
      h.store,
      name: 'Flow A',
      baseUrl: 'http://192.168.1.10:8080/v1',
      defaultModel: 'flow-a',
    );
    expect(h.store.activeProviderId, idA);

    // Seed a second custom provider directly; B is never made active.
    const second = ProviderConfig(
      id: 'flow-b',
      name: 'Flow B',
      baseUrl: 'http://192.168.1.11:8080/v1',
      defaultModel: 'flow-b',
      apiKey: '',
      iconAsset: '',
      brandColor: '',
      isCustom: true,
    );
    await h.store.saveCustomProviders(
        <ProviderConfig>[...h.store.loadCustomProviders(), second]);
    await h.store.saveProviderOrder(
        <String>[...h.store.loadProviderOrder(), second.id]);
    h.container.invalidate(providerListProvider);
    await tester.pumpAndSettle();
    expect(find.text('Flow B'), findsOneWidget);

    // Delete B: the active id must stay on A.
    await _openProviderCard(tester, 'Flow B');
    await tester.tap(find.byKey(const ValueKey('deleteProviderButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('Flow B'), findsNothing);
    expect(find.text('Flow A'), findsOneWidget);
    expect(h.store.loadCustomProviders().map((p) => p.id), <String>[idA]);
    expect(h.store.loadProviderOrder(), <String>[idA]);
    expect(h.store.activeProviderId, idA);
    expect(h.prefs.getString('moodpet.provider.activeId'), idA);
  });
}
