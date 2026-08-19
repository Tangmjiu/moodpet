import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodpet/core/models/provider_config.dart';
import 'package:moodpet/core/providers.dart';
import 'package:moodpet/core/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Id of the custom provider seeded by the tests below.
const String _customId = 'local-llm';

/// A custom provider entry the way the settings UI would persist it.
ProviderConfig _customProvider() => const ProviderConfig(
      id: _customId,
      name: 'Local LLM',
      baseUrl: 'http://localhost:11434/v1',
      defaultModel: 'llama3',
      apiKey: '',
      iconAsset: '',
      brandColor: '',
      isCustom: true,
    );

/// Persist an enabled custom provider, mark it active and give it an API key.
Future<void> _seedActiveCustom(SettingsStore store) async {
  await store.saveCustomProviders(<ProviderConfig>[_customProvider()]);
  await store.setActiveProviderId(_customId);
  await store.setApiKey(_customId, 'sk-local-test');
}

/// Build a Riverpod container over mock SharedPreferences, optionally seeded
/// through a real [SettingsStore]. First-run is marked complete so the plugin
/// bootstrap is skipped; the plugin manager then only scans the (mocked)
/// application-support directory.
Future<(ProviderContainer, SettingsStore)> _container({
  Future<void> Function(SettingsStore store)? seed,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'moodpet.firstRunComplete': true,
  });
  final prefs = await SharedPreferences.getInstance();
  final store = SettingsStore(prefs);
  if (seed != null) await seed(store);
  final container = ProviderContainer(
    overrides: <Override>[
      sharedPrefsProvider.overrideWith((ref) async => prefs),
    ],
  );
  addTearDown(container.dispose);
  return (container, store);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // agentServiceProvider transitively resolves the plugin manager, which
  // scans a directory under the application-support dir. Point path_provider
  // at a per-test temp directory.
  const MethodChannel pathProviderChannel =
      MethodChannel('plugins.flutter.io/path_provider');
  late Directory supportDir;

  setUp(() {
    supportDir = Directory.systemTemp.createTempSync('moonpet_providers_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      pathProviderChannel,
      (MethodCall call) async => supportDir.path,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
  });

  group('activeProviderConfigProvider', () {
    test('active custom provider resolves with the API key injected',
        () async {
      final (container, _) = await _container(seed: _seedActiveCustom);

      final config = await container.read(activeProviderConfigProvider.future);

      expect(config, isNotNull);
      expect(config!.id, _customId);
      expect(config.isCustom, isTrue);
      // Guard against misleading success: the persisted key must be injected.
      expect(config.apiKey, 'sk-local-test');
      expect(config.isConfigured, isTrue);
    });

    test('disabled active provider resolves to null (disabled-as-absent)',
        () async {
      final (container, _) = await _container(
        seed: (store) async {
          await _seedActiveCustom(store);
          await store.setProviderEnabled(_customId, false);
        },
      );

      final config = await container.read(activeProviderConfigProvider.future);

      expect(config, isNull);
    });

    test('no active provider id resolves to null even when keys are seeded',
        () async {
      final (container, _) = await _container(
        seed: (store) => store.setApiKey('deepseek', 'sk-deepseek-test'),
      );

      final config = await container.read(activeProviderConfigProvider.future);

      expect(config, isNull);
    });

    test('enabled active builtin resolves with the API key injected',
        () async {
      final (container, _) = await _container(
        seed: (store) async {
          await store.setActiveProviderId('deepseek');
          await store.setApiKey('deepseek', 'sk-deepseek-test');
        },
      );

      final config = await container.read(activeProviderConfigProvider.future);

      expect(config, isNotNull);
      expect(config!.id, 'deepseek');
      expect(config.isCustom, isFalse);
      expect(config.apiKey, 'sk-deepseek-test');
      expect(config.isConfigured, isTrue);
    });
  });

  group('agentServiceProvider', () {
    test('agent readiness follows the active provider enabled flag', () async {
      final (container, store) = await _container(seed: _seedActiveCustom);

      final agent = await container.read(agentServiceProvider.future);
      expect(agent.displayName, 'PocketClaw');
      expect(agent.isReady, isTrue);

      // Toggle the flag, then re-resolve through a fresh provider read so the
      // result cannot come from a cached agent instance.
      await store.setProviderEnabled(_customId, false);
      container.invalidate(agentServiceProvider);

      final disabledAgent = await container.read(agentServiceProvider.future);
      expect(disabledAgent.isReady, isFalse);
    });
  });
}
