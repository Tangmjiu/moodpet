# Task 4 — Custom Providers: supplementary key-splitting/rotation unit tests

## Scope

New file `test/core/agent/key_rotation_test.dart` ONLY. No `lib/` edits, no
edit to the existing `test/core/agent/llm_client_test.dart`. This is
characterization / coverage hardening of the key-splitting and multi-key retry
behavior already implemented in `lib/core/agent/llm_client.dart`
(`splitApiKeys` top-level function + `chatCompletion` random-pick rotation on
401/403/429 with an optional injectable `http.Client? client`).

The five new test cases lock the documented contract:

1. `splitApiKeys` multi-separator: `'a, b\nc  d'` → `['a','b','c','d']`;
   `'  '` → `[]`; `''` → `[]`; `'a,a'` → `['a','a']` (no dedupe).
2. THREE-key rotation: `apiKey: 'k1 k2 k3'`, `MockClient` returns 403, 403, then
   200 (openai protocol, helper-built `ProviderConfig`) → EXACTLY 3 requests,
   3 DISTINCT `Authorization` headers `{Bearer k1, Bearer k2, Bearer k3}` (set
   comparison — order is random per attempt), result ok.
3. single key + 403 → EXACTLY 1 request, result fail, error contains
   `'HTTP 403'`.
4. 2 keys both 429 → exactly 2 requests, final fail with `'HTTP 429'` (loop
   terminates — no infinite retry).
5. keyless custom (`isCustom: true`, `apiKey: ''`) + 401 → exactly 1 request,
   no `Authorization` header, fail `'HTTP 401'` (keyless path never retries).

The functions under test already exist; the tests passed on the first run,
recording the current behavior as the baseline.

## VERIFY 1 — new tests green (baseline)

Command: `flutter test test/core/agent/key_rotation_test.dart`

```
00:00 +0: loading /home/mjiutang/moonpet/test/core/agent/key_rotation_test.dart
00:00 +0: splitApiKeys splits on commas, spaces, newlines, and tabs, dropping empty segments
00:00 +1: splitApiKeys whitespace-only and empty input produce no keys
00:00 +2: splitApiKeys duplicates are preserved (no dedupe)
00:00 +3: chatCompletion key rotation three keys rotate through all keys on 403 and succeed
00:00 +4: chatCompletion key rotation single key with 403 fails after exactly one request
00:00 +5: chatCompletion key rotation two keys both rate-limited at 429 terminate without infinite retry
00:00 +6: chatCompletion key rotation keyless custom provider does not retry on 401 and sends no Authorization header
00:00 +7: All tests passed!
```

Result: PASS — 7/7 tests green (3 `splitApiKeys` + 4 `chatCompletion` key
rotation). All five required cases covered; case 1 is split across the three
`splitApiKeys` tests as in the existing sibling suite.

## VERIFY 2 — analyzer clean

Command: `flutter analyze test/core/agent/key_rotation_test.dart`

```
Analyzing key_rotation_test.dart...
No issues found! (ran in 0.7s)
```

Result: PASS — zero issues. `lsp_diagnostics` on the file also reports
`No diagnostics found`.

## VERIFY 3 — full agent test directory green (3 files)

Command: `flutter test test/core/agent/`

```
00:00 +0: loading /home/mjiutang/moonpet/test/core/agent/key_rotation_test.dart
... (7 key_rotation_test tests, +0..+6) ...
00:00 +7: /home/mjiutang/moonpet/test/core/agent/models_client_test.dart: fetchAvailableModels openai protocol sends Bearer header and returns sorted ids
... (11 models_client_test tests, +7..+17) ...
00:00 +18: /home/mjiutang/moonpet/test/core/agent/llm_client_test.dart: splitApiKeys splits on commas and any whitespace run, dropping empty segments
... (18 llm_client_test tests, +18..+35) ...
00:00 +36: All tests passed!
```

Result: PASS — 36/36 tests green across the 3 files
(`key_rotation_test.dart` = 7, `models_client_test.dart` = 11,
`llm_client_test.dart` = 18). The pre-existing `llm_client_test.dart` and
`models_client_test.dart` were not modified and still pass unchanged.

## VERIFY 4 — forbidden-term attribution grep

Command: `grep -niE "rikka|borrowed|adapted from|inspired by" test/core/agent/key_rotation_test.dart; echo "grep exit: $?"`

```
grep exit: 1
```

Result: PASS — zero hits (grep exit 1 = no matches).

## Adversarial classes

- **Flaky tests (random-pick order independence) → PROBED.** The 3-key
  rotation test asserts the SET of `Authorization` headers, not the order,
  because `chatCompletion` picks a random untried key per attempt. To prove the
  set-equality assertion is order-stable across the random draw, the test was
  run 10 times in a loop:

  ```
  for i in $(seq 10); do
    flutter test test/core/agent/key_rotation_test.dart --plain-name "three keys" \
      >/tmp/opencode/three-keys-run-$i.log 2>&1 || break
  done
  ```

  Result: **pass=10 fail=0**. Sample run 1 and run 10 logs:

  ```
  00:00 +0: loading /home/mjiutang/moonpet/test/core/agent/key_rotation_test.dart
  00:00 +0: chatCompletion key rotation three keys rotate through all keys on 403 and succeed
  00:00 +1: All tests passed!
  ```

  The set-equality assertion holds regardless of which random order the three
  keys are tried in — every run produces exactly the set
  `{Bearer k1, Bearer k2, Bearer k3}`.
- **Misleading success output → GUARDED.** Assertions read the captured
  `http.Request.headers` from `MockClient` (request count, `Authorization`
  header presence/values), not just the `LlmResult` return value, so the
  auth/rotation behavior is verified on the wire, not inferred from a passing
  result. The `requests.single.headers.containsKey('Authorization')` assertion
  in the keyless-custom case directly proves the header is absent.
- **Stale state** — N/A: `splitApiKeys` is pure; `chatCompletion` is
  stateless per call (builds its own URI/headers/`triedIndices` set from the
  passed `ProviderConfig` and a fresh `Random()`); injected `MockClient`s are
  caller-owned and never closed by the function.
- **Dirty worktree** — N/A: only the new test file and this evidence file were
  touched; no `lib/` file and no existing test file was modified; no git
  commands run per constraints.
- **Hung commands** — N/A: all commands completed in seconds; `MockClient`
  responses are immediate and synchronous; no real network, timers, or I/O.
- **Malformed input / new input parsing** — N/A: this task adds no parsing
  code; it only exercises the existing `splitApiKeys` separator behavior and
  the existing retry/rotation control flow. Malformed-JSON response handling
  is already covered by the sibling `llm_client_test.dart` suite.
- **Prompt injection** — N/A: no external/untrusted input consumed; all test
  data is literal.
- **Cancel-resume / repeated interruptions** — N/A: single-pass deterministic
  task.

## Cleanup receipt

None required beyond normal test artifacts. `flutter test` only wrote to
`.dart_tool/` (gitignored); the 10x probe wrote 10 small logs to
`/tmp/opencode/` (outside the workspace). No stray files inside the repo.
