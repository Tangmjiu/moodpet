/// LLM provider configuration (§5.2 Step 3 / §12 step 5).
///
/// A [ProviderConfig] describes one LLM provider the user can select during
/// onboarding (Step 3) or in settings. The container ships a built-in catalog
/// of well-known providers keyed by [id]; the user picks one, fills in their
/// API key, and may override the default model / base URL. The active provider
/// is persisted and read by the PocketClaw agent (§10) to make LLM calls.
library;

/// The wire protocol a provider speaks.
///
/// The built-in catalog is OpenAI-compatible by default; some providers use
/// their own request/response contract and must be handled by a dedicated
/// code path in the agent.
enum LlmProtocol {
  /// OpenAI-compatible chat-completions contract (the default).
  openai,

  /// Anthropic Messages API contract.
  claude,

  /// Google Gemini generate-content contract.
  gemini;

  /// Stable string used when persisting this protocol to JSON.
  String get jsonValue => switch (this) {
        LlmProtocol.openai => 'openai',
        LlmProtocol.claude => 'claude',
        LlmProtocol.gemini => 'gemini',
      };

  /// Parse a persisted protocol string. Unknown or missing values fall back
  /// to [LlmProtocol.openai] so older or hand-edited configs keep loading.
  static LlmProtocol fromJsonValue(String? v) {
    for (final protocol in LlmProtocol.values) {
      if (protocol.jsonValue == v) return protocol;
    }
    return LlmProtocol.openai;
  }
}

/// One user-configurable LLM provider entry.
///
/// Immutable. The [apiKey] is persisted in SharedPreferences (plain text on
/// disk; a move to encrypted storage is a pending product decision) and only
/// loaded into a [ProviderConfig] at runtime — it is never serialised into
/// the customs JSON or the share payloads.
class ProviderConfig {
  /// Stable provider id, e.g. `openai`, `deepseek`, `glm`, `kimi`.
  final String id;

  /// Display name shown in onboarding/settings UI.
  final String name;

  /// Default chat-completions base URL (no trailing slash). The agent appends
  /// `/chat/completions` (or the provider-specific path) at call time.
  final String baseUrl;

  /// Default model id, e.g. `gpt-4o-mini`, `deepseek-chat`.
  final String defaultModel;

  /// The user's API key for this provider. May be empty when not yet configured.
  final String apiKey;

  /// Whether this provider is recommended for the detected region.
  final bool recommended;

  /// Optional override model chosen by the user in advanced settings.
  final String? modelOverride;

  /// Asset path to the provider's SVG logo (e.g.
  /// `assets/icons/providers/openai.svg`). Rendered via `flutter_svg`.
  final String iconAsset;

  /// Brand accent colour (`#RRGGBB`) for the provider — used as the fallback
  /// tint behind the logo and as the CircleAvatar background when the SVG is
  /// not yet loaded. Parsed to [Color] by the UI layer.
  final String brandColor;

  /// Path appended to [baseUrl] for listing available models, when the
  /// provider exposes an OpenAI-compatible `GET /models` endpoint. `null`
  /// means the provider has no compatible models-listing endpoint and the UI
  /// must fall back to a free-text model field.
  final String? modelsEndpoint;

  /// The wire protocol this provider speaks. Built-in providers are
  /// OpenAI-compatible unless declared otherwise; custom providers default to
  /// [LlmProtocol.openai].
  final LlmProtocol protocol;

  /// Whether this entry was added by the user (custom endpoint) rather than
  /// coming from the built-in catalog. Custom entries are configured once
  /// they have a [baseUrl]; they do not require an [apiKey].
  final bool isCustom;

  /// Path appended to [baseUrl] for chat completions calls. Defaults to the
  /// OpenAI-style `/chat/completions`; custom providers may override it.
  final String chatCompletionsPath;

  /// Whether this provider is currently active in the UI. Runtime-only state:
  /// never persisted by [toJson].
  final bool enabled;

