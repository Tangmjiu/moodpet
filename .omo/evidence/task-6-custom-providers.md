# Task 6 — Custom Providers: SettingsStore custom-provider storage, order, enabled flags, model lists

**Date:** 2026-08-18
**Project:** /home/mjiutang/moonpet (moodpet)
**Flutter:** 3.44.6 (channel stable) • Dart 3.12.2 • shared_preferences 2.5.5 • flutter_lints ^6.0.0
**Scope:** `lib/core/storage/settings_store.dart` (extended) + `test/core/storage/settings_store_test.dart` (new) only.

---

## Changes

### `lib/core/storage/settings_store.dart`

- New imports: `dart:convert`, `../models/provider_config.dart`.
- New private key constants (alongside existing ones, style-matched):
  - `_kCustomProvidersKey = 'moodpet.provider.customProviders'`
  - `_kProviderOrderKey = 'moodpet.provider.order'`
  - `_kProviderEnabledPrefix = 'moodpet.provider.enabled.'`
  - `_kProviderModelsPrefix = 'moodpet.provider.models.'`
- New sections and methods (all pre-existing constants/methods byte-compatible; only appended):
  - `loadCustomProviders()` — null/empty → `[]`; `jsonDecode` wrapped so any decode error → `[]`; non-List JSON → `[]`; each entry parsed via `ProviderConfig.fromJson` inside per-entry try/catch, malformed entries skipped, never rethrows.
  - `saveCustomProviders(List<ProviderConfig>)` — `jsonEncode(list of toJson())`; doc comment notes `toJson` never serialises secrets (release-safe).
  - `loadProviderOrder()` / `saveProviderOrder(List<String>)` — string-list round-trip, absent → `[]`.
  - `isProviderEnabled(String id)` — `getBool ?? true` (default enabled).
  - `setProviderEnabled(String id, bool)` — enabling removes the key (default is true, keeps prefs lean); disabling stores `false`.
  - `modelsFor(String id)` / `setModels(String id, List<String>)` — string-list round-trip; empty list removes the key.
  - `removeProviderState(String id)` — guard: no-op unless `id` appears in `loadCustomProviders()`; then removes the apiKey / modelOverride / enabled / models keys for that id.

### `test/core/storage/settings_store_test.dart` (new)

10 tests across 6 groups covering plan cases a–j, using
`SharedPreferences.setMockInitialValues` (built into shared_preferences; no new dependency).

---

## Step: test-first (before implementation)

Command: `flutter test test/core/storage/settings_store_test.dart`

Result: FAIL (compile errors — new methods undefined). Relevant lines:

```
test/core/storage/settings_store_test.dart:54:19: Error: The method 'saveCustomProviders' isn't defined for the type 'SettingsStore'.
      await store.saveCustomProviders(providers);
                  ^^^^^^^^^^^^^^^^^^^
test/core/storage/settings_store_test.dart:55:28: Error: The method 'loadCustomProviders' isn't defined for the type 'SettingsStore'.
      final loaded = store.loadCustomProviders();
                           ^^^^^^^^^^^^^^^^^^^
test/core/storage/settings_store_test.dart:75:26: Error: The method 'loadCustomProviders' isn't defined for the type 'SettingsStore'.
test/core/storage/settings_store_test.dart:78:25: Error: The method 'loadCustomProviders' isn't defined for the type 'SettingsStore'.
test/core/storage/settings_store_test.dart:83:20: Error: The method 'loadCustomProviders' isn't defined for the type 'SettingsStore'.
test/core/storage/settings_store_test.dart:99:28: Error: The method 'loadCustomProviders' isn't defined for the type 'SettingsStore'.
test/core/storage/settings_store_test.dart:108:20: Error: The method 'loadProviderOrder' isn't defined for the type 'SettingsStore'.
test/core/storage/settings_store_test.dart:110:19: Error: The method 'saveProviderOrder' isn't defined for the type 'SettingsStore'.
```

(The same class of "method isn't defined for SettingsStore" error was emitted for every new
API used by the tests; no pre-existing code or test was touched.)

## VERIFY 1 — new tests green

Command: `flutter test test/core/storage/settings_store_test.dart`

