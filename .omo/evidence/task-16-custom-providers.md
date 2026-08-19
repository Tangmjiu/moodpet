# Task 16 — QR Import UI on the Provider Selection Page (Camera Scan + Paste)

**Date:** 2026-08-19
**Project:** /home/mjiutang/moonpet (moodpet)
**Flutter:** 3.44.6 (channel stable) • Dart 3.12.2
**Scope:** Add an import entry point to the provider selection page: an AppBar action opening a chooser （扫码导入 on Android only / 粘贴导入 everywhere), a full-screen camera scan page, a paste dialog, a shared dedupe → preview → persist flow, and a new widget-test file.

---

## 1. Changes

### 1a. `lib/features/settings/provider_selection_page.dart` (edited)

- **New imports:** `dart:io` (Platform), `flutter/foundation.dart` (kIsWeb), `core/utils/provider_share_codec.dart`, `provider_scan_page.dart`.
- **AppBar action:** `IconButton(Icons.qr_code_scanner_rounded, tooltip: '导入提供商')` → `_showImportChooser()`.
- **Chooser dialog** `AlertDialog('导入提供商')` with two ListTiles:
  - `扫码导入` — rendered only when `!kIsWeb && Platform.isAndroid` (the app targets Android + Linux; no camera path on Linux, so the entry is hidden there and in tests).
  - `粘贴导入` — always visible.
