import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:moodpet/core/agent/connection_tester.dart';
import 'package:moodpet/core/agent/models_client.dart';
import 'package:moodpet/core/models/provider_config.dart';
import 'package:moodpet/core/providers.dart';
import 'package:moodpet/core/utils/provider_share_codec.dart';
import 'package:moodpet/features/settings/provider_detail_page.dart';
import 'package:qr_flutter/qr_flutter.dart';
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

/// A builtin carrying a secret key, to prove the share surface never leaks
/// key material into the payload.
ProviderConfig _deepseekWithKey() =>
    builtinProviderById('deepseek')!.copyWith(apiKey: 'sk-secret-share-test');

/// In-memory clipboard behind the 'flutter/platform' channel; the test
/// binding ships no clipboard handler of its own.
String? _clipboardText;

void _mockClipboard() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    switch (call.method) {
      case 'Clipboard.setData':
        _clipboardText =
            (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
        return null;
      case 'Clipboard.getData':
        final text = _clipboardText;
        if (text == null) return null;
        return <String, dynamic>{'text': text};
      default:
        return null;
    }
  });
  addTearDown(() {
    _clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
}

/// Pump [ProviderDetailPage] directly as the home route over mock prefs.
Future<void> _pumpDetailPage(
  WidgetTester tester, {
  required ProviderConfig provider,
  bool isNewCustom = false,
}) async {
  // Tall surface so the config tab and the share sheet lay out fully.
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPrefsProvider.overrideWith((ref) async => prefs),
      ],
      child: MaterialApp(
        home: ProviderDetailPage(
          provider: provider,
          isNewCustom: isNewCustom,
          modelFetcher: _noNetworkFetch,
          connectionTester: _noNetworkTest,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'share action is visible for a saved provider and hidden in create mode',
      (tester) async {
    // Pump 1: a builtin provider — the share action is offered.
    await _pumpDetailPage(tester, provider: _deepseekWithKey());
    expect(find.byKey(const ValueKey('shareProviderButton')), findsOneWidget);

    // Pump 2: create mode (isNewCustom) — nothing saved yet, action hidden.
    await _pumpDetailPage(tester, provider: _draft(), isNewCustom: true);
    expect(find.byKey(const ValueKey('shareProviderButton')), findsNothing);
  });

  testWidgets('tapping share opens the sheet with QR, payload and copy button',
      (tester) async {
    final provider = _deepseekWithKey();
    await _pumpDetailPage(tester, provider: provider);

    await tester.tap(find.byKey(const ValueKey('shareProviderButton')));
    await tester.pumpAndSettle();

    expect(find.text('分享提供商'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(
      find.textContaining('moodpet-provider:v1:', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('复制口令'), findsOneWidget);
    // The full payload travels in the SelectableText.
    final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(selectable.data, encodeProviderShare(provider));
  });

  testWidgets('copy button writes the payload to the clipboard and confirms',
      (tester) async {
    _mockClipboard();
    final provider = _deepseekWithKey();
    await _pumpDetailPage(tester, provider: provider);

    await tester.tap(find.byKey(const ValueKey('shareProviderButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('copySharePayloadButton')));
    await tester.pumpAndSettle();

    final data = await Clipboard.getData('text/plain');
    expect(data?.text, encodeProviderShare(provider));
    expect(find.text('已复制，发送给对方粘贴导入'), findsOneWidget);
  });

  testWidgets(
      'displayed payload decodes to the same endpoint with an empty apiKey',
      (tester) async {
    final provider = _deepseekWithKey();
    await _pumpDetailPage(tester, provider: provider);

    await tester.tap(find.byKey(const ValueKey('shareProviderButton')));
    await tester.pumpAndSettle();

    final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
    final payload = selectable.data!;
    // No secret material anywhere in the displayed string.
    expect(payload, isNot(contains('sk-secret-share-test')));

    final decoded = decodeProviderShare(payload);
    expect(decoded, isNotNull);
    expect(decoded!.name, provider.name);
    expect(decoded.baseUrl, provider.baseUrl);
    expect(decoded.protocol, provider.protocol);
    // The import lands as a keyless custom provider — no secret leak.
    expect(decoded.apiKey, isEmpty);
    expect(decoded.isCustom, isTrue);
  });

  testWidgets('builtin share shows the import-as-custom note', (tester) async {
    await _pumpDetailPage(tester, provider: _deepseekWithKey());

    await tester.tap(find.byKey(const ValueKey('shareProviderButton')));
    await tester.pumpAndSettle();

    expect(find.text('将以自定义提供商形式分享'), findsOneWidget);
    expect(find.text('口令不包含 API Key 和模型列表，接收方导入后需自行填写 Key'), findsOneWidget);
  });
}
