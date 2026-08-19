# custom-providers - Work Plan

## TL;DR (For humans)
<!-- Fill this LAST, after the detailed plan below is written, so it summarizes the REAL plan. -->
<!-- Plain English for a non-engineer: NO file paths, NO todo numbers, NO wave/agent/tool names. -->

**What you'll get:** The app gains a full provider-management system: three real API protocols (so Anthropic Claude and Google Gemini finally work for chat, not just model listing), the ability to add your own providers (self-hosted or relay) with multiple models each, several API keys rotated automatically per provider, a one-tap connection test, QR-code/short-string sharing of provider setups, and a provider list you can search, reorder, and switch on/off — while your existing key and model choices keep working untouched.

**Why this approach:** Built-in providers stay as protected app presets and only your personal additions are saved as data, which means upgrades never touch what you already configured; the protocol is chosen per provider so each service is contacted in its own native dialect instead of one-size-fits-none.

**What it will NOT do:** It will not auto-detect what each model is capable of, will not stream replies or call external tools, will not show account balances, and will never put your API keys into shared QR codes or files.

**Effort:** XL
**Risk:** Medium - real third-party API shapes (Claude/Gemini) and a new camera/QR dependency; mitigated by mocked unit tests plus a live-device check.
**Decisions to sanity-check:** Built-in providers are locked except keys/models/on-off; one shared reorder list mixes built-ins and customs; API keys rotate randomly (no usage tracking); local providers over plain http are enabled for desktop/Android local addresses only.

Your next move: approve to start execution (user already said 开工). Full execution detail follows below.

---

> TL;DR (machine): XL effort, Medium risk, 19 todos across 5 waves — protocol-dispatched LLM clients, unified provider registry, custom provider CRUD + model management UI, multi-key rotation, QR share/import, integration tests.

## Scope
### Must have
- LlmProtocol enum (openai/claude/gemini); protocol-dispatched chat + model-list clients; builtin Claude/Gemini chat fixed via native APIs
- Custom provider CRUD: name/baseUrl/protocol/key(optional)/modelsEndpoint/defaultModel/chatCompletionsPath; enable/disable; merged drag-reorder
- Per-provider model list: fetch-from-endpoint multi-select sheet + manual add + active-model select (reuses modelOverride key)
- Multi-API-key: single field split on [\s,]+; random pick per request; retry with a different key ONLY on 401/403/429
- Advisory connection tester (real protocol-aware chat ping, latency + expandable error, never blocks save)
- QR share (image + copyable string) / import (Android camera scan + paste); moodpet-provider:v1 payload WITHOUT keys/models
- ProviderRegistry single resolution path (builtins + customs + overlays, order-reconciled); both old duplicate call sites rewired
- Zero-migration: existing SharedPreferences keys untouched; legacy installs behave identically
- Unit tests (MockClient / mock prefs) + widget tests; flutter analyze clean; agent-executed QA evidence
### Must NOT have (guardrails, anti-slop, scope boundaries)
- NO model capability inference/DSL, NO streaming, NO tool/function calling, NO LRU state, NO balance queries, NO custom headers/bodies
- NO API keys inside the customs JSON or the QR payload
- NO builtin deletion; builtin name/baseUrl/protocol stay read-only
- NO migration/deletion of legacy per-id SharedPreferences keys
- NO external-project names or attribution in code, comments, or naming
- NO commits (user has not requested them); NO fixes of unrelated pre-existing issues

## Verification strategy
> Agent-executed wherever a runner exists. Unit/widget suites are headless; the live-device pass is explicitly conditional (todo 19 fallback records device absence and flags human QA at delivery).
- Test decision: tests-after — package:flutter_test + package:http/testing.dart MockClient (both already available); new deps qr_flutter + mobile_scanner (UI) and dev-only integration_test (todo 17)
- Evidence: .omo/evidence/task-<N>-custom-providers.md

## Execution strategy
### Parallel execution waves
> Target 5-8 todos per wave. Fewer than 3 (except the final) means you under-split.

- Wave 1 (protocol foundation): 1 → (2 ∥ 3) → (4 ∥ 5)
- Wave 2 (storage & registry): 6 → 7 → 8 → 9
- Wave 3 (management UI): (10 ∥ 11 ∥ 12) → 13
- Wave 4 (share/import): 14 ∥ 17 → (15 ∥ 16)
- Wave 5 (integration & audit): 18 → 19

### Dependency matrix
| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| 1 | — | 2,3,6,7,11,13,14 | — |
| 2 | 1 | 4,5 | 3 |
| 3 | 1 | 4,12 | 2 |
| 4 | 2 | — | 5 |
| 5 | 2 | 11 | 4 |
| 6 | 1 | 7,9,13,16 | — |
| 7 | 6 | 8,9,10 | — |
| 8 | 7 | 10,18 | — |
| 9 | 7,8 | — | — |
| 10 | 7,8 | 13,16,18 | 11,12 |
| 11 | 5,7 | 13,15 | 10,12 |
| 12 | 3,7 | 13 | 10,11 |
| 13 | 6,10,11,12 | 18 | — |
| 14 | 1 | 15,16 | 17 |
| 15 | 11,14,17 | — | 16 |
| 16 | 6,10,14,17 | 18 | 15 |
| 17 | — | 15,16,19 | 14 |
| 18 | 8,10,13,16 | 19 | — |
| 19 | 18 | — | — |

