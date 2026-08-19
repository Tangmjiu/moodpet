# Task 13 — Custom provider create/edit/delete flow wiring verification + end-to-end flow widget test

**Date:** 2026-08-19
**Project:** /home/mjiutang/moonpet (moodpet)
**Flutter:** 3.44.6 (channel stable) • Dart 3.12.2 • flutter_riverpod ^2.6.1 • shared_preferences ^2.3.3 • flutter_lints ^6.0.0
**Scope:** `test/features/settings/custom_provider_flow_test.dart` (new, 5 tests). **Zero page edits** — the wiring audit found no gaps (see below). Nothing else touched: no core files, no codecs, no provider_scan_page, no pre-existing tests. No new packages. No git operations.

---

## Wiring audit (both page files read end-to-end, contracts verified)

**Files audited:** `lib/features/settings/provider_selection_page.dart` (902 lines) and
`lib/features/settings/provider_detail_page.dart` (1341 lines), cross-checked against
`lib/core/provider_registry.dart`, `lib/core/storage/settings_store.dart` and
`lib/core/models/provider_config.dart`.

1. **create → save → appears in `providerListProvider` with order appended** — VERIFIED, no fix.
   `ProviderSelectionPage._onAddCustomProvider` mints a `Uuid().v4()` draft
   (`isCustom: true`, empty fields; selection page lines 91-111) and pushes
   `ProviderDetailPage(provider: draft, isNewCustom: true)`. `_saveCustom` upserts into
   `loadCustomProviders()`, appends the id to the order only when `isNewCustom` and not
   already present (detail page lines 281-301), persists the key via `setApiKey`, sets
   enabled + active id; `_save` invalidates `providerListProvider` +
   `activeProviderConfigProvider` and `pop(true)` (lines 273-275). The registry reconciles
   the persisted order on every read (`ProviderRegistry.all`).
2. **edit existing custom → fields pre-populated from the overlaid config** — VERIFIED, no fix.
   `initState` seeds every controller from `widget.provider` (name / baseUrl /
   modelsEndpoint / defaultModel / chatCompletionsPath / protocol / enabled / apiKey,
   lines 122-139); the selection list hands over the registry-overlaid config
   (`_overlay` re-attaches key/override/enabled). `_loadPersistedState` re-reads
   key/enabled/models/override from `SettingsStore` post-frame as the source of truth.
   Delete affordance gated on `_isCustom && !widget.isNewCustom` (line 650).
3. **delete → customs JSON shrinks, order pruned, per-provider keys cleared, active id
   cleared if active** — VERIFIED, no fix. `_confirmDelete` (lines 303-341): confirm dialog
   with `删除后其 Key 与模型配置将一并清除` → `removeProviderState(id)` runs FIRST (its guard
   requires the id to still be in the custom list) → remove from customs + save → order
   `..remove(id)` + save → `clearActiveProviderId()` when it was the active one →
   invalidate both providers → `pop(true)`. Builtins are protected by the
   `removeProviderState` custom-list guard and by the edit-mode-only delete button.
4. **popping contracts** — VERIFIED, no fix. Save and delete both `pop(true)`; the config
   tab writes nothing until `_save` runs, so AppBar back / cancel persists nothing.
   (The models tab's per-row actions persist immediately by design; out of this flow's
   scope and untouched by the cancel test.)

**Fixes applied: none.** All four contracts were already correctly wired by todos 10-12.

---

## New test file — `test/features/settings/custom_provider_flow_test.dart` (5 tests)

Harness: `SharedPreferences.setMockInitialValues({})` per test, a hand-held
`ProviderContainer` (`sharedPrefsProvider.overrideWith`) mounted via
`UncontrolledProviderScope` so tests can `container.invalidate(providerListProvider)`
after direct store seeding and read providers back; `MaterialApp(home:
ProviderSelectionPage())` supplies the real Navigator; 1080×3200 surface so the full
16-card builtin list, the trailing add card and the detail form all lay out. The detail
page is reached exclusively through the real selection-page navigation (no direct pump
of the detail page), and its network seams stay untouched — the flows never open the
models tab nor tap 测试连接, so no fetch/test call can fire. Persistence is asserted on
raw prefs (`prefs.getString/getStringList`) and `SettingsStore`, never just UI text.

a. **CREATE** — seed order `[openai, deepseek]`; tap 添加自定义提供商 → create mode (delete
   and share buttons absent) → fill 名称 `Flow LLM`, 接口地址 `http://192.168.1.10:8080/v1`,
   默认模型 `flow-7b`, key `sk-flow` → 保存并使用 → back at selection page: card visible with
   自定义 chip; persisted: `loadCustomProviders` single entry (normalized fields), order
   exactly `[openai, deepseek, id]` (appended last), `activeProviderId == id`,
   `apiKeyFor(id) == 'sk-flow'`; raw customs JSON contains the name but NOT the key;
   `providerListProvider` lists the custom third with the seeded ids first.
