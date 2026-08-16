import '../models/region_info.dart';

/// 鉴权方式。
enum AuthType {
  /// 标准 Bearer Token。
  bearer,

  /// 自定义 Header（如 x-api-key）。
  apiKeyHeader,

  /// Query 参数（如 ?key=xxx）。
  queryParam,

  /// 特殊鉴权（文心一言 access_token、讯飞星火 HMAC 签名）。
  custom,
}

/// LLM 提供商完整配置。
class LLMProvider {
  const LLMProvider({
    required this.id,
    required this.name,
    required this.iconAsset,
    required this.officialEndpoint,
    required this.defaultModel,
    required this.authType,
    this.codingEndpoint,
    this.models = const [],
    this.codingModels,
    this.isRecommended = false,
    this.description,
    this.docsUrl,
    this.regions = const {AppRegion.prc},
    this.authHeaderName,
    this.authQueryParam,
    this.requiresSecretKey = false,
    this.modelHint,
  });

  final String id;
  final String name;
  final String iconAsset; // assets/icons/xxx.svg
  final String officialEndpoint;

  /// Coding Plan 专用 Endpoint（若有）。
  final String? codingEndpoint;

  final String defaultModel;

  /// 常规可选模型列表。
  final List<String> models;

  /// Coding Plan 专用模型列表。
  final List<String>? codingModels;

  final bool isRecommended;
  final String? description;
  final String? docsUrl;
  final AuthType authType;

  /// 该提供商出现于哪些地区分组（DeepSeek 同时出现在 PRC 与 OTHER）。
  final Set<AppRegion> regions;

  final String? authHeaderName;
  final String? authQueryParam;

  /// 特殊鉴权是否需要第二密钥（讯飞 / 文心）。
  final bool requiresSecretKey;

  /// 当模型需要用户自行填写时的提示（火山方舟为部署接入点 ID）。
  final String? modelHint;

  bool get hasCodingPlan =>
      codingEndpoint != null &&
      codingEndpoint!.trim().isNotEmpty &&
      (codingModels?.isNotEmpty ?? false);

  bool get requiresCustomModelId => defaultModel.trim().isEmpty;

  bool isAvailableIn(AppRegion region) => regions.contains(region);

  /// Coding Plan 开启时返回 codingModels；
  /// 未开启时返回常规模型（若没有 coding endpoint，则合并列出的全部模型）。
  List<String> modelsFor({required bool codingPlanEnabled}) {
    if (codingPlanEnabled && hasCodingPlan) {
      return List.unmodifiable(codingModels ?? const []);
    }
    if (hasCodingPlan) return List.unmodifiable(models);
    return List.unmodifiable({
      ...models,
      if (!requiresCustomModelId) defaultModel,
      ...?codingModels,
    }.where((m) => m.trim().isNotEmpty));
  }

  LLMProvider copyWith({
    bool? isRecommended,
  }) {
    return LLMProvider(
      id: id,
      name: name,
      iconAsset: iconAsset,
      officialEndpoint: officialEndpoint,
      codingEndpoint: codingEndpoint,
      defaultModel: defaultModel,
      models: models,
      codingModels: codingModels,
      isRecommended: isRecommended ?? this.isRecommended,
      description: description,
      docsUrl: docsUrl,
      authType: authType,
      regions: regions,
      authHeaderName: authHeaderName,
      authQueryParam: authQueryParam,
      requiresSecretKey: requiresSecretKey,
      modelHint: modelHint,
    );
  }

  @override
  String toString() => 'LLMProvider($id, $name)';
}

