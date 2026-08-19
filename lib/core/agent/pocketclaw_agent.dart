/// PocketClaw — the container's default Agent engine (§10).
///
/// Responsibilities:
///   1. Read the active Friend plugin's system prompt.
///   2. Receive user input.
///   3. Call the configured LLM provider via [LlmClient].
///   4. Parse the returned JSON into an [EmotionResponse].
///   5. Fall back to the Friend's keyword-based [EmojiMapping] when no provider
///      is configured or the LLM call fails.
///
/// PocketClaw itself can be replaced by an Application plugin that declares
/// `overrides.services.agent = true` ([社区]). The replacement registers an
/// alternative [AgentService] with the Application runtime.
library;

import 'dart:convert';

import '../models/emotion.dart';
import '../models/provider_config.dart';
import '../plugin/plugin_manager.dart';
import '../provider_registry.dart';
import '../storage/settings_store.dart';
import 'agent_service.dart';
import 'llm_client.dart';

/// The default agent. One instance per app process.
class PocketClawAgent implements AgentService {
  final PluginManager _plugins;
  final SettingsStore _settings;
  final ProviderRegistry _registry;

  PocketClawAgent(this._plugins, this._settings, this._registry);

  @override
  String get displayName => 'PocketClaw';

  @override
  bool get isReady {
    final provider = _activeProvider;
    return provider != null && provider.isConfigured;
  }

  /// Resolve the active [ProviderConfig] through the registry, or `null` when
  /// no provider is selected or the selected one is disabled. The registry
  /// already overlays the persisted API key and model override.
  ProviderConfig? get _activeProvider {
    final id = _settings.activeProviderId;
    if (id == null) return null;
    return _registry.activeById(id);
  }

  @override
  Future<AgentResult> respond(String userInput) async {
    // Step 1: get the system prompt from the active Friend.
    final systemPrompt = await _plugins.activeFriendSystemPrompt();

    // Step 2: try the LLM path when a provider is configured.
    final provider = _activeProvider;
    if (provider != null && provider.isConfigured) {
      final result = await chatCompletion(
        provider: provider,
        systemPrompt: systemPrompt.replaceAll('{name}', _plugins.activeFriendName),
        userInput: userInput,
      );
      if (result.isOk) {
        final parsed = _parseEmotionJson(result.content);
        if (parsed != null) return AgentResult.ok(parsed);
        // LLM returned non-JSON → fall through to keyword fallback.
      }
      // LLM call failed → fall through to keyword fallback.
    }

    // Step 3: keyword-based fallback using the Friend's emoji mapping.
    final mapping = await _plugins.activeFriendEmojiMapping();
    if (mapping != null) {
      return AgentResult.ok(mapping.resolve(userInput));
    }

    // Step 4: ultimate fallback — the idle response.
    return const AgentResult.ok(EmotionResponse.idle);
  }

  /// Parse the LLM's text reply into an [EmotionResponse].
  ///
  /// The system prompt instructs the LLM to return a JSON object with
  /// `emoji`, `color`, `vibration`, and `suggestion` fields. The reply may
  /// contain markdown code fences or extra text, so we extract the first
  /// `{...}` block before parsing.
  EmotionResponse? _parseEmotionJson(String raw) {
    // Strip markdown code fences if present.
    final jsonStr = _extractJsonBlock(raw);
    if (jsonStr == null) return null;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, Object?>) return null;
      return EmotionResponse.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Extract the first `{ ... }` JSON object from a possibly noisy string.
  String? _extractJsonBlock(String raw) {
    final trimmed = raw.trim();
    // Fast path: the whole string is JSON.
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return trimmed;
    }
    // Strip markdown code fences: ```json ... ``` or ``` ... ```
    final fenceStart = trimmed.indexOf('```');
    if (fenceStart >= 0) {
      final afterFence = trimmed.substring(fenceStart + 3);
      final lineEnd = afterFence.indexOf('\n');
      final jsonStart = lineEnd >= 0 ? afterFence.substring(lineEnd + 1) : afterFence;
      final fenceEnd = jsonStart.indexOf('```');
      final candidate = fenceEnd >= 0
          ? jsonStart.substring(0, fenceEnd).trim()
          : jsonStart.trim();
      if (candidate.startsWith('{')) return candidate;
    }
    // Fallback: find the first { and the last }.
    final firstBrace = trimmed.indexOf('{');
    final lastBrace = trimmed.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      return trimmed.substring(firstBrace, lastBrace + 1);
    }
    return null;
  }
}