b. **EDIT** — after create, tap the `Flow LLM` card → fields pre-populated (名称
   `Flow LLM`, 接口地址 `http://192.168.1.10:8080/v1`, 默认模型 `flow-7b`, 模型列表端点
   `/models`, 聊天路径 `/chat/completions`, API Key `sk-flow`; delete button present) →
   change 默认模型 to `flow-13b` → save → customs still has exactly 1 entry with
   `defaultModel == 'flow-13b'`; raw JSON contains `flow-13b`; the card shows the new
   effective model.
c. **DELETE ACTIVE** — after create, seed `sk-flow-secret` key + `['flow-7b-32k']` models
   for the id (so the cleanup is observable, not vacuous) → open card → 删除此提供商 →
   confirm dialog text asserted → 删除 → back at selection: card gone; persisted: customs
   empty, order empty, `activeProviderId == null`, `apiKeyFor/modelsFor` empty; raw
   per-id keys physically removed (`apiKey.<id>`, `models.<id>`, `activeId` all null);
   `activeProviderConfigProvider` resolves null (home falls back to offline mode).
d. **CANCEL** — open create mode → type a name → AppBar back button → selection page;
   customs/order/activeId all untouched; raw `customProviders` key absent.
e. **DELETE NON-ACTIVE** — create A via the full UI flow (becomes active), seed B directly
   via `store.saveCustomProviders` + `saveProviderOrder` + container invalidate → delete
   B → B's card and entry gone, order `[idA]`, and `activeProviderId` still A's id (raw
   prefs `activeId == idA`).

---

## Verification (commands + output)

### Targeted suite — green (5/5)

```
$ flutter test test/features/settings/custom_provider_flow_test.dart
00:00 +0: loading .../test/features/settings/custom_provider_flow_test.dart
00:00 +0: create flow persists the custom provider, appends it to the order and lists it with the custom chip
00:01 +1: edit flow pre-populates the fields from the overlaid config and persists the update
00:02 +2: deleting the ACTIVE custom provider clears its per-provider state, prunes the order and clears the active id
00:03 +3: backing out of create mode without saving persists nothing
00:03 +4: deleting a NON-active custom provider keeps the active id on the remaining provider
00:04 +5: All tests passed!
```

### Analyze — zero issues

```
$ flutter analyze lib/features/settings/ test/features/settings/custom_provider_flow_test.dart
Analyzing 2 items...
No issues found! (ran in 1.4s)
```

### Full suite — green (168/168)

```
$ flutter test
...
00:08 +167: .../custom_provider_flow_test.dart: deleting a NON-active custom provider keeps the active id on the remaining provider
00:09 +168: All tests passed!
```

168 tests, 0 failures — includes the pre-existing `provider_selection_page_test.dart`
and `provider_detail_page_test.dart` suites against the unchanged page files.

### Attribution grep — zero hits

```
$ grep -rniE "rikka|borrowed|adapted from|inspired by" test/features/settings/custom_provider_flow_test.dart lib/features/settings/provider_selection_page.dart lib/features/settings/provider_detail_page.dart
(no matches; exit 1)
```

---

## Adversarial coverage

- **Stale state:** test (c) deletes the ACTIVE provider and asserts `activeProviderId`
  cleared (store + raw prefs + `activeProviderConfigProvider` resolves null); test (e)
  deletes a NON-active provider and asserts the active id survives on A. Delete ordering
  hazard (removeProviderState's membership guard) is covered by (c) asserting the seeded
  key/models are physically gone.
- **Misleading success:** every flow asserts raw persisted prefs
  (`customProviders` JSON string, `order` string list, `activeId`, per-id key/models
  keys) in addition to UI text; (a) also asserts the merged `providerListProvider` order
  from the real registry, and that the API key never enters the provider JSON.
- **Flaky:** all async boundaries settled with `pumpAndSettle`; tall fixed surface so no
  scrolling is needed for any tap; the detail page's auto-fetch cannot fire (models tab
  never opened; key-only guard unsatisfied in (c)'s flow).
- **Not applicable:** camera/platform channels (no device features in this flow);
  golden tests (none in the repo); reduced-motion (no continuous animations added);
  malicious input (invalid-input create validation already covered by the detail page
  suite, todo 11/12 evidence test a).

## Residual risk

- None blocking. The two pre-existing page implementations required zero changes; the
  flow tests pin the cross-page contract (navigation modes, pop results, persisted keys)
  so any future regression in either page fails loudly here.
- `provider.name` equality is not part of `ProviderConfig.==`; the tests therefore
  assert persisted fields individually rather than whole-object equality.
