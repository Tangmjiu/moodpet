# Task 18 — Custom Providers: Onboarding + Settings Integration Fixes & Verification

**Date:** 2026-08-19
**Project:** /home/mjiutang/moonpet (moodpet)
**Flutter:** 3.44.6 (channel stable) • Dart 3.12.2
**Scope:** (a) verify `ProviderSelectionPage(fromOnboarding: true)` merged list + intact offline-skip section; (b) fix `settings_page._providerDisplayName` to resolve through the registry; (c) delete the external-project attribution comment at `onboarding_page.dart:302`; (d) new widget tests; (e) keep `test/app_test.dart` green.

---

## 1. (a) ProviderSelectionPage(fromOnboarding: true) — verification

### 1a. Code-read findings

- `lib/features/settings/provider_selection_page.dart:289` — the page watches `providerListProvider`, which resolves to `ProviderRegistry.all()` (`lib/core/providers.dart:101-103`): built-in catalog **plus persisted customs**, overlays applied, order reconciled (`lib/core/provider_registry.dart:29-49`). Customs are therefore in the rendered list in onboarding mode.
- Custom badge: `_ProviderCard` renders the `自定义` chip for `provider.isCustom` (`provider_selection_page.dart:546-555`).
- Offline-skip section intact (`provider_selection_page.dart:437-461`): shown only when `widget.fromOnboarding` is true — `FilledButton.icon` labelled `进入离线陪伴模式` (`Navigator.of(context).pop(false)`) plus the advisory text `不配置 LLM 也能用：伙伴会用本地情绪词库回应你（约 12 种情绪），但没有 AI 思考能力。随时可在设置里补配提供商。` Unchanged by this todo.

### 1b. Widget-test confirmation

Test 1 in `test/features/onboarding_settings_integration_test.dart` pumps `ProviderSelectionPage(fromOnboarding: true)` with one seeded custom provider and asserts: custom name + `自定义` chip visible, custom card laid out **above** the offline section (`getTopLeft(...).dy` comparison), `进入离线陪伴模式` and the advisory text (`find.textContaining('不配置 LLM 也能用')`) both visible. Green (§5a).

---

## 2. (b) settings_page._providerDisplayName — fix

**Before:** `_providerDisplayName` scanned `kBuiltinProviders` and fell back to the raw id — a custom active provider displayed its uuid.

**After** (`lib/features/settings/settings_page.dart`):

```dart
// lines 42-52 (build)
// Resolve through the registry so custom providers show their display
// name, not their id. The registry future is one async hop past the
// already-loaded settings; fall back to the raw id while it resolves.
final registryAsync = ref.watch(providerRegistryProvider);
final providerName = activeProviderId != null
    ? registryAsync.maybeWhen(
        data: (registry) => _providerDisplayName(registry, activeProviderId),
        orElse: () => activeProviderId,
      )
    : null;

// lines 180-183
/// Display name for the provider with [id], resolved through the merged
/// registry (builtins + customs). Falls back to the raw id when unknown.
String _providerDisplayName(ProviderRegistry registry, String id) =>
    registry.byId(id)?.name ?? id;
```

- Exactly the prescribed `registry.byId(id)?.name ?? id` semantics; while the registry future resolves, the row shows the id (one frame in practice — `settingsStoreProvider` is already loaded, so the registry hop completes immediately after).
- `import '../../core/provider_registry.dart';` added (the `ProviderRegistry` type); the `kBuiltinProviders` scan removed.
- `ProviderRegistry.byId` re-reads storage on every call (`SettingsStore` getters read prefs live), so any rebuild of the row resolves against current storage.

## 3. (c) onboarding_page.dart attribution comment — deleted

**Before (line 302):** `/// full-page provider selection page (like rikkahub's SettingProviderPage).`

**After (lines 301-302):**

```dart
/// Step 3: Provider config — shows detected region with emoji, launches the
/// full-page provider selection page.
```