  const ProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
    required this.apiKey,
    required this.iconAsset,
    required this.brandColor,
    this.modelsEndpoint = '/models',
    this.recommended = false,
    this.modelOverride,
    this.protocol = LlmProtocol.openai,
    this.isCustom = false,
    this.chatCompletionsPath = '/chat/completions',
    this.enabled = true,
  });

  /// The model id the agent should actually use — [modelOverride] if set,
  /// else [defaultModel].
  String get effectiveModel => modelOverride ?? defaultModel;

  /// Whether the provider is ready to make LLM calls. Built-in providers need
  /// a non-empty [apiKey]; custom providers only need a [baseUrl] (a key may
  /// still be sent when present).
  bool get isConfigured => isCustom ? baseUrl.isNotEmpty : apiKey.isNotEmpty;

  /// Whether this provider supports online model discovery via [modelsEndpoint].
  bool get supportsModelDiscovery => modelsEndpoint != null;

  /// Persisted form of this provider.
  ///
  /// Only durable, non-secret fields are written: [id], [name], [baseUrl],
  /// [defaultModel], [protocol], [modelsEndpoint], [chatCompletionsPath] and
  /// [isCustom]. The [apiKey], [modelOverride], [recommended], [iconAsset],
  /// [brandColor] and [enabled] are runtime/secret or derivable and are never
  /// serialised.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'defaultModel': defaultModel,
        'protocol': protocol.jsonValue,
        'modelsEndpoint': modelsEndpoint,
        'chatCompletionsPath': chatCompletionsPath,
        'isCustom': isCustom,
      };

  /// Restore a provider persisted by [toJson].
  ///
  /// Missing optional keys fall back to their defaults; unknown protocol
  /// strings fall back to [LlmProtocol.openai]. Secret/runtime-only fields
  /// are not persisted, so they come back as safe defaults ([apiKey] empty,
  /// [recommended] false, [enabled] true). A value present with the wrong
  /// type throws a [FormatException].
  factory ProviderConfig.fromJson(Map<String, Object?> json) => ProviderConfig(
        id: _requiredString(json, 'id'),
        name: _requiredString(json, 'name'),
        baseUrl: _requiredString(json, 'baseUrl'),
        defaultModel: _requiredString(json, 'defaultModel'),
        apiKey: '',
        iconAsset: '',
        brandColor: '',
        modelsEndpoint: _optionalString(json, 'modelsEndpoint'),
        protocol: LlmProtocol.fromJsonValue(
          _optionalString(json, 'protocol'),
        ),
        chatCompletionsPath:
            _optionalString(json, 'chatCompletionsPath') ?? '/chat/completions',
        isCustom: _optionalBool(json, 'isCustom') ?? false,
      );

  /// Read a mandatory string [key] from [json]; throws [FormatException] when
  /// missing or not a string.
  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is String) return value;
    throw FormatException('ProviderConfig.$key must be a String', json);
  }

  /// Read an optional string [key] from [json]; `null`/missing stays `null`,
  /// a non-string value throws [FormatException].
  static String? _optionalString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    throw FormatException('ProviderConfig.$key must be a String?', json);
  }

  /// Read an optional bool [key] from [json]; `null`/missing stays `null`,
  /// a non-bool value throws [FormatException].
  static bool? _optionalBool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is bool) return value;
    throw FormatException('ProviderConfig.$key must be a bool?', json);
  }

  /// Copy with updated fields. Used by settings UI edits.
  ProviderConfig copyWith({
    String? apiKey,
    String? modelOverride,
    bool? recommended,
    LlmProtocol? protocol,
    String? chatCompletionsPath,
    bool? enabled,
  }) =>
      ProviderConfig(
        id: id,
        name: name,
        baseUrl: baseUrl,
        defaultModel: defaultModel,
        apiKey: apiKey ?? this.apiKey,
        iconAsset: iconAsset,
        brandColor: brandColor,
        modelsEndpoint: modelsEndpoint,
        recommended: recommended ?? this.recommended,
        modelOverride: modelOverride ?? this.modelOverride,
        protocol: protocol ?? this.protocol,
        isCustom: isCustom,
        chatCompletionsPath: chatCompletionsPath ?? this.chatCompletionsPath,
        enabled: enabled ?? this.enabled,
      );

  @override
  bool operator ==(Object other) =>
      other is ProviderConfig &&
      other.id == id &&
      other.name == name &&
      other.baseUrl == baseUrl &&
      other.defaultModel == defaultModel &&
      other.apiKey == apiKey &&
      other.modelOverride == modelOverride &&
      other.recommended == recommended &&
      other.protocol == protocol &&
      other.isCustom == isCustom &&
      other.modelsEndpoint == modelsEndpoint &&
      other.iconAsset == iconAsset &&
      other.brandColor == brandColor &&
      other.chatCompletionsPath == chatCompletionsPath &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        baseUrl,
        defaultModel,
        apiKey,
        modelOverride,
        recommended,
        protocol,
        isCustom,
        modelsEndpoint,
        iconAsset,
        brandColor,
        chatCompletionsPath,
        enabled,
      );
}