## Todos
> Implementation + Test = ONE todo. Never separate.
<!-- APPEND TASK BATCHES BELOW THIS LINE WITH edit/apply_patch - never rewrite the headers above. -->
- [x] 1. ProviderConfig gains protocol/custom fields + JSON codec
  What to do / Must NOT do: In lib/core/models/provider_config.dart add `enum LlmProtocol { openai, claude, gemini }` (json values 'openai'/'claude'/'gemini'). Add fields to ProviderConfig: `protocol` (default LlmProtocol.openai), `isCustom` (default false), `chatCompletionsPath` (default '/chat/completions'). Add `toJson()`/`fromJson()` covering id/name/baseUrl/defaultModel/protocol/modelsEndpoint/chatCompletionsPath/isCustom ONLY — NEVER serialize apiKey, modelOverride, recommended, iconAsset, brandColor into JSON (fromJson sets iconAsset='' and brandColor='' for customs; UI letter-avatar fallback already exists). Extend copyWith with protocol + chatCompletionsPath; update ==/hashCode with protocol + isCustom. Change `isConfigured` getter to: isCustom ? baseUrl.isNotEmpty : apiKey.isNotEmpty (local providers need no key). In kBuiltinProviders: set claude entry `protocol: LlmProtocol.claude`, gemini entry `protocol: LlmProtocol.gemini`, all others default openai. Must NOT: change builtin baseUrl values; add capability/modality fields; mention any external project in comments.
  Parallelization: Wave 1 | Blocked by: none | Blocks: 2,3,6,14
  References (executor has NO interview context - be exhaustive): lib/core/models/provider_config.dart:14-104 (class), :52-63 (constructor), :65-73 (getters), :76-92 (copyWith), :94-103 (==/hashCode), :111-280 (kBuiltinProviders), :234-257 (claude+gemini entries)
  Acceptance criteria (agent-executable): `flutter analyze lib/core/models/provider_config.dart` exits 0; a `dart run` snippet or unit test constructs ProviderConfig.fromJson(p.toJson()) round-trip for a custom provider and asserts equality of id/name/baseUrl/protocol.
  QA scenarios (name the exact tool + invocation): happy — `flutter test test/core/models/provider_config_test.dart` (new: round-trip + defaults + isConfigured matrix builtin-vs-custom); failure — fromJson with missing optional keys applies defaults, unknown protocol string falls back to openai. Evidence .omo/evidence/task-1-custom-providers.md
  Commit: N
- [x] 2. chatCompletion protocol dispatch + multi-key rotation + retry
  What to do / Must NOT do: In lib/core/agent/llm_client.dart refactor chatCompletion to dispatch on provider.protocol. Add top-level `List<String> splitApiKeys(String raw)` splitting on RegExp(r'[\s,]+') filtering empties. Request flow: keys = splitApiKeys(provider.apiKey); if empty AND provider.isCustom → send request WITHOUT Authorization header; if empty AND !isCustom → LlmResult.fail('provider not configured (missing base URL or API key)', 0) replacing the stale 'provider API key is empty' message at llm_client.dart:60. openai branch: current behavior (POST {baseUrl}{provider.chatCompletionsPath}, Bearer when key present, OpenAI body/response). claude branch: POST {baseUrl}/v1/messages when baseUrl does NOT end with '/v1', else {baseUrl}/messages; headers x-api-key + anthropic-version: 2023-06-01 + content-type; body {model, max_tokens: maxTokens (REQUIRED), system: systemPrompt, messages:[{role:'user',content:userInput}]}; parse content as List, first block with type=='text' → block['text']. gemini branch: POST {baseUrl}/v1beta/models/{effectiveModel}:generateContent?key=<key>, but when baseUrl already ends with '/v1beta' use {baseUrl}/models/{effectiveModel}:generateContent (symmetric with the claude /v1 guard — no doubled path segments); body {systemInstruction:{parts:[{text:systemPrompt}]}, contents:[{role:'user',parts:[{text:userInput}]}], generationConfig:{temperature, maxOutputTokens: maxTokens}}; parse candidates[0].content.parts[0].text. RETRY: on HTTP 401/403/429 with >1 keys, retry with a DIFFERENT random key (track tried indices, max attempts = keys.length); NEVER retry on 400/404/500 or network exceptions. Keep LlmResult + _truncate unchanged. Must NOT: streaming, tool calls, key persistence/LRU state, external-project names.
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 4,5
  References: lib/core/agent/llm_client.dart:46-115 (chatCompletion), :17-27 (ChatMessage), :30-43 (LlmResult); lib/core/models/provider_config.dart:65-70 (effectiveModel/isConfigured); lib/core/agent/models_client.dart:100-116 (existing auth-header pattern to mirror for claude/gemini)
  Acceptance criteria: `flutter test test/core/agent/llm_client_test.dart` passes (new file, uses package:http/testing.dart MockClient — already available via http dep, NO new dependency); `flutter analyze lib/core/agent/llm_client.dart` exits 0.
  QA scenarios: happy — MockClient 200 asserts openai/claude/gemini request URL+headers+body shape and response parsing per branch; failure — 429 then 200 with 2 keys asserts second attempt used the other key; 400 returns fail WITHOUT retry; empty-key custom sends no Authorization. Evidence .omo/evidence/task-2-custom-providers.md
  Commit: N
