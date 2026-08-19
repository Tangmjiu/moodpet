import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodpet/core/models/provider_config.dart';
import 'package:moodpet/core/providers.dart';
import 'package:moodpet/core/storage/settings_store.dart';
import 'package:moodpet/core/utils/provider_share_codec.dart';
import 'package:moodpet/features/settings/provider_scan_page.dart';
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

/// A distinct provider the paste tests import — never collides with [_custom].
const ProviderConfig _incoming = ProviderConfig(
  id: 'incoming-id',
  name: '导入测试',
  baseUrl: 'https://example.com/v1',
  defaultModel: 'demo-model',
  apiKey: '',
  iconAsset: '',
  brandColor: '',
  isCustom: true,
);

Map<String, Object> _seedValues() => <String, Object>{
      'moodpet.provider.customProviders':
          jsonEncode(<Map<String, Object?>>[_custom.toJson()]),
      'moodpet.provider.order': <String>['test-custom'],
    };

Future<SharedPreferences> _pumpPage(WidgetTester tester) async {
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

/// Open the import chooser and tap 粘贴导入, leaving the paste dialog open.
Future<void> _openPasteDialog(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.text('粘贴导入'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('import action opens chooser; scan entry hidden off-Android',
      (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
    await tester.pumpAndSettle();

    expect(find.text('导入提供商'), findsOneWidget);
    expect(find.text('粘贴导入'), findsOneWidget);
    // Tests never run on Android, so the camera entry must be hidden.
    expect(find.text('扫码导入'), findsNothing);
  });

  testWidgets('paste flow: valid payload previews and persists', (tester) async {
    final prefs = await _pumpPage(tester);
    await _openPasteDialog(tester);

    // Whitespace padding is tolerated — the codec trims before decoding.
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '  \n${encodeProviderShare(_incoming)}\n ',
    );
    await tester.tap(find.widgetWithText(FilledButton, '导入'));
    await tester.pumpAndSettle();

    // Preview sheet shows the decoded fields and the no-API-key note.
    expect(find.text('确认导入提供商'), findsOneWidget);
    expect(find.text('导入测试'), findsOneWidget);
    expect(find.text('https://example.com/v1'), findsOneWidget);
    expect(find.text('OpenAI 兼容'), findsOneWidget);
    expect(find.text('口令不含 API Key，导入后请自行填写'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '确认导入'));
    await tester.pumpAndSettle();

    // Success snackbar.
    expect(find.text('已导入「导入测试」'), findsOneWidget);

    // Persisted state, not just UI: one extra custom, order appended.
    final store = SettingsStore(prefs);
    final customs = store.loadCustomProviders();
    expect(customs.length, 2);
    final imported = customs.firstWhere((p) => p.name == '导入测试');
    expect(imported.isCustom, isTrue);
    expect(imported.apiKey, isEmpty);
    expect(imported.id, isNot('incoming-id')); // fresh local id on import
    final order = store.loadProviderOrder();
    expect(order, <String>['test-custom', imported.id]);
  });

  testWidgets('paste garbage shows 口令无效 and persists nothing',
      (tester) async {
    final prefs = await _pumpPage(tester);
    await _openPasteDialog(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'hello world',
    );
    await tester.tap(find.widgetWithText(FilledButton, '导入'));
    await tester.pumpAndSettle();

    expect(find.text('口令无效'), findsOneWidget);
    // The paste dialog (titled 粘贴导入) stays open so the user can fix it.
    expect(find.text('粘贴导入'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('确认导入提供商'), findsNothing);

    final store = SettingsStore(prefs);
    expect(store.loadCustomProviders().length, 1);
    expect(store.loadProviderOrder(), <String>['test-custom']);
  });

  testWidgets('duplicate name+baseUrl warns first; 仍要导入 proceeds',
      (tester) async {
    final prefs = await _pumpPage(tester);
    await _openPasteDialog(tester);

    // Same name and base URL as the seeded custom provider.
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      encodeProviderShare(_custom),
    );
    await tester.tap(find.widgetWithText(FilledButton, '导入'));
    await tester.pumpAndSettle();

    // Dedupe warning appears before the preview sheet.
    expect(find.text('已存在相同提供商，仍要导入吗？'), findsOneWidget);
    expect(find.text('确认导入提供商'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, '仍要导入'));
    await tester.pumpAndSettle();
    expect(find.text('确认导入提供商'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '确认导入'));
    await tester.pumpAndSettle();

    final store = SettingsStore(prefs);
    expect(store.loadCustomProviders().length, 2);
    expect(store.loadProviderOrder().length, 2);
    expect(find.text('已导入「Test Custom LLM」'), findsOneWidget);
  });

  test('ProviderScanPage type exists (camera path is device-verified)', () {
    // Headless widget tests cannot run the camera plugin; the type reference
    // pins compilation and the on-device run covers the real scan flow.
    expect(ProviderScanPage, isA<Type>());
  });
}
