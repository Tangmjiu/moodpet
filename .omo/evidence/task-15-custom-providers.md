# Task 15 — Custom Providers: QR share UI on the provider detail page

## What was built

Edited `lib/features/settings/provider_detail_page.dart` (MD3 Expressive claymorphism
style — `ClayContainer`, `kSpace*`, `kRadiusLg`/`kRadiusMd` tokens from `lib/app.dart`):

1. **AppBar share action** — `IconButton` (`Icons.ios_share_rounded`, key
   `shareProviderButton`, tooltip `分享提供商`) in the AppBar `actions`. Rendered for
   ALL providers, builtins included (a builtin shares its baseUrl/defaults so the
   recipient imports it as a CUSTOM provider — the sheet carries the one-line note
   `将以自定义提供商形式分享` for builtins). Hidden when `isNewCustom == true`
   (a fresh draft has nothing saved to share yet).

2. **`_showShareSheet()`** — encodes the payload via
   `encodeProviderShare(widget.provider)` at tap time, then opens a
   `showModalBottomSheet(isScrollControlled: true)` hosting the new private
   `_ShareSheet` widget:
   - Drag handle (32x4 rounded bar, `onSurfaceVariant` at 0.4 alpha) + title `分享提供商`.
   - Centered `ClayContainer` (white surface, `kRadiusLg`, `shadowIntensity: 0.4`)
     wrapping `QrImageView(data: payload, size: 240, backgroundColor: Colors.white)`
     — the QR always renders on a light surface regardless of theme so scanners can
     read it (default eye style / quiet zone).
   - Provider name (`titleMedium`) + baseUrl (`bodySmall`) caption below the QR.
   - Builtin-only note `将以自定义提供商形式分享` (primary-coloured caption).
   - The full payload string in a `SelectableText` with monospace `bodySmall` style,
     inside a 72px-high (~3 caption lines) `surfaceContainerHighest` container
     (`kRadiusMd`) with an inner `SingleChildScrollView` — visually ~3 lines,
     scrollable, fully selectable.
   - `复制口令` `FilledButton.tonalIcon` (key `copySharePayloadButton`) →
     `Clipboard.setData(ClipboardData(text: payload))` + SnackBar
     `已复制，发送给对方粘贴导入` (mounted-checked before use of context).
   - Footer note `口令不包含 API Key 和模型列表，接收方导入后需自行填写 Key`.

New widget test `test/features/settings/provider_share_sheet_test.dart` (5 tests,
cases a–e) — `ProviderScope` with `sharedPrefsProvider.overrideWith((ref) async => prefs)`,
network seams stubbed with no-network fakes, clipboard mocked through
`TestDefaultBinaryMessengerBinding` on the `flutter/platform` channel.

No other files edited; no git commands run; no new packages added (qr_flutter 4.1.0
was already in pubspec from todo 17 — `QrImageView` is its current API, no fallback
to the deprecated `QrImage` needed).

## VERIFY 1 — new widget tests green

Command: `flutter test test/features/settings/provider_share_sheet_test.dart`

```
00:00 +0: loading /home/mjiutang/moonpet/test/features/settings/provider_share_sheet_test.dart
00:00 +0: share action is visible for a saved provider and hidden in create mode
00:01 +1: tapping share opens the sheet with QR, payload and copy button
00:01 +2: copy button writes the payload to the clipboard and confirms
00:01 +3: displayed payload decodes to the same endpoint with an empty apiKey
00:01 +4: builtin share shows the import-as-custom note
00:01 +5: All tests passed!
```

Result: PASS — 5/5 tests green. Coverage of the required cases:

| Case | Test |
|------|------|
| a visible for builtin / hidden when isNewCustom (two pumps) | `share action is visible for a saved provider and hidden in create mode` |
| b sheet opens: QrImageView + payload text + 复制口令 | `tapping share opens the sheet with QR, payload and copy button` |
| c copy → clipboard has payload + SnackBar 已复制 | `copy button writes the payload to the clipboard and confirms` |
| d payload decodes; same name/baseUrl/protocol; EMPTY apiKey | `displayed payload decodes to the same endpoint with an empty apiKey` |
| e builtin shows 将以自定义提供商形式分享 | `builtin share shows the import-as-custom note` |

(The first run of this command failed to COMPILE because the parallel todo-16
worker was mid-edit on `provider_selection_page.dart` (`_showImportChooser` call
site present, method not yet written). That file was not touched by this task; a
re-run after the worker landed the method passed as shown above.)

