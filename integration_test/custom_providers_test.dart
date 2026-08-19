/// End-to-end integration tests for custom LLM providers, driven against the
/// real app UI on a device/emulator.
///
/// A stub HTTP server (`dart:io` [HttpServer], bound to 127.0.0.1 on an
/// ephemeral port) plays the provider endpoint:
///
///   POST /v1/chat/completions → 200 with a fixed emotion-JSON assistant reply
///   GET  /v1/models           → 200 with two model ids (stub-7b, stub-13b)
///   anything else             → 404
///
/// The test process runs on the device itself (flutter test integration_test/
/// with -d pointing at a device), so the app reaches the stub at 127.0.0.1
/// directly; the app's network security config permits cleartext to 127.0.0.1.
///
/// Coverage: create + connection test + save (flow 1), model discovery and
/// activation (flow 2), home chat round-trip against the stub (flow 3), QR
/// share payload read-back (flow 4), paste import with the duplicate warning
/// (flow 5), drag reorder with raw SharedPreferences persistence assertion
/// (flow 6), disable-active → offline badge (flow 7), delete cleanup
/// (flow 8). The camera QR-scan path is not automated: the virtual emulator
/// camera cannot be fed a QR image from Dart — paste import covers the codec
/// round trip; camera scanning is flagged for human QA.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moodpet/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences keys mirrored from SettingsStore (its constants are
/// private; tests assert on the raw persisted values, as other suites do).
const String _kCustomProvidersKey = 'moodpet.provider.customProviders';
const String _kProviderOrderKey = 'moodpet.provider.order';
const String _kActiveProviderIdKey = 'moodpet.provider.activeId';
const String _kOnboardingCompleteKey = 'moodpet.onboardingComplete';

const String _kCustomName = 'Stub Local';

HttpServer? _stubServer;
int _stubPort = 0;

/// Bind the stub server and start serving canned responses.
Future<void> _startStubServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) async {
    final response = request.response;
    if (request.method == 'POST' &&
        request.uri.path == '/v1/chat/completions') {
      response.statusCode = HttpStatus.ok;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{
              'role': 'assistant',
              'content': '{"emoji":"😀","color":"#FFD54F",'
                  '"vibration":"light","suggestion":"stub ok"}',
            },
          },
        ],
      }));
    } else if (request.method == 'GET' && request.uri.path == '/v1/models') {
      response.statusCode = HttpStatus.ok;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(<String, Object?>{
        'data': <Object?>[
          <String, Object?>{'id': 'stub-7b'},
          <String, Object?>{'id': 'stub-13b'},
        ],
      }));
    } else {
      response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  });
  _stubServer = server;
  _stubPort = server.port;
}

/// Bounded pumpAndSettle for pages without continuous animations.
Future<void> _settle(WidgetTester tester) {
  return tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 20),
  );
}

/// Pump in small steps until [finder] matches at least one widget; throws
/// after [timeout]. Used on the home page, whose continuous breathing
/// animation makes pumpAndSettle unusable, and for real-network waits.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('pumpUntilFound timed out after $timeout: $finder');
}

/// Boot the real app and wait for the home page.
Future<void> _bootApp(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: MoodPetApp()));
  await _pumpUntilFound(
    tester,
    find.text('点我说话'),
    timeout: const Duration(seconds: 45),
  );
}

/// Home → settings → provider selection page.
Future<void> _openProviderSelection(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await _settle(tester);
  await tester.tap(find.text('提供商'));
  await _settle(tester);
  expect(find.text('选择提供商'), findsOneWidget);
}

/// Pop selection → settings → home. The home page never settles (breathing
/// animation), so the final leg uses bounded pumps instead of pumpAndSettle.
Future<void> _backToHome(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await _settle(tester);
  await tester.tap(find.byType(BackButton));
  await _pumpUntilFound(tester, find.text('点我说话'));
}

/// Enter [text] into [field] and verify the value landed (the field renders
/// it). On a real device the system IME can clobber a value set while it is
/// still attaching, so retry a few times before failing.
Future<void> _enterTextVerified(
  WidgetTester tester,
  Finder field,
  String text,
) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    await tester.enterText(field, text);
    await tester.pump(const Duration(milliseconds: 300));
    if (find.text(text).evaluate().isNotEmpty) return;
  }
  throw TestFailure('enterText did not stick in $field after retries');
}

