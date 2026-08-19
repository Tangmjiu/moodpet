# Task 10 — Custom Providers: provider_selection_page reworked into merged provider-management list

**Date:** 2026-08-18
**Project:** /home/mjiutang/moonpet (moodpet)
**Flutter:** 3.44.6 (channel stable) • Dart 3.12.2 • flutter_riverpod ^2.6.1 • flutter_svg ^2.3.0 • uuid ^4.5.1 (already in pubspec) • flutter_lints ^6.0.0
**Scope:** `lib/features/settings/provider_selection_page.dart` (reworked), `test/features/settings/provider_selection_page_test.dart` (new) only. `provider_detail_page.dart` / `settings_store.dart` / `providers.dart` untouched by this task; no pre-existing tests touched; no new packages.

---

## Changes

### `lib/features/settings/provider_selection_page.dart`

- **Attribution doc comment deleted** (old line 3, "Inspired by …") and replaced with a plain
  functional file doc comment describing the merged list, card contents and create flow.
- **Data source:** `kBuiltinProviders` usage replaced with `ref.watch(providerListProvider)`.
  `AsyncValue` handled: centered `CircularProgressIndicator` while loading; error state with
  message + 重试 `FilledButton` calling `ref.invalidate(providerListProvider)`.
  `_filteredProviders` getter became `_filterProviders(list)` — same name/id
  case-insensitive `contains` filtering, now over the merged list. Region banner and
  `_isRecommendedForRegion` (kChinaRecommendedProviderIds / kGlobalRecommendedProviderIds)
  are byte-for-byte unchanged.
- **List → `ReorderableListView.builder`** inside `Expanded`, `buildDefaultDragHandles: false`,
  every card keyed `ValueKey(provider.id)`. Drag affordance is an explicit
  `ReorderableDragStartListener` handle rendered only when `_searchQuery.isEmpty`
  (`dragIndex == null` hides it while filtering). `onReorderItem` (the non-deprecated
  callback — see SDK note below) no-ops when a search filter is active, otherwise builds the
  full id list from the currently displayed order, persists via
  `settings.saveProviderOrder(ids)` inside try/catch (failure keeps the old order, UI stays
  responsive), then `ref.invalidate(providerListProvider)`.
- **`+ 添加自定义提供商` card** is a non-reorderable sibling BELOW the
  `Expanded(ReorderableListView)` — same Column level as the fromOnboarding section, never a
  list item. Styled like a provider card but dashed/subtle: 52px rounded `+` box
  (surfaceContainerHighest @ 0.5 alpha), title 添加自定义提供商, subtitle 自定义接口地址与协议,
  rounded dashed outline painted by a small `_DashedBorderPainter` (dash 6 / gap 4,
  outlineVariant, 1.5px stroke). onTap builds a fresh draft
  `ProviderConfig(id: const Uuid().v4(), name: '', baseUrl: '', defaultModel: '', apiKey: '',
  iconAsset: '', brandColor: '', isCustom: true)` and pushes
  `ProviderDetailPage(provider: draft, fromOnboarding: widget.fromOnboarding,
  isNewCustom: true)`. `package:uuid/uuid.dart` imported.
- **Card (`_ProviderCard`)**: icon renders the letter-avatar directly when
  `provider.iconAsset.isEmpty` (customs) — `SvgPicture.asset` is never called with an empty
  path; empty name falls back to `?`. Builtins keep the existing SVG + placeholderBuilder
  path unchanged. Badges: 推荐 chip unchanged; new 自定义 chip
  (secondaryContainer/onSecondaryContainer) when `isCustom`; when `!enabled` the whole card
  content is wrapped in `Opacity(0.5)` and an 已停用 chip shows
  (surfaceContainerHighest/onSurfaceVariant — see SDK note below). Below the effective-model
  mono line, `'$modelCount 个模型'` caption renders when the count is non-zero; the page
  watches `settingsStoreProvider` and reads `modelsFor(id).length` synchronously once
  resolved (`valueOrNull ?? 0`). The mono caption now shows `provider.effectiveModel`.
  Tap still routes through the unchanged `_onProviderTap`. The 需网络代理 / 国内可直连 row is
  kept for builtins and hidden for customs (custom endpoint reachability is unknown).
- **Not added** (per scope): no AppBar import/QR action (todo 16), no delete affordance
  (lives in the detail page), fromOnboarding offline-mode bottom section byte-identical.

### `test/features/settings/provider_selection_page_test.dart` (new)

- Pumps `ProviderSelectionPage` (fromOnboarding=false) in
  `ProviderScope(overrides: [sharedPrefsProvider.overrideWith((ref) async => prefs)])` +
  `MaterialApp`, on a 1080x3200 logical test surface so all 17 lazy-built cards exist in the
  tree. Seeds via `SharedPreferences.setMockInitialValues`:
  - `moodpet.provider.customProviders` = JSON of one custom provider
    (id `test-custom`, name `Test Custom LLM`, `toJson()` format),
  - `moodpet.provider.order` = `['test-custom']` (custom first),
  - `moodpet.provider.enabled.deepseek` = `false`,
  - `moodpet.provider.models.kimi` = `['m1', 'm2']`.
- Test 1 asserts the custom provider name, 自定义 chip, deepseek's 已停用 chip, kimi's
  `2 个模型` caption, the 添加自定义提供商 add card (+ subtitle), and the absence of the
  offline-mode section when fromOnboarding=false.