- [x] 3. fetchAvailableModels protocol dispatch
  What to do / Must NOT do: In lib/core/agent/models_client.dart replace the provider.id string switches with provider.protocol switches in _buildModelsUri/_authHeaders/_extractModelIds. openai: GET {baseUrl}{modelsEndpoint}, Bearer when key present, data[].id extraction (KEEP existing fallthrough to models[].name for Cohere-shaped responses). claude: GET {baseUrl}{modelsEndpoint} (builtin stays '/v1/models'), x-api-key + anthropic-version, data[].id. gemini: GET {baseUrl}{modelsEndpoint}?key= (builtin stays '/v1beta/models'), models[].name with 'models/' prefix strip. modelsEndpoint == null → existing fail unchanged. Must NOT: change ModelsResult shape; remove the cohere (models[].name) fallback.
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 4,12
  References: lib/core/agent/models_client.dart:50-86 (fetchAvailableModels), :89-97 (_buildModelsUri), :99-116 (_authHeaders), :118-145 (_extractModelIds); lib/core/models/provider_config.dart:234-257 (claude/gemini builtin endpoints)
  Acceptance criteria: `flutter test test/core/agent/models_client_test.dart` passes (new, MockClient per protocol asserting URL + headers + id extraction); `flutter analyze lib/core/agent/models_client.dart` exits 0.
  QA scenarios: happy — per-protocol 200 fixture parses to sorted id list; failure — 401 fixture returns fail with HTTP status; gemini fixture strips 'models/' prefix. Evidence .omo/evidence/task-3-custom-providers.md
  Commit: N
- [x] 4. Key splitting/rotation unit tests
  What to do / Must NOT do: test/core/agent/key_rotation_test.dart covering splitApiKeys: 'a, b\nc  d' → [a,b,c,d]; empty/whitespace → []; dedupe NOT required (document behavior). Retry indexing: with 3 keys and MockClient failing 403 twice then 200, assert 3 distinct Authorization values used, order non-repeating. Must NOT: mock via 3rd-party packages.
  Parallelization: Wave 1 | Blocked by: 2,3 | Blocks: none
  References: lib/core/agent/llm_client.dart (new splitApiKeys + retry loop from todo 2)
  Acceptance criteria: `flutter test test/core/agent/key_rotation_test.dart` passes.
  QA scenarios: happy — multi-separator split; failure — single key + 403 → exactly 1 attempt. Evidence .omo/evidence/task-4-custom-providers.md
  Commit: N
- [x] 5. Connection tester (protocol-aware ping)
  What to do / Must NOT do: New lib/core/agent/connection_tester.dart: `class ConnectionTestResult { final bool ok; final int statusCode; final String? error; final int latencyMs; }` and `Future<ConnectionTestResult> testProviderConnection({required ProviderConfig provider})` calling chatCompletion with systemPrompt 'Reply with OK.', userInput 'OK', maxTokens 8, timeout 15s, measuring Stopwatch latency; maps LlmResult to ConnectionTestResult. Unit test test/core/agent/connection_tester_test.dart with MockClient. Must NOT: gate or block saving; add streaming/tool dimensions; UI in this todo (wired in todo 11).
  Parallelization: Wave 1 | Blocked by: 2 | Blocks: 11
  References: lib/core/agent/llm_client.dart:46-115 (chatCompletion signature after todo 2)
  Acceptance criteria: `flutter test test/core/agent/connection_tester_test.dart` passes; `flutter analyze lib/core/agent/connection_tester.dart` exits 0.
  QA scenarios: happy — 200 → ok:true + latency>0 recorded; failure — 401 → ok:false, error surfaced, statusCode 401. Evidence .omo/evidence/task-5-custom-providers.md
  Commit: N
