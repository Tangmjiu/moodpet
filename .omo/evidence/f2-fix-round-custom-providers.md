# F2 Code-Review Fix Round — Custom Providers

Date: 2026-08-19
Scope: surgical fixes only; no refactors beyond the F2 list.

## Fixes applied

### A. [BLOCKER] `ref.invalidate` after `await` without mounted guard
- `lib/features/settings/provider_detail_page.dart`
  - `_save`: added `if (!mounted) return;` immediately after the store awaits,
    before the three `ref.invalidate(...)` calls.
  - `_confirmDelete`: added `if (!mounted) return;` after the store awaits,
    before its `ref.invalidate(...)` calls.
- `lib/features/settings/provider_selection_page.dart`
  - `_onReorder`: added `if (!mounted) return;` after the persist
    try/catch, before `ref.invalidate(providerListProvider)`.
  - `_showImportPreview`: moved the mounted guard so it runs BEFORE
    `ref.invalidate(providerListProvider)`; the snackbar follows without a
    second guard (already covered).

### B. [multi-key model discovery broken]
- `lib/core/agent/models_client.dart`
  - Imports `dart:math` and `splitApiKeys` from `llm_client.dart`
    (`show splitApiKeys`).
  - `fetchAvailableModels` now splits the raw key field and picks ONE key at
    random per call (`keys[Random().nextInt(keys.length)]`, empty string when
    keyless). No retry loop (mirrors the chat client's random pick; discovery
    is single-attempt).
  - `_authHeaders(provider, key)` and `_buildModelsUri(provider, endpoint,
    key)` take the picked key; the joined multi-key string is never used as
    Bearer / x-api-key / `?key=`.
  - Claude branch omits `x-api-key` when the picked key is empty (keyless
    custom), keeping `anthropic-version` and `Content-Type`.
- `test/core/agent/models_client_test.dart` (2 new tests):
  1. apiKey `'k1, k2'` → captured `Authorization` asserted `isIn(['Bearer
     k1','Bearer k2'])` AND `isNot('Bearer k1, k2')` (exact header values,
     not just presence).
  2. Keyless custom claude-protocol provider → request has NO `x-api-key`
     header, keeps `anthropic-version`, and the fetch still 200s.

### C. [Dismissible resurrection race]
- `lib/features/settings/provider_detail_page.dart`
  - `_removeModel`: optimistic update — `setState` removes the model from
    `_models` FIRST (and clears `_modelOverride` in the same setState when it
    equals the dismissed model), THEN awaits persistence. On persistence
    exception the previous list/override are restored and a SnackBar
    `删除失败` is shown.
  - `_addManualModel`: same pattern — `setState` adds first (and clears the
    input), then persists; on exception the addition is reverted and a
    SnackBar `添加失败` is shown.

### D. `_onDetect` mounted guard
- `lib/features/settings/provider_scan_page.dart`: `if (!mounted) return;`
  added immediately after the `_handled` guard, before any
  ScaffoldMessenger/Navigator use.

### E. [equality semantics]
- `lib/core/models/provider_config.dart`: `operator==` and `hashCode` now
  include ALL persisted identity fields — `name`, `baseUrl`, `defaultModel`,
  `modelsEndpoint`, `iconAsset`, `brandColor` — in addition to the existing
  `id`, `apiKey`, `modelOverride`, `recommended`, `protocol`, `isCustom`,
  `chatCompletionsPath`, `enabled`.
- New test in `test/core/models/provider_config_test.dart`: two configs
  sharing `id` but differing in `baseUrl` are NOT equal (and hashCodes
  differ).
- Full-suite impact: no existing test relied on the loose equality — zero
  test-expectation changes were required. The registry enabled-toggle test
  (`test/core/provider_registry_test.dart`) compares configs from the same
  overlaid source (same name/baseUrl), and the todo-1 equality tests use
  `copyWith()` which preserves the identity fields, so both stay green under
  the new semantics.

### F. [doc accuracy]
- `lib/core/models/provider_config.dart`: header doc corrected — the API key
  is persisted in SharedPreferences (plain text on disk; encrypted-storage
  migration is a pending product decision), never serialised into the customs
  JSON or share payloads.
- `lib/core/storage/settings_store.dart`: checked — contains NO "secure"
  claim (`grep -in 'secure|encrypt|keystore|keychain'` → no hits). Its docs
  already describe SharedPreferences accurately; no change made.
- Storage mechanism NOT migrated, per instructions.

### G. [plan deviation] `_saveEnabled`
- `lib/features/settings/provider_detail_page.dart`: builtin save is now
  enabled when `key non-empty OR !_enabled` (disabling a keyless builtin is
  saveable).
- `test/features/settings/provider_detail_page_test.dart` ("builtin mode is
  read-only and save requires an API key"): read first, then extended —
  builtin + empty key + still-enabled → save DISABLED; toggle off → save
  ENABLED; toggle back on → DISABLED again; entering a key → ENABLED.

### H. [plan deviation] network security config
- `android/app/src/main/res/xml/network_security_config.xml`: NO domain entry
  added for 192.168.x.x and NO base-config cleartext. DECISION (documented in
  an XML comment in the file): Android network-security-config domain entries
  do not support CIDR ranges or IP wildcards, so 192.168.0.0/16 cannot be
  expressed; the only alternative (`base-config cleartextTrafficPermitted`)
  would weaken every domain and is deliberately not set. Domain-scoped
  localhost / 127.0.0.1 / 10.0.2.2 kept as-is; the limitation is documented
  in the XML comment.

## Verification

- `flutter analyze` → `No issues found! (ran in 1.3s)` (re-run after the
  final formatting repair: `No issues found! (ran in 0.9s)`).
- `flutter test` FULL suite → `+174: All tests passed!` (174 = 171 previous +
  2 new models_client tests + 1 new provider_config equality test; the G
  widget test was extended in place). Includes the todo-1 equality tests and
  the registry enabled-toggle equality test — all green under the new
  equality semantics.
- Targeted run: `flutter test test/core/agent/models_client_test.dart
  test/core/models/provider_config_test.dart
  test/features/settings/provider_detail_page_test.dart` → `+39: All tests
  passed!`; `test/core/models/provider_config_test.dart` alone after the
  formatting repair → `+19: All tests passed!`.
- Attribution grep (`claude|anthropic|openai|gpt|copilot|cursor|codeium|
  windsurf|tabnine|amazonq|gemini codeassist`) over the 10 changed files: all
  hits are the app's own LLM-provider domain vocabulary (`LlmProtocol`
  values, builtin catalog entries, user-facing protocol labels) — zero
  references to external coding tools/projects.
- Regression watch during the round: one formatting slip (joined line) in
  `provider_config_test.dart` was introduced and immediately repaired; tests
  and analyze re-verified green after the repair.

## Constraints honored

- Plain functional English/Chinese-matching comments; no external-project
  names; no git operations; no new packages; no files touched outside the
  10-file allowlist.
