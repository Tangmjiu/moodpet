import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:moodpet/core/agent/connection_tester.dart';
import 'package:moodpet/core/agent/models_client.dart';
import 'package:moodpet/core/models/provider_config.dart';
import 'package:moodpet/core/providers.dart';
import 'package:moodpet/core/storage/settings_store.dart';
import 'package:moodpet/features/settings/provider_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default stub: tests must never touch the network unless they inject a
/// fake through the page's seams.
Future<ModelsResult> _noNetworkFetch({
  required ProviderConfig provider,
  http.Client? client,
}) async =>
    const ModelsResult.fail('no network in tests', 0);

Future<ConnectionTestResult> _noNetworkTest({
  required ProviderConfig provider,
  http.Client? client,
}) async =>
    const ConnectionTestResult(
      ok: false,
      statusCode: 0,
      error: 'no network in tests',
      latencyMs: 1,
    );

/// A fresh create-mode draft the way the selection page mints it.
ProviderConfig _draft() => const ProviderConfig(
      id: 'draft-custom-1',
      name: '',
      baseUrl: '',
      defaultModel: '',
      apiKey: '',
      iconAsset: '',
      brandColor: '',
      isCustom: true,
    );

/// An already-saved custom provider (edit mode).
ProviderConfig _existingCustom() => const ProviderConfig(
      id: 'my-local',
      name: 'My LLM',
      baseUrl: 'http://localhost:11434/v1',
      defaultModel: 'llama3',
      apiKey: '',
      iconAsset: '',
      brandColor: '',
      isCustom: true,
    );

ProviderConfig _deepseek() => builtinProviderById('deepseek')!;