- [x] 6. SettingsStore: custom providers + order + enabled + models keys
  What to do / Must NOT do: In lib/core/storage/settings_store.dart add keys: 'moodpet.provider.customProviders' (JSON string), 'moodpet.provider.order' (string list), 'moodpet.provider.enabled.<id>' (bool), 'moodpet.provider.models.<id>' (string list). Methods: `List<ProviderConfig> loadCustomProviders()` (jsonDecode → ProviderConfig.fromJson per entry, SKIP malformed entries, NEVER throw on corrupt JSON — return what parses), `Future<void> saveCustomProviders(List<ProviderConfig>)`, `List<String> loadProviderOrder()`, `Future<void> saveProviderOrder(List<String>)`, `bool isProviderEnabled(String id)` default true, `Future<void> setProviderEnabled(String id, bool)`, `List<String> modelsFor(String id)`, `Future<void> setModels(String id, List<String>)`, `Future<void> removeProviderState(String id)` clearing apiKey/modelOverride/enabled/models for a deleted custom provider — GUARD: no-op unless id is present in loadCustomProviders() (legacy builtin keys must never be cleared through this method). Keep every existing key/method byte-compatible. Must NOT: migrate or delete existing keys; serialize apiKey anywhere in the customs JSON.
  Parallelization: Wave 2 | Blocked by: 1 | Blocks: 7,9
  References: lib/core/storage/settings_store.dart:9-16 (key constants), :64-92 (existing provider methods to mirror); lib/core/models/provider_config.dart (toJson/fromJson from todo 1)
  Acceptance criteria: `flutter test test/core/storage/settings_store_test.dart` passes (new; uses SharedPreferences.setMockInitialValues — built into shared_preferences, NO new dep); `flutter analyze lib/core/storage/settings_store.dart` exits 0.
  QA scenarios: happy — save+load 2 customs round-trip, order persist, enabled toggle; failure — corrupt JSON in customs key → returns [] without throw. Evidence .omo/evidence/task-6-custom-providers.md
  Commit: N
- [x] 7. ProviderRegistry — unified merge + resolution
  What to do / Must NOT do: New lib/core/provider_registry.dart: `class ProviderRegistry { ProviderRegistry(this._settings); List<ProviderConfig> all(); ProviderConfig? byId(String id); }`. all(): builtins (each overlaid with apiKeyFor/modelOverrideFor/isProviderEnabled) + loadCustomProviders (same overlay), ordered by loadProviderOrder reconciled — ids in order list first (stale ids dropped), remaining providers appended in catalog-then-custom order. ProviderConfig gains runtime-only `enabled` field (default true, NOT serialized) populated by registry; explicitly update `operator==`/`hashCode` to include `enabled` (Object.hash of existing fields + enabled) so enable/disable toggles repaint list cards. Add `ProviderConfig? activeById(String id)` that returns null when the provider is missing OR disabled — the disabled→offline semantic lives HERE only, not in consumers. Expose Riverpod `providerRegistryProvider` (FutureProvider deriving from settingsStoreProvider) and `providerListProvider` (FutureProvider<List<ProviderConfig>>) in lib/core/providers.dart. Must NOT: persist enabled inside customs JSON; change builtin catalog order constants.
  Parallelization: Wave 2 | Blocked by: 6 | Blocks: 8,9,10
  References: lib/core/models/provider_config.dart:307-312 (builtinProviderById being replaced), :94-103 (equality — include enabled); lib/core/providers.dart:25-27 (settingsStoreProvider), :82-93 (activeProviderConfigProvider to rewire in todo 8); lib/core/storage/settings_store.dart (new methods from todo 6)
  Acceptance criteria: `flutter test test/core/provider_registry_test.dart` passes: merge order reconcile (unknown appended, stale dropped), byId finds builtin AND custom, disabled flag surfaced.
  QA scenarios: happy — order [custom1, deepseek] renders custom1 first; failure — order contains deleted id → skipped silently. Evidence .omo/evidence/task-7-custom-providers.md
  Commit: N
- [x] 8. Rewire active-provider resolution (kill duplication)
  What to do / Must NOT do: lib/core/providers.dart: activeProviderConfigProvider resolves via providerRegistryProvider's registry.activeById(activeProviderId) (null when disabled → home page shows offline mode). agentServiceProvider constructs ProviderRegistry(settings) and passes into PocketClawAgent. lib/core/agent/pocketclaw_agent.dart: constructor takes registry; delete _activeProvider's builtinProviderById logic — resolve via registry.activeById (disabled check inside the registry, not here); effectiveModel semantics unchanged (modelOverride key = active model id). KEEP builtinProviderById exported and unchanged — pre-existing tests (test/models/provider_config_test.dart:12-21, test/models_test.dart:171-174) call it; only lib call sites switch to the registry. Must NOT: change AgentService contract or home_page behavior beyond disabled→offline.
  Parallelization: Wave 2 | Blocked by: 7 | Blocks: 10,18
  References: lib/core/providers.dart:50-60 (agentServiceProvider), :82-93 (activeProviderConfigProvider); lib/core/agent/pocketclaw_agent.dart:26-51 (constructor + _activeProvider), :36-39 (isReady); lib/core/models/provider_config.dart:307-312
  Acceptance criteria: `flutter analyze lib/` exits 0; `grep -rn "builtinProviderById" lib/` returns only sanctioned references (or none); registry unit test from todo 7 still passes.
  QA scenarios: happy — set activeProviderId to a custom id (mock prefs) → activeProviderConfigProvider returns it with key injected; failure — active id disabled → returns null. Evidence .omo/evidence/task-8-custom-providers.md
  Commit: N
