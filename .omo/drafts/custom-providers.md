---
slug: custom-providers
status: plan-written
intent: clear
review_required: false
pending-action: deliver summary; execution begins on user confirmation (user already said 开工)
approach: Protocol-type provider architecture (openai/claude/gemini) with built-in presets as code templates + user overlays, custom providers persisted as JSON, unified ProviderRegistry resolution, rikkahub-style management UI (clean-room reimplementation, plain comments), multi-key rotation, QR share/import, advisory connection tester.
metis-review: 2 passes complete. Pass 1 (design forks): A2/B1/C1/E1/F2/G2/H1/I/J1/K1/L adopted. Pass 2 (written-plan gap analysis, ses_feaba001dffe6Cg75jJsDkCb58): 32 findings folded in — 5 blockers fixed (gemini /v1beta guard, dangling active-model fallback, integration_test replacing human-only manual steps, F3 redefined, pre-existing rikkahub attribution comments at provider_selection_page.dart:3 + onboarding_page.dart:302 explicitly slated for removal), ~20 should-fixes (cleartext networkSecurityConfig for local providers, minSdk check, ValueKey reorder cards, add-card as sibling, search-disables-reorder, removeProviderState custom-only guard, registry.activeById centralization, settings_page display-name fix, ==/hashCode include enabled, QrImageView version fallback, mobile_scanner API verify, matrix edges 4/6/8/9/13/16/17), nits accepted as-is.
momus-review: ses_feaaedea0ffetrelD3T690eMWD — verdict [OKAY] unconditional; all file:line references verified on disk; single nit (build.gradle → build.gradle.kts) folded into todo 17.
---

# Draft: custom-providers

## Components (topology ledger)
| id | outcome (one line) | status | evidence path |
| --- | --- | --- | --- |
| C1 protocol-foundation | Chat + models clients dispatch on LlmProtocol enum; builtin Claude/Gemini chat actually works | active | .omo/evidence/ |
| C2 storage-registry | Custom providers persisted (keys excluded); ProviderRegistry merges builtins+customs+overlays; single resolution path | active | .omo/evidence/ |
| C3 multi-key | One key field holds many keys; random pick per request; retry with next key on 401/403/429 | active | .omo/evidence/ |
| C4 management-ui | Provider list (search/reorder/enable/badges), detail page with Config+Models tabs, custom provider add/edit/delete | active | .omo/evidence/ |
| C5 connection-tester | Real chat ping per protocol, advisory with save-anyway | active | .omo/evidence/ |
| C6 qr-share-import | QR generation + camera scan (Android) + paste-string import, moodpet-provider:v1 payload | active | .omo/evidence/ |

## Open assumptions (announced defaults)
| assumption | adopted default | rationale | reversible? |
| --- | --- | --- | --- |
| Storage layout | Hybrid: builtins stay code templates; customs in one JSON list (NO keys inside); per-id SharedPreferences overlays kept for all providers | Zero migration for existing installs; presets update with app releases | yes |
| Builtin editability | Core fields (name/baseUrl/icon/brandColor) read-only; editable: keys, models, enabled, order | "Protected presets" semantics; wanting a different URL = create custom | yes |
| Reorder | One merged order list incl. builtins; unknown ids appended, stale ids pruned at load | User asked reorder + protected (delete-only protection) | yes |
| Model entity | Flat list of model id strings per provider; NO capability inference | App has a single JSON-emotion call path; capabilities have no consumer | yes |
| Active model | Reuse existing modelOverride SharedPreferences key as "active model id" | Migration-free; existing selections keep working | yes |
| Multi-key strategy | Random pick + retry with a DIFFERENT key only on 401/403/429 (never on 400/404/500) | Random achieves load spread; retry matters more than LRU | yes |
| QR payload | `moodpet-provider:v1:<base64(json)>`; keys + models stripped | Own format, no cross-app compat expectation | yes |
| New dependencies | qr_flutter (generate) + mobile_scanner (Android scan) | User chose camera scan + paste | yes |
| Tester | One real chat ping (tiny max_tokens), advisory; save allowed even if test fails | Tests the actual code path incl. protocol dispatch; never blocks UX | yes |
| Test strategy | tests-after: unit tests (mock http.Client) for protocol request/response shapes, key splitting/rotation, registry merge, QR codec; QA via `flutter test` + `flutter analyze` + manual run | Zero existing provider tests; network paths must be mock-tested | yes |
| Onboarding | Flow unchanged; provider list shows builtins + any imported customs | First-time users pick a preset; customs are a settings feature | yes |
| Comments/attribution | Plain functional comments only; no external project names/attribution anywhere | User's explicit constraint | n/a |

