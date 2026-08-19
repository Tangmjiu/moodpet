# Task 9 — Custom Providers: storage + registry legacy-install integration test

**Date:** 2026-08-19
**Project:** /home/mjiutang/moonpet (moodpet)
**Flutter:** 3.44.6 (channel stable) • Dart 3.12.2 • shared_preferences 2.5.5 • flutter_lints ^6.0.0
**Scope:** `test/core/legacy_install_integration_test.dart` (NEW) only. No production code touched, no pre-existing tests edited, no new packages.

---

## What this task is

Todo 9 of `.omo/plans/custom-providers.md` asks for an integration test that
simulates an EXISTING (pre-refactor) install — SharedPreferences seeded with
ONLY the legacy keys `moodpet.provider.activeId`,
`moodpet.provider.apiKey.<id>`, `moodpet.provider.modelOverride.<id>` — and
proves the `SettingsStore` + `ProviderRegistry` pair reads them byte-for-byte,
overlays them onto the builtin catalog, and never migrates or deletes them.

Per the task brief: production code already exists and is verified, so these
tests are **characterization of existing behavior**, not test-first-new-code.
The first run is the baseline; any failure would be a real integration defect
to escalate, not a patch target. **All 5 cases passed on the first run** — no
production defect found.

---

## The new file

`test/core/legacy_install_integration_test.dart` — a single `group('Legacy
install integration')` with five tests, each backed by a fresh
`SharedPreferences.setMockInitialValues` seed via the `_legacyInstall` helper
that returns a `(ProviderRegistry, SettingsStore, SharedPreferences)` triple
over the SAME prefs instance (so raw prefs can be re-read after registry use
for the byte-identical assertions).

Raw key constants are mirrored from `SettingsStore` (same pattern as the
existing `test/core/storage/settings_store_test.dart`) so the tests can seed
and inspect storage directly without going through the store API — this is
what makes the "NOTHING migrated" assertions meaningful.

The custom-provider factory `_custom(id)` matches the shape the settings UI
persists (the same factory used by `test/core/provider_registry_test.dart`).

No helper from the existing test files is imported or duplicated — the file is
self-contained, so editing it can never disturb `settings_store_test.dart` or
`provider_registry_test.dart`.

---

## Case-by-case

### Case 1 — Legacy upgrade path (no migration)

Seed:
```
moodpet.provider.activeId                 = 'deepseek'
moodpet.provider.apiKey.deepseek          = 'sk-legacy'
moodpet.provider.modelOverride.deepseek   = 'deepseek-reasoner'
```

Assertions:
- `registry.byId('deepseek').apiKey == 'sk-legacy'`
- `.modelOverride == 'deepseek-reasoner'`
- `.effectiveModel == 'deepseek-reasoner'` (override drives effectiveModel)
- `registry.activeById('deepseek')` non-null (enabled by default → resolvable)
- `registry.all().length == 16` and ids match `kBuiltinProviders` order (no
  customs, no order key → catalog order)
- `store.loadCustomProviders() == []`, `store.loadProviderOrder() == []`
- **NOTHING migrated** — re-read raw prefs: `prefs.getString(_kActiveIdKey)`
  == `'deepseek'`, `prefs.getString('...apiKey.deepseek')` == `'sk-legacy'`,
  `prefs.getString('...modelOverride.deepseek')` == `'deepseek-reasoner'`;
  `prefs.containsKey(_kCustomProvidersKey)` is `false`,
  `prefs.containsKey(_kProviderOrderKey)` is `false`.

### Case 2 — Legacy + custom coexistence

Same legacy seed as case 1, then `store.saveCustomProviders([_custom('my-local')])`.

Assertions:
- `registry.all().length == 17` (16 builtins + 1 custom)
- First 16 ids == `kBuiltinProviders` order; `all[16].id == 'my-local'`,
  `all[16].isCustom == true` (order reconcile appends the custom AFTER
  builtins because no order key is set)
- Legacy deepseek overlay STILL intact: `byId('deepseek').apiKey ==
  'sk-legacy'`, `.modelOverride == 'deepseek-reasoner'`,
  `.effectiveModel == 'deepseek-reasoner'`
- **Legacy keys byte-identical afterwards** — re-read raw prefs for the three
  legacy keys, same values as seeded.

### Case 3 — Legacy active id pointing at unknown provider

Seed `moodpet.provider.activeId = 'removed-provider'` (no key, no override).

Assertions:
- `registry.activeById('removed-provider') == null` (no crash)
- `registry.byId('removed-provider') == null`
- `registry.all().length == 16` (catalog still loads)

### Case 4 — Legacy modelOverride survives order change

Seed as case 1, then `store.saveProviderOrder(['kimi', 'deepseek'])`.