- [x] 9. Storage + registry integration test
  What to do / Must NOT do: test/core/provider_registry_test.dart (extend from todo 7) + settings_store_test.dart integration: simulate an EXISTING install (setMockInitialValues with legacy keys moodpet.provider.activeId='deepseek', apiKey.deepseek, modelOverride.deepseek) → registry.all() contains builtins with key injected, active resolution works, NOTHING migrated/deleted. Then add a custom provider → order reconciliation appends it. Must NOT: touch real device prefs.
  Parallelization: Wave 2 | Blocked by: 7,8 | Blocks: none
  References: test/core/storage/settings_store_test.dart (todo 6), test/core/provider_registry_test.dart (todo 7)
  Acceptance criteria: `flutter test test/core/` all pass.
  QA scenarios: happy — legacy prefs load identically to pre-refactor behavior; failure — legacy activeId pointing at removed/unknown id → null, no crash. Evidence .omo/evidence/task-9-custom-providers.md
  Commit: N
- [x] 10. Provider selection page: merged list + reorder + badges + entries
  What to do / Must NOT do: Rework lib/features/settings/provider_selection_page.dart: data from providerListProvider (not kBuiltinProviders); search filters merged list; region banner + recommended logic unchanged; convert list to ReorderableListView (long-press drag, each card wrapped with `key: ValueKey(provider.id)`) persisting via saveProviderOrder — onReorder is DISABLED (no-op) while _searchQuery.isNotEmpty, since reordering a filtered subset cannot map to full-list indices; the '+ 添加自定义提供商' card is a NON-reorderable sibling BELOW the Expanded(ReorderableListView) (same Column level as the fromOnboarding section), never an item in the list; when reworking this file, DELETE the pre-existing external-project attribution doc comment at line 3 (project rule: no attribution). card badges: '自定义' chip when isCustom, greyed + '已停用' when !enabled, 'N 个模型' line when modelsFor non-empty; card tap → detail (existing); trailing '+ 添加自定义提供商' card → detail in create mode; AppBar actions: import icon (QR import, wired in todo 16). Letter-avatar rendering when iconAsset empty (customs) — guard SvgPicture.asset. Keep fromOnboarding bottom section byte-identical. Must NOT: remove recommended/region features; allow deleting builtins (no delete affordance here at all).
  Parallelization: Wave 3 | Blocked by: 7,8 | Blocks: 13,16,18
  References: lib/features/settings/provider_selection_page.dart:30-58 (state + filters), :60-76 (_onProviderTap), :78-216 (build), :219-356 (_ProviderCard), :358-389 (_StatusChip); lib/core/providers.dart (providerListProvider from todo 7); lib/core/storage/settings_store.dart (saveProviderOrder todo 6)
  Acceptance criteria: `flutter analyze lib/features/settings/provider_selection_page.dart` exits 0; widget smoke test test/features/settings/provider_selection_page_test.dart renders merged list with a custom provider and finds '自定义' chip.
  QA scenarios: happy — drag card 3→1 persists new order (assert via mock prefs); failure — empty provider list (all disabled) still renders add card. Evidence .omo/evidence/task-10-custom-providers.md
  Commit: N
- [x] 11. Provider detail page: Config tab (builtin overlay vs custom full edit) + tester
  What to do / Must NOT do: Rework lib/features/settings/provider_detail_page.dart into a TabBarView with [配置, 模型] tabs (models tab = todo 12). Config tab — BUILTIN mode: header read-only (logo/name/baseUrl), API key field MULTILINE (hint '可粘贴多个 Key，逗号或空格分隔'), enable switch (setProviderEnabled), '测试连接' button (todo 5; shows spinner→✓ latency / ✗ expandable error), save (setApiKey + setActiveProviderId, pop(true)) — save enabled when key non-empty OR provider disabled-intent. CUSTOM create/edit mode adds: name field (required non-empty), baseUrl field (validator: Uri.parse has scheme http/https + host; normalize with trimRight('/') on save so a user-entered trailing slash never doubles path segments), protocol SegmentedButton (openai/claude/gemini — disabled for builtin) with helper text '自定义 Claude/Gemini 提供商需使用标准接口路径（/v1/messages、/v1beta/models/…:generateContent）', modelsEndpoint field (default '/models'; empty → null with hint '留空表示不支持在线拉取'), defaultModel field (required), chatCompletionsPath field (openai only, default '/chat/completions'), key field OPTIONAL for customs (hint '本地服务可留空'), delete button (edit mode only, confirm dialog → removeProviderState + saveCustomProviders + pop). Save for customs: upsert into loadCustomProviders/saveCustomProviders + append order when new. Must NOT: let builtin name/baseUrl/protocol be edited; block save on tester failure (advisory only).
  Parallelization: Wave 3 | Blocked by: 5,7 | Blocks: 13,15
  References: lib/features/settings/provider_detail_page.dart:36-131 (state/load/save), :133-258 (build), :278-375 (_ProviderHeader); lib/core/agent/connection_tester.dart (todo 5); lib/core/storage/settings_store.dart (todo 6 methods); uuid package (pubspec.yaml:29) for create ids
  Acceptance criteria: `flutter analyze lib/features/settings/provider_detail_page.dart` exits 0; widget test test/features/settings/provider_detail_page_test.dart: create-mode validation rejects empty name + bad URL, accepts valid; tester button invokes callback.
  QA scenarios: happy — fill valid custom form → saved provider appears in loadCustomProviders; failure — 'not-a-url' baseUrl shows inline error, save disabled. Evidence .omo/evidence/task-11-custom-providers.md
  Commit: N