Plain functional comment, no external-project name. Project-wide attribution grep now returns zero hits (§5e).

## 4. (d) Widget tests — test/features/onboarding_settings_integration_test.dart (new)

Three tests, all green (§5a):

1. **onboarding selection lists the custom provider above the offline-skip section** — custom card (name + `自定义` chip) visible above the offline section; `进入离线陪伴模式` + advisory text still visible. (Seeds: one custom provider in mock prefs, order putting it first; tall 1080x3200 surface.)
2. **settings provider row shows the custom provider name, not its id** — mock prefs with customs JSON + `activeId` = custom uuid; asserts `Home Server LLM` present AND the raw uuid absent (anti-misleading-success: name asserted, uuid denied).
3. **settings name refreshes when the custom provider is created after the page was opened** (adversarial stale-state probe) — seeds only `activeId` (provider unknown → row falls back to the raw uuid), then persists the custom provider via `SettingsStore(prefs).saveCustomProviders(...)` and calls `container.invalidate(providerRegistryProvider)` on a `ProviderContainer` attached through `UncontrolledProviderScope`; after settle the row shows the name and the uuid is gone. Feasible as asserted-by-invalidate; invalidates the provider the row actually watches (the registry re-reads storage per resolution).

## 5. Verification commands

### 5a. `flutter test test/features/onboarding_settings_integration_test.dart`

```
00:00 +0: loading .../onboarding_settings_integration_test.dart
00:00 +0: onboarding selection lists the custom provider above the offline-skip section
00:01 +1: settings provider row shows the custom provider name, not its id
00:01 +2: settings name refreshes when the custom provider is created after the page was opened
00:01 +3: All tests passed!
```
**PASS — 3/3.**

### 5b. `flutter test test/app_test.dart` (todo e)

```
00:00 +1: MoodPetApp shows home page when onboarding is complete
00:00 +2: All tests passed!
```
**PASS — 4 consecutive runs (1 + 3 repeats), zero flakes, pump durations UNCHANGED (3s + 1s).**

Reason no bump was needed: the extra registry hop added by todo 8 (`activeProviderConfigProvider` → `providerRegistryProvider` → `settingsStoreProvider`) resolves inside the existing budget. `settingsStoreProvider` already resolved during the splash phase, so the remaining hops are plain microtask-chained futures; each `tester.pump()` drains pending microtasks, and the 3s pump covers far more frames than the two extra microtask hops require. Empirically stable across 4 runs, so the pre-existing test file was left byte-identical.

### 5c. `flutter analyze lib/features/settings/settings_page.dart lib/features/onboarding_page.dart test/features/onboarding_settings_integration_test.dart`