## VERIFY 2 — analyzer clean

Command: `flutter analyze lib/features/settings/provider_detail_page.dart test/features/settings/provider_share_sheet_test.dart`

```
Analyzing 2 items...
No issues found! (ran in 1.8s)
```

Result: PASS — zero issues (flutter_lints v6 clean). `lsp_diagnostics` on the
edited page also reports "No diagnostics found".

## VERIFY 3 — full suite green

Command: `flutter test`

```
...
00:06 +153: All tests passed!
```

Result: PASS — 153/153 tests green across the whole suite (includes the 5 new
share-sheet tests and all pre-existing tests, none of which were modified).

## VERIFY 4 — attribution grep

Command: `grep -rniE "rikka|borrowed|adapted from|inspired by|based on|copied from|ported from|forked from|shamelessly" lib/features/settings/provider_detail_page.dart test/features/settings/provider_share_sheet_test.dart`

```
(no output)
grep exit: 1
```

Result: PASS — zero hits. No external project names or attribution anywhere in the
touched files. UI strings are Chinese; code comments are plain functional English.

## Adversarial classes

- **Misleading success → PROBED.** Test d does not trust the rendered string: it
  pulls the exact `SelectableText.data`, asserts it does NOT contain the secret
  marker (`sk-secret-share-test`), then round-trips it through the REAL
  `decodeProviderShare` and asserts name/baseUrl/protocol match the source provider
  AND `decoded.apiKey` is empty — a key leak through the QR/payload surface would
  fail two independent assertions (substring + decoded field). Test c reads the
  clipboard back through `Clipboard.getData` instead of trusting `setData`'s return.
- **Stale state → HANDLED.** The payload is encoded from `widget.provider` inside
  `_showShareSheet()` at tap time and captured by the sheet — not cached in state,
  not derived from the (editable, possibly dirty) form controllers. What is shared
  is the saved provider identity this page was opened with.
- **Secret leakage → PROBED.** The test provider carries `apiKey: sk-secret-share-test`;
  see "Misleading success" above. The codec itself was proven key-free in todo 14.
- **Theme-dependent QR scannability → HANDLED.** QR sits on a white `ClayContainer`
  with `backgroundColor: Colors.white` regardless of light/dark theme.
- **Prompt injection → N/A.** This task only ENCODES and displays local provider
  data; no payload string is executed, navigated to, or used as a dispatch key.
  (Decode/import trust handling belongs to todo 16.)
- **Dirty worktree → RESPECTED.** `provider_selection_page.dart` (parallel worker),
  `provider_share_codec.dart`, and all pre-existing tests were left untouched; only
  `provider_detail_page.dart` was edited and one new test file created.
- **Hung commands / flaky tests → N/A.** All flutter commands completed in seconds;
  tests use no timers, randomness, or real I/O (prefs mocked, clipboard mocked,
  network seams stubbed).

## Cleanup receipt

None required. `flutter test` / `flutter analyze` wrote only to `.dart_tool/`
(gitignored). Files touched: `lib/features/settings/provider_detail_page.dart`
(edited), `test/features/settings/provider_share_sheet_test.dart` (new), this
evidence file (new). No temp or stray files.

## DoneClaim

```json
{
  "todo": 15,
  "title": "QR share UI on detail page",
  "status": "done",
  "files": [
    "lib/features/settings/provider_detail_page.dart",
    "test/features/settings/provider_share_sheet_test.dart"
  ],
  "evidence": ".omo/evidence/task-15-custom-providers.md",
  "verify": {
    "flutter test test/features/settings/provider_share_sheet_test.dart": "PASS 5/5",
    "flutter analyze lib/features/settings/provider_detail_page.dart test/features/settings/provider_share_sheet_test.dart": "PASS zero issues",
    "flutter test (full suite)": "PASS 153/153",
    "attribution grep": "PASS zero hits"
  },
  "adversarial": {
    "misleading_success": "probed — payload decoded via real decodeProviderShare in test d; apiKey asserted empty; secret marker asserted absent from displayed string",
    "stale_state": "handled — payload encoded from widget.provider at tap time",
    "secret_leakage": "probed — keyed provider used in tests; two independent no-leak assertions",
    "prompt_injection": "n/a — encode/display only, no execution of payload data",
    "dirty_worktree": "respected — parallel-worker's selection page, codec, and pre-existing tests untouched",
    "hung_commands_flaky_tests": "n/a — no timers/randomness/real I/O; all commands completed in seconds"
  },
  "cleanup": "none required — no temp or stray files"
}
```