- Test 2 drags the first card's drag handle past the next card and asserts the persisted
  `moodpet.provider.order` is the FULL 17-id list with the custom moved below OpenAI, and
  that the rebuilt list (after the provider invalidation) shows OpenAI above the custom.
- Test 3 enters a search query, asserts the drag handles disappear
  (`find.byIcon(Icons.drag_handle_rounded)` findsNothing), drags the filtered card, and
  asserts the persisted order is unchanged (`['test-custom']`) — the reorder is a no-op
  while filtering.

## SDK / contract notes (deviations from the task text, both forced by gates)

- **`onReorder` → `onReorderItem`:** Flutter 3.44.6 deprecates
  `ReorderableListView.onReorder` ("Use the onReorderItem callback instead … deprecated after
  v3.41.0-0.0.pre"). The new callback delivers `newIndex` pre-adjusted, so the manual
  `if (newIndex > oldIndex) newIndex -= 1` fix-up was removed from `_onReorder`. Using the
  deprecated member would have broken the zero-issue analyze gate.
- **`surfaceVariant` → `surfaceContainerHighest` for the 已停用 chip:** `ColorScheme.surfaceVariant`
  is deprecated in this SDK (after v3.18.0-0.1.pre) and would break the same gate;
  `surfaceContainerHighest` is the designated M3 successor token for the same muted-surface
  role (already used by the app theme). Foreground stays `onSurfaceVariant` as specified.
- **`isNewCustom` contract race:** at first compile the parallel todo-11/12 worker had not
  landed `ProviderDetailPage.isNewCustom` yet. Per instructions the call site was written
  against the contract; to run verification I temporarily constructed the detail page
  without the param, and the worker landed `final bool isNewCustom; … this.isNewCustom =
  false` (and their store additions) mid-run — after which `isNewCustom: true` was restored
  and ALL verification below re-ran against the final code.

## Verification (final code, `isNewCustom: true` in place)

```
$ flutter test test/features/settings/provider_selection_page_test.dart
00:00 +0: merged list shows custom, disabled, model-count and add entry
00:00 +1: reorder persists the new id order
00:01 +2: drag is a no-op while a search filter is active
00:01 +3: All tests passed!
```

```
$ flutter analyze lib/features/settings/provider_selection_page.dart test/features/settings/provider_selection_page_test.dart
Analyzing 2 items...
No issues found! (ran in 1.0s)
```

```
$ flutter analyze lib/features/settings/
Analyzing settings...
No issues found! (ran in 0.9s)
```

```
$ flutter test
…
00:03 +140: …provider_selection_page_test.dart: drag is a no-op while a search filter is active
00:04 +141: All tests passed!
```

Full suite: **141/141 passed** (138 pre-existing + the 3 new tests in this task).

```
$ grep -rniE "rikka|borrowed|adapted from|inspired by" \
    lib/features/settings/provider_selection_page.dart \
    test/features/settings/provider_selection_page_test.dart
# exit 1 — zero hits
```

LSP diagnostics on both changed files: no diagnostics found.

## Adversarial review

- **Stale state (reorder persists across invalidation):** covered by test 2 — after the
  drag, `_onReorder` persists the full id list and calls `ref.invalidate(providerListProvider)`;
  the registry re-reads prefs (no caches), and the test asserts both the persisted order and
  the rebuilt visual order (OpenAI above the custom). The persist is awaited before
  invalidation, so the refresh can never read a half-written order; a persist failure is
  caught and simply leaves the old order (UI stays responsive).
- **Filtered-reorder index corruption:** double-guarded — the drag handle is not rendered
  while `_searchQuery.isNotEmpty` (test 3 asserts findsNothing), and `_onReorder` itself
  no-ops in that state (test 3 asserts prefs unchanged after a drag attempt).
- **Misleading success:** test 1 asserts the real rendered strings/chips (`Test Custom LLM`,
  `自定义`, `已停用`, `2 个模型`, `添加自定义提供商`) seeded through the real persistence format
  (`ProviderConfig.toJson` JSON + the same prefs keys SettingsStore uses), not mocks of the
  page internals; test 2 asserts the persisted prefs content, not just widget positions.
- **Flaky tests (AsyncValue timing):** every test ends interactions with `pumpAndSettle()`,
  and the tall surface removes scroll-dependent lazy-build nondeterminism. SVG loading in the
  test environment is covered by the pre-existing `placeholderBuilder` (unchanged behavior).
- **Empty custom name crash:** `_buildIcon` uses `'?'` when `provider.name.isEmpty` (the
  create-mode draft has an empty name; the old `name.characters.first` would throw).
- **onReorderItem index semantics:** verified against the SDK source
  (`packages/flutter/lib/src/widgets/reorderable_list.dart` migration doc) — newIndex arrives
  pre-adjusted; the old manual adjustment was removed, and test 2 proves the persisted order
  matches the visual drag outcome.
- **fromOnboarding regression:** bottom offline-mode section kept byte-identical; test 1
  asserts it is absent when fromOnboarding=false (default), and onboarding_page.dart's
  `ProviderSelectionPage(fromOnboarding: true)` call site is untouched.
- n/a: network/provider-reachability (UI-only task; customs intentionally hide the
  reachability row), deletion flows (owned by the detail page), QR import (todo 16).

Cleanup: none required (no temp files; the temporary no-param call site was restored to the
contract form before final verification).
