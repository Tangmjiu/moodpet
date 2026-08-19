# Task 19 — No-attribution audit + integration test suite + full regression

**Date:** 2026-08-19
**Project:** /home/mjiutang/moonpet (moodpet)
**Flutter:** 3.44.6 (channel stable) • Dart 3.12.2 • Device: Android emulator `emulator-5554` (API 36, android-x64)
**Scope:** (A) `providerRegistryProvider` invalidation fix in `provider_detail_page.dart` save + delete paths; (B) `integration_test/custom_providers_test.dart` with a local stub HTTP server driving the real app through 8 flows; (C) full regression: analyze, unit/widget suite, attribution audit, on-device integration suite.

---

## Part A — audit fix: registry invalidation on save/delete

### Change

`lib/features/settings/provider_detail_page.dart` — one line added alongside the existing invalidations in both mutation paths:

```dart
// _save() (custom + builtin saves), after the two existing lines:
      ref.invalidate(providerListProvider);
      ref.invalidate(activeProviderConfigProvider);
      // The settings page row watches the registry directly.
      ref.invalidate(providerRegistryProvider);

// _confirmDelete(), after the two existing lines:
    ref.invalidate(providerListProvider);
    ref.invalidate(activeProviderConfigProvider);
    // The settings page row watches the registry directly.
    ref.invalidate(providerRegistryProvider);
```

### Why (code-path reasoning)

`settings_page.dart:45` — the provider row watches `providerRegistryProvider` and resolves the name via `registry.byId(activeProviderId)?.name`. The settings page stays mounted (maintainState) while detail/selection routes are above it; popping back does not rebuild it. Without invalidating a provider the row watches, a renamed custom provider (save path) or a deleted active provider (delete path) leaves the row showing the stale name/id until manual re-entry. The added line makes the row rebuild on the next frame with live storage (ProviderRegistry re-reads prefs per call).

### Other mutation-site audit (grep)

```
$ grep -rn "ref.invalidate\|container.invalidate" lib/features/
plugin_management_page.dart:107,116  ref.invalidate(pluginManagerProvider)        — plugin state, unrelated
provider_selection_page.dart:249     ref.invalidate(providerListProvider)         — import: appends a NEW, non-active provider
provider_selection_page.dart:283     ref.invalidate(providerListProvider)         — reorder: changes order only
provider_selection_page.dart:394     ref.invalidate(providerListProvider)         — error-retry button, not a mutation
provider_detail_page.dart:273-275    save path  → FIXED (this todo)
provider_detail_page.dart:339-341    delete path → FIXED (this todo)
```

Neither remaining site can change the **active provider's name or id** (import mints a fresh non-active uuid; reorder only permutes ids), so the settings row content cannot go stale from them — no further changes needed, per the brief's one-line-each scope.

### Part A verification

- `flutter analyze lib/features/settings/provider_detail_page.dart` → **No issues found!**
- `flutter test test/features/` → **28/28 passed**, including the todo-18 stale-state test (`settings name refreshes when the custom provider is created after the page was opened`) — still green after the fix.
- Full suite re-run in Part C (below) also covers it.

---

## Part B — integration test suite

### File

`integration_test/custom_providers_test.dart` (new, 409 lines, lint-clean under flutter_lints v6, **no analysis_options exclusion added**).

### Design

- `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`; the REAL app is pumped (`ProviderScope(child: MoodPetApp())` — the `main.dart` entry).
- **Stub server** inside the test file: `HttpServer.bind(InternetAddress.loopbackIPv4, 0)` serving `POST /v1/chat/completions` → 200 with the fixed emotion-JSON assistant content `{"emoji":"😀","color":"#FFD54F","vibration":"light","suggestion":"stub ok"}`; `GET /v1/models` → 200 `{"data":[{"id":"stub-7b"},{"id":"stub-13b"}]}`; all else → 404. Closed in `tearDownAll` (`close(force: true)`), followed by a final `prefs.clear()`.
- **State isolation**: `setUpAll` does `SharedPreferences.getInstance()` → `clear()` → sets only `moodpet.onboardingComplete=true` (boots straight to home; `firstRunComplete` deliberately left unset so the bundled default Friend extraction runs exactly like a fresh install).
- **Deviation from the brief — base URL is `http://127.0.0.1:<port>/v1`, not 10.0.2.2.** `flutter test integration_test/ -d emulator-5554` runs the test bundle *on the device* (same process/isolate as the app), so the stub binds the *emulator's* loopback and the app reaches it at 127.0.0.1 directly. The brief's 10.0.2.2 assumption applies to host-side drivers (`flutter drive`). The app's `network_security_config.xml` permits cleartext to both 127.0.0.1 and 10.0.2.2, so the connection test and agent calls succeed. Verified empirically: flow 1's 测试连接 reports 连接成功 against the stub.
- Three `testWidgets` group the eight flows (state is interdependent across boots: prefs persist on the device; each test re-boots the app):
  1. `flows 1-3: create, connect, discover models, home chat`
  2. `flows 4-6: share payload, paste import, reorder persists`
  3. `flows 7-8: disable active shows offline badge, delete cleanup`