- [x] 12. Provider detail page: Models tab (list + fetch picker + manual + active select)
  What to do / Must NOT do: Models tab in provider_detail_page.dart: shows defaultModel first (locked, '默认' badge) + settings.modelsFor(id).where((m) => m != defaultModel) entries (never render defaultModel twice); per-row: tap → set active (setModelOverride; tapping the defaultModel row clears the override via setModelOverride(id, null), '当前' badge), swipe-to-dismiss delete (defaultModel row not dismissible) — ON DISMISS: if modelOverrideFor(id) == dismissedModel, call setModelOverride(id, null) so effectiveModel falls back to defaultModel and the '当前' badge moves to the default row (no dangling active model); '拉取模型列表' button shown ONLY when provider.supportsModelDiscovery (modelsEndpoint == null → manual-add only) → fetchAvailableModels → modal bottom sheet with CheckboxListTile multi-select + '全选' toggle → merge selected into setModels (dedupe, strip defaultModel, preserve order: existing first then new alphabetical); manual add: TextField + add button (validate non-empty, dedupe). Disabled when provider disabled? No — manageable regardless. Must NOT: capability badges/inference; reorder models (flat managed list only).
  Parallelization: Wave 3 | Blocked by: 3,7 | Blocks: 13
  References: lib/features/settings/provider_detail_page.dart:377-484 (_ModelSelector being replaced by tab), :82-104 (_fetchModels pattern to reuse); lib/core/agent/models_client.dart (todo 3); lib/core/storage/settings_store.dart (modelsFor/setModels todo 6, modelOverrideFor/setModelOverride existing :71-92)
  Acceptance criteria: widget test: fetch sheet with MockClient 2-model fixture → select both → modelsFor returns both; tapping a row writes modelOverride.
  QA scenarios: happy — fetch+select+activate round-trip; failure — fetch 401 shows inline error, manual add still works. Evidence .omo/evidence/task-12-custom-providers.md
  Commit: N
- [x] 13. Custom provider create/edit/delete flow wiring
  What to do / Must NOT do: Wire navigation: selection-page add card → ProviderDetailPage(createMode: true) (empty draft: id=Uuid().v4(), isCustom=true, protocol=openai, modelsEndpoint='/models'); card tap on custom → edit mode. Delete: confirm dialog ('删除后其 Key 与模型配置将一并清除') → removeProviderState(id) + remove from customs JSON + prune from order + if it was activeProviderId clear active → pop to list. On save-create: append id to order list. Widget test the create→persist→list round-trip with mock prefs. Must NOT: offer delete on builtins; duplicate ids (uuid collision check unnecessary).
  Parallelization: Wave 3 | Blocked by: 10,11,12 | Blocks: 18
  References: lib/features/settings/provider_selection_page.dart:60-76 (navigation result contract), :168-175 (card builder); lib/features/settings/provider_detail_page.dart:114-131 (_save pattern); lib/core/storage/settings_store.dart (removeProviderState todo 6)
  Acceptance criteria: `flutter test test/features/settings/custom_provider_flow_test.dart` passes: create → persists + ordered; delete → state cleared + order pruned.
  QA scenarios: happy — full CRUD cycle; failure — delete the ACTIVE custom provider → activeProviderId cleared, home falls to offline mode without crash. Evidence .omo/evidence/task-13-custom-providers.md
  Commit: N
- [x] 14. QR share payload codec
  What to do / Must NOT do: New lib/core/utils/provider_share_codec.dart: `String encodeProviderShare(ProviderConfig p)` → 'moodpet-provider:v1:' + base64Encode(utf8.encode(jsonEncode({v:1, name, baseUrl, protocol: protocol.name, modelsEndpoint, defaultModel, chatCompletionsPath}))); `ProviderConfig? decodeProviderShare(String raw)` → trim; require prefix; base64Decode (try/catch → null); jsonDecode; validate name+baseUrl non-empty strings, protocol ∈ enum names (fallback openai); build ProviderConfig(id: Uuid().v4(), isCustom: true, apiKey:'', iconAsset:'', brandColor:''). NEVER include apiKey/models/enabled/iconAsset/brandColor in payload. Unit tests test/core/utils/provider_share_codec_test.dart: round-trip, wrong prefix, corrupt base64, missing name → null. Must NOT: accept other apps' payload prefixes; leak keys.
  Parallelization: Wave 4 | Blocked by: 1 | Blocks: 15,16
  References: lib/core/models/provider_config.dart (constructor + LlmProtocol from todo 1); lib/core/utils/color_hex.dart (existing utils dir convention)
  Acceptance criteria: `flutter test test/core/utils/provider_share_codec_test.dart` passes; payload string asserted to NOT contain any test key material.
  QA scenarios: happy — encode→decode preserves name/baseUrl/protocol; failure — garbage string returns null (no throw). Evidence .omo/evidence/task-14-custom-providers.md
  Commit: N
