import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import 'models.dart';

export 'models.dart';

/// PocketClaw agent.
///
/// The framework follows a **local-decision + cloud-LLM** pattern:
/// 1. input is routed locally through registered tools (`@toolName args`);
/// 2. if no local tool claims the input, a cloud LLM call is dispatched using
///    the provider / auth strategy supplied at construction time.
///
/// ```dart
/// final agent = PocketClaw(
///   provider: 'deepseek',
///   apiKey: apiKey,
///   baseUrl: 'https://api.deepseek.com',
///   defaultModel: 'deepseek-chat',
///   tools: [],
///   systemPrompt: '...',
/// );
/// final response = await agent.chat('今天好累');
/// print(response.content);
/// ```
class PocketClaw {
  PocketClaw({
    required this.provider,
    required this.apiKey,
    this.baseUrl,
    this.defaultModel = 'default',
    this.systemPrompt,
    this.tools = const [],
    this.authType = PocketClawAuthType.bearer,
    this.authHeaderName,
    this.authQueryParam,
    this.secretKey,
    this.timeout = const Duration(seconds: 15),
    this.httpClient,
  })  : assert(apiKey.trim().isNotEmpty, 'apiKey must not be empty'),
        assert(baseUrl == null || baseUrl.trim().isNotEmpty,
            'baseUrl must not be empty when provided');

  final String provider;

  /// API key / bearer token. For ERNIE / Spark it is the "API Key" part and
  /// [secretKey] carries the companion secret.
  final String apiKey;

  /// Base endpoint, e.g. `https://api.deepseek.com`.
  final String? baseUrl;

  final String defaultModel;
  final String? systemPrompt;
  final List<PocketClawTool> tools;
  final PocketClawAuthType authType;
  final String? authHeaderName;
  final String? authQueryParam;
  final String? secretKey;
  final Duration timeout;

  /// Injectable client (tests / retries).
  final http.Client? httpClient;

  /// Sends one user turn to the cloud model and returns raw content +
  /// metadata. Throws [PocketClawException] on transport / provider errors.
  Future<AgentResponse> chat(String text, {String? model}) async {
    if (text.trim().isEmpty) {
      throw const PocketClawException(
        '输入不能为空',
        code: PocketClawVerifyCode.unknown,
      );
    }

    // ---- 1. local decision routing ----
    final local = await _runLocalTool(text);
    if (local != null) {
      return AgentResponse(
        content: local,
        metadata: {'local': true, 'tool': _matchedToolName(text)},
      );
    }

    // ---- 2. cloud LLM invocation ----
    final result = await _dispatch(text, model: model ?? defaultModel);
    return AgentResponse(
      content: result.content,
      metadata: {
        'provider': provider,
        'model': model ?? defaultModel,
        'local': false,
        'usage': result.usage,
      },
    );
  }

  /// Lightweight verification call. It performs a real request against the
  /// configured endpoint / model and maps HTTP-level outcomes to
  /// [PocketClawVerifyCode] so callers can render the seven MoodPet checks.
  Future<PocketClawVerifyResult> verify({String? model}) async {
    final effectiveModel = model ?? defaultModel;
    try {
      final result = await _dispatch(
        '你好，请回复：ok',
        model: effectiveModel,
        verification: true,
      );
      return PocketClawVerifyResult(
        ok: true,
        message: '连接成功',
        statusCode: result.statusCode,
      );
    } on PocketClawException catch (e) {
      return PocketClawVerifyResult(
        ok: false,
        message: e.message,
        code: e.code,
      );
    } catch (_) {
      return const PocketClawVerifyResult(
        ok: false,
        message: '连接失败',
        code: PocketClawVerifyCode.unknown,
      );
    }
  }

  // ---------------------------------------------------------------- local ----
  String? _matchedToolName(String text) {
    final trimmed = text.trim();
    for (final tool in tools) {
      if (trimmed == '@${tool.name}' ||
          trimmed.startsWith('@${tool.name} ')) {
        return tool.name;
      }
    }
    return null;
  }