### Flow coverage vs the brief

1. **Create** — settings → 提供商 → 添加自定义提供商 → name `Stub Local`, baseUrl `http://127.0.0.1:<port>/v1`, default model `stub-7b` → 测试连接 → **连接成功** → 保存并使用 → card at top of the merged list (persisted order precedes the builtin catalog) with the 自定义 chip. Persisted customs length asserted = 1.
2. **Models** — 模型 tab → 拉取模型列表 → stub's two models fetched. **Interpretation note:** the picker excludes the current default model by design (`candidates = fetched − default − cached`), so only `stub-13b` is pickable; 全选 → 添加所选 (1) → the models tab then lists BOTH (`stub-7b` default row + `stub-13b` added row) → tap `stub-13b` → 当前 chip asserted + raw-prefs `moodpet.provider.modelOverride.<id>` = `stub-13b`.
3. **Home chat** — mic → dialog → enter `今天很开心` → 发送 → **asserts the stub's exact suggestion `stub ok`** (anti-misleading-success: the keyword fallback would show the Friend's mapping text or the idle `我在这里陪着你`) + orb emoji `😀` + processing completed (`点我说话` back).
4. **QR share** — detail → share action → sheet shows QR + payload; payload read from the `SelectableText` widget data; asserted `startsWith('moodpet-provider:v1:')`.
5. **QR import** — selection import action → 粘贴导入 → paste payload → **dedupe dialog 已存在相同提供商，仍要导入吗？ asserted** → 仍要导入 → preview sheet shows `Stub Local` → 确认导入 → two custom cards with 自定义 chips.
6. **Reorder** — second custom's drag handle dragged step-wise to the first card → **raw-prefs `moodpet.provider.order` asserted**: first two entries exactly `[id2, id1]` (the task's mandated raw-prefs read, not a UI proxy).
7. **Disable-active → offline** — **interpretation note:** "first custom" is read as the *active* custom from flow 1 (its intent is "disable-active"); after the reorder it is the second `Stub Local` card (`prefs.activeProviderId == id1` asserted first). 启用此提供商 off → 保存并使用 → home → **离线陪伴模式 badge asserted**.
8. **Cleanup** — both customs deleted via detail pages (删除此提供商 → confirm) → `Stub Local` gone, 自定义 chip gone; raw-prefs: `customProviders == '[]'`, order has 16 builtin ids with neither custom id, `activeProviderId` null.

**Not automated:** the camera QR-scan path (`ProviderScanPage`) — the emulator's virtual camera cannot be fed a QR image from Dart. The plan's own coverage note (todo 17/19) scopes automated tests to the paste path; paste import covers the full codec round-trip end-to-end. Camera scanning is **flagged human-required** at delivery.

### Root causes found and fixed while making the suite green

