# Tasks 11+12 (merged) — Provider detail page: two-tab editor (配置 / 模型) with builtin overlay editing + full custom provider create/edit/delete

**Date:** 2026-08-18
**Project:** /home/mjiutang/moonpet (moodpet)
**Flutter:** 3.44.6 (channel stable) • Dart 3.12.2 • flutter_riverpod ^2.6.1 • shared_preferences ^2.3.3 • flutter_lints ^6.0.0
**Scope:** `lib/features/settings/provider_detail_page.dart` (rewritten), `test/features/settings/provider_detail_page_test.dart` (new), `lib/core/storage/settings_store.dart` (one method appended, byte-compatible). No other files touched: selection page, models_client, connection_tester, provider_config and all pre-existing tests untouched. No new packages. No git operations.

---

## Changes

### `lib/core/storage/settings_store.dart` (append only)

- Added `Future<void> clearActiveProviderId() => _prefs.remove(_kActiveProviderIdKey);` directly
  after `setActiveProviderId`. Needed by the delete flow when the deleted custom provider is the
  active one (task brief allowed this append; the method did not exist). No existing line changed.

### `lib/features/settings/provider_detail_page.dart` (full rewrite, 485 → ~1200 lines)

**Widget contract (matches the parallel selection-page worker):**

```dart
ProviderDetailPage({
  super.key,
  required this.provider,          // overlaid config for edit; fresh uuid draft for create
  this.fromOnboarding = false,
  this.isNewCustom = false,
  this.modelFetcher = fetchAvailableModels,      // typedef ModelFetcher {required provider, client}
  this.connectionTester = testProviderConnection // typedef ConnectionTester {required provider, client}
})
```

Both seams are public typedefs in the page file and default to the real functions.