/// The persisted custom provider ids, in customs-storage order.
List<String> _readCustomIds(SharedPreferences prefs) {
  final raw = prefs.getString(_kCustomProvidersKey);
  if (raw == null || raw.isEmpty) return <String>[];
  final decoded = jsonDecode(raw);
  if (decoded is! List) return <String>[];
  return <String>[
    for (final entry in decoded)
      (entry as Map<String, Object?>)['id'] as String,
  ];
}

/// Send [text] through the home mic → dialog → agent → stub, and wait for
/// the stub's suggestion to render. Retries the send once: the first attempt
/// can race the agent provider's initial resolution (a null agent makes
/// _respond a silent no-op).
Future<void> _sendAndExpectStubReply(WidgetTester tester, String text) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await _pumpUntilFound(tester, find.text('跟伙伴说点什么'));
    // Let the dialog's autofocus + system IME attach settle before entering
    // text; entering too early races the IME and the value is clobbered.
    await tester.pump(const Duration(milliseconds: 600));
    await _enterTextVerified(
      tester,
      find.descendant(
        of: find.widgetWithText(Dialog, '跟伙伴说点什么'),
        matching: find.byType(TextField),
      ),
      text,
    );
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    try {
      await _pumpUntilFound(tester, find.text('stub ok'));
      return;
    } on TestFailure {
      // Fall through and retry the send once.
    }
  }
  throw TestFailure('home never showed the stub response after two sends');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUpAll(() async {
    // Isolate provider state: wipe persisted settings from any earlier run,
    // then mark onboarding complete so the app boots straight to home.
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setBool(_kOnboardingCompleteKey, true);
    await _startStubServer();
  });

  tearDownAll(() async {
    await _stubServer?.close(force: true);
    await prefs.clear();
  });

  testWidgets('flows 1-3: create, connect, discover models, home chat',
      (tester) async {
    final baseUrl = 'http://127.0.0.1:$_stubPort/v1';
    await _bootApp(tester);

    // ---- Flow 1: create + connection test + save ----
    await _openProviderSelection(tester);
    await tester.tap(find.text('添加自定义提供商'));
    await _settle(tester);
    await _enterTextVerified(
        tester, find.byKey(const ValueKey('customNameField')), _kCustomName);
    await _enterTextVerified(
        tester, find.byKey(const ValueKey('customBaseUrlField')), baseUrl);
    await _enterTextVerified(tester,
        find.byKey(const ValueKey('customDefaultModelField')), 'stub-7b');

    await tester.ensureVisible(find.byKey(const ValueKey('testConnectionButton')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('testConnectionButton')));
    await _pumpUntilFound(tester, find.textContaining('连接成功'),
        timeout: const Duration(seconds: 25));

    await tester.ensureVisible(find.byKey(const ValueKey('saveButton')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('saveButton')));
    await _settle(tester);
    // The saved custom lands at the top of the merged list with its chip.
    expect(find.text(_kCustomName), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);
    expect(_readCustomIds(prefs), hasLength(1));

    // ---- Flow 2: model discovery + activation ----
    await tester.tap(find.text(_kCustomName));
    await _settle(tester);
    await tester.tap(find.text('模型'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('fetchModelsButton')));
    await _settle(tester);
    // The default model is filtered out of the picker; only stub-13b is new.
    expect(find.text('选择要添加的模型'), findsOneWidget);
    expect(find.text('stub-13b'), findsOneWidget);
    await tester.tap(find.text('全选'));
    await _settle(tester);
    await tester.tap(find.text('添加所选 (1)'));
    await _settle(tester);
    // Both stub models are now listed: the default row plus the added one.
    expect(find.text('stub-7b'), findsOneWidget);
    expect(find.text('stub-13b'), findsOneWidget);
    await tester.tap(find.text('stub-13b'));
    await _settle(tester);
    expect(find.text('当前'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await _settle(tester);

    // ---- Flow 3: home chat round-trip against the stub ----
    await _backToHome(tester);
    // Real-time window for the agent provider to resolve before first send.
    await tester.pump(const Duration(seconds: 3));
    await _sendAndExpectStubReply(tester, '今天很开心');
    // The orb shows the stub's emoji and the processing state completed.
    expect(find.text('😀'), findsOneWidget);
    expect(find.text('点我说话'), findsOneWidget);
  });

  testWidgets('flows 4-6: share payload, paste import, reorder persists',
      (tester) async {
    await _bootApp(tester);

    // ---- Flow 4: QR share sheet + payload read-back ----
    await _openProviderSelection(tester);
    await tester.tap(find.text(_kCustomName));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('shareProviderButton')));
    await _settle(tester);
    expect(find.text('分享提供商'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    final payload =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(payload, startsWith('moodpet-provider:v1:'));
    await tester.pageBack();
    await _settle(tester);
    await tester.tap(find.byType(BackButton));
    await _settle(tester);

    // ---- Flow 5: paste import with the duplicate warning ----
    await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
    await _settle(tester);
    await tester.tap(find.text('粘贴导入'));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await _enterTextVerified(
      tester,
      find.descendant(
        of: find.widgetWithText(AlertDialog, '粘贴导入'),
        matching: find.byType(TextField),
      ),
      payload,
    );
    await tester.tap(find.widgetWithText(FilledButton, '导入'));
    await _settle(tester);
    // The payload shares name + baseUrl with the existing custom.
    expect(find.text('已存在相同提供商，仍要导入吗？'), findsOneWidget);
    await tester.tap(find.text('仍要导入'));
    await _settle(tester);
    expect(find.text('确认导入提供商'), findsOneWidget);
    // The preview sheet shows the decoded provider name.
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(_kCustomName),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('确认导入'));
    await _settle(tester);
    // Both customs are now listed at the top with their chips.
    expect(find.text(_kCustomName), findsNWidgets(2));
    expect(find.text('自定义'), findsNWidgets(2));

    // ---- Flow 6: drag the second custom above the first; order persists ----
    final ids = _readCustomIds(prefs);
    expect(ids, hasLength(2));
    final id1 = ids[0];
    final id2 = ids[1];
    // Drag the second card's handle up to the first card's name, in small
    // pumped steps so the ReorderableListView tracks the gap. The end point
    // stays inside the first card: leaving the list would cancel the drag.
    final dragStart =
        tester.getCenter(find.byIcon(Icons.drag_handle_rounded).at(1));
    final dragEnd = tester.getCenter(find.text(_kCustomName).at(0));
    final drag = await tester.startGesture(dragStart);
    await tester.pump(const Duration(milliseconds: 100));
    final stepDy = (dragEnd.dy - dragStart.dy) / 6;
    for (var i = 0; i < 6; i++) {
      await drag.moveBy(Offset(0, stepDy));
      await tester.pump(const Duration(milliseconds: 80));
    }
    await drag.up();
    await _settle(tester);
    // Raw-prefs assertion: the second custom now precedes the first.
    final order = prefs.getStringList(_kProviderOrderKey) ?? <String>[];
    expect(order.take(2).toList(), <String>[id2, id1]);
  });

  testWidgets('flows 7-8: disable active shows offline badge, delete cleanup',
      (tester) async {
    await _bootApp(tester);

    // ---- Flow 7: disable the ACTIVE custom → home offline badge ----
    final ids = _readCustomIds(prefs);
    expect(ids, hasLength(2));
    final id1 = ids[0];
    final id2 = ids[1];
    // Import and reorder never touch the active id: the flow-1 custom stays
    // active, and after the reorder it is the second Stub Local card.
    expect(prefs.getString(_kActiveProviderIdKey), id1);

    await _openProviderSelection(tester);
    await tester.tap(find.text(_kCustomName).last);
    await _settle(tester);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await _settle(tester);
    await tester.tap(find.byType(SwitchListTile));
    await _settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('saveButton')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('saveButton')));
    await _settle(tester);
    await _backToHome(tester);
    await _pumpUntilFound(tester, find.text('离线陪伴模式'));

    // ---- Flow 8: delete both customs; builtins only ----
    await _openProviderSelection(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text(_kCustomName).first);
      await _settle(tester);
      await tester.ensureVisible(
          find.byKey(const ValueKey('deleteProviderButton')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('deleteProviderButton')));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await _settle(tester);
    }
    expect(find.text(_kCustomName), findsNothing);
    expect(find.text('自定义'), findsNothing);
    // Raw-prefs assertions: no customs remain and no order entry dangles.
    expect(prefs.getString(_kCustomProvidersKey), '[]');
    final order = prefs.getStringList(_kProviderOrderKey) ?? <String>[];
    expect(order, hasLength(16));
    expect(order.contains(id1), isFalse);
    expect(order.contains(id2), isFalse);
    expect(prefs.getString(_kActiveProviderIdKey), isNull);
  });
}
