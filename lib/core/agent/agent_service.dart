/// Agent service interface (§10).
///
/// The container's default agent is [PocketClawAgent], but an Application
/// plugin that declares `overrides.services.agent = true` may register a
/// replacement [AgentService] implementation. The UI and the home page call
/// [AgentService.respond] without knowing which implementation is active.
///
/// This is the contract the container exposes; community Application plugins
/// ([社区]) provide alternative implementations.
library;

import '../models/emotion.dart';

/// The result of an agent call: either a parsed [EmotionResponse] or an error
/// message. Never throws — failures are communicated via [error].
class AgentResult {
  final EmotionResponse? response;
  final String? error;

  const AgentResult.ok(this.response) : error = null;
  const AgentResult.fail(this.error) : response = null;

  bool get isOk => response != null;
}

/// The agent service contract.
///
/// Implementations:
///   - [PocketClawAgent] — the container default (§10).
///   - Community Application plugins ([社区]) — registered via the
///     Application runtime to override `agent`.
abstract class AgentService {
  /// Process [userInput] and return an [AgentResult].
  ///
  /// Implementations must not throw — all failures are returned as
  /// [AgentResult.fail]. A successful call returns a parsed
  /// [EmotionResponse] with emoji / color / vibration / suggestion.
  Future<AgentResult> respond(String userInput);

  /// Whether the agent is ready to make calls (e.g. has a configured provider
  /// with a non-empty API key). The UI uses this to decide whether to show a
  /// "configure provider" prompt.
  bool get isReady;

  /// Human-readable name for display (e.g. "PocketClaw").
  String get displayName;
}
