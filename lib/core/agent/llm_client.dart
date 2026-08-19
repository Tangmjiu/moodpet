/// Multi-protocol chat completions HTTP client.
///
/// Every provider speaks one of the wire protocols declared by
/// [LlmProtocol]; this client dispatches the request shape, auth scheme, and
/// response parsing on [ProviderConfig.protocol]. When a provider carries
/// several API keys (see [splitApiKeys]), one untried key is picked at random
/// per attempt and key-level failures (HTTP 401/403/429) are retried with a
/// different key. Community Application plugins that override the `agent`
/// service ([社区]) may bypass this client entirely and call their own
/// backend.
library;

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/provider_config.dart';

/// A single chat message in the OpenAI format.
class ChatMessage {
  final String role; // "system" | "user" | "assistant"
  final String content;

  const ChatMessage({required this.role, required this.content});

  Map<String, String> toJson() => <String, String>{
        'role': role,
        'content': content,
      };
}

/// The result of an LLM call.
class LlmResult {
  /// The assistant's text reply.
  final String content;

  /// HTTP status code (200 on success).
  final int statusCode;

  /// Error message when the call failed; `null` on success.
  final String? error;

  const LlmResult.ok(this.content, this.statusCode) : error = null;
  const LlmResult.fail(this.error, this.statusCode) : content = '';

  bool get isOk => error == null && content.isNotEmpty;
}

/// Split a raw multi-key field into individual API keys.
///
/// Keys are separated by any run of whitespace or commas (`RegExp(r'[\s,]+')`),
/// empty segments are dropped, and the original order is preserved.
/// Duplicates are NOT removed: every entry is treated as a distinct
/// credential and gets its own attempt in the retry loop.
List<String> splitApiKeys(String raw) => raw
    .split(RegExp(r'[\s,]+'))
    .where((key) => key.isNotEmpty)
    .toList(growable: false);

/// Send a non-streaming chat completion request to [provider]'s endpoint.
///
/// [systemPrompt] becomes the system instruction and [userInput] the single
/// user message; [ProviderConfig.effectiveModel] is the model id. The exact
/// URL, headers, body, and response parsing are dispatched on
/// [ProviderConfig.protocol].
///
/// Key handling: [ProviderConfig.apiKey] may hold several keys separated by
/// commas or whitespace (see [splitApiKeys]). Each attempt picks a random
/// untried key; on HTTP 401/403/429 the call is retried with a different key
/// until every key has been tried once (at most `keys.length` attempts).
/// Other statuses (400/404/5xx) and network or timeout failures are never
/// retried. A custom provider without any key is called once without
/// credentials, which is what local endpoints expect; a built-in provider
/// without any key fails immediately without touching the network.
///
/// [client] injects the HTTP client to use (mainly for tests); when `null`,
/// a short-lived default client is created and closed after the call.
Future<LlmResult> chatCompletion({
  required ProviderConfig provider,
  required String systemPrompt,
  required String userInput,
  double temperature = 0.8,
  int maxTokens = 300,
  Duration timeout = const Duration(seconds: 30),
  http.Client? client,
}) async {
  final keys = splitApiKeys(provider.apiKey);
  if (keys.isEmpty && !provider.isCustom) {
    return const LlmResult.fail(
      'provider not configured (missing base URL or API key)',
      0,
    );
  }

  final httpClient = client ?? http.Client();
  try {
    final maxAttempts = keys.isEmpty ? 1 : keys.length;
    final triedIndices = <int>{};
    final random = Random();
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final key = _pickUntriedKey(keys, triedIndices, random);
      final request = _ChatRequest.build(
        provider,
        key,
        systemPrompt,
        userInput,
        temperature,
        maxTokens,
      );

      http.Response response;
      try {
        response = await httpClient
            .post(request.uri, headers: request.headers, body: request.body)
            .timeout(timeout);
      } catch (e) {
        // Network/timeout failures are never retried with another key.
        return LlmResult.fail('request failed: $e', 0);
      }

      // Rotate keys on auth/rate-limit failures while untried keys remain.
      if (_isKeyRetryable(response.statusCode) &&
          triedIndices.length < keys.length) {
        continue;
      }
      if (response.statusCode != 200) {
        return LlmResult.fail(
          'HTTP ${response.statusCode}: ${_truncate(response.body, 200)}',
          response.statusCode,
        );
      }
      return _parseResponse(provider.protocol, response);
    }
    // Unreachable: the loop always returns on its final attempt.
    throw StateError('chatCompletion retry loop exited unexpectedly');
  } finally {
    if (client == null) httpClient.close();
  }
}