/// Pump an opener page that pushes [ProviderDetailPage]; the push result is
/// forwarded to [onPopped] so tests can assert the `pop(true)` contract.
/// Returns the SettingsStore over the same mock prefs the page uses.
Future<SettingsStore> _pumpDetailPage(
  WidgetTester tester, {
  required ProviderConfig provider,
  bool isNewCustom = false,
  ModelFetcher modelFetcher = _noNetworkFetch,
  ConnectionTester connectionTester = _noNetworkTest,
  Map<String, Object> seed = const <String, Object>{},
  void Function(bool? result)? onPopped,
}) async {
  // Tall surface so the whole config tab and model list are laid out.
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  final store = SettingsStore(prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPrefsProvider.overrideWith((ref) async => prefs),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => ProviderDetailPage(
                        provider: provider,
                        isNewCustom: isNewCustom,
                        modelFetcher: modelFetcher,
                        connectionTester: connectionTester,
                      ),
                    ),
                  );
                  onPopped?.call(result);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets(
      'create mode rejects invalid input with inline errors and persists '
      'nothing', (tester) async {
    var popped = false;
    final store = await _pumpDetailPage(
      tester,
      provider: _draft(),
      isNewCustom: true,
      onPopped: (_) => popped = true,
    );

    // Name and default model left empty; base URL is not a URL at all.
    await tester.enterText(
        find.byKey(const ValueKey('customBaseUrlField')), 'not-a-url');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('saveButton')));
    await tester.pumpAndSettle();

    expect(find.text('请输入名称'), findsOneWidget);
    expect(find.text('请输入合法的 http(s) 地址'), findsOneWidget);
    expect(find.text('请输入默认模型'), findsOneWidget);
    // Guard against misleading success: nothing reached storage.
    expect(store.loadCustomProviders(), isEmpty);
    expect(store.loadProviderOrder(), isEmpty);
    expect(store.activeProviderId, isNull);
    expect(popped, isFalse);
  });

  testWidgets(
      'valid custom create persists the provider with a normalized baseUrl, '
      'appends the order and pops true', (tester) async {
    bool? popped;
    final store = await _pumpDetailPage(
      tester,
      provider: _draft(),
      isNewCustom: true,
      onPopped: (r) => popped = r,
    );

    await tester.enterText(
        find.byKey(const ValueKey('customNameField')), 'My LLM');
    await tester.enterText(find.byKey(const ValueKey('customBaseUrlField')),
        'http://localhost:11434/v1/');
    await tester.enterText(
        find.byKey(const ValueKey('customDefaultModelField')), 'llama3');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('saveButton')));
    await tester.pumpAndSettle();

    final customs = store.loadCustomProviders();
    expect(customs, hasLength(1));
    expect(customs.single.id, 'draft-custom-1');
    expect(customs.single.name, 'My LLM');
    // The trailing slash is stripped so the chat path never doubles segments.
    expect(customs.single.baseUrl, 'http://localhost:11434/v1');
    expect(customs.single.defaultModel, 'llama3');
    expect(customs.single.isCustom, isTrue);
    expect(store.loadProviderOrder(), contains('draft-custom-1'));
    expect(store.activeProviderId, 'draft-custom-1');
    expect(store.isProviderEnabled('draft-custom-1'), isTrue);
    expect(popped, isTrue);
  });

  testWidgets('connection tester reports success with latency', (tester) async {
    await _pumpDetailPage(
      tester,
      provider: _deepseek(),
      connectionTester: ({
        required ProviderConfig provider,
        http.Client? client,
      }) async =>
          const ConnectionTestResult(ok: true, statusCode: 200, latencyMs: 42),
    );

    await tester.tap(find.byKey(const ValueKey('testConnectionButton')));
    await tester.pumpAndSettle();

    expect(find.text('连接成功 · 42ms'), findsOneWidget);
  });

  testWidgets(
      'models tab fetches and merges new models; dismissing the active model '
      'clears the override', (tester) async {
    const id = 'deepseek';
    final store = await _pumpDetailPage(
      tester,
      provider: _deepseek(),
      seed: const <String, Object>{
        'moodpet.provider.models.$id': <String>['mB'],
        'moodpet.provider.modelOverride.$id': 'mB',
      },
      modelFetcher: ({
        required ProviderConfig provider,
        http.Client? client,
      }) async =>
          const ModelsResult.ok(<String>['mC', 'mD'], 200),
    );

    await tester.tap(find.text('模型'));
    await tester.pumpAndSettle();

    // The seeded model row shows the active badge; the default row is locked.
    expect(find.text('mB'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
    expect(find.text('deepseek-chat'), findsOneWidget);
    expect(find.text('默认'), findsOneWidget);

    // Fetch two new models and merge both through the picker sheet.
    await tester.tap(find.byKey(const ValueKey('fetchModelsButton')));
    await tester.pumpAndSettle();
    expect(find.text('mC'), findsOneWidget);
    expect(find.text('mD'), findsOneWidget);
    await tester.tap(find.text('mC'));
    await tester.tap(find.text('mD'));
    await tester.pump();
    await tester.tap(find.text('添加所选 (2)'));
    await tester.pumpAndSettle();
    expect(store.modelsFor(id), containsAll(<String>['mB', 'mC', 'mD']));

    // Dismiss the ACTIVE model: the override must be cleared so the active
    // model falls back to the default instead of dangling.
    await tester.drag(
        find.byKey(const ValueKey('model-row-mB')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(store.modelsFor(id), isNot(contains('mB')));
    expect(store.modelOverrideFor(id), isNull);
    // The 当前 badge has moved back to the default row.
    expect(find.text('当前'), findsOneWidget);
  });

  testWidgets('builtin mode is read-only and save requires an API key',
      (tester) async {
    await _pumpDetailPage(tester, provider: _deepseek());

    // None of the custom editable fields are offered for a builtin.
    expect(find.byKey(const ValueKey('customNameField')), findsNothing);
    expect(find.byKey(const ValueKey('customBaseUrlField')), findsNothing);
    expect(find.byKey(const ValueKey('customDefaultModelField')), findsNothing);
    // Endpoint details render as read-only text instead.
    expect(find.text('DeepSeek'), findsWidgets);
    expect(find.text('https://api.deepseek.com'), findsOneWidget);

    FilledButton saveButton() =>
        tester.widget<FilledButton>(find.byKey(const ValueKey('saveButton')));
    // Save stays disabled while the key is empty and the provider is still
    // enabled.
    expect(saveButton().onPressed, isNull);

    // Toggling the switch off expresses the intent to disable, which must be
    // saveable even without a key.
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(saveButton().onPressed, isNotNull);
    // Toggle back on: empty key disables save again.
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(saveButton().onPressed, isNull);

    await tester.enterText(
        find.byKey(const ValueKey('apiKeyField')), 'sk-test');
    await tester.pump();
    expect(saveButton().onPressed, isNotNull);
  });

  testWidgets(
      'deleting the active custom provider clears its state, prunes the order '
      'and clears the active id', (tester) async {
    final custom = _existingCustom();
    bool? popped;
    final store = await _pumpDetailPage(
      tester,
      provider: custom.copyWith(apiKey: 'sk-local', enabled: true),
      seed: <String, Object>{
        'moodpet.provider.customProviders':
            jsonEncode(<Object?>[custom.toJson()]),
        'moodpet.provider.order': <String>['deepseek', custom.id],
        'moodpet.provider.activeId': custom.id,
        'moodpet.provider.apiKey.${custom.id}': 'sk-local',
        'moodpet.provider.models.${custom.id}': <String>['llama3-8b'],
      },
      onPopped: (r) => popped = r,
    );

    await tester.tap(find.byKey(const ValueKey('deleteProviderButton')));
    await tester.pumpAndSettle();
    expect(find.text('删除后其 Key 与模型配置将一并清除'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(store.loadCustomProviders(), isEmpty);
    expect(store.loadProviderOrder(), isNot(contains(custom.id)));
    expect(store.activeProviderId, isNull);
    // Per-provider state is gone: removeProviderState ran before the entry
    // was removed from the custom list (the guard requires that order).
    expect(store.apiKeyFor(custom.id), isEmpty);
    expect(store.modelsFor(custom.id), isEmpty);
    expect(popped, isTrue);
  });

  testWidgets('manual model add rejects duplicates with a snackbar',
      (tester) async {
    final store = await _pumpDetailPage(
      tester,
      provider: _deepseek(),
      seed: const <String, Object>{
        'moodpet.provider.models.deepseek': <String>['mB'],
      },
    );

    await tester.tap(find.text('模型'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('manualModelField')), 'mB');
    await tester.tap(find.byKey(const ValueKey('manualModelAddButton')));
    await tester.pumpAndSettle();

    expect(find.text('已存在'), findsOneWidget);
    expect(store.modelsFor('deepseek'), <String>['mB']);
  });
}