- [x] 15. QR share UI on detail page
  What to do / Must NOT do: Add AppBar share action on provider_detail_page (ALL providers incl. builtins — builtin shares its URL/defaults so recipients import as a custom provider): modal bottom sheet with the resolved qr_flutter version's image widget (`QrImageView(data:, size: 240)` for qr_flutter ≥4.1; fall back to `QrImage` if the resolver picked an older line — check the version recorded in todo 17 evidence before coding) + SelectableText payload + '复制口令' button (Clipboard.setData + SnackBar '已复制'). Requires qr_flutter (todo 17). Must NOT: include key in QR; offer share before provider saved in create mode (hide action in create mode).
  Parallelization: Wave 4 | Blocked by: 11,14,17 | Blocks: none
  References: lib/core/utils/provider_share_codec.dart (todo 14); lib/features/settings/provider_detail_page.dart (AppBar from todo 11); qr_flutter QrImageView API
  Acceptance criteria: widget test finds QrImageView + payload text; clipboard copy asserted via TestDefaultBinaryMessenger.
  QA scenarios: happy — open sheet, QR renders, copy works; failure — share action hidden in create mode (assert action absent in create-mode widget test). Evidence .omo/evidence/task-15-custom-providers.md
  Commit: N
- [x] 16. QR import UI (camera scan + paste) on selection page
  What to do / Must NOT do: AppBar import action (todo 10) → dialog '导入提供商': two ListTiles — '扫码导入' (visible only when Platform.isAndroid; pushes full-screen mobile_scanner page, onDetect → decodeProviderShare → pop with result) and '粘贴导入' (TextField dialog → decodeProviderShare). On decoded payload: preview sheet (name/baseUrl/protocol rows + '口令不含 API Key，导入后请自行填写') → '确认导入' → dedupe check: existing custom with same name+baseUrl → AlertDialog '已存在相同提供商，仍要导入吗？' → saveCustomProviders append + order append + SnackBar '已导入'. Null decode → SnackBar '口令无效'. Requires mobile_scanner (todo 17) — BEFORE coding, read the resolved mobile_scanner version's CHANGELOG/README for its current `onDetect`/`BarcodeCapture` API (recent majors use `void Function(BarcodeCapture)` with `capture.barcodes.first.rawValue`; older differ) and record version+signature in evidence. COVERAGE NOTE: the camera-scan path cannot be unit/widget-tested headlessly — only the paste path has automated tests; camera scanning is verified in the todo-19 device run (or flagged human-required if no Android device is available). Must NOT: request camera permission preemptively (mobile_scanner handles); scan on non-Android (option hidden via dart:io Platform).
  Parallelization: Wave 4 | Blocked by: 10,14,17 | Blocks: 18
  References: lib/core/utils/provider_share_codec.dart (todo 14); lib/features/settings/provider_selection_page.dart (AppBar from todo 10); lib/core/storage/settings_store.dart (todo 6); mobile_scanner MobileScanner API
  Acceptance criteria: widget test: paste valid payload → preview shows name; confirm → loadCustomProviders grows by 1; paste garbage → '口令无效' snackbar.
  QA scenarios: happy — paste-import round-trip; failure — duplicate name+baseUrl triggers confirm dialog. Evidence .omo/evidence/task-16-custom-providers.md
  Commit: N
- [x] 17. Dependencies + Android permissions/config
  What to do / Must NOT do: Run `flutter pub add qr_flutter mobile_scanner` and `flutter pub add --dev integration_test --sdk flutter` (resolves latest compatible versions; record ALL resolved versions in evidence). Read android/app/src/main/AndroidManifest.xml first, then add `<uses-permission android:name="android.permission.CAMERA"/>` inside <manifest> (NOT inside <application>) if absent. Verify minSdk: read android/app/build.gradle.kts (Kotlin DSL) for flutter.minSdkVersion and check the resolved mobile_scanner version's required minSdk floor — bump minSdk in build.gradle.kts if below it (record in evidence). LOCAL-PROVIDER CLEARTEXT: AndroidManifest currently sets android:usesCleartextTraffic="false" (confirmed line 8), which blocks http:// local providers (Ollama at http://localhost:11434) on Android — create android/app/src/main/res/xml/network_security_config.xml permitting cleartext ONLY to localhost / 10.0.2.2 / 192.168.0.0/16 (domain-config entries), reference it via android:networkSecurityConfig="@xml/network_security_config" on the <application> tag, and KEEP usesCleartextTraffic="false" as the public-internet default. Must NOT: pin versions by hand; touch linux/ platform config; add iOS entries (no ios/ dir); enable global cleartext.
  Parallelization: Wave 4 | Blocked by: none | Blocks: 15,16,19
  References: pubspec.yaml:9-41 (current deps); android/app/src/main/AndroidManifest.xml; android/app/build.gradle.kts
  Acceptance criteria: `flutter pub get` exits 0; `flutter analyze` exits 0; `grep CAMERA android/app/src/main/AndroidManifest.xml` finds the permission; `grep networkSecurityConfig android/app/src/main/AndroidManifest.xml` finds the attribute; `cat android/app/src/main/res/xml/network_security_config.xml` shows localhost-scoped cleartext only.
  QA scenarios: happy — pub get + analyze clean; failure — pub version conflict or minSdk error → record conflict, bump to compatible version/minSdk, note in evidence. Evidence .omo/evidence/task-17-custom-providers.md
  Commit: N