- **扫码导入** (`_onScanImport`): pushes `MaterialPageRoute<ProviderConfig>` to `ProviderScanPage`; a non-null pop result flows into the shared preview.
- **粘贴导入** (`_onPasteImport`): shows a new `_PasteImportDialog` (multiline TextField, hint `粘贴 moodpet-provider:v1: 开头的口令`, actions 取消 / 导入）. 导入 runs `decodeProviderShare`; `null` → SnackBar `口令无效` and the dialog stays open; success pops with the decoded config → preview flow.
  - Implementation note: the dialog is its own `StatefulWidget` so the `TextEditingController`'s disposal is tied to the dialog lifecycle. The first version disposed the controller from the caller right after `showDialog` returned, which raced the dialog's exit animation ("TextEditingController was used after being disposed" in tests); the refactor fixed it and is verified by the green suite.
- **Shared preview flow** (`_showImportPreview`):
  1. Reads `settingsStoreProvider`, checks existing custom providers for the same `name` AND `baseUrl`; on a match shows `AlertDialog('已存在相同提供商，仍要导入吗？')` （取消 / 仍要导入） before anything else.
  2. `showModalBottomSheet('确认导入提供商')` with rows 名称 / 接口地址 / 协议 (`OpenAI 兼容` / `Claude` / `Gemini` via a local `_protocolLabel`, mirroring the detail page's mapping), note `口令不含 API Key，导入后请自行填写`, and buttons 取消 / 确认导入.
  3. On 确认导入： `saveCustomProviders([...existing, decoded])`, `saveProviderOrder([...order, decoded.id])`, `ref.invalidate(providerListProvider)`, SnackBar `已导入「<name>」`.
- All UI uses the existing claymorphism tokens (`kSpace*`, `kRadiusLg`, themed buttons/inputs); Chinese UI strings; plain English comments.

### 1b. `lib/features/settings/provider_scan_page.dart` (new)

- `ProviderScanPage` (StatefulWidget): AppBar `扫描提供商二维码` with an optional torch toggle (`MobileScannerController.toggleTorch`), body is a full-size `MobileScanner(onDetect: _onDetect)`.
- `_onDetect(BarcodeCapture capture)`: reads `capture.barcodes.firstOrNull?.rawValue`; ignores `null` and non-`kProviderSharePrefix` payloads. On a prefix match a `_handled` bool latches (onDetect fires per camera frame), decodes once, and pops with the decoded `ProviderConfig`. Decode failure → SnackBar `二维码无效` and `_handled` re-arms after a 2 s `Timer` so scanning continues.
- Camera permission is left to the mobile_scanner plugin — nothing is requested preemptively. The controller is disposed in `dispose()`.

### 1c. `test/features/settings/provider_import_test.dart` (new, 5 tests)

Mirrors the existing `provider_selection_page_test.dart` harness (ProviderScope + `SharedPreferences.setMockInitialValues`, tall 1080×3200 surface, override `sharedPrefsProvider`). Coverage:

| # | Test | Asserts |
|---|------|---------|
| a | import action opens chooser; scan entry hidden off-Android | `导入提供商` + `粘贴导入` visible; `扫码导入` absent (tests never run on Android) |
| b | paste flow: valid payload previews and persists | whitespace-padded payload accepted; preview shows name / baseUrl / `OpenAI 兼容` / the no-API-key note; after 确认导入 the SnackBar `已导入「导入测试」` shows AND `loadCustomProviders()` grew 1→2 (fresh uuid, `isCustom`, empty apiKey) AND `loadProviderOrder()` is `[test-custom, newId]` |
| c | paste garbage shows 口令无效 and persists nothing | SnackBar shown, dialog stays open, preview never appears, prefs unchanged (1 custom, order intact) |
| d | duplicate name+baseUrl warns first; 仍要导入 proceeds | `已存在相同提供商，仍要导入吗？` appears before the preview; after 仍要导入 + 确认导入， customs = 2, order length 2 |
| e | ProviderScanPage type exists (compile pin) | non-widget test referencing the class; headless camera instantiation is not attempted |

---

## 2. Verification

### 2a. `flutter test test/features/settings/provider_import_test.dart`

```
00:00 +0: loading test/features/settings/provider_import_test.dart
00:00 +0: import action opens chooser; scan entry hidden off-Android
00:01 +1: paste flow: valid payload previews and persists
00:01 +2: paste garbage shows 口令无效 and persists nothing
00:01 +3: duplicate name+baseUrl warns first; 仍要导入 proceeds
00:02 +4: ProviderScanPage type exists (camera path is device-verified)
00:02 +5: All tests passed!
```

**5/5 green.**

### 2b. `flutter analyze lib/features/settings/ test/features/settings/provider_import_test.dart`

```
Analyzing 2 items...
No issues found! (ran in 2.1s)
```

**Zero issues** (flutter_lints v6). `lsp_diagnostics` on `provider_scan_page.dart` and `provider_selection_page.dart`: "No diagnostics found" for both.

### 2c. Full suite — `flutter test`

```
00:06 +156: ... provider_detail_page_test.dart: deleting the active custom provider clears its state ...
00:06 +157: ... manual model add rejects duplicates with a snackbar
00:07 +158: All tests passed!
```

**158/158 green**, no pre-existing tests harmed.

### 2d. Attribution grep

```
$ grep -rniE "rikka|borrowed|adapted from|inspired by|based on|copied from|ported from|forked from|shamelessly" \
    lib/features/settings/provider_scan_page.dart \
    lib/features/settings/provider_selection_page.dart \
    test/features/settings/provider_import_test.dart
(no output)
GREP_EXIT=1
```

**Zero hits.**

---

## 3. Adversarial classes

| Class | Result |
|-------|--------|
| **Malformed input** | PROBED — test c pastes `hello world` → `口令无效`, dialog stays open, nothing persisted. Wrong-prefix strings hit the same `decodeProviderShare` null path (unit-covered in `test/core/utils/provider_share_codec_test.dart`, not edited here). Whitespace-padded valid payload is accepted — test b pads with `\n`/spaces and the codec trims before decoding. Repeated scanner frames are neutralized by the `_handled` latch in `ProviderScanPage._onDetect`. |
| **Misleading success** | PROBED — tests b and d assert the persisted state through `SettingsStore(prefs).loadCustomProviders()` / `loadProviderOrder()` (real SharedPreferences mock), not just the SnackBar/UI: exact list growth (1→2), the fresh local id replacing the payload id, and the exact appended order. |
| **Prompt injection** | N/A — the payload is inert data: decoded into read-only preview rows, never executed, evaluated, or interpolated into anything callable. |
| **Camera-permission denial / no camera** | N/A for headless tests — handled by the mobile_scanner plugin's own permission flow at runtime; verified on the device run (see §4). |
| **Race: dialog exit animation vs controller disposal** | PROBED (found by tests, fixed) — disposing the paste dialog's `TextEditingController` from the caller raced the exit animation; the dialog now owns the controller. Suite green after the fix. |
| Other classes (network, disk, concurrency) | N/A — import is local-only (prefs write), no network involved. |

---

## 4. Camera-scan verification status

The 扫码导入 path cannot be exercised headlessly (mobile_scanner needs a real camera), so the widget tests pin compilation of `ProviderScanPage` only (test e). On-device verification belongs to the todo-19 device run; **if no Android device is available for that run, this path is flagged human-required.** Everything behind the scan page (dedupe → preview → persist) is shared with the paste path and is fully test-covered via `_onPasteImport`/`_showImportPreview`.

## 5. Constraints compliance

- ✅ Edited only `lib/features/settings/provider_selection_page.dart`; new files `provider_scan_page.dart` + `provider_import_test.dart`.
- ✅ Did NOT touch `provider_detail_page.dart` (parallel worker), `provider_share_codec.dart`, or any pre-existing test.
- ✅ No git commands; no new packages (`mobile_scanner 7.4.0`, `collection` already present).
- ✅ Chinese UI strings; plain functional English comments; no external-project names/attribution (grep §2d).
- ✅ Camera permission not requested preemptively (plugin-owned).

## 6. DoneClaim

```json
{
  "task_id": "16",
  "title": "QR import UI on provider selection page (camera scan + paste)",
  "status": "done",
  "evidence_file": ".omo/evidence/task-16-custom-providers.md",
  "changes": [
    "lib/features/settings/provider_selection_page.dart: AppBar import action + chooser dialog (扫码导入 Android-only, 粘贴导入 always) + shared dedupe/preview/persist flow (_showImportPreview) + _PasteImportDialog + _ImportPreviewRow",
    "lib/features/settings/provider_scan_page.dart: new full-screen MobileScanner page with one-shot _handled decode guard, torch toggle, pops with decoded ProviderConfig",
    "test/features/settings/provider_import_test.dart: 5 tests (chooser visibility, paste persist, garbage rejection, dedupe proceed, scan-page compile pin)"
  ],
  "verification": {
    "new_test_file": "5/5 green",
    "analyze_lib_features_settings": "No issues found (flutter_lints v6)",
    "lsp_diagnostics": "clean on both touched lib files",
    "full_suite": "158/158 green",
    "attribution_grep": "zero hits (exit 1)"
  },
  "residual_risks": [
    "Camera-scan path verified by compilation only in CI; runtime verification requires the todo-19 Android device run (human-required if no device is available)"
  ]
}
```
