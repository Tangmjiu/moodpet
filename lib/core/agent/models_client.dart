/// Online model discovery for LLM providers.
///
/// Request construction dispatches on [ProviderConfig.protocol]:
///
///   - [LlmProtocol.openai] providers send `Authorization: Bearer <key>`;
///     the header is omitted when the key is empty (keyless custom providers
///     such as local servers).
///   - [LlmProtocol.claude] providers send `x-api-key` + `anthropic-version`
///     headers instead of a Bearer token; `x-api-key` is omitted when the
///     key is empty (keyless custom providers).
///   - [LlmProtocol.gemini] providers authenticate via a `?key=` query
///     parameter (merged into any existing query string) and send no auth
///     header.
///
/// Multi-key fields: [ProviderConfig.apiKey] may hold several keys separated
/// by commas or whitespace (see [splitApiKeys]); one key is picked at random
/// per call, mirroring the chat client's random pick (discovery has no retry
/// loop, so no untried-key tracking is needed).
///
/// Response parsing is protocol-agnostic: it accepts either the
/// `{ "data": [{ "id": "..." }] }` shape or the
/// `{ "models": [{ "name": "..." }] }` shape, stripping a leading `models/`
/// prefix from names.
///
/// Providers whose [ProviderConfig.modelsEndpoint] is `null` do not support
/// online discovery; the UI falls back to a free-text model field for those.
library;

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/provider_config.dart';
import 'llm_client.dart' show splitApiKeys;

/// The outcome of a model-list fetch.
class ModelsResult {
  /// Model ids discovered, sorted alphabetically. Empty when the call failed
  /// or returned no models.
  final List<String> models;

  /// HTTP status code (200 on success).
  final int statusCode;

  /// Error message when the call failed; `null` on success.
  final String? error;

  const ModelsResult.ok(this.models, this.statusCode) : error = null;
  const ModelsResult.fail(this.error, this.statusCode) : models = const <String>[];

  bool get isOk => error == null;
}

/// Fetch the list of available model ids for [provider].
///
/// Uses [provider.apiKey] for authentication and [provider.modelsEndpoint] as
/// the path appended to [provider.baseUrl]. When the key field holds several
/// keys, exactly one is picked at random and sent — the joined multi-key
/// string is never used as a credential. Returns [ModelsResult.fail] when
/// the provider has no compatible models endpoint, a built-in (non-custom)
/// provider has an empty key, or the request fails — the caller should fall
/// back to [ProviderConfig.defaultModel] or a free-text field in those cases.
/// Custom providers may fetch with an empty key (local servers often need no
/// auth).
///
/// [client] injects an HTTP client (used by tests); when omitted, an
/// ephemeral client is created and closed for the duration of the call.
Future<ModelsResult> fetchAvailableModels({
  required ProviderConfig provider,
  Duration timeout = const Duration(seconds: 15),
  http.Client? client,
}) async {
  final endpoint = provider.modelsEndpoint;
  if (endpoint == null) {
    return const ModelsResult.fail('此提供商不支持在线获取模型列表', 0);
  }
  final keys = splitApiKeys(provider.apiKey);
  if (keys.isEmpty && !provider.isCustom) {
    return const ModelsResult.fail('请先填写 API Key', 0);
  }
  // Pick one key per call, at random; empty means a keyless request.
  final key = keys.isEmpty ? '' : keys[Random().nextInt(keys.length)];

  final uri = _buildModelsUri(provider, endpoint, key);
  final headers = _authHeaders(provider, key);
  final httpClient = client ?? http.Client();

  try {
    final response = await httpClient.get(uri, headers: headers).timeout(timeout);
    if (response.statusCode != 200) {
      return ModelsResult.fail(
        'HTTP ${response.statusCode}: ${_truncate(response.body, 200)}',
        response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      return ModelsResult.fail('响应不是 JSON 对象', response.statusCode);
    }
    final ids = _extractModelIds(provider, decoded);
    if (ids.isEmpty) {
      return ModelsResult.fail('响应中没有可用的模型', response.statusCode);
    }
    ids.sort();
    return ModelsResult.ok(ids, response.statusCode);
  } catch (e) {
    return ModelsResult.fail('请求失败: $e', 0);
  } finally {
    // Close only clients this function created; an injected client is owned
    // by the caller.
    if (client == null) httpClient.close();
  }
}

/// Build the request URI. Gemini-protocol providers authenticate through a
/// `key` query parameter, which is merged into any query string already
/// present in the endpoint; other protocols use the plain URL. An empty
/// [key] means keyless: no query parameter is added.
Uri _buildModelsUri(ProviderConfig provider, String endpoint, String key) {
  final uri = Uri.parse('${provider.baseUrl}$endpoint');
  if (provider.protocol != LlmProtocol.gemini || key.isEmpty) {
    return uri;
  }
  return uri.replace(queryParameters: <String, String>{
    ...uri.queryParameters,
    'key': key,
  });
}

/// Build auth headers for the models request, per [ProviderConfig.protocol].
/// [key] is the single picked key for this call; an empty key means keyless.
Map<String, String> _authHeaders(ProviderConfig provider, String key) {
  switch (provider.protocol) {
    case LlmProtocol.claude:
      return <String, String>{
        // Keyless custom providers (e.g. local servers) send no credential.
        if (key.isNotEmpty) 'x-api-key': key,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      };
    case LlmProtocol.gemini:
      // Gemini-protocol providers authenticate via the `key` query
      // parameter, not a header.
      return <String, String>{'Content-Type': 'application/json'};
    case LlmProtocol.openai:
      // Keyless custom providers (e.g. local servers) send no auth header.
      if (key.isEmpty) return const <String, String>{};
      return <String, String>{
        'Authorization': 'Bearer $key',
      };
  }
}

/// Extract model ids from the decoded response body, handling the three
/// known response shapes (OpenAI `data[].id`, Cohere `models[].name`,
/// Gemini `models[].name` with `models/` prefix).
List<String> _extractModelIds(ProviderConfig provider, Map<String, Object?> body) {
  // OpenAI-compatible: { "data": [{ "id": "..." }] }
  final data = body['data'];
  if (data is List) {
    final ids = data
        .whereType<Map<String, Object?>>()
        .map((m) => m['id'])
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (ids.isNotEmpty) return ids;
  }
  // Cohere / Gemini: { "models": [{ "name": "..." }] }
  final models = body['models'];
  if (models is List) {
    return models
        .whereType<Map<String, Object?>>()
        .map((m) => m['name'] ?? m['id'])
        .whereType<String>()
        .map((name) => name.startsWith('models/') ? name.substring(7) : name)
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

String _truncate(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…';