- [x] 18. Onboarding + settings integration fixes & verification
  What to do / Must NOT do: (a) Verify (code-read + widget test) onboarding ProviderSelectionPage(fromOnboarding: true) renders merged providerListProvider list incl. customs, offline-skip section unchanged (provider_selection_page.dart:179-202). (b) FIX settings_page._providerDisplayName (settings_page.dart:172-177): it currently scans kBuiltinProviders and falls back to the raw id — a custom active provider would display its uuid; rewire to resolve via providerRegistryProvider's registry.byId(id)?.name ?? id. (c) DELETE the pre-existing external-project attribution comment at onboarding_page.dart:302 (project rule: no attribution). (d) Widget test: fromOnboarding with one custom provider in mock prefs → custom card visible above the offline section; settings page shows the custom provider's NAME when active. (e) Include test/app_test.dart in this todo's run scope — after todo 8 the home page's activeProviderConfigProvider resolves through an extra async hop (registry FutureProvider); if the existing pump durations (3s+1s) flake, bump them minimally and note it in evidence. Fix only integration breaks caused by THIS refactor; other pre-existing issues are noted, not fixed.
  Parallelization: Wave 5 | Blocked by: 8,10,13,16 | Blocks: 19
  References: lib/features/onboarding_page.dart (ProviderSelectionPage launch + line 302 comment), lib/features/settings/settings_page.dart:172-177 (_providerDisplayName), lib/features/settings/provider_selection_page.dart:20-28 (fromOnboarding flag), :179-202 (offline section), test/app_test.dart:29-51 (home test pumps)
  Acceptance criteria: `flutter test test/features/ test/app_test.dart` all pass; `flutter analyze` exits 0; settings page widget test asserts custom provider NAME (not uuid) displayed.
  QA scenarios: happy — onboarding shows custom provider card + settings shows its name; failure — no providers configured → offline skip still navigates. Evidence .omo/evidence/task-18-custom-providers.md
  Commit: N
- [x] 19. No-attribution audit + integration test suite + full regression
  What to do / Must NOT do: (1) Run `grep -rniE "rikka|borrowed|adapted from|inspired by" lib/ test/` → MUST return zero hits (todos 10/18 removed the two pre-existing ones; confirm). (2) `flutter analyze` zero issues. (3) `flutter test` 100% pass INCLUDING pre-existing suites (test/models/, test/models_test.dart). (4) Write integration_test/custom_providers_test.dart using integration_test + flutter_test driving the REAL app UI: (a) add custom provider http://localhost:11434 protocol openai no key → tester reports unreachable gracefully (no crash); (b) multi-key field with 2 keys on a builtin → save → home input responds (MockClient not available in integration tests — use a local stub HTTP server via dart:io HttpServer binding 127.0.0.1 serving canned chat-completion JSON, or accept the offline-fallback path as pass criteria — pick the stub-server approach and record the decision); (c) QR export → copy payload → paste-import round-trip; (d) drag reorder → hot restart → order persists; (e) disable active provider → home shows offline mode. Run `flutter test integration_test/ -d linux`; if NO runnable device exists in the execution environment, record the blocker in evidence, expand the equivalent coverage into widget tests where feasible, and flag the live-device run as human-required at delivery. Must NOT: commit anything; fix unrelated pre-existing issues.
  Parallelization: Wave 5 | Blocked by: 18 | Blocks: none
  References: all changed files; integration_test/custom_providers_test.dart (new); pubspec.yaml (integration_test from todo 17)
  Acceptance criteria: grep audit empty; analyze clean; `flutter test` all green; integration suite green on a runnable device (or documented device-absence fallback).
  QA scenarios: happy — all green; failure — any red step → fix root cause and re-run before closing. Evidence .omo/evidence/task-19-custom-providers.md
  Commit: N

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [x] F1. Plan compliance audit
- [x] F2. Code quality review
- [x] F3. Real device QA — integration_test suite green on a runnable device (todo 19), or the documented device-absence fallback with human-QA flag surfaced to the user
- [x] F4. Scope fidelity

## Commit strategy
No commits — the user has not requested any. All todos are Commit: N. Leave the worktree with changes in place; final state reported to the user.

## Success criteria
- `flutter analyze` exits 0 with zero issues across the repo
- `flutter test` 100% pass (new unit + widget suites under test/core/ and test/features/)
- Custom provider full lifecycle works in a real run: create (with and without key) → appears in merged list → models fetched/added → activated → home responds → QR exported → imported on paste → edited → disabled (home falls back to offline mode) → deleted (state cleared)
- Builtin Claude/Gemini chat paths construct native requests (verified by unit tests)
- Legacy-install simulation test passes with zero migration
- Attribution audit grep returns zero hits