/// Pick a random key whose index is not yet in [triedIndices] and mark it as
/// tried. Returns an empty string when [keys] is empty (keyless request).
String _pickUntriedKey(List<String> keys, Set<int> triedIndices, Random random) {
  if (keys.isEmpty) return '';
  final untried = <int>[
    for (var i = 0; i < keys.length; i++)
      if (!triedIndices.contains(i)) i,
  ];
  final index = untried[random.nextInt(untried.length)];
  triedIndices.add(index);
  return keys[index];
}

/// Whether [statusCode] is a key-level auth/rate-limit failure that may
/// succeed with a different key (401/403/429). Everything else — 400, 404,
/// 5xx — is a request- or server-level failure and is never retried.
bool _isKeyRetryable(int statusCode) =>
    statusCode == 401 || statusCode == 403 || statusCode == 429;

/// A prepared HTTP request for one attempt.
class _ChatRequest {
  final Uri uri;
  final Map<String, String> headers;
  final String body;

  const _ChatRequest(this.uri, this.headers, this.body);

  /// Build the request for [provider]'s protocol. [key] is the credential for
  /// this attempt and may be empty for keyless custom providers, in which
  /// case no auth credential is sent at all.
  factory _ChatRequest.build(
    ProviderConfig provider,
    String key,
    String systemPrompt,
    String userInput,
    double temperature,
    int maxTokens,
  ) {
    switch (provider.protocol) {
      case LlmProtocol.openai:
        return _ChatRequest(
          Uri.parse('${provider.baseUrl}${provider.chatCompletionsPath}'),
          <String, String>{
            'Content-Type': 'application/json',
            if (key.isNotEmpty) 'Authorization': 'Bearer $key',
          },
          jsonEncode(<String, Object?>{
            'model': provider.effectiveModel,
            'messages': <Map<String, String>>[
              ChatMessage(role: 'system', content: systemPrompt).toJson(),
              ChatMessage(role: 'user', content: userInput).toJson(),
            ],
            'temperature': temperature,
            'max_tokens': maxTokens,
          }),
        );
      case LlmProtocol.claude:
        return _ChatRequest(
          _claudeMessagesUri(provider.baseUrl),
          <String, String>{
            'Content-Type': 'application/json',
            if (key.isNotEmpty) 'x-api-key': key,
            'anthropic-version': '2023-06-01',
          },
          jsonEncode(<String, Object?>{
            'model': provider.effectiveModel,
            // max_tokens is a REQUIRED field of the Messages API.
            'max_tokens': maxTokens,
            'system': systemPrompt,
            'messages': <Map<String, String>>[
              ChatMessage(role: 'user', content: userInput).toJson(),
            ],
          }),
        );
      case LlmProtocol.gemini:
        return _ChatRequest(
          _geminiGenerateContentUri(provider, key),
          <String, String>{'Content-Type': 'application/json'},
          jsonEncode(<String, Object?>{
            'systemInstruction': <String, Object?>{
              'parts': <Map<String, String>>[
                <String, String>{'text': systemPrompt},
              ],
            },
            'contents': <Map<String, Object?>>[
              <String, Object?>{
                'role': 'user',
                'parts': <Map<String, String>>[
                  <String, String>{'text': userInput},
                ],
              },
            ],
            'generationConfig': <String, Object?>{
              'temperature': temperature,
              'maxOutputTokens': maxTokens,
            },
          }),
        );
    }
  }
}

/// The Anthropic Messages endpoint for [baseUrl]. Relay base URLs that
/// already end in `/v1` get `/messages` appended directly so the version
/// segment is never doubled.
Uri _claudeMessagesUri(String baseUrl) => Uri.parse(
    baseUrl.endsWith('/v1') ? '$baseUrl/messages' : '$baseUrl/v1/messages');