```
00:00 +0: SettingsStore custom providers save + load round-trips two providers without persisting API keys
00:00 +1: SettingsStore custom providers load returns empty list when the key is absent or empty
00:00 +2: SettingsStore custom providers load returns empty list for a corrupt JSON string
00:00 +3: SettingsStore custom providers load skips malformed entries and keeps the valid ones
00:00 +4: SettingsStore provider order order round-trips and defaults to empty
00:00 +5: SettingsStore provider enabled flags defaults to true; disabling persists; re-enabling removes the key
00:00 +6: SettingsStore provider model lists setModels round-trips and an empty list removes the key
00:00 +7: SettingsStore removeProviderState clears every per-provider key for a custom provider id
00:00 +8: SettingsStore removeProviderState never clears keys for a built-in provider id (guard)
00:00 +9: SettingsStore legacy coexistence legacy provider keys are untouched by custom-provider storage
00:00 +10: All tests passed!
```

Result: PASS — 10/10 green.

## VERIFY 2 — analyzer clean

Command: `flutter analyze lib/core/storage/settings_store.dart test/core/storage/settings_store_test.dart`

```
Analyzing 2 items...
No issues found! (ran in 0.8s)
```

Result: PASS — zero issues. `lsp_diagnostics` on both files also reports none.

## VERIFY 3 — pre-existing tests unchanged

Command: `flutter test` (full suite)

```
00:01 +93: /home/mjiutang/moonpet/test/models/provider_config_test.dart: RegionInfo country names countryNameFromCode returns upper-cased code for unknown
00:01 +94: All tests passed!
```

Result: PASS — 94/94 (84 pre-existing + 10 new) green; no pre-existing file edited.

## VERIFY 4 — attribution grep

Command: `grep -rniE "rikka|borrowed|adapted from|inspired by|generated by|written by|co-authored" lib/core/storage/settings_store.dart test/core/storage/settings_store_test.dart`

```
attribution grep exit: 1
```

Result: PASS — zero hits (grep exit 1 = no matches). A broader sweep
(`claude|anthropic|openai|gpt|copilot|cursor|aider|codeium|windsurf|gemini|codex|kimi|qwen|deepseek|glm`)
matches only the project's own domain identifiers mandated by the spec: `LlmProtocol.openai` /
`LlmProtocol.gemini` enum values and built-in catalog ids (`deepseek`, `openai`) that cases (a), (i)
and (j) explicitly require. No external-project attribution exists in either file.

## Adversarial classes

- **Malformed input → PROBED (cases c, d, j).** Corrupt JSON string `'{not json'` returns `[]`
  without throwing (test: "load returns empty list for a corrupt JSON string"); a list mixing one
  valid entry with one wrong-typed entry (`defaultModel: 42` → `FormatException` inside
  `ProviderConfig.fromJson`) returns the valid entry only (test: "load skips malformed entries");
  absent/empty key and legacy-only storage both yield `[]` while legacy reads stay intact (tests:
  "absent or empty", "legacy provider keys are untouched").
- **Stale state → PROBED (cases h, i).** `removeProviderState` effects are verified by re-reading
  both through the store (`apiKeyFor`/`modelOverrideFor`/`isProviderEnabled`/`modelsFor`) and
  through raw `prefs.containsKey` after the call — all four keys gone for a custom id; for a
  built-in id the seeded apiKey survives via store read AND raw key check (guard proven, not assumed).
- **Secret leakage → PROBED (case a).** Raw stored JSON string is read back from prefs and asserted
  to not contain the `sk-` marker even though both saved providers carried `sk-*` apiKey values.
- **Dirty worktree** — N/A: only the two intended files plus this evidence file were touched; no git
  commands run per constraints (pre-existing worktree dirt left untouched).
- **Hung commands** — N/A: all commands completed in ~1s (see outputs above).
- **Flaky tests** — N/A: no timers, randomness, or real I/O; SharedPreferences is the in-memory
  mock; two consecutive runs are identical.
- **Misleading success output** — guarded: the test-first failing compile output above proves the
  tests exercise the new APIs (they did not compile before the implementation).
- **Prompt injection** — N/A: no external/untrusted input consumed; all test data is literal.
- **Cancel-resume / repeated interruptions** — N/A: single-pass deterministic task.

## Cleanup receipt

None required. `flutter test` wrote only to `.dart_tool/` (gitignored); no temp files, no stray
files outside the two intended paths plus this evidence file. No new packages, no git operations.
