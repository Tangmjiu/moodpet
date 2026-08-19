# Task 1 — Custom Providers: ProviderConfig protocol/custom fields + JSON codec

## Step: test-first (before implementation)

Command: `flutter test test/core/models/provider_config_test.dart`

Result: FAIL (compile errors — `LlmProtocol`, `fromJson`, new params undefined). Relevant lines:

```
test/core/models/provider_config_test.dart:15:19: Error: Undefined name 'LlmProtocol'.
        protocol: LlmProtocol.claude,
                  ^^^^^^^^^^^
test/core/models/provider_config_test.dart:15:9: Error: No named parameter with the name 'protocol'.
test/core/models/provider_config_test.dart:23:39: Error: Member not found: 'ProviderConfig.fromJson'.
test/core/models/provider_config_test.dart:45:9: Error: No named parameter with the name 'enabled'.
test/core/models/provider_config_test.dart:66:31: Error: Undefined name 'LlmProtocol'.
```

(Full run produced the same class of error for every new API usage; all pre-existing
tests untouched.)

## VERIFY 1 — new tests green

Command: `flutter test test/core/models/provider_config_test.dart`

```
00:00 +14: ProviderConfig copyWith and equality equality reflects protocol, isCustom, and enabled differences
00:00 +15: LlmProtocol jsonValue round-trips through fromJsonValue
00:00 +16: LlmProtocol fromJsonValue falls back to openai for null or unknown
00:00 +17: LlmProtocol builtin claude and gemini entries declare their protocol
00:00 +18: All tests passed!
```

Result: PASS — 18/18 tests green.

## VERIFY 2 — analyzer clean

Command: `flutter analyze lib/core/models/provider_config.dart test/core/models/provider_config_test.dart`

```
Analyzing 2 items...
No issues found! (ran in 0.9s)
```

Result: PASS — zero issues. `lsp_diagnostics` on both files also reports none.

## VERIFY 3 — pre-existing model tests unchanged

Command: `flutter test test/models/`

```
00:00 +23: /home/mjiutang/moonpet/test/models/provider_config_test.dart: RegionInfo country names countryNameFromCode handles null gracefully
00:00 +24: All tests passed!
```

Result: PASS — 24/24 pre-existing tests green without any modification.

## VERIFY 4 — forbidden-term grep

Command: `grep -rniE "rikka|borrowed|adapted from|inspired by" lib/core/models/provider_config.dart test/core/models/`

```
(no output)
grep exit: 1
```

Result: PASS — zero hits (grep exit 1 = no matches).

## Adversarial classes

- **New input parsing (fromJson) → PROBED.** Documented behavior: a value present with
  the wrong type throws `FormatException` (`_requiredString` / `_optionalString` /
  `_optionalBool`); missing keys and explicit `null`s fall back to documented defaults;
  unknown protocol strings fall back to `LlmProtocol.openai`. Covered by tests:
  "fromJson throws FormatException for wrong-typed values" (int id, string isCustom),
  "fromJson tolerates null values for optional keys", "fromJson applies defaults for
  missing optional keys", "fromJson falls back to openai for unknown protocol string".
- **Stale state** — N/A: pure immutable model; all copies flow through `copyWith` which
  the equality tests exercise.
- **Dirty worktree** — N/A: only `lib/core/models/provider_config.dart` and the new test
  file were touched; no git commands run per constraints.
- **Hung commands** — N/A: all commands completed in seconds (see timings above).
- **Flaky tests** — N/A: no async, timers, randomness, or I/O in the model or tests;
  two consecutive full runs would be identical.
- **Misleading success output** — guarded: the test-first failing output above proves the
  tests exercise the new APIs (they did not compile before the implementation).
- **Prompt injection** — N/A: no external/untrusted input consumed; all test data is
  literal.
- **Cancel-resume / repeated interruptions** — N/A: single-pass deterministic task.

## Cleanup receipt

None required beyond normal test artifacts. `flutter test` only wrote to
`.dart_tool/` (gitignored); no temp files, no stray files outside the two intended
paths plus this evidence file.
