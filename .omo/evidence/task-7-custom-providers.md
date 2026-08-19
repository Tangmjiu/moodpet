# Task 7 — Custom Providers: ProviderRegistry merge + resolution + Riverpod exposure

**Date:** 2026-08-18
**Project:** /home/mjiutang/moonpet (moodpet)
**Flutter:** 3.44.6 (channel stable) • Dart 3.12.2 • shared_preferences 2.5.5 • flutter_riverpod ^2.6.1 • flutter_lints ^6.0.0
**Scope:** `lib/core/provider_registry.dart` (new), `lib/core/providers.dart` (append-only), `lib/core/models/provider_config.dart` (one-line root-cause fix), `test/core/provider_registry_test.dart` (new) only.

---

## Changes

### `lib/core/provider_registry.dart` (new)

`class ProviderRegistry { ProviderRegistry(this._settings); }` over `SettingsStore`:

- `List<ProviderConfig> all()` — builtins (`kBuiltinProviders`, catalog order) then persisted
  customs (`loadCustomProviders()`, storage order), each passed through `_overlay`
  (`copyWith(apiKey: apiKeyFor(id), modelOverride: modelOverrideFor(id), enabled: isProviderEnabled(id))`).
  The persisted order list (`loadProviderOrder()`) is reconciled on every read via an
  insertion-ordered `LinkedHashMap`: ids in the order list come first (stale ids silently
  dropped — `remove` returns null and the loop moves on), remaining providers follow in
  builtin-catalog-then-customs order. Empty order list short-circuits to the merged order.
- `ProviderConfig? byId(String id)` — linear scan of `all()` (16 builtins + few customs).
- `ProviderConfig? activeById(String id)` — `byId(id)`, null when missing OR `!enabled`.
  The disabled-as-absent semantic lives only here; `byId` still resolves disabled providers
  for management UI.
- Plain functional doc comments; no external-project names or attribution.

### `lib/core/providers.dart` (append-only)

- New import `provider_registry.dart` (sorted into the existing relative-import block).
- Appended two providers after `activeProviderConfigProvider`; zero existing providers touched:
  - `providerRegistryProvider` — `FutureProvider<ProviderRegistry>` deriving from
    `settingsStoreProvider.future`.
  - `providerListProvider` — `FutureProvider<List<ProviderConfig>>` =
    `(await providerRegistryProvider.future).all()`.

### `lib/core/models/provider_config.dart` (one-line root-cause fix)

`copyWith` did not pass `isCustom` to the new instance, so any overlaid custom provider
silently degraded to `isCustom: false`. The registry's specified overlay mechanism
(`copyWith`) exposed this; fixed by adding `isCustom: isCustom,` to the `copyWith`
constructor call. Pre-existing copyWith tests use a non-custom `base` fixture
(`base.copyWith() == base` still holds: false preserved), so no pre-existing test needed
editing — confirmed by the full-suite run below.

### `test/core/provider_registry_test.dart` (new)

8 tests across 3 groups covering plan cases a–g with `SharedPreferences.setMockInitialValues`
(built into shared_preferences; no new dependency). The `_registry()` helper returns the
`(ProviderRegistry, SettingsStore)` pair so tests can mutate the store after registry
construction (registry reads through to prefs on every call — no caching).

---

## Step: test-first (before implementation)

Command: `flutter test test/core/provider_registry_test.dart`

Result: FAIL (compile errors — registry file/type missing). Relevant lines:

```
test/core/provider_registry_test.dart:3:8: Error: Error when reading 'lib/core/provider_registry.dart': No such file or directory
import 'package:moodpet/core/provider_registry.dart';
       ^
test/core/provider_registry_test.dart:20:9: Error: Type 'ProviderRegistry' not found.
Future<(ProviderRegistry, SettingsStore)> _registry([
        ^^^^^^^^^^^^^^^^
test/core/provider_registry_test.dart:26:11: Error: Method not found: 'ProviderRegistry'.
  return (ProviderRegistry(store), store);
          ^^^^^^^^^^^^^^^^
00:00 +0 -1: Some tests failed.
```

## Step: red-to-green intermediate (root-cause find)

After implementing the registry, the first green run failed 2 tests — both
`expect(...isCustom, isTrue)`:

```
00:00 +2 -1: ProviderRegistry.all custom providers merge after the builtins by default [E]
  Expected: true
    Actual: <false>
  test/core/provider_registry_test.dart 88:7
00:00 +4 -2: ProviderRegistry.byId / activeById byId resolves builtins and customs; unknown ids return null [E]
  test/core/provider_registry_test.dart 136:7
```

Diagnosis (proven with a throwaway debug test, since deleted): `saveCustomProviders` →
`loadCustomProviders` round-trips `isCustom: true` correctly; the flag was lost inside
`ProviderConfig.copyWith`, which omitted `isCustom: isCustom` from its constructor call.
One-line fix in `copyWith` (above); both failures went green without touching the tests.

## VERIFY 1 — new tests green

Command: `flutter test test/core/provider_registry_test.dart`

