# Task 3 — Custom Providers: models_client protocol-based dispatch + client injection

## Scope

Edited `lib/core/agent/models_client.dart` only; added
`test/core/agent/models_client_test.dart`. `fetchAvailableModels` now
dispatches request construction on `ProviderConfig.protocol` (openai / claude /
gemini) instead of `provider.id` string matching, accepts an optional injectable
`http.Client? client` (backward compatible — existing call site in
`provider_detail_page.dart` unchanged), and allows an empty API key for
`isCustom` providers (keyless custom fetch sends no `Authorization` header).
Gemini key query param is merged into any existing endpoint query string and is
omitted entirely when the key is empty. `_extractModelIds` fallthrough logic
kept exactly as-is (shape-based, protocol-agnostic). Top-of-file doc comment
rewritten to describe protocol-based dispatch.

## Step: test-first (before implementation)

Command: `flutter test test/core/agent/models_client_test.dart`

Result: FAIL — compile errors, `client` named parameter did not exist yet.
Relevant lines:

```
test/core/agent/models_client_test.dart:199:9: Error: No named parameter with the name 'client'.
        client: client,
        ^^^^^^
lib/core/agent/models_client.dart:50:22: Context: Found this candidate, but the arguments don't match.
Future<ModelsResult> fetchAvailableModels({
                     ^^^^^^^^^^^^^^^^^^^^
test/core/agent/models_client_test.dart:212:9: Error: No named parameter with the name 'client'.
test/core/agent/models_client_test.dart:225:9: Error: No named parameter with the name 'client'.
test/core/agent/models_client_test.dart:237:9: Error: No named parameter with the name 'client'.
00:00 +0 -1: Some tests failed.
```

(Every test using the `client:` parameter failed to compile; the suite could
not load. No pre-existing tests touched.)

## VERIFY 1 — new tests green

Command: `flutter test test/core/agent/models_client_test.dart`

```
00:00 +0: fetchAvailableModels openai protocol sends Bearer header and returns sorted ids
00:00 +1: fetchAvailableModels openai protocol falls back to the models[] response shape
00:00 +2: fetchAvailableModels claude protocol sends x-api-key and anthropic-version headers
00:00 +3: fetchAvailableModels gemini protocol authenticates via key query param and strips prefix
00:00 +4: fetchAvailableModels gemini key query param merges with an existing endpoint query
00:00 +5: fetchAvailableModels provider without modelsEndpoint fails without any HTTP call
00:00 +6: fetchAvailableModels keyless built-in provider fails without any HTTP call
00:00 +7: fetchAvailableModels keyless custom provider fetches without an Authorization header
00:00 +8: fetchAvailableModels non-200 response fails with the HTTP status in the error
00:00 +9: fetchAvailableModels non-object JSON body fails instead of crashing
00:00 +10: fetchAvailableModels empty model list fails with a no-models error
00:00 +11: All tests passed!
```

Result: PASS — 11/11 tests green. Coverage of required cases:
a = Bearer + sorted ids; b = models[] shape fallback; c = claude headers + URL;
d = gemini key query + `models/` prefix strip; e = null endpoint, no HTTP call;
f = keyless built-in fails, no HTTP call; g = keyless custom proceeds without
Authorization; h = 401 surfaces 'HTTP 401'; i = non-object JSON fails cleanly;
j = empty data list fails with '响应中没有可用的模型'. Plus one extra: gemini
`?key=` merge with a pre-existing endpoint query string.

## VERIFY 2 — analyzer clean

Command: `flutter analyze lib/core/agent/models_client.dart test/core/agent/models_client_test.dart`

```
Analyzing 2 items...
No issues found! (ran in 1.1s)
```

Result: PASS — zero issues. `lsp_diagnostics` on both files also reports none.

## VERIFY 3 — pre-existing model tests unchanged

Command: `flutter test test/models/`

```
00:00 +23: /home/mjiutang/moonpet/test/models/provider_config_test.dart: RegionInfo country names countryNameFromCode handles null gracefully
00:00 +24: All tests passed!
```

Result: PASS — 24/24 pre-existing tests green without any modification
(exit=0).

## VERIFY 4 — forbidden-term grep

Command: `grep -rniE "rikka|borrowed|adapted from|inspired by" lib/core/agent/models_client.dart test/core/agent/`

```
(no output)
grep exit: 1
```

Result: PASS — zero hits (grep exit 1 = no matches).

## Adversarial classes

- **Malformed input → PROBED.** Test "non-object JSON body fails instead of
  crashing" posts `[1,2,3]` (valid JSON, wrong top-level type) and asserts a
  `ModelsResult.fail('响应不是 JSON 对象')` rather than an exception; "empty
  model list fails" posts `{"data":[]}` and asserts the no-models failure; the
  `catch` path still maps transport errors to `ModelsResult.fail('请求失败: …')`.
- **Misleading success output → GUARDED.** The test-first run above proves the
  tests did not compile before the implementation (no `client` parameter), so
  the green run reflects the new code. Header/query assertions read the
  captured `http.Request` from `MockClient`, not just the return value, so
  auth behavior is verified on the wire, not inferred.
- **New input parsing → PROBED.** Gemini query-merge test posts an endpoint
  that already contains `?alt=json` and asserts both `alt` and `key` survive
  (merge, not overwrite).
- **Stale state** — N/A: function is stateless; each call builds its own
  URI/headers from the passed `ProviderConfig`; injected clients are
  caller-owned and never closed by the function.
- **Dirty worktree** — N/A: only `lib/core/agent/models_client.dart`, the new
  test file, and this evidence file were touched; no git commands run per
  constraints. Existing caller (`provider_detail_page.dart`) compiles
  unchanged because `client` is an optional named parameter.
- **Hung commands** — N/A: all commands completed in seconds; `MockClient`
  responses are immediate, and the production path keeps its 15s timeout.
- **Flaky tests** — N/A: no real network, timers, randomness, or I/O; all
  responses are literal `MockClient` payloads, so runs are deterministic.
- **Prompt injection** — N/A: no external/untrusted input consumed; all test
  data is literal.
- **Cancel-resume / repeated interruptions** — N/A: single-pass deterministic
  task.

## Cleanup receipt

None required beyond normal test artifacts. `flutter test` only wrote to
`.dart_tool/` (gitignored); no temp files, no stray files outside the two
intended paths plus this evidence file.
