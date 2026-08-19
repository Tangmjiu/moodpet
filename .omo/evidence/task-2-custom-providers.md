# Task 2 — Custom Providers: chatCompletion protocol dispatch + multi-key rotation + retry

## Step: test-first (before implementation)

Command: `flutter test test/core/agent/llm_client_test.dart`

Result: FAIL (compile errors — `splitApiKeys` and the `client` parameter did not
exist yet). Relevant lines:

```
test/core/agent/llm_client_test.dart:42:14: Error: Method not found: 'splitApiKeys'.
      expect(splitApiKeys('a, b\nc  d'), <String>['a', 'b', 'c', 'd']);
             ^^^^^^^^^^^^
test/core/agent/llm_client_test.dart:68:9: Error: No named parameter with the name 'client'.
        client: client,
        ^^^^^^
lib/core/agent/llm_client.dart:51:19: Context: Found this candidate, but the arguments don't match.
Future<LlmResult> chatCompletion({
                  ^^^^^^^^^^^^^^
00:00 +0 -1: Some tests failed.
```

(Every new API usage failed the same way; all pre-existing tests untouched.)

## VERIFY 1 — new tests green

Command: `flutter test test/core/agent/llm_client_test.dart`

```
00:00 +13: chatCompletion multi-key rotation and retry 429 retries once with the other key and succeeds
00:00 +14: chatCompletion multi-key rotation and retry 400 never retries, even with untried keys remaining
00:00 +15: chatCompletion multi-key rotation and retry network exceptions fail immediately without retrying
00:00 +16: chatCompletion key handling keyless custom provider sends no Authorization header
00:00 +17: chatCompletion key handling keyless builtin provider fails without any HTTP call
00:00 +18: All tests passed!
```

Result: PASS — 18/18 tests green.

Mid-implementation note: the first green run showed 17/18 with one failure —
my own test expectation for the claude relay case asserted
`https://relay.example.com/messages` while the spec defines the relay URL as
`{baseUrl}/messages` = `https://relay.example.com/v1/messages` (append
`/messages` to the `/v1`-suffixed base; the `/v1` segment itself is kept).
The implementation matched the spec; the test expectation was wrong and was
corrected (plus a `/v1/v1/` non-doubling assertion added). Not an
implementation defect.

## VERIFY 2 — analyzer clean

Command: `flutter analyze lib/core/agent/llm_client.dart test/core/agent/llm_client_test.dart`

```
Analyzing 2 items...
No issues found! (ran in 1.0s)
```

Result: PASS — zero issues (flutter_lints v6). `lsp_diagnostics` on both files
also reports none.

## VERIFY 3 — pre-existing model tests unchanged

Command: `flutter test test/models/`

```
00:00 +23: /home/mjiutang/moonpet/test/models/provider_config_test.dart: RegionInfo country names countryNameFromCode handles null gracefully
00:00 +24: All tests passed!
```

Result: PASS — 24/24 pre-existing tests green without any modification.

## VERIFY 4 — forbidden-term grep

Command: `grep -rniE "rikka|borrowed|adapted from|inspired by" lib/core/agent/llm_client.dart test/core/agent/`

```
(no output)
grep exit: 1
```

Result: PASS — zero hits (grep exit 1 = no matches).

## VERIFY 5 — full-suite regression

Command: `flutter test`

```
00:02 +111: /home/mjiutang/moonpet/test/models/provider_config_test.dart: RegionInfo country names countryNameFromCode handles null gracefully
00:02 +112: All tests passed!
```

Result: PASS — 112/112 tests green across the whole repo (includes the
pre-existing `test/app_test.dart`, which exercises the `pocketclaw_agent` →
`chatCompletion` call path; the backward-compatible optional `client`
parameter kept that call site untouched).

## Adversarial classes

- **Malformed input (garbage 200 body) → PROBED, does not crash.** Covered by
  tests: "openai 200 with a non-JSON body fails with a reason instead of
  throwing" (body `<<garbage>>` → `response is not valid JSON`, error does not
  contain `request failed`), "claude 200 with no text content block fails"
  (`{content: []}`), "gemini 200 with no candidates fails" (`{}`). All
  response-shape mismatches fail with a specific reason; `jsonDecode` is the
  only throwing call and is wrapped in a `FormatException` guard.
- **Retry-boundary abuse → PROBED.** 429 rotates to a different untried key
  (2 requests, distinct `Authorization` values, asserted as the set
  `{Bearer k1, Bearer k2}`); 400 with 2 keys performs exactly 1 request and
  fails; a network exception with 2 keys performs exactly 1 call and fails
  with `request failed` — no speculative retries on non-key failures.
- **Misleading success output → guarded.** The test-first failing output above
  proves the tests exercise the new APIs (they did not compile before the
  implementation), and every VERIFY entry shows the exact re-runnable command
  with its real output from this run.
- **Randomness/flakiness → N/A.** With `keys.length` keys and key-retryable
  statuses, the loop tries each key at most once; the retry test uses 2 keys
  so the second attempt deterministically uses the only untried key — request
  count and key set are stable across runs.
- **Backward compatibility → PROBED.** `chatCompletion` gained only the
  optional named `http.Client? client`; the sole production caller
  (`pocketclaw_agent.dart`) compiles and its suite (`test/app_test.dart`,
  inside VERIFY 5's full run) passes unmodified. `LlmResult`, `ChatMessage`,
  and `_truncate` are unchanged; the openai request/response contract is
  byte-identical to the previous implementation (asserted in the openai happy
  test: URL, Bearer header, model/messages/temperature/max_tokens body).
- **Stale state / dirty worktree / hung commands / prompt injection /
  cancel-resume → N/A:** pure function + immutable config, no persistence;
  only `lib/core/agent/llm_client.dart` and the new test file were touched, no
  git commands run per constraints; all commands completed in seconds; all
  test data is literal; single-pass deterministic task.

## Cleanup receipt

None required beyond normal test artifacts. `flutter test` only wrote to
`.dart_tool/` (gitignored); no temp files, no stray files outside the two
intended paths plus this evidence file. No new packages added (MockClient
ships with `package:http/testing.dart` from the existing `http` dependency).
