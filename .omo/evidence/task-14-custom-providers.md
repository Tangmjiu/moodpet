# Task 14 — Custom Providers: QR share payload codec

## What was built

New file `lib/core/utils/provider_share_codec.dart` (matches `color_hex.dart` comment style —
`///` doc comments + `library;` directive, plain functional English):

- `const String kProviderSharePrefix = 'moodpet-provider:v1:'`
- `String encodeProviderShare(ProviderConfig provider)` — serialises only endpoint-shape
  fields (`v`, `name`, `baseUrl`, `protocol`, `modelsEndpoint`, `defaultModel`,
  `chatCompletionsPath`) to a `moodpet-provider:v1:<base64-json>` string. The `apiKey`,
  `modelOverride`, `enabled`, `iconAsset`, `brandColor`, `id` and `isCustom` are never
  written: secrets and local state stay on the device; the recipient's app assigns a
  fresh local id on import (documented in the function doc comment).
- `ProviderConfig? decodeProviderShare(String raw)` — trims, requires the prefix,
  base64-decodes (try/catch → null), utf8-decodes + jsonDecodes (try/catch → null),
  requires a Map with non-empty `name` and `baseUrl` strings, falls back to
  `LlmProtocol.openai` for unknown/missing protocol, and builds a fresh
  `ProviderConfig(id: Uuid().v4(), isCustom: true, apiKey:'', iconAsset:'', brandColor:'')`
  with optional-field defaults (`modelsEndpoint` null, `defaultModel` '',
  `chatCompletionsPath` '/chat/completions').

New test `test/core/utils/provider_share_codec_test.dart` (10 tests, cases a–i).

No other files edited; no git commands run; no new packages added.

## Step: test-first (before implementation)

Command: `flutter test test/core/utils/provider_share_codec_test.dart`

Result: FAIL (compile errors — `lib/core/utils/provider_share_codec.dart` did not exist
yet, so `encodeProviderShare`, `decodeProviderShare` and `kProviderSharePrefix` were
undefined). Relevant lines:

```
test/core/utils/provider_share_codec_test.dart:5:8: Error: Error when reading 'lib/core/utils/provider_share_codec.dart': No such file or directory
import 'package:moodpet/core/utils/provider_share_codec.dart';
       ^
test/core/utils/provider_share_codec_test.dart:26:23: Error: Method not found: 'encodeProviderShare'.
test/core/utils/provider_share_codec_test.dart:27:23: Error: Method not found: 'decodeProviderShare'.
test/core/utils/provider_share_codec_test.dart:65:48: Error: Undefined name 'kProviderSharePrefix'.
test/core/utils/provider_share_codec_test.dart:87:14: Error: Method not found: 'decodeProviderShare'.
... (same class of error for every encode/decode call site and the prefix constant)
```

This proves the tests exercise the new API surface rather than passing trivially.

## VERIFY 1 — new tests green

Command: `flutter test test/core/utils/provider_share_codec_test.dart`

```
00:00 +0: loading /home/mjiutang/moonpet/test/core/utils/provider_share_codec_test.dart
00:00 +0: provider_share_codec round-trip encode -> decode preserves fields and strips secret/local state
00:00 +1: provider_share_codec payload safety encoded string and its decoded JSON omit apiKey and modelOverride
00:00 +2: provider_share_codec decode failure modes wrong prefix returns null
00:00 +3: provider_share_codec decode failure modes corrupt base64 returns null
00:00 +4: provider_share_codec decode failure modes valid base64 of non-JSON returns null
00:00 +5: provider_share_codec decode failure modes JSON missing name returns null
00:00 +6: provider_share_codec decode failure modes JSON missing baseUrl returns null
00:00 +7: provider_share_codec decode defaults unknown protocol string falls back to openai
00:00 +8: provider_share_codec decode defaults missing optional fields use defaults
00:00 +9: provider_share_codec decode defaults leading/trailing whitespace in raw still decodes
00:00 +10: All tests passed!
```