  Future<String?> _runLocalTool(String text) async {
    final name = _matchedToolName(text);
    if (name == null) return null;
    final tool = tools.firstWhere((t) => t.name == name);
    if (tool.handler == null) {
      throw PocketClawException('工具 $name 未注册处理器');
    }
    final argsText = text.trim().substring(name.length + 1).trim();
    final args = argsText.isEmpty
        ? const <String, dynamic>{}
        : _safeDecodeMap(argsText);
    final value = await tool.handler!(args);
    return jsonEncode({'tool': name, 'result': value});
  }

  static Map<String, dynamic> _safeDecodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'value': decoded};
    } catch (_) {
      return {'value': raw};
    }
  }

  // ---------------------------------------------------------------- cloud ---
  Future<_RawResult> _dispatch(
    String text, {
    required String model,
    bool verification = false,
  }) async {
    final url = baseUrl?.trim();
    if (url == null || url.isEmpty) {
      throw const PocketClawException('未配置 Provider Endpoint');
    }

    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    try {
      final uri = Uri.parse(url);
      switch (_normalizeProvider()) {
        case 'claude':
        case 'anthropic':
          return await _callAnthropic(client, uri, text, model, verification);
        case 'gemini':
        case 'google':
          return await _callGemini(client, uri, text, model, verification);
        case 'cohere':
          return await _callCohere(client, uri, text, model, verification);
        case 'ernie':
          return await _callErnie(client, uri, text, model, verification);
        case 'spark':
          return await _callSpark(client, uri, text, model, verification);
        default:
          return await _callOpenAiCompatible(
              client, uri, text, model, verification);
      }
    } on PocketClawException {
      rethrow;
    } on TimeoutException {
      throw const PocketClawException(
        '连接超时，请稍后重试',
        code: PocketClawVerifyCode.timeout,
      );
    } on SocketException catch (e) {
      throw PocketClawException(
        '网络不可达：${e.message}',
        code: PocketClawVerifyCode.networkError,
      );
    } on http.ClientException catch (e) {
      throw PocketClawException(
        '网络不可达：${e.message}',
        code: PocketClawVerifyCode.networkError,
      );
    } finally {
      if (ownsClient) client.close();
    }
  }

  String _normalizeProvider() => provider.toLowerCase().trim();

  Future<http.Response> _send(
    http.Client client,
    Uri uri,
    Object? body,
    Map<String, String> headers,
  ) async {
    return client
        .post(uri, headers: headers, body: body == null ? null : jsonEncode(body))
        .timeout(timeout);
  }

  Map<String, String> _baseHeaders({String? contentType = 'application/json'}) {
    final headers = <String, String>{
      if (contentType != null) 'Content-Type': contentType,
      'Accept': 'application/json',
    };
    return headers;
  }

  void _applyAuth(Map<String, String> headers) {
    switch (authType) {
      case PocketClawAuthType.bearer:
        headers['Authorization'] = 'Bearer $apiKey';
        break;
      case PocketClawAuthType.apiKeyHeader:
        headers[authHeaderName ?? 'x-api-key'] = apiKey;
        break;
      case PocketClawAuthType.queryParam:
      case PocketClawAuthType.custom:
        // applied by provider-specific builders
        break;
    }
  }

  /// OpenAI-compatible `POST {base}/chat/completions` (DeepSeek, Kimi, GLM,
  /// MiniMax, Qwen, Hunyuan, Volcengine, OpenAI, Groq, Mistral, Perplexity).
  Future<_RawResult> _callOpenAiCompatible(
    http.Client client,
    Uri base,
    String text,
    String model,
    bool verification,
  ) async {
    var uri = _appendPath(base, '/chat/completions');
    if (authType == PocketClawAuthType.queryParam) {
      uri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        authQueryParam ?? 'key': apiKey,
      });
    }
    final headers = _baseHeaders();
    _applyAuth(headers);
    final body = <String, dynamic>{
      'model': model,
      'messages': [
        if (systemPrompt != null && systemPrompt!.trim().isNotEmpty)
          {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': text},
      ],
      'max_tokens': verification ? 8 : 1024,
      'temperature': verification ? 0 : 0.7,
      if (tools.isNotEmpty) 'tools': tools.map((t) => t.toJson()).toList(),
    };
    final response = await _send(client, uri, body, headers);
    return _parseOpenAiCompatible(response);
  }

  _RawResult _parseOpenAiCompatible(http.Response response) {
    final decoded = _decodeResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _classifyError(response.statusCode, decoded);
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw PocketClawException(
        '响应格式异常：缺少 choices',
        code: PocketClawVerifyCode.unknown,
      );
    }
    final first = choices.first;
    if (first is! Map) {
      throw PocketClawException(
        '响应格式异常：choices 结构错误',
        code: PocketClawVerifyCode.unknown,
      );
    }
    final message = first['message'];
    final content = message is Map ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw PocketClawException(
        '响应内容为空',
        code: PocketClawVerifyCode.unknown,
      );
    }
    return _RawResult(content.trim(), response.statusCode, decoded['usage']);
  }

  /// Anthropic Messages API.
  Future<_RawResult> _callAnthropic(
    http.Client client,
    Uri base,
    String text,
    String model,
    bool verification,
  ) async {
    final uri = _appendPath(base, '/messages');
    final headers = _baseHeaders()
      ..['x-api-key'] = apiKey
      ..['anthropic-version'] = '2023-06-01';
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': verification ? 8 : 1024,
      'messages': [
        {'role': 'user', 'content': text},
      ],
      if (systemPrompt != null && systemPrompt!.trim().isNotEmpty)
        'system': systemPrompt,
    };
    final response = await _send(client, uri, body, headers);
    final decoded = _decodeResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _classifyError(response.statusCode, decoded);
    }
    final content = decoded['content'];
    String out = '';
    if (content is List) {
      out = content
          .whereType<Map>()
          .map((block) => (block['text'] as String?) ?? '')
          .join();
    } else if (content is String) {
      out = content;
    }
    if (out.trim().isEmpty) {
      throw PocketClawException(
        '响应内容为空',
        code: PocketClawVerifyCode.unknown,
      );
    }
    return _RawResult(out.trim(), response.statusCode, decoded['usage']);
  }

  /// Google Gemini `POST {base}/models/{model}:generateContent?key=...`.
  Future<_RawResult> _callGemini(
    http.Client client,
    Uri base,
    String text,
    String model,
    bool verification,
  ) async {
    final path =
        '${_pathPrefix(base.path)}/models/$model:generateContent'.replaceAll(
            RegExp(r'/+'), '/');
    final uri = base.replace(
      path: path,
      queryParameters: {
        ...base.queryParameters,
        authQueryParam ?? 'key': apiKey,
      },
    );
    final body = <String, dynamic>{
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': text},
          ],
        },
      ],
      if (systemPrompt != null && systemPrompt!.trim().isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt},
          ],
        },
      'generationConfig': {
        'temperature': verification ? 0 : 0.7,
        'maxOutputTokens': verification ? 8 : 1024,
      },
    };
    final response = await _send(client, uri, body, _baseHeaders());
    final decoded = _decodeResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _classifyError(response.statusCode, decoded);
    }
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw PocketClawException(
        '响应格式异常：缺少 candidates',
        code: PocketClawVerifyCode.unknown,
      );
    }
    final content = (candidates.first as Map)['content'];
    final parts = content is Map ? content['parts'] : null;
    String out = '';
    if (parts is List) {
      out = parts.whereType<Map>().map((p) => (p['text'] as String?) ?? '').join();
    }
    if (out.trim().isEmpty) {
      throw PocketClawException(
        '响应内容为空',
        code: PocketClawVerifyCode.unknown,
      );
    }
    return _RawResult(
      out.trim(),
      response.statusCode,
      decoded['usageMetadata'],
    );
  }

  /// Cohere chat API (non OpenAI-compatible body).
  Future<_RawResult> _callCohere(
    http.Client client,
    Uri base,
    String text,
    String model,
    bool verification,
  ) async {
    final uri = _appendPath(base, '/chat');
    final headers = _baseHeaders()..['Authorization'] = 'Bearer $apiKey';
    final body = <String, dynamic>{
      'model': model,
      'message': text,
      'max_tokens': verification ? 8 : 1024,
      if (systemPrompt != null && systemPrompt!.trim().isNotEmpty)
        'preamble': systemPrompt,
    };
    final response = await _send(client, uri, body, headers);
    final decoded = _decodeResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _classifyError(response.statusCode, decoded);
    }
    final out = decoded['text'] as String?;
    if (out == null || out.trim().isEmpty) {
      throw PocketClawException(
        '响应内容为空',
        code: PocketClawVerifyCode.unknown,
      );
    }
    return _RawResult(out.trim(), response.statusCode, decoded['meta']);
  }

  /// Baidu ERNIE: first obtain an access_token (when a secret is supplied)
  /// then call the chat endpoint with `?access_token=...`.
  Future<_RawResult> _callErnie(
    http.Client client,
    Uri base,
    String text,
    String model,
    bool verification,
  ) async {
    var token = apiKey;
    if (secretKey != null && secretKey!.trim().isNotEmpty) {
      final tokenUri = Uri.parse('https://aip.baidubce.com/oauth/2.0/token')
          .replace(queryParameters: {
        'grant_type': 'client_credentials',
        'client_id': apiKey,
        'client_secret': secretKey,
      });
      final tokenResponse = await client.post(tokenUri).timeout(timeout);
      final tokenJson = _decodeResponse(tokenResponse);
      if (tokenResponse.statusCode != 200 || tokenJson['access_token'] is! String) {
        throw PocketClawException(
          'API Key 无效，请重新输入',
          code: PocketClawVerifyCode.authError,
        );
      }
      token = tokenJson['access_token'] as String;
    }

    final uri = base.replace(queryParameters: {
      ...base.queryParameters,
      'access_token': token,
    });
    final body = <String, dynamic>{
      'messages': [
        {'role': 'user', 'content': text},
      ],
      if (systemPrompt != null && systemPrompt!.trim().isNotEmpty)
        'system': systemPrompt,
      'max_output_tokens': verification ? 8 : 1024,
    };
    final response = await _send(client, uri, body, _baseHeaders());
    final decoded = _decodeResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _classifyError(response.statusCode, decoded);
    }
    final out = decoded['result'] as String?;
    if (out == null || out.trim().isEmpty) {
      throw PocketClawException(
        '响应内容为空',
        code: PocketClawVerifyCode.unknown,
      );
    }
    return _RawResult(out.trim(), response.statusCode, decoded['usage']);
  }

  /// iFlytek Spark: HMAC-SHA256 request signature.
  Future<_RawResult> _callSpark(
    http.Client client,
    Uri base,
    String text,
    String model,
    bool verification,
  ) async {
    if (secretKey == null || secretKey!.trim().isEmpty) {
      throw const PocketClawException(
        '讯飞星火需要 API Key + Secret Key（格式：APIKey:APISecret）',
        code: PocketClawVerifyCode.authError,
      );
    }
    final host = base.host;
    final path = base.path.isEmpty ? '/' : base.path;
    final date = _rfc1123Date(DateTime.now().toUtc());
    final requestLine = 'POST $path HTTP/1.1';
    final signatureOrigin = 'host: $host\ndate: $date\n$requestLine';
    final hmac = crypto.Hmac(crypto.sha256, utf8.encode(secretKey!));
    final signature = base64Encode(
      hmac.convert(utf8.encode(signatureOrigin)).bytes,
    );
    final authorization = 'api_key="$apiKey", algorithm="hmac-sha256", '
        'headers="host date request-line", signature="$signature"';

    final uri = base.replace(queryParameters: {
      ...base.queryParameters,
      'authorization': base64Encode(utf8.encode(authorization)),
      'date': date,
      'host': host,
    });
    final headers = _baseHeaders()..['Authorization'] = authorization;
    final body = <String, dynamic>{
      'header': {'app_id': apiKey, 'uid': 'moodpet'},
      'parameter': {
        'chat': {
          'domain': model,
          'temperature': verification ? 0 : 0.7,
          'max_tokens': verification ? 8 : 1024,
        },
      },
      'payload': {
        'message': {
          'text': [
            if (systemPrompt != null && systemPrompt!.trim().isNotEmpty)
              {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': text},
          ],
        },
      },
    };
    final response = await _send(client, uri, body, headers);
    final decoded = _decodeResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _classifyError(response.statusCode, decoded);
    }
    final header = decoded['header'];
    if (header is Map && header['code'] != null && header['code'] != 0) {
      throw PocketClawException(
        '星火接口错误：${header['message'] ?? header['code']}',
        code: PocketClawVerifyCode.authError,
      );
    }
    final payload = decoded['payload'];
    final choices = payload is Map ? payload['choices'] : null;
    if (choices is Map && choices['text'] is List) {
      final parts = (choices['text'] as List)
          .whereType<Map>()
          .map((m) => (m['content'] as String?) ?? '')
          .join();
      if (parts.trim().isNotEmpty) {
        return _RawResult(parts.trim(), response.statusCode, decoded['payload']);
      }
    }
    throw PocketClawException(
      '响应内容为空',
      code: PocketClawVerifyCode.unknown,
    );
  }

  // ------------------------------------------------------------- helpers ----
  static Uri _appendPath(Uri base, String suffix) {
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final suffixPath =
        suffix.startsWith('/') ? suffix.substring(1) : suffix;
    return base.replace(path: '$prefix/$suffixPath');
  }

  static String _pathPrefix(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.body.isEmpty) return const {};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  static PocketClawException _classifyError(
    int statusCode,
    Map<String, dynamic> decoded,
  ) {
    final raw = jsonEncode(decoded);
    final text = (decoded['error'] is Map
            ? (decoded['error'] as Map)['message']?.toString()
            : decoded['message']?.toString()) ??
        raw;
    if (statusCode == 401 || statusCode == 403) {
      return PocketClawException(
        'API Key 无效，请重新输入',
        code: PocketClawVerifyCode.authError,
      );
    }
    if (statusCode == 402 || text.contains('quota') || text.contains('balance')) {
      return PocketClawException(
        'API 余额不足，请充值',
        code: PocketClawVerifyCode.quotaError,
      );
    }
    if (statusCode == 404 ||
        text.contains('model') && text.contains('not')) {
      return PocketClawException(
        '所选模型无效，请更换',
        code: PocketClawVerifyCode.modelError,
      );
    }
    if (statusCode == 429) {
      return PocketClawException(
        '请求过于频繁或配额不足',
        code: PocketClawVerifyCode.quotaError,
      );
    }
    return PocketClawException(
      '接口错误 ($statusCode)：$text',
      code: PocketClawVerifyCode.unknown,
    );
  }

  static String _rfc1123Date(DateTime utc) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    String two(int n) => n.toString().padLeft(2, '0');
    return '${weekdays[utc.weekday - 1]}, ${two(utc.day)} '
        '${months[utc.month - 1]} ${utc.year} '
        '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} GMT';
  }
}

class _RawResult {
  const _RawResult(this.content, this.statusCode, this.usage);

  final String content;
  final int statusCode;
  final Object? usage;
}