```
Analyzing 3 items...
No issues found! (ran in 1.4s)
```
**PASS — zero issues** (flutter_lints v6 ruleset via the project's `analysis_options.yaml`).

### 5d. `flutter test` (FULL suite)

```
00:11 +170: .../custom_provider_flow_test.dart: deleting a NON-active custom provider keeps the active id on the remaining provider
00:13 +171: All tests passed!
```
**PASS — 171/171** (168 pre-existing + 3 new from this todo's integration test file).

### 5e. Attribution grep

```
$ grep -rniE "rikka|borrowed|adapted from|inspired by" \
    lib/features/settings/settings_page.dart \
    lib/features/onboarding_page.dart \
    test/features/onboarding_settings_integration_test.dart \
    test/app_test.dart
CHANGED_FILES_GREP_EXIT=1        # zero hits

$ grep -rniE "rikka|borrowed|adapted from|inspired by" lib/ test/
FULL_GREP_EXIT=1                 # zero hits
```
**PASS — zero attribution anywhere in `lib/` or `test/`.**

---

## 6. Adversarial probes

| Probe class | Result |
|-------------|--------|
| **Stale state** — settings display name must reflect a custom provider created after settings was opened | Covered by test 3 (§4): feasible and asserted via `container.invalidate(providerRegistryProvider)` on an attached container; row switches from raw uuid to the resolved name. Note on production propagation: mutation sites (`provider_detail_page.dart:273-274,338-339`, `provider_selection_page.dart:249,283,394`) invalidate `providerListProvider`/`activeProviderConfigProvider`, not the registry provider the settings row now watches; the row still self-refreshes in the real app because returning to settings rebuilds the page (route transition) and `ProviderRegistry.byId` re-reads live storage on every build. Flagged for the todo-19 audit; no code change needed for this todo's acceptance. |
| **Misleading success** — assert the NAME text, not uuid | Tests 2 and 3 assert both directions: `find.text('Home Server LLM') == findsOneWidget` AND `find.text(_custom.id) == findsNothing`. Test 1 asserts the visible name + chip, not just card presence. |
| Long external commands | `flutter test`/`analyze` each finished in ≤ 13 s; no hangs. |
| Others (disk full, network, device absence) | n/a — widget tests run on the headless `flutter_tester`; no device or network involved. |

## 7. Constraints compliance

- ✅ Comments plain functional English; no external-project names/attribution added (grep §5e).
- ✅ Did NOT edit provider pages (`provider_selection_page.dart`, `provider_detail_page.dart`, `provider_scan_page.dart`), core files (`lib/core/**`), or any pre-existing test — `test/app_test.dart` left byte-identical after 4 green runs proved no pump bump was needed (§5b).
- ✅ No git commands; no new packages.
- ✅ `flutter analyze` zero issues on all touched files (§5c).

## 8. Files changed

| File | Change |
|------|--------|
| `lib/features/settings/settings_page.dart` | `_providerDisplayName` rewired to `registry.byId(id)?.name ?? id` via watched `providerRegistryProvider`; `provider_registry.dart` import added; `kBuiltinProviders` scan removed. |
| `lib/features/onboarding_page.dart` | Attribution comment at :302 replaced with a plain functional comment. |
| `test/features/onboarding_settings_integration_test.dart` | **New file.** 3 widget tests: onboarding merged-list/offline-section, settings custom-name display, post-open stale-state refresh. |
| `.omo/evidence/task-18-custom-providers.md` | **New file.** This evidence. |

## 9. DoneClaim

```json
{
  "task_id": "18",
  "title": "Onboarding + settings integration fixes & verification",
  "status": "done",
  "evidence_file": ".omo/evidence/task-18-custom-providers.md",
  "changes": [
    "settings_page.dart: _providerDisplayName now resolves via providerRegistryProvider (registry.byId(id)?.name ?? id) — custom active provider shows its name, not its uuid",
    "onboarding_page.dart:302: external-project attribution comment replaced with plain functional comment",
    "test/features/onboarding_settings_integration_test.dart: new — 3 widget tests (onboarding custom card above offline section; settings shows custom NAME not uuid; post-open stale-state refresh via container invalidate)"
  ],
  "verification": {
    "integration_test": "flutter test test/features/onboarding_settings_integration_test.dart — 3/3 passed",
    "app_test": "flutter test test/app_test.dart — passed 4/4 runs, pump durations unchanged (no bump needed; registry async hop resolves within existing 3s+1s budget)",
    "analyze": "flutter analyze settings_page.dart onboarding_page.dart onboarding_settings_integration_test.dart — No issues found!",
    "full_suite": "flutter test — 171/171 passed",
    "attribution_grep": "grep -rniE 'rikka|borrowed|adapted from|inspired by' lib/ test/ — zero hits"
  },
  "residual_risks": [
    "Settings row watches providerRegistryProvider while mutation sites invalidate providerListProvider/activeProviderConfigProvider; the row still self-refreshes on re-entry (route-transition rebuild + live storage reads in ProviderRegistry.byId). Flagged for the todo-19 audit."
  ]
}
```