1. **REAL APP BUG (fixed): bundled Friend plugin's `assets/identity.json` was never packaged.** Flow 3 failed with the home stuck on the idle response; a provider-state probe showed `pluginManagerProvider = AsyncError(Unable to load asset: "assets/plugins/moodpet.friend.default_smiley.moodfriend/assets/identity.json")` → `agentServiceProvider` never resolved → `_respond` silently no-ops on a fresh install. Cause: flutter_tools' `_parseAssetsFromFolder` (`packages/flutter_tools/lib/src/asset.dart`) expands pubspec directory entries **non-recursively** — only files *directly* in the declared dir are bundled, so the plugin's nested `assets/` subdir was skipped. Fix: one line in `pubspec.yaml` declaring `assets/plugins/moodpet.friend.default_smiley.moodfriend/assets/` explicitly. Proof after fix: `build/app/intermediates/flutter/debug/flutter_assets/assets/plugins/moodpet.friend.default_smiley.moodfriend/assets/identity.json` now exists, and flow 3 passes. (Latent secondary: `plugin_bootstrap.dart`'s per-file catch is `on Exception` while `rootBundle.loadString` throws `FlutterError`, an `Error` — so the missing asset crashed the provider instead of being skipped. Not touched: out of this task's scope; the bundling fix removes the defect path. Flagged as residual risk.)
2. **IME race on real device (test-only fix).** `tester.enterText` into the freshly-opened autofocus dialog field was clobbered by the attaching system IME (the field's hint `今天怎么样？` persisted, `_canSend` stayed false, 发送 disabled — diagnosed via a temporary dump showing the dialog still open with an empty field). Fix: `_enterTextVerified` helper (enter → pump 300ms → assert the value rendered → retry up to 3 times) used for every text entry, plus a 600ms settle pump after the dialog opens.
3. **ReorderableListView drag (test-only fix).** `tester.drag(handle, Offset(0,-140))` and a fixed −160px manual gesture both produced no reorder (the end point left the list bounds). Fix: step-wise `startGesture` from the second card's handle to the *computed center of the first card's name text*, 6 pumped steps — end point guaranteed inside the first card.

### Environment incident (hung-command protocol)

First run's Gradle build died: `Gradle build daemon disappeared unexpectedly` after 223s — host has 14 GiB RAM with swap nearly full and the daemon requests `-Xmx8G` (project `gradle.properties`); kernel OOM-killed it. Per protocol: captured the log, retried once — the retry built in 67.6s and completed. No project file was changed for this.

---

## Part C — full regression (verbatim outputs)

### 1. `flutter analyze` — zero issues

```
12 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing moonpet...
No issues found! (ran in 2.1s)
```
(The "newer versions" line is the routine pub version-check nag, not an analysis issue.)

### 2. `flutter test` — 100% pass, 171/171

```
00:10 +168: .../provider_detail_page_test.dart: manual model add rejects duplicates with a snackbar
00:10 +169: .../custom_provider_flow_test.dart: backing out of create mode without saving persists nothing
00:11 +170: .../custom_provider_flow_test.dart: deleting a NON-active custom provider keeps the active id on the remaining provider
00:12 +171: All tests passed!
```

### 3. Attribution audit — zero hits

```
$ grep -rniE "rikka|borrowed|adapted from|inspired by" lib/ test/ integration_test/
GREP_EXIT=1        # exit 1 = no matches
```

### 4. `flutter test integration_test/ -d emulator-5554` — all flows green

```
00:00 +0: loading /home/mjiutang/moonpet/integration_test/custom_providers_test.dart
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk...        1,026ms
00:00 +0: (setUpAll)
00:00 +0: flows 1-3: create, connect, discover models, home chat
00:40 +1: flows 4-6: share payload, paste import, reorder persists
00:51 +2: flows 7-8: disable active shows offline badge, delete cleanup
01:04 +3: (tearDownAll)
01:04 +3: All tests passed!
EXIT=0
```

Flow-by-flow: each of the 8 flows lives inside one of the three named tests above (mapping in §"Flow coverage"); all assertions inside them passed — the test runner reports per-test pass, and any failed assertion would have failed the enclosing test (earlier iterations of this suite failed exactly that way until the root causes above were fixed).

One non-fatal warning in the passing run: `tester.pageBack()`'s internal back-button tap is covered by the share sheet's barrier; pageBack still succeeds via the system-back path (sheet closed, flow 5 proceeded). Left as-is — the test is green and the behavior matches a real user's system-back.

---

## Adversarial probes

| Probe class | Result |
|-------------|--------|
| **Flaky tests** | Emulator integration inherently flaky: fixed three real root causes (asset bundling, IME race, drag target) rather than masking with waits. Bounded pump helpers (`_settle` 20s cap, `_pumpUntilFound` timeout-throwing, `_enterTextVerified` 3-retry). Chat send retries once to cover the agent provider's first resolution race. |
| **Misleading success** | Home response asserts the stub's exact `stub ok` text and `😀` emoji (fallback would render the Friend mapping or the idle text). Reorder + cleanup assert **raw SharedPreferences** (`moodpet.provider.order`, `customProviders`, `activeId`), not UI proxies. Settings-name staleness asserted by the todo-18 widget test (still green). |
| **Stale state (Part A)** | After save/delete, `providerRegistryProvider` invalidation forces the settings row to rebuild against live storage on pop-back; verified by code-path reasoning + 28/28 feature tests green. |
| **Hung commands** | First integration run's Gradle daemon OOM-killed (223s); captured log, retried once → green. No >10min hangs; each `flutter test` run ≤ ~5min including build. |
| **Cleanup** | Stub `HttpServer` closed in `tearDownAll` (+ final `prefs.clear()`). Post-run `adb shell ps` shows **no moodpet process** on the emulator. Host `ps`: two idle `flutter_tester` processes (PIDs 243898, 424390) are pre-existing orphans from earlier sessions (reparented to `systemd --user`, started before this task's first flutter invocation) — not spawned by this task's runs, which all exited EXIT=0. |

## Constraints compliance

- Plain functional English comments; Chinese UI strings unchanged; no external-project names/attribution (grep §C3).
- No commits; no unrelated fixes — with one disclosed exception: the `pubspec.yaml` nested-assets line, the root-cause fix for the fresh-install plugin-bundling defect that blocked the mandated flow 3 (documented above; it also fixes the real product bug).
- Stub server code lives entirely inside the test file; flutter_lints v6 clean with **no** analysis_options exclusion.
- Integration test uses the emulator as instructed; Linux desktop fallback not needed.

## Files changed

| File | Change |
|------|--------|
| `lib/features/settings/provider_detail_page.dart` | Part A: `ref.invalidate(providerRegistryProvider)` added in `_save()` and `_confirmDelete()` (+ one explanatory comment each). |
| `pubspec.yaml` | Declared the Friend plugin's nested `assets/` dir explicitly (non-recursive bundling fix) + comment noting why. |
| `integration_test/custom_providers_test.dart` | **New.** Stub HTTP server + 3 tests covering the 8 flows + pump/enter/drag helpers. |
| `.omo/evidence/task-19-custom-providers.md` | **New.** This evidence. |

## Residual risks

- `plugin_bootstrap.dart` catches `on Exception` per asset file; a `FlutterError` (missing asset) escapes and fails `pluginManagerProvider`. Dormant while every listed asset is bundled (now true); worth a one-line hardening (`on Object`) in a future pass — not changed here (out of scope).
- Camera QR-scan path has no automated coverage (virtual camera can't be fed frames); flagged human-required at delivery.
- The two pre-existing idle `flutter_tester` orphans on the host are not from this task and were left untouched.

## DoneClaim

```json
{
  "task_id": "19",
  "title": "No-attribution audit + integration test suite + full regression",
  "status": "done",
  "evidence_file": ".omo/evidence/task-19-custom-providers.md",
  "changes": [
    "provider_detail_page.dart: ref.invalidate(providerRegistryProvider) added to save + delete paths — settings row no longer shows stale name after pop-back",
    "pubspec.yaml: nested assets/ dir of the bundled Friend plugin declared explicitly — fixes a real fresh-install bug (identity.json was never bundled → pluginManagerProvider AsyncError → agent dead); verified in flutter_assets",
    "integration_test/custom_providers_test.dart: new — dart:io stub server (127.0.0.1, ephemeral port) + 3 tests covering all 8 flows; green on emulator-5554"
  ],
  "verification": {
    "analyze": "flutter analyze — No issues found! (zero issues repo-wide, integration_test included)",
    "unit_widget_suite": "flutter test — 171/171 passed",
    "attribution_grep": "grep -rniE 'rikka|borrowed|adapted from|inspired by' lib/ test/ integration_test/ — exit 1, zero hits",
    "integration_suite": "flutter test integration_test/ -d emulator-5554 — 3/3 passed (flows 1-8), EXIT=0",
    "part_a_regression": "flutter test test/features/ — 28/28 passed incl. todo-18 stale-state test"
  },
  "residual_risks": [
    "plugin_bootstrap.dart per-file catch is 'on Exception' and misses FlutterError on missing assets (dormant while all declared assets exist)",
    "camera QR-scan path not automated (virtual camera can't be fed frames); flagged human-required",
    "two pre-existing idle flutter_tester orphan processes on the host predate this task and were left untouched"
  ]
}
```