## Findings (cited - path:lines)
- ProviderConfig immutable template; `kBuiltinProviders` 17 presets; `builtinProviderById` — lib/core/models/provider_config.dart:14-104,111-280,307-312
- SharedPreferences keys: activeId / apiKey.\<id\> / modelOverride.\<id\> — lib/core/storage/settings_store.dart:14-16,64-92
- Duplicate resolution path #1 — lib/core/providers.dart:82-93 (activeProviderConfigProvider)
- Duplicate resolution path #2 — lib/core/agent/pocketclaw_agent.dart:43-51 (_activeProvider)
- OpenAI-only chat client (Bearer, /chat/completions, non-streaming) — lib/core/agent/llm_client.dart:51-115
- Model discovery special-cased by provider.id string (claude/gemini/cohere) — lib/core/agent/models_client.dart:89-145
- Selection page renders kBuiltinProviders only — lib/features/settings/provider_selection_page.dart:42-50
- Detail page: key field + fetch models + dropdown/manual + save — lib/features/settings/provider_detail_page.dart:56-131
- Entry points: settings + onboarding (fromOnboarding offline skip) — lib/features/settings/settings_page.dart, lib/features/onboarding_page.dart
- Deps present: riverpod, shared_preferences, http, flutter_svg, uuid; NO qr packages — pubspec.yaml:9-41
- Zero tests covering provider code — blast-radius notes on all provider symbols
- App UI strings are Chinese; doc comments in English

## Decisions (with rationale)
- Scope: FULL version (user) — protocol types, custom CRUD, per-provider model management, multi-key, QR, tester, enable/disable+reorder, fix builtin Claude/Gemini chat
- QR: camera scan + paste (user) — mobile_scanner on Android, paste fallback everywhere
- E1 protocol enum dispatch (Metis) — one call path; strategy pattern is over-engineering; replaces id-string matching in models_client too
- A2 hybrid storage / B1 overlay-limited builtins / C1 merged reorder / F2 no capability inference / G2 real-call tester / H1 activeModelId=modelOverride key / I unified ProviderRegistry / J1 onboarding unchanged / K1 random+retry / L moodpet-provider:v1 (Metis recommendations, adopted)
- Claude chat: POST {baseUrl}/v1/messages, x-api-key + anthropic-version headers, top-level `system`, required max_tokens, parse content[0].text
- Gemini chat: POST {baseUrl}/models/{model}:generateContent, ?key= auth, contents[].parts[].text + systemInstruction, parse candidates[0].content.parts[0].text
- Retry never on 400/404/500 (different key cannot help)
- Never serialize API keys into the custom-providers JSON (security)

## Scope IN
- LlmProtocol enum (openai/claude/gemini) on ProviderConfig; protocol-aware chatCompletion + fetchAvailableModels
- Fix builtin Claude/Gemini chat via native protocols
- Custom provider CRUD + enable/disable + merged reorder
- Per-provider model list management (fetch from endpoint + manual add/remove + active model select)
- Multi-API-key field, random rotation, auth-failure retry with next key
- Connection tester (real ping, protocol-aware, advisory)
- QR share (generate image + copy string) / import (camera scan + paste)
- ProviderRegistry replacing builtinProviderById everywhere
- Provider list UI: search, reorder, enable/disable, badges (built-in/custom/disabled/N models)
- Provider detail UI: Config tab + Models tab; add/edit/delete custom; builtin lock semantics
- Onboarding list shows merged providers
- Unit tests (mock http) + flutter analyze clean + agent-executed QA

## Scope OUT (Must NOT have)
- Model capability inference / ModelRegistry-style DSL
- Streaming chat or streaming tests; tool/function calling
- LRU key rotation state
- Balance checking, per-model provider override, custom headers/bodies
- Assistants/personas, MCP, search grounding, TTS/ASR
- Provider export to file; WebDAV/sync
- Migrating/deleting existing per-id SharedPreferences keys
- Any external-project attribution in code comments or naming

## Open questions
- None blocking. All forks resolved (2 user answers + Metis-adopted defaults above).

## Approval gate
status: approved (user: 可以，开工)
pending action: NONE — plan written, Metis-folded, TL;DR filled. Next: begin execution per plan waves.
<!-- When exploration is exhausted and unknowns are answered, set status: awaiting-approval. -->
<!-- That durable record is the loop guard: on a later turn read it and resume at the gate instead of re-running exploration. -->