/// The built-in provider catalog (§5.2 Step 3 — "自动检测地区推荐提供商").
///
/// These are the well-known OpenAI-compatible endpoints the container knows
/// about out of the box. Community Application plugins may register additional
/// providers or override LLM calling entirely (§11).
const List<ProviderConfig> kBuiltinProviders = <ProviderConfig>[
  ProviderConfig(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com',
    defaultModel: 'gpt-4o-mini',
    apiKey: '',
    iconAsset: 'assets/icons/providers/openai.svg',
    brandColor: '#10A37F',
    modelsEndpoint: '/v1/models',
  ),
  ProviderConfig(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    defaultModel: 'deepseek-chat',
    apiKey: '',
    iconAsset: 'assets/icons/providers/deepseek.svg',
    brandColor: '#5786FE',
    modelsEndpoint: '/models',
  ),
  ProviderConfig(
    id: 'glm',
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    defaultModel: 'glm-4-flash',
    apiKey: '',
    iconAsset: 'assets/icons/providers/glm.svg',
    brandColor: '#4D6BFE',
    modelsEndpoint: '/models',
  ),
  ProviderConfig(
    id: 'kimi',
    name: 'Moonshot Kimi',
    baseUrl: 'https://api.moonshot.cn',
    defaultModel: 'moonshot-v1-8k',
    apiKey: '',
    iconAsset: 'assets/icons/providers/kimi.svg',
    brandColor: '#000000',
    modelsEndpoint: '/v1/models',
  ),
  ProviderConfig(
    id: 'qwen',
    name: '通义千问',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultModel: 'qwen-turbo',
    apiKey: '',
    iconAsset: 'assets/icons/providers/qwen.svg',
    brandColor: '#6950EF',
    modelsEndpoint: '/models',
  ),
  ProviderConfig(
    id: 'spark',
    name: '讯飞星火',
    baseUrl: 'https://spark-api-open.xf-yun.com',
    defaultModel: 'generalv3.5',
    apiKey: '',
    iconAsset: 'assets/icons/providers/spark.svg',
    brandColor: '#0098E5',
    // iFlyTek Spark OpenAPI has no OpenAI-compatible /models listing.
    modelsEndpoint: null,
  ),
  ProviderConfig(
    id: 'hunyuan',
    name: '腾讯混元',
    baseUrl: 'https://api.hunyuan.cloud.tencent.com',
    defaultModel: 'hunyuan-lite',
    apiKey: '',
    iconAsset: 'assets/icons/providers/hunyuan.svg',
    brandColor: '#0052D9',
    modelsEndpoint: '/v1/models',
  ),
  ProviderConfig(
    id: 'ernie',
    name: '百度文心',
    baseUrl: 'https://qianfan.baidubce.com',
    defaultModel: 'ernie-speed-128k',
    apiKey: '',
    iconAsset: 'assets/icons/providers/ernie.svg',
    brandColor: '#2932E1',
    // Qianfan uses its own /v2/models contract; not OpenAI-compatible.
    modelsEndpoint: null,
  ),
  ProviderConfig(
    id: 'minimax',
    name: 'MiniMax',
    baseUrl: 'https://api.minimax.chat',
    defaultModel: 'abab6.5s-chat',
    apiKey: '',
    iconAsset: 'assets/icons/providers/minimax.svg',
    brandColor: '#E73562',
    modelsEndpoint: '/v1/models',
  ),
  ProviderConfig(
    id: 'volcengine',
    name: '火山引擎',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    defaultModel: 'doubao-lite-4k',
    apiKey: '',
    iconAsset: 'assets/icons/providers/volcengine.svg',
    brandColor: '#3C8CFF',
    modelsEndpoint: '/models',
  ),
  ProviderConfig(
    id: 'mistral',
    name: 'Mistral',
    baseUrl: 'https://api.mistral.ai',
    defaultModel: 'mistral-small-latest',
    apiKey: '',
    iconAsset: 'assets/icons/providers/mistral.svg',
    brandColor: '#FA520F',
    modelsEndpoint: '/v1/models',
  ),
  ProviderConfig(
    id: 'groq',
    name: 'Groq',
    baseUrl: 'https://api.groq.com/openai',
    defaultModel: 'llama-3.1-8b-instant',
    apiKey: '',
    iconAsset: 'assets/icons/providers/groq.svg',
    brandColor: '#F55036',
    modelsEndpoint: '/v1/models',
  ),
  ProviderConfig(
    id: 'claude',
    name: 'Anthropic Claude',
    baseUrl: 'https://api.anthropic.com',
    defaultModel: 'claude-3-5-haiku-latest',
    apiKey: '',
    iconAsset: 'assets/icons/providers/claude.svg',
    brandColor: '#D97757',
    // Anthropic exposes models via /v1/models but uses a custom auth header
    // (x-api-key + anthropic-version); the models client handles this.
    modelsEndpoint: '/v1/models',
    protocol: LlmProtocol.claude,
  ),
  ProviderConfig(
    id: 'gemini',
    name: 'Google Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com',
    defaultModel: 'gemini-1.5-flash',
    apiKey: '',
    iconAsset: 'assets/icons/providers/gemini.svg',
    brandColor: '#8E75B2',
    // Gemini lists models via /v1beta/models?key=... (query-param auth, custom
    // response shape). The models client handles this; not OpenAI-compatible.
    modelsEndpoint: '/v1beta/models',
    protocol: LlmProtocol.gemini,
  ),
  ProviderConfig(
    id: 'cohere',
    name: 'Cohere',
    baseUrl: 'https://api.cohere.com',
    defaultModel: 'command-r-plus',
    apiKey: '',
    iconAsset: 'assets/icons/providers/cohere.svg',
    brandColor: '#39594D',
    // Cohere uses /v1/models with Bearer auth but a non-OpenAI response shape;
    // the models client handles the `models[]` array extraction.
    modelsEndpoint: '/v1/models',
  ),
  ProviderConfig(
    id: 'perplexity',
    name: 'Perplexity',
    baseUrl: 'https://api.perplexity.ai',
    defaultModel: 'llama-3.1-sonar-small-128k-online',
    apiKey: '',
    iconAsset: 'assets/icons/providers/perplexity.svg',
    brandColor: '#1FB8CD',
    modelsEndpoint: '/models',
  ),
];

/// Provider ids recommended for users in China (lower-cost, no-VPN access).
const Set<String> kChinaRecommendedProviderIds = <String>{
  'deepseek',
  'glm',
  'kimi',
  'qwen',
  'spark',
  'hunyuan',
  'ernie',
  'minimax',
  'volcengine',
};

/// Provider ids recommended for users outside China.
const Set<String> kGlobalRecommendedProviderIds = <String>{
  'openai',
  'claude',
  'gemini',
  'mistral',
  'groq',
  'cohere',
  'perplexity',
};

/// Look up a built-in provider template by id (no API key).
ProviderConfig? builtinProviderById(String id) {
  for (final p in kBuiltinProviders) {
    if (p.id == id) return p;
  }
  return null;
}