Assertions:
- `registry.all().length == 16`
- `all.first.id == 'kimi'`, `all[1].id == 'deepseek'` (order reconciled)
- `registry.byId('deepseek').modelOverride == 'deepseek-reasoner'` (override
  NOT stripped by reorder)
- `.effectiveModel == 'deepseek-reasoner'`

### Case 5 — Regression guard: direct SettingsStore legacy semantics

Seed `activeId='deepseek'` + `apiKey.deepseek='sk-legacy'` (no override).

Assertions (on the store directly, the pre-refactor read path):
- `store.activeProviderId == 'deepseek'`
- `store.apiKeyFor('deepseek') == 'sk-legacy'`
- `store.modelOverrideFor('deepseek') == null` (null, never empty-string, for
  the override API — pins the contract)
- `registry.activeById('deepseek')?.apiKey == 'sk-legacy'` (registry composes
  the same picture from those reads)

---

## Verification summary

| Check | Result |
|---|---|
| `flutter test test/core/legacy_install_integration_test.dart` | 5/5 passed (first run, baseline — no production defect) |
| `flutter analyze test/core/legacy_install_integration_test.dart` | No issues found (ran in 1.3s) |
| `flutter test` (full suite) | 163/163 passed |
| Attribution grep `claude\|anthropic\|gpt\|copilot\|generated.by\|co-authored\|chatgpt\|rikka\|borrowed\|adapted from\|inspired by` on the new file | 0 hits |
| LSP diagnostics on the new file | no diagnostics |

Cleanup: none required — single new test file, no production change.

---

## Command outputs

### `flutter analyze test/core/legacy_install_integration_test.dart`

```
$ flutter analyze test/core/legacy_install_integration_test.dart
Analyzing legacy_install_integration_test.dart...
No issues found! (ran in 1.3s)
```

### `flutter test test/core/legacy_install_integration_test.dart`

```
$ flutter test test/core/legacy_install_integration_test.dart
00:00 +0: loading /home/mjiutang/moonpet/test/core/legacy_install_integration_test.dart
00:00 +0: Legacy install integration case 1: legacy keys overlay the builtin deepseek and are left byte-identical in storage (no migration)
00:00 +1: Legacy install integration case 2: adding a custom provider appends after builtins and leaves the legacy deepseek overlay byte-identical
00:00 +2: Legacy install integration case 3: a legacy activeId pointing at a removed/unknown provider resolves to null without crashing and the catalog still loads
00:00 +3: Legacy install integration case 4: a legacy modelOverride is still applied after the user reorders providers
00:00 +4: Legacy install integration case 5: direct SettingsStore reads match pre-refactor legacy semantics (apiKeyFor + activeProviderId)
00:00 +5: All tests passed!
```

### `flutter test` (full suite)

```
$ flutter test
...
00:06 +163: All tests passed!
```

### Attribution grep

```
$ grep -rniE "claude|anthropic|gpt|copilot|generated.by|co-authored|chatgpt|rikka|borrowed|adapted from|inspired by" \
    test/core/legacy_install_integration_test.dart
# (no output — 0 hits, exit 1)
```

### LSP diagnostics

```
lsp_diagnostics(/home/mjiutang/moonpet/test/core/legacy_install_integration_test.dart)
→ No diagnostics found
```

---

## Adversarial review

- **Stale state (cases 1 & 2):** the "NOTHING migrated / byte-identical
  afterwards" assertions read the raw legacy keys back through
  `prefs.getString(...)` AFTER the registry has been constructed and exercised
  (`registry.all()`, `registry.byId`, `registry.activeById` all read overlays
  before the assertion). The registry and store are read-only over the seeded
  keys; if any code path silently wrote/migrated, the raw-prefs re-read would
  catch it. The assertion is on the raw stored string, not derived state, so a
  future read-path change cannot make it pass falsely.
- **Misleading success (cases 1, 2, 5):** assertions are on the exact seeded
  values (`'sk-legacy'`, `'deepseek-reasoner'`, `'deepseek'`) read through
  BOTH the public API (`apiKeyFor`, `modelOverrideFor`, `activeProviderId`,
  `registry.byId(...).apiKey`) AND the raw prefs string — so a provider
  resolved without the overlay, or a value silently defaulted, would fail.
- **Cache/reuse of prefs across cases:** n/a — each case builds a fresh
  `_legacyInstall(...)` over a fresh `SharedPreferences.setMockInitialValues`
  seed; no state leaks between cases.
- **Order-reconcile correctness (case 4):** asserts both the new first
  position (`all.first.id == 'kimi'`) and that the overlay survives the
  reorder, so a reorder that dropped overlays would fail on the
  `modelOverride` assertion.
- **Unknown-id crash guard (case 3):** asserts `activeById` and `byId` BOTH
  return null AND `all()` still returns 16 — a registry that threw on an
  unknown active id, or that returned an empty list, would fail.

Cleanup: none.
