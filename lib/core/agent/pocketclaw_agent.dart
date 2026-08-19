/// PocketClaw — the container's default Agent engine (§10).
///
/// Responsibilities:
///   1. Read the active Friend plugin's system prompt.
///   2. Receive user input.
///   3. Call the configured LLM provider via [LlmClient].
///   4. Parse the returned JSON into an [EmotionResponse].
///   5. Fall back to the Friend's keyword-based [EmojiMapping] **only when no
///      provider is configured** (true offline mode). When a provider IS
///      configured but the LLM call fails or returns unparseable output, the
///      failure is surfaced to the caller via [AgentResult.fail] — never
///      silently degraded — so the UI can show the error and the user can
///      diagnose it via the log viewer.
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
import '../storage/conversation_store.dart';
import '../storage/settings_store.dart';
import 'agent_logger.dart';
import 'agent_service.dart';
import 'llm_client.dart';

/// The default agent. One instance per app process.
class PocketClawAgent implements AgentService {
  final PluginManager _plugins;
  final SettingsStore _settings;
  final ProviderRegistry _registry;
  final ConversationStore? _conversation;

  /// [conversation] is optional — when null, the agent runs stateless (no
  /// history fed to the LLM, no persistence). The app wires it in via the
  /// provider; tests can omit it.
  PocketClawAgent(
    this._plugins,
    this._settings,
    this._registry, [
    this._conversation,
  ]);

  @override
  String get displayName => 'PocketClaw';

  @override
  bool get isReady {
    // `isReady` reports **configuration completeness**, not live reachability
    // — a provider with a non-empty API key (built-in) or baseUrl (custom)
    // counts as ready even if the endpoint is currently down. Live failures
    // are surfaced at call time via [AgentResult.fail] and the [AgentLogger],
    // not via this flag. The UI uses this to decide whether to show the
    // "离线陪伴模式" badge (shown when NOT ready) — the badge therefore means
    // "no provider configured", which is the user-actionable state.
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
    final log = AgentLogger.instance;

    final systemPrompt = await _plugins.activeFriendSystemPrompt();
    final friendName = _plugins.activeFriendName;

    // Build LLM context from recent conversation history (last 10 turns →
    // 20 messages). This gives the partner continuity across restarts.
    final history = <ChatMessage>[];
    if (_conversation != null) {
      for (final turn in _conversation.recent(10)) {
        history.add(ChatMessage(role: 'user', content: turn.userInput));
        history.add(ChatMessage(role: 'assistant', content: turn.partnerReply));
      }
    }

    final provider = _activeProvider;
    if (provider != null && provider.isConfigured) {
      log.info('agent', 'LLM 调用: provider=${provider.id} model=${provider.effectiveModel} history=${history.length ~/ 2}轮 input="${_truncate(userInput, 60)}"');
      final result = await chatCompletion(
        provider: provider,
        systemPrompt: systemPrompt.replaceAll('{name}', friendName),
        userInput: userInput,
        history: history,
      );
      if (result.isOk) {
        var parsed = _parseEmotionJson(result.content);
        if (parsed != null) {
          // If the JSON carried no `message`, recover any natural-language
          // text the LLM wrote outside the JSON block as the partner's full
          // reply. The system prompt only asks for a ≤10-char suggestion, so
          // without this recovery the LLM's actual conversational words are
          // lost and the bubble shows only the short suggestion — which is the
          // "原来的回答被吞掉了" bug.
          final hasMessage =
              parsed.message != null && parsed.message!.isNotEmpty;
          if (!hasMessage) {
            final outside = _textOutsideJson(result.content);
            if (outside != null && outside.isNotEmpty) {
              parsed = parsed.copyWith(message: outside);
            }
          }
          final replyText = parsed.displayText;
          log.info('agent', 'LLM 成功，已解析为 EmotionResponse',
              rawPayload: result.content);
          await _conversation?.append(userInput, replyText);
          return AgentResult.ok(parsed);
        }
        final text = result.content.trim();
        if (text.isNotEmpty) {
          log.warn('agent', 'LLM 未返回 JSON，自愈为纯文本回应',
              rawPayload: result.content);
          final healed = EmotionResponse(
            emoji: '😊',
            color: '#E8A87C',
            vibration: const <int>[],
            suggestion: _truncate(text, 10),
            message: text,
          );
          await _conversation?.append(userInput, text);
          return AgentResult.ok(healed);
        }
        log.warn('agent', 'LLM 返回内容为空', rawPayload: result.content);
        return AgentResult.fail('LLM 返回了空内容');
      }
      log.error('llm', 'LLM 调用失败: ${result.error}',
          rawPayload: 'HTTP ${result.statusCode}');
      return AgentResult.fail(result.error);
    }

    log.info('agent', '离线模式：未配置 LLM provider，使用关键词词库回应');
    final mapping = await _plugins.activeFriendEmojiMapping();
    if (mapping != null) {
      final resolved = mapping.resolve(userInput);
      final withMessage = resolved.copyWith(message: resolved.suggestion);
      log.info('agent', '关键词匹配: ${resolved.emoji} "${resolved.suggestion}"');
      await _conversation?.append(userInput, resolved.suggestion);
      return AgentResult.ok(withMessage);
    }

    log.warn('agent', '无 emoji_mapping 可用，返回 idle 默认响应');
    await _conversation?.append(userInput, EmotionResponse.idle.displayText);
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

  /// Recover natural-language text that the LLM wrote outside the JSON block.
  ///
  /// When the LLM returns "自然语言 + {json}" (or the reverse), `_extractJsonBlock`
  /// keeps only the JSON and the surrounding prose — the partner's actual reply —
  /// is lost. This helper returns that surrounding prose so it can be used as
  /// `EmotionResponse.message`. Returns `null` when there is nothing outside
  /// the JSON block.
  String? _textOutsideJson(String raw) {
    final firstBrace = raw.indexOf('{');
    final lastBrace = raw.lastIndexOf('}');
    if (firstBrace < 0 || lastBrace <= firstBrace) return null;
    final before = raw.substring(0, firstBrace).trim();
    final after = raw.substring(lastBrace + 1).trim();
    // Strip markdown code-fence remnants (```json / ```) from the edges.
    final cleanedBefore = before
        .replaceAll(RegExp(r'^```\w*\s*'), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();
    final cleanedAfter = after
        .replaceAll(RegExp(r'^```\w*\s*'), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();
    final parts = [cleanedBefore, cleanedAfter]
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return null;
    return parts.join('\n');
  }

  /// Truncate [s] to [max] chars with an ellipsis, for log summaries.
  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}