Result: PASS — 10/10 tests green. Coverage of the required cases:

| Case | Test |
|------|------|
| a round-trip + isCustom/apiKey/id | `encode -> decode preserves fields and strips secret/local state` |
| b payload safety (no secret/override) | `encoded string and its decoded JSON omit apiKey and modelOverride` |
| c wrong prefix → null | `wrong prefix returns null` |
| d corrupt base64 → null | `corrupt base64 returns null` |
| e valid base64 of non-JSON → null | `valid base64 of non-JSON returns null` |
| f missing name / missing baseUrl → null | `JSON missing name returns null` + `JSON missing baseUrl returns null` |
| g unknown protocol → openai | `unknown protocol string falls back to openai` |
| h missing optional fields → defaults | `missing optional fields use defaults` |
| i leading/trailing whitespace → decodes | `leading/trailing whitespace in raw still decodes` |

## VERIFY 2 — analyzer clean

Command: `flutter analyze lib/core/utils/provider_share_codec.dart test/core/utils/provider_share_codec_test.dart`

```
Analyzing 2 items...
No issues found! (ran in 1.2s)
```

Result: PASS — zero issues. `lsp_diagnostics` on both files also reports "No
diagnostics found".

## VERIFY 3 — forbidden-term grep

Command: `grep -rniE "rikka|borrowed|adapted from|inspired by|based on|copied from|ported from|forked from|shamelessly" lib/core/utils/provider_share_codec.dart test/core/utils/provider_share_codec_test.dart`

```
(no output)
grep exit: 1
```

Result: PASS — zero hits (grep exit 1 = no matches). No external project names or
attribution present anywhere in the new files.

## Adversarial classes

- **Malformed input (c, d, e, f, i) → PROBED.** Wrong prefix, corrupt base64
  (`!!!not-b64`), valid-base64-of-non-JSON, JSON missing `name`, JSON missing
  `baseUrl`, and whitespace-padded raw are each a dedicated test. `c/d/e/f` assert
  `null`; `i` asserts a successful decode. Every decode failure path returns `null`
  rather than throwing — wrapped in try/catch on both the base64 and the
  utf8/jsonDecode steps, plus an explicit `is! Map` and non-empty-string guard.
- **Prompt injection → N/A.** The payload is inert data: it is base64-decoded,
  JSON-parsed into a `Map<String, Object?>`, and only string fields are read into a
  `ProviderConfig`. No value from the payload is ever executed, rendered as code,
  or used as a key/identifier for further dispatch. A malicious payload can at worst
  produce `null` (rejected) or a `ProviderConfig` whose `name`/`baseUrl` strings are
  attacker-controlled — which is exactly the intended trust model of a share/import
  feature (the recipient reviews the imported endpoint in UI before use; todo 15/16
  own that surface). No string from the payload is interpolated into a command, URL
  fetch, or query by this codec.
- **Stale state** — N/A: pure functional codec, no caches, no shared mutable state.
- **Dirty worktree** — N/A: only two new files were created; no pre-existing files or
  tests were modified.
- **Hung commands** — N/A: `flutter test` and `flutter analyze` each completed in
  under 2s (see timings above).
- **Flaky tests** — N/A: no async, timers, randomness, or I/O. `Uuid().v4()` produces
  a fresh id per run but the tests assert `isNotEmpty` / `!= original.id` rather than
  a fixed value, so runs are deterministic in pass/fail terms.
- **Misleading success output** — guarded: the test-first failing output above proves
  the tests exercise the new API (they did not compile before the implementation
  existed); the payload-safety test decodes the base64 segment and greps the inner
  JSON, so a leak in either layer would fail the assertion.

## Cleanup receipt

None required. `flutter test` / `flutter analyze` wrote only to `.dart_tool/`
(gitignored). No temp files, no stray files. The only files created are the two
intended source/test files plus this evidence file.