**Structure:** `Scaffold` → `AppBar(title: provider.name.isEmpty ? '新建提供商' : provider.name,
bottom: TabBar[配置, 模型])` → `TabBarView`. No share/QR AppBar action (todo 15's job). An explicit
`TabController` (SingleTickerProviderStateMixin) is used instead of `DefaultTabController` — the
tab-index listener drives the models-tab auto-fetch-once; observable structure (two tabs, TabBar +
TabBarView) is identical.

**Tab 1 — 配置 (both modes):**
- Clay `_ProviderHeader` kept; when `iconAsset.isEmpty` a `_LetterAvatar` (brand-primary bg, first
  letter, `'?'` for empty name) renders directly — `SvgPicture.asset` is never called with an empty
  path. Custom subtitle row shows 自定义提供商; builtins keep 国内可直连/需网络代理.
- API key field: multiline paste area with visibility toggle, hint
  `粘贴 API Key；可粘贴多个，逗号或空格分隔` (+ `；本地服务可留空` for customs). See correction #2
  below for the obscure/multiline framework constraint.
- `测试连接` (key `testConnectionButton`): runs `connectionTester(provider: _draftConfig())` with a
  spinner; success → green `连接成功 · {latencyMs}ms`; failure → red expandable panel
  (`连接失败[ · HTTP xxx]，点击查看详情`, tap toggles full error text). Advisory only — never blocks
  save; result clears on key edit.
- `启用此提供商` SwitchListTile (seeded from `isProviderEnabled(id)`; true for fresh drafts);
  persisted on save.
- `保存并使用` (key `saveButton`):
  - Builtin: disabled while key empty; save → `setApiKey` + `setProviderEnabled` +
    `setActiveProviderId`, model override untouched (tab 2 owns it), invalidate
    `providerListProvider` + `activeProviderConfigProvider`, `pop(true)`.
  - Custom: button stays tappable and validates on press (see correction #3): name/URL/defaultModel
    inline errors (`请输入名称` / `请输入合法的 http(s) 地址` / `请输入默认模型`); on valid → build config
    with `apiKey: ''` in JSON (key persisted separately via `setApiKey`), baseUrl normalized by
    stripping ALL trailing `/`, upsert into `loadCustomProviders` (replace same id else append),
    `saveCustomProviders`; create mode also appends id to provider order; `setApiKey` (empty
    clears), `setProviderEnabled`, `setActiveProviderId`, invalidate both providers, `pop(true)`.
- `删除此提供商` (key `deleteProviderButton`, error color; custom edit only — never builtins, never
  create mode): AlertDialog `删除后其 Key 与模型配置将一并清除` （取消/删除） → `removeProviderState(id)`
  FIRST (its guard requires the id to still be in the custom list) → remove from customs + save →
  prune order → `clearActiveProviderId()` if it was active → invalidate → `pop(true)`.

**Builtin mode:** name/baseUrl/protocol/modelsEndpoint/defaultModel/chatCompletionsPath render as
read-only `_InfoRow`s inside a `ClayContainer` — no editable TextFields.

**Custom create/edit adds:** 名称, 接口地址 (http/https + non-empty host validation via
`Uri.tryParse`), 协议 `SegmentedButton<LlmProtocol>` [OpenAI 兼容/Claude/Gemini] with the required
standard-path helper text, 模型列表端点 (default `/models`, empty → null, hint
`留空表示不支持在线拉取模型列表`), 默认模型， 聊天路径 (default `/chat/completions`, visible only for
openai protocol).

**Tab 2 — 模型:**
- Active model = `modelOverrideFor(id) ?? currentDefaultModel` (for customs the CURRENT draft
  field value, so create mode can pre-populate models under the draft id before first save).
- Default-model row first (locked, `默认` chip; `当前` chip too when active), then
  `modelsFor(id)` minus the default as clay rows. Tap non-default → `setModelOverride(id, m)`;
  tap default → `setModelOverride(id, null)`; badge moves via setState.
- Dismissible (endToStart, red bg + delete icon, non-default rows only): removes from `setModels`;
  dismissing the ACTIVE model clears the override (no dangling active model).
- `拉取模型列表` `FilledButton.tonalIcon` (key `fetchModelsButton`) only when the DRAFT config's
  `modelsEndpoint != null` (emptying the endpoint field hides it live). Calls
  `modelFetcher(provider: _draftConfig())` (draft already embeds the current key text). Success →
  modal bottom sheet: `全选` toggle row, `CheckboxListTile` per candidate (already-listed models
  skipped), `添加所选 (N)` confirm (disabled at 0) → merge `existing + selectedNew..sort()` deduped
  into `setModels`. Failure → inline red error under the button; manual add stays usable. When all
  fetched models are already listed → SnackBar `没有可添加的新模型`.
- 手动添加： TextField (key `manualModelField`, hint `模型 ID，例如 gpt-4o-mini`) + add IconButton
  (key `manualModelAddButton`); trim + non-empty + dup check (also against the default model) →
  SnackBar `已存在`, else append to `setModels`.
- `modelsEndpoint == null` → no fetch button, caption `此提供商不支持在线拉取，请手动添加模型`.
- Auto-fetch once on first tab view when discovery supported + key non-empty + no models yet
  (guarded, best-effort, failures leave manual add usable).

**Overlay reads:** key/enabled/models/override are read from `SettingsStore` in a post-frame load
(not trusted from `widget.provider`), so the page is correct for both today's non-overlaid catalog
caller and the parallel worker's overlaid `providerListProvider` configs.

### `test/features/settings/provider_detail_page_test.dart` (new, 7 tests)

Harness: mock `SharedPreferences` + `ProviderScope(sharedPrefsProvider.overrideWith)`, opener page
pushes the detail page and captures the `pop(true)` result; default no-network stubs for both
seams; tall 1080×2600 surface.

a. Create-mode invalid input (empty name, `not-a-url`, empty default model) → all three inline
   errors, `loadCustomProviders`/order/activeId all untouched, no pop.
b. Valid custom create (`My LLM`, `http://localhost:11434/v1/` with trailing slash, `llama3`, empty
   key) → 1 persisted entry with normalized `http://localhost:11434/v1`, order contains id, active
   id set, popped `true`.
c. Fake `connectionTester` (ok, 42ms) → tap 测试连接 → `连接成功 · 42ms` visible.
d. Models tab: seeded `['mB']` + override `mB`; fake fetcher returns `[mC, mD]` → mB row shows
   `当前`; fetch → check both → `添加所选 (2)` → store has mB,mC,mD; dismiss active mB →
   `modelOverrideFor(id)` is null, badge falls back to default row.
e. Builtin deepseek → no custom TextFields (key finders absent), name/baseUrl read-only text
   present, save disabled with empty key and enabled after typing one.
f. (extra, adversarial stale-state) Delete the ACTIVE custom provider → customs empty, order
   pruned, `activeProviderId` null, key/models state cleared, popped `true`.
g. (extra, adversarial dup input) Manual add of an existing model → SnackBar `已存在`, list
   unchanged.

---

## Corrections to the task brief's API facts (discovered during implementation)

1. **`ProviderConfig.copyWith` does NOT cover all fields.** It only takes `apiKey, modelOverride,
   recommended, protocol, chatCompletionsPath, enabled`; name/baseUrl/defaultModel/modelsEndpoint/
   iconAsset/brandColor/isCustom are not settable (provider_config.dart:200-223, and editing that
   file was forbidden). `_draftConfig()` therefore constructs `ProviderConfig(...)` directly for
   customs; only the `apiKey: ''` blanking before JSON persistence uses `copyWith`. No functional
   impact on the contract.
2. **Framework assert forbids multiline obscured fields** (`text_field.dart`: `assert(!obscureText
   || maxLines == 1, 'Obscured fields cannot be multiline.')`). The key field implements the
   multiline+obscure spec by switching dynamically: obscured → single-line masked; revealed →
   minLines 1 / maxLines 3 paste area.
3. **Custom save button enablement:** the brief said "enabled when name+baseUrl+defaultModel
   valid", but acceptance test (a) requires TAPPING save on an invalid form to surface inline
   errors — impossible with a disabled button. Resolution: custom save stays tappable and validates
   on press (inline errors, nothing persisted); builtin save is disabled with an empty key per
   test (e). Behavior matches both tests.
4. **Dart analyzer quirk:** `_settings ?? await ref.read(settingsStoreProvider.future)` infers
   `SettingsStore?` (verified with minimal repros against the project packages: one-step →
   nullable, two-step → non-nullable). A `_requireSettings()` helper (null-check the cached field,
   then read) is used in `_save`/`_confirmDelete`.
5. `DefaultTabController` → explicit `TabController` (structure identical; needed for the
   tab-index listener driving auto-fetch-once).

---

## Verification (commands + output)

### Targeted widget suite — green (7/7)

```
$ flutter test test/features/settings/provider_detail_page_test.dart
00:00 +0: loading .../test/features/settings/provider_detail_page_test.dart
00:00 +0: create mode rejects invalid input with inline errors and persists nothing
00:01 +1: valid custom create persists the provider with a normalized baseUrl, appends the order and pops true
00:01 +2: connection tester reports success with latency
00:01 +3: models tab fetches and merges new models; dismissing the active model clears the override
00:02 +4: builtin mode is read-only and save requires an API key
00:02 +5: deleting the active custom provider clears its state, prunes the order and clears the active id
00:02 +6: manual model add rejects duplicates with a snackbar
00:02 +7: All tests passed!
```

### Analyze — zero issues

```
$ flutter analyze lib/features/settings/provider_detail_page.dart test/features/settings/provider_detail_page_test.dart lib/core/storage/settings_store.dart
Analyzing 3 items...
No issues found! (ran in 0.8s)

$ flutter analyze lib/
Analyzing lib...
No issues found! (ran in 1.2s)   # includes the parallel worker's selection page against my contract
```

### Full suite — green (148/148)

```
$ flutter test
...
00:05 +148: All tests passed!
```

148 tests, 0 failures — includes the parallel worker's `provider_selection_page_test.dart`
(reorder/merge/add-card), which now calls `ProviderDetailPage(provider:, isNewCustom: true)` at
provider_selection_page.dart:100-103 against this page's constructor. The integration compiles and
passes.

### Attribution grep — zero hits on touched files

```
$ grep -rniE "rikka|borrowed|adapted from|inspired by" lib/features/settings/provider_detail_page.dart lib/core/storage/settings_store.dart test/features/settings/provider_detail_page_test.dart
(no matches; exit 1)
```

---

## Adversarial coverage

- **Malformed input:** bad URL (`not-a-url` → scheme missing), empty name/default model, duplicate
  manual model (also blocked against the default model), trailing-slash URL normalization —
  covered by tests a/b/g. `Uri.parse('localhost:11434')` is rejected too (parses as scheme
  `localhost`, not http/https).
- **Stale state:** dismiss-active-model clears the override (test d); delete-active-provider clears
  the active id via the new `clearActiveProviderId` (test f); `removeProviderState` runs BEFORE
  list removal because its guard requires membership (test f proves state keys are gone).
- **Misleading success:** tests assert persisted prefs (`loadCustomProviders`, `loadProviderOrder`,
  `activeProviderId`, `modelsFor`, `modelOverrideFor`, `apiKeyFor`), not just UI text.
- **Flaky:** all async settled via `pumpAndSettle`; auto-fetch is double-guarded in test d (models
  non-empty AND key empty) so the injected fetcher only fires from the explicit button tap.
- **Key handling:** custom save persists the key only via `setApiKey` (provider JSON carries
  `apiKey: ''`; `toJson` never serialises it — re-verified against provider_config.dart:138-147).
- **Not applicable:** camera/platform channels (no device features in this page); golden tests
  (none exist in the repo); reduced-motion (page adds no continuous animations).

## Residual risk

- None blocking. The parallel selection-page worker has landed `isNewCustom: true` usage and the
  full suite is green; if their draft-minting details change, the constructor contract
  (`provider` draft + `isNewCustom`) already isolates the page from it.
- `SvgPicture.asset` for builtin logos works headless in widget tests (assets bundle loads in
  tests e/d without error builders).
