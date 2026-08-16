/// Core models shared by the PocketClaw agent framework.
library;

/// Authentication strategy used when calling a cloud LLM endpoint.
enum PocketClawAuthType {
  /// Standard `Authorization: Bearer <token>`.
  bearer,

  /// Custom header, e.g. `x-api-key: <key>`.
  apiKeyHeader,

  /// Key appended as a query parameter, e.g. `?key=<key>`.
  queryParam,

  /// Special auth flow (Baidu ERNIE access-token, iFlytek Spark HMAC, ...).
  custom,
}

/// A single chat message in OpenAI-compatible shape.
class PocketClawMessage {
  const PocketClawMessage({required this.role, required this.content});

  final String role; // system | user | assistant
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// A callable tool that can be registered on an agent. Kept intentionally
/// small so MoodPet can later register timers / messaging tools.
class PocketClawTool {
  const PocketClawTool({
    required this.name,
    required this.description,
    this.parameters,
    this.handler,
  });

  final String name;
  final String description;

  /// JSON-schema style parameter description.
  final Map<String, dynamic>? parameters;

  /// Optional synchronous handler used by local decision routing.
  final Future<dynamic> Function(Map<String, dynamic> args)? handler;

  Map<String, dynamic> toJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          if (parameters != null) 'parameters': parameters,
        },
      };
}

/// Structured result returned by [PocketClaw.chat].
class AgentResponse {
  const AgentResponse({required this.content, this.metadata = const {}});

  /// Plain text (or JSON string) produced by the model.
  final String content;

  /// Arbitrary metadata (model name, usage, raw provider payload, ...).
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {'content': content, 'metadata': metadata};
}

/// Result of a connection / key / model verification call.
class PocketClawVerifyResult {
  const PocketClawVerifyResult({
    required this.ok,
    this.message = '',
    this.code = PocketClawVerifyCode.ok,
    this.statusCode,
  });

  final bool ok;
  final String message;
  final PocketClawVerifyCode code;
  final int? statusCode;
}

enum PocketClawVerifyCode {
  ok,
  networkError,
  authError,
  modelError,
  quotaError,
  timeout,
  unknown,
}

class PocketClawException implements Exception {
  const PocketClawException(this.message, {this.code = PocketClawVerifyCode.unknown});

  final String message;
  final PocketClawVerifyCode code;

  @override
  String toString() => 'PocketClawException($code): $message';
}