/// 全部 16 个真实可用的 LLM 提供商。
///
/// 说明：PRC 组 9 个 + OTHER 组 5 个新提供商 + DeepSeek（两组重复出现），
/// 去重后为 16 个。文档“17 个”应为按地区列表累加的口径。
const List<LLMProvider> kAllLLMProviders = [
  // ---------------------------------------------------------------- PRC ---
  LLMProvider(
    id: 'deepseek',
    name: 'DeepSeek',
    iconAsset: 'assets/icons/deepseek.svg',
    officialEndpoint: 'https://api.deepseek.com',
    codingEndpoint: 'https://api.deepseek.com',
    defaultModel: 'deepseek-chat',
    models: ['deepseek-chat'],
    codingModels: ['deepseek-coder'],
    isRecommended: true,
    description: '高性价比中文对话与代码模型',
    docsUrl: 'https://platform.deepseek.com/api-docs',
    authType: AuthType.bearer,
    regions: {AppRegion.prc, AppRegion.other},
  ),
  LLMProvider(
    id: 'kimi',
    name: 'Kimi (Moonshot)',
    iconAsset: 'assets/icons/kimi.svg',
    officialEndpoint: 'https://api.moonshot.cn/v1',
    codingEndpoint: 'https://api.kimi.com/coding/v1',
    defaultModel: 'moonshot-v1-8k',
    models: ['moonshot-v1-8k'],
    codingModels: ['kimi-for-coding'],
    isRecommended: true,
    description: '长文本理解与 Coding Plan',
    docsUrl: 'https://platform.kimi.com',
    authType: AuthType.bearer,
    regions: {AppRegion.prc},
  ),
  LLMProvider(
    id: 'glm',
    name: 'GLM (智谱)',
    iconAsset: 'assets/icons/glm.svg',
    officialEndpoint: 'https://open.bigmodel.cn/api/paas/v4',
    codingEndpoint: 'https://open.bigmodel.cn/api/coding/paas/v4',
    defaultModel: 'glm-4-flash',
    models: ['glm-4-flash'],
    codingModels: ['glm-4-plus'],
    isRecommended: true,
    description: '智谱 AI 开放平台',
    docsUrl: 'https://docs.bigmodel.cn/cn/coding-plan/quick-start',
    authType: AuthType.bearer,
    regions: {AppRegion.prc},
  ),
  LLMProvider(
    id: 'minimax',
    name: 'MiniMax',
    iconAsset: 'assets/icons/minimax.svg',
    officialEndpoint: 'https://api.minimaxi.com/v1',
    codingEndpoint: 'https://api.minimaxi.com/v1',
    defaultModel: 'abab6.5s-chat',
    models: ['abab6.5s-chat'],
    codingModels: ['abab6.5s-coding'],
    isRecommended: true,
    description: '国内端点（国际：api.minimax.chat/v1）',
    docsUrl: 'https://docs.minimaxi.com',
    authType: AuthType.bearer,
    regions: {AppRegion.prc},
  ),
  LLMProvider(
    id: 'qwen',
    name: '通义千问 (Qwen)',
    iconAsset: 'assets/icons/qwen.svg',
    officialEndpoint: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    codingEndpoint: 'https://coding.dashscope.aliyuncs.com/v1',
    defaultModel: 'qwen-turbo',
    models: ['qwen-turbo'],
    codingModels: ['qwen-coder-turbo'],
    description: '阿里云百炼 OpenAI 兼容模式',
    docsUrl: 'https://help.aliyun.com/zh/model-studio/',
    authType: AuthType.bearer,
    regions: {AppRegion.prc},
  ),
  LLMProvider(
    id: 'ernie',
    name: '文心一言 (ERNIE)',
    iconAsset: 'assets/icons/ernie.svg',
    officialEndpoint:
        'https://aip.baidubce.com/rpc/2.0/ai_custom/v1/wenxinworkshop/chat',
    defaultModel: 'ernie-3.5-8k',
    models: ['ernie-3.5-8k', 'ernie-coder'],
    description: '百度智能云千帆（API Key:Secret Key）',
    docsUrl: 'https://cloud.baidu.com/doc/WENXINWORKSHOP/index.html',
    authType: AuthType.custom,
    requiresSecretKey: true,
    regions: {AppRegion.prc},
  ),
  LLMProvider(
    id: 'hunyuan',
    name: '腾讯混元 (Hunyuan)',
    iconAsset: 'assets/icons/hunyuan.svg',
    officialEndpoint: 'https://api.hunyuan.cloud.tencent.com/v1',
    defaultModel: 'hunyuan-lite',
    models: ['hunyuan-lite', 'hunyuan-code'],
    description: '腾讯混元大模型 API',
    docsUrl: 'https://cloud.tencent.com/document/product/1729',
    authType: AuthType.bearer,
    regions: {AppRegion.prc},
  ),
  LLMProvider(
    id: 'spark',
    name: '讯飞星火 (Spark)',
    iconAsset: 'assets/icons/spark.svg',
    officialEndpoint: 'https://spark-api.cn-huabei-1.xf-yun.com/v2.1/chat',
    defaultModel: 'generalv2',
    models: ['generalv2', 'generalv3'],
    description: 'HTTP 直连，需 API Key:APISecret',
    docsUrl: 'https://www.xfyun.cn/doc/spark/Web.html',
    authType: AuthType.custom,
    requiresSecretKey: true,
    regions: {AppRegion.prc},
  ),
  LLMProvider(
    id: 'volcengine',
    name: '火山方舟 (Volcengine)',
    iconAsset: 'assets/icons/volcengine.svg',
    officialEndpoint: 'https://ark.cn-beijing.volces.com/api/v3',
    codingEndpoint: 'https://ark.cn-beijing.volces.com/api/coding/v3',
    defaultModel: '',
    models: [],
    codingModels: [],
    description: 'OpenAI 兼容；模型为用户部署的接入点 ID',
    docsUrl: 'https://www.volcengine.com/docs/82379',
    authType: AuthType.bearer,
    regions: {AppRegion.prc},
    modelHint: '填写方舟控制台部署的推理接入点 ID（ep-xxx）',
  ),
  // -------------------------------------------------------------- OTHER ---
  LLMProvider(
    id: 'openai',
    name: 'OpenAI (GPT)',
    iconAsset: 'assets/icons/openai.svg',
    officialEndpoint: 'https://api.openai.com/v1',
    defaultModel: 'gpt-4o-mini',
    models: ['gpt-4o-mini', 'gpt-4o'],
    isRecommended: true,
    description: 'GPT 系列旗舰模型',
    docsUrl: 'https://platform.openai.com/docs',
    authType: AuthType.bearer,
    regions: {AppRegion.other},
  ),
  LLMProvider(
    id: 'claude',
    name: 'Claude (Anthropic)',
    iconAsset: 'assets/icons/claude.svg',
    officialEndpoint: 'https://api.anthropic.com/v1',
    defaultModel: 'claude-3-5-haiku-latest',
    models: ['claude-3-5-haiku-latest', 'claude-3-5-sonnet-latest'],
    isRecommended: true,
    description: 'Anthropic Messages API',
    docsUrl: 'https://docs.anthropic.com',
    authType: AuthType.apiKeyHeader,
    authHeaderName: 'x-api-key',
    regions: {AppRegion.other},
  ),
  LLMProvider(
    id: 'gemini',
    name: 'Google Gemini',
    iconAsset: 'assets/icons/gemini.svg',
    officialEndpoint: 'https://generativelanguage.googleapis.com/v1beta',
    defaultModel: 'gemini-1.5-flash',
    models: ['gemini-1.5-flash', 'gemini-2.0-flash'],
    description: 'Google Generative Language API',
    docsUrl: 'https://ai.google.dev/gemini-api/docs',
    authType: AuthType.queryParam,
    authQueryParam: 'key',
    regions: {AppRegion.other},
  ),
  LLMProvider(
    id: 'groq',
    name: 'Groq',
    iconAsset: 'assets/icons/groq.svg',
    officialEndpoint: 'https://api.groq.com/openai/v1',
    defaultModel: 'llama-3.1-8b-instant',
    models: ['llama-3.1-8b-instant', 'deepseek-r1-distill-llama-70b'],
    description: '超低延迟推理',
    docsUrl: 'https://console.groq.com/docs',
    authType: AuthType.bearer,
    regions: {AppRegion.other},
  ),
  LLMProvider(
    id: 'cohere',
    name: 'Cohere',
    iconAsset: 'assets/icons/cohere.svg',
    officialEndpoint: 'https://api.cohere.com/v1',
    defaultModel: 'command-r-plus',
    models: ['command-r-plus', 'command-r'],
    description: '企业级 RAG 与对话模型',
    docsUrl: 'https://docs.cohere.com',
    authType: AuthType.bearer,
    regions: {AppRegion.other},
  ),
  LLMProvider(
    id: 'mistral',
    name: 'Mistral AI',
    iconAsset: 'assets/icons/mistral.svg',
    officialEndpoint: 'https://api.mistral.ai/v1',
    defaultModel: 'mistral-small-latest',
    models: ['mistral-small-latest', 'codestral-latest'],
    description: '欧洲开源模型领军者',
    docsUrl: 'https://docs.mistral.ai',
    authType: AuthType.bearer,
    regions: {AppRegion.other},
  ),
  LLMProvider(
    id: 'perplexity',
    name: 'Perplexity',
    iconAsset: 'assets/icons/perplexity.svg',
    officialEndpoint: 'https://api.perplexity.ai',
    defaultModel: 'sonar-small-chat',
    models: ['sonar-small-chat', 'sonar-pro'],
    description: '在线搜索增强模型',
    docsUrl: 'https://docs.perplexity.ai',
    authType: AuthType.bearer,
    regions: {AppRegion.other},
  ),
];

/// 按地区返回全部可用提供商（保持文档顺序）。
List<LLMProvider> llmProvidersForRegion(AppRegion region) =>
    kAllLLMProviders.where((p) => p.isAvailableIn(region)).toList();

/// 按地区返回推荐提供商。
List<LLMProvider> recommendedProvidersForRegion(AppRegion region) =>
    llmProvidersForRegion(region).where((p) => p.isRecommended).toList();

/// 按地区返回默认折叠的备选提供商。
List<LLMProvider> backupProvidersForRegion(AppRegion region) =>
    llmProvidersForRegion(region).where((p) => !p.isRecommended).toList();

LLMProvider? llmProviderById(String? id) {
  if (id == null) return null;
  for (final provider in kAllLLMProviders) {
    if (provider.id == id) return provider;
  }
  return null;
}