/// The Gemini generateContent endpoint for [provider], authenticating via the
/// `key` query parameter (omitted entirely when [key] is empty). Base URLs
/// that already end in `/v1beta` skip the version prefix.
Uri _geminiGenerateContentUri(ProviderConfig provider, String key) {
  final base = provider.baseUrl.endsWith('/v1beta')
      ? provider.baseUrl
      : '${provider.baseUrl}/v1beta';
  final uri = Uri.parse('$base/models/${provider.effectiveModel}:generateContent');
  if (key.isEmpty) return uri;
  return uri.replace(queryParameters: <String, String>{'key': key});
}

/// Parse a 200 response body according to [protocol]. Every malformed shape —
/// non-JSON bodies, missing fields, wrong types — fails with a reason instead
/// of throwing.
LlmResult _parseResponse(LlmProtocol protocol, http.Response response) {
  final Object? decoded;
  try {
    decoded = jsonDecode(response.body);
  } on FormatException {
    return LlmResult.fail('response is not valid JSON', response.statusCode);
  }
  if (decoded is! Map<String, Object?>) {
    return LlmResult.fail('response is not a JSON object', response.statusCode);
  }
  switch (protocol) {
    case LlmProtocol.openai:
      return _parseOpenAiResponse(decoded, response.statusCode);
    case LlmProtocol.claude:
      return _parseClaudeResponse(decoded, response.statusCode);
    case LlmProtocol.gemini:
      return _parseGeminiResponse(decoded, response.statusCode);
  }
}

/// Extract the assistant content from an OpenAI chat-completions response
/// (`choices[0].message.content`).
LlmResult _parseOpenAiResponse(Map<String, Object?> decoded, int statusCode) {
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty) {
    return LlmResult.fail('response has no choices', statusCode);
  }
  final firstChoice = choices[0];
  if (firstChoice is! Map<String, Object?>) {
    return LlmResult.fail('first choice is not an object', statusCode);
  }
  final message = firstChoice['message'];
  if (message is! Map<String, Object?>) {
    return LlmResult.fail('choice has no message', statusCode);
  }
  final content = message['content'];
  if (content is! String || content.isEmpty) {
    return LlmResult.fail('message content is empty', statusCode);
  }
  return LlmResult.ok(content, statusCode);
}

/// Extract the assistant text from an Anthropic Messages response: the first
/// `content` block whose `type` is `text`.
LlmResult _parseClaudeResponse(Map<String, Object?> decoded, int statusCode) {
  final blocks = decoded['content'];
  if (blocks is! List || blocks.isEmpty) {
    return LlmResult.fail('response has no content blocks', statusCode);
  }
  for (final block in blocks) {
    if (block is! Map<String, Object?>) continue;
    if (block['type'] != 'text') continue;
    final text = block['text'];
    if (text is String && text.isNotEmpty) {
      return LlmResult.ok(text, statusCode);
    }
  }
  return LlmResult.fail('response has no text content block', statusCode);
}

/// Extract the assistant text from a Gemini generateContent response
/// (`candidates[0].content.parts[0].text`).
LlmResult _parseGeminiResponse(Map<String, Object?> decoded, int statusCode) {
  final candidates = decoded['candidates'];
  if (candidates is! List || candidates.isEmpty) {
    return LlmResult.fail('response has no candidates', statusCode);
  }
  final firstCandidate = candidates[0];
  if (firstCandidate is! Map<String, Object?>) {
    return LlmResult.fail('first candidate is not an object', statusCode);
  }
  final content = firstCandidate['content'];
  if (content is! Map<String, Object?>) {
    return LlmResult.fail('candidate has no content', statusCode);
  }
  final parts = content['parts'];
  if (parts is! List || parts.isEmpty) {
    return LlmResult.fail('candidate content has no parts', statusCode);
  }
  final firstPart = parts[0];
  if (firstPart is! Map<String, Object?>) {
    return LlmResult.fail('first part is not an object', statusCode);
  }
  final text = firstPart['text'];
  if (text is! String || text.isEmpty) {
    return LlmResult.fail('part text is empty', statusCode);
  }
  return LlmResult.ok(text, statusCode);
}

String _truncate(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…';