```
00:00 +0: ProviderRegistry.all empty prefs returns the 16 builtins in catalog order, all enabled with empty apiKey
00:00 +1: ProviderRegistry.all apiKey + enabled overlays apply to builtins; activeById hides a disabled provider while byId still finds it
00:00 +2: ProviderRegistry.all custom providers merge after the builtins by default
00:00 +3: ProviderRegistry.all persisted order is reconciled: known ids first, stale ids dropped, the rest appended in catalog-then-customs order
00:00 +4: ProviderRegistry.all modelOverride overlay applies and drives effectiveModel
00:00 +5: ProviderRegistry.byId / activeById byId resolves builtins and customs; unknown ids return null
00:00 +6: ProviderRegistry.byId / activeById activeById returns the overlaid provider when enabled
00:00 +7: ProviderRegistry equality sensitivity toggling enabled changes the overlaid config (== includes enabled, so Riverpod invalidation repaints)
00:00 +8: All tests passed!
```

Result: PASS — 8/8 green.

## VERIFY 2 — analyzer clean

Command: `flutter analyze lib/core/provider_registry.dart lib/core/providers.dart test/core/provider_registry_test.dart`

```
Analyzing 3 items...
No issues found! (ran in 0.6s)
```

Result: PASS — zero issues. Also run with `lib/core/models/provider_config.dart` included
(4 items): zero issues. `lsp_diagnostics` on the new registry file reports none.

## VERIFY 3 — full suite

Command: `flutter test`

```
00:01 +120: All tests passed!
```

Result: PASS — 120/120 (112 pre-existing from todos 1–6/14/17 + 8 new). No pre-existing
test or file edited beyond the one-line `copyWith` fix.

## VERIFY 4 — attribution grep

Command: `grep -rniE "rikka|borrowed|adapted from|inspired by|generated by|written by|co-authored" lib/core/provider_registry.dart lib/core/providers.dart lib/core/models/provider_config.dart test/core/provider_registry_test.dart`

```
attribution grep exit: 1
```

Result: PASS — zero hits (grep exit 1 = no matches). The broader sweep
(`claude|anthropic|openai|gemini|deepseek|kimi|...`) matches only the project's own domain
identifiers mandated by the spec: built-in catalog ids (`deepseek`, `kimi`, `openai`) and
`LlmProtocol` enum values that cases (a), (b), (e), (f) explicitly require.

## Adversarial classes

- **Stale state → PROBED (case d).** `saveProviderOrder(['custom-b','deepseek','ghost-id'])`
  with two customs persisted: `'ghost-id'` resolves to nothing and is silently dropped
  (asserted `ids isNot(contains('ghost-id'))` and length stays 18); the surviving order is
  exactly `custom-b, deepseek`, then builtins-minus-deepseek in catalog order, then
  `custom-a` — proven by comparing the full tail against a list computed from
  `kBuiltinProviders` in the test, not hardcoded.
- **Malformed input → PROBED (case a).** Empty prefs: `all()` returns exactly the 16
  builtins in catalog order, every entry `enabled == true`, `apiKey == ''`,
  `isCustom == false` (per-entry assertions with `reason:`). Corrupt-JSON customs storage is
  already covered by task 6's settings-store tests (registry consumes `loadCustomProviders`,
  which never throws).
- **Disabled-as-absent single-source → PROBED (case b).** After `setProviderEnabled('deepseek', false)`:
  `activeById('deepseek')` is null while `byId('deepseek')` still resolves with
  `enabled == false` and the seeded key — the two semantics are asserted side by side.
- **Riverpod repaint sensitivity → PROBED (case g).** Toggling `setProviderEnabled` between
  two `byId` snapshots flips `==` (asserted `isNot(equals(before))`) with `apiKey`,
  `modelOverride`, `id` asserted unchanged — only `enabled` differs, so
  `providerListProvider` invalidation will repaint list cards.
- **Overlay non-destructiveness → PROBED.** The two failing-first-then-fixed tests prove the
  overlay preserves `isCustom` for customs (the `copyWith` root-cause fix); builtin fields
  (`baseUrl`, `protocol`, etc.) are constructor-carried and covered by case (a)'s
  catalog-order assertion and the full suite.
- **Dirty worktree** — N/A: only the four intended files plus this evidence file were
  touched; no git commands run per constraints.
- **Hung commands** — N/A: all commands completed in ~1s (see outputs above).
- **Flaky tests** — N/A: no timers, randomness, or real I/O; SharedPreferences is the
  in-memory mock; repeated runs are identical.
- **Misleading success output** — guarded: the failing-compile output above proves the tests
  exercise the new type, and the intermediate 2-test failure proves they detect real
  behavioral regressions (the `isCustom` loss).
- **Prompt injection** — N/A: no external/untrusted input consumed; all test data is literal.
- **Cancel-resume / repeated interruptions** — N/A: single-pass deterministic task.

## Cleanup receipt

The throwaway debug test (`test/core/_debug_test.dart` + `/tmp/opencode/debug_registry_test.dart`)
used to diagnose the `isCustom` loss was deleted immediately after diagnosis. `flutter test`
wrote only to `.dart_tool/` (gitignored); no other stray files. No new packages, no git
operations.
