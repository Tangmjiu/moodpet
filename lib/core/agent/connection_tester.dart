/// Advisory provider connectivity probe.
///
/// Sends a tiny chat completion through the shared multi-protocol client so
/// the probe exercises the provider's real wire protocol. The result is
/// advisory only — callers decide whether a failure blocks anything.
library;

import 'package:http/http.dart' as http;

import '../models/provider_config.dart';
import 'llm_client.dart';

/// The outcome of a provider connectivity probe.
class ConnectionTestResult {
  /// Whether the probe chat completion succeeded.
  final bool ok;

  /// HTTP status code reported by the probe (0 for network/timeout failures).
  final int statusCode;

  /// Error message when the probe failed; `null` on success.
  final String? error;

  /// Round-trip latency measured by the probe, in milliseconds.
  final int latencyMs;

  const ConnectionTestResult({
    required this.ok,
    required this.statusCode,
    this.error,
    required this.latencyMs,
  });
}

/// Probe a provider with a real (tiny) chat completion against its actual
/// wire protocol. Advisory only — callers decide whether a failure blocks
/// anything (the settings UI lets users save anyway).
Future<ConnectionTestResult> testProviderConnection({
  required ProviderConfig provider,
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final sw = Stopwatch()..start();
  final result = await chatCompletion(
    provider: provider,
    systemPrompt: 'Reply with OK.',
    userInput: 'OK',
    maxTokens: 8,
    timeout: timeout,
    client: client,
  );
  sw.stop();
  return ConnectionTestResult(
    ok: result.isOk,
    statusCode: result.statusCode,
    error: result.error,
    latencyMs: sw.elapsedMilliseconds,
  );
}
