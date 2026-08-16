import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pocketclaw/pocketclaw.dart';

import '../llm/auth_config.dart';
import '../llm/llm_provider.dart';
import '../models/emotion.dart';
import 'emotion_rules.dart';

/// 一次情绪分析结果（含是否走了本地兜底）。
class AgentAnalysis {
  const AgentAnalysis({
    required this.emotion,
    required this.ruleName,
    required this.isLocal,
    this.rawContent,
    this.note,
  });

  final Emotion emotion;
  final String ruleName;
  final bool isLocal;
  final String? rawContent;
  final String? note;
}

/// PocketClaw 封装：初始化、系统提示词、chat 调用、JSON 提取、本地兜底。
class AgentService {
  AgentService({required this.agent, required this.providerId});

  final PocketClaw agent;
  final String providerId;

  /// System Prompt：强制 LLM 返回结构化 JSON。
  static const String systemPrompt = '''
你是 MoodPet，一个情绪精灵。
用户会对你说一句话，请分析情绪并返回 JSON：
{"emoji":"😊","color":"#FFD93D","vibration":[100,80,100,80,100],"suggestion":"简短建议"}
可选 emoji: 😊😢😩😤🤩😌🤔😨🤗😐
color 为 6 位色值（带 #）
vibration 为毫秒数组
suggestion 不超过 10 个字
''';

  /// 按用户配置构建 PocketClaw。
  static PocketClaw build({
    required LLMProvider provider,
    required String apiKey,
    required String model,
    required bool codingPlanEnabled,
    String? systemPromptOverride,
  }) {
    final auth = AuthConfig.of(provider);
    final parts = auth.requiresSecretKey
        ? AuthKeyParts.parse(apiKey)
        : AuthKeyParts(apiKey);
    final baseUrl = codingPlanEnabled
        ? (provider.codingEndpoint ?? provider.officialEndpoint)
        : provider.officialEndpoint;

    return PocketClaw(
      provider: provider.id,
      apiKey: parts.apiKey,
      secretKey: parts.secretKey,
      baseUrl: baseUrl,
      defaultModel: model.isEmpty ? provider.defaultModel : model,
      systemPrompt: systemPromptOverride ?? systemPrompt,
      authType: auth.pocketClawType,
      authHeaderName: auth.headerName,
      authQueryParam: auth.queryParam,
      tools: [
        // 可注册自定义工具（如设置闹钟、发消息等）。这里先不注册，保留扩展性。
      ],
    );
  }

  /// 处理用户输入：PocketClaw 云端分析 → 结构化 JSON → 失败走本地规则。
  Future<AgentAnalysis> analyze(String text) async {
    if (text.trim().isEmpty) {
      final local = resolveLocalEmotion('开心');
      return AgentAnalysis(
        emotion: local.emotion,
        ruleName: local.name,
        isLocal: true,
        note: '输入为空，使用默认情绪',
      );
    }
    try {
      final content = await _chatWithRetry(text);
      final emotion = _extractEmotion(content);
      if (emotion != null) {
        return AgentAnalysis(
          emotion: emotion,
          ruleName: _ruleNameFor(emotion),
          isLocal: false,
          rawContent: content,
        );
      }
      final local = resolveLocalEmotion(text);
      return AgentAnalysis(
        emotion: local.emotion,
        ruleName: local.name,
        isLocal: true,
        rawContent: content,
        note: '云端返回无法解析，已使用本地规则',
      );
    } on PocketClawException catch (e) {
      final local = resolveLocalEmotion(text);
      return AgentAnalysis(
        emotion: local.emotion,
        ruleName: local.name,
        isLocal: true,
        note: '云端调用失败（${e.message}），已使用本地规则',
      );
    } catch (e) {
      final local = resolveLocalEmotion(text);
      return AgentAnalysis(
        emotion: local.emotion,
        ruleName: local.name,
        isLocal: true,
        note: '发生异常（$e），已使用本地规则',
      );
    }
  }

  Future<String> _chatWithRetry(String text) async {
    try {
      final response = await agent.chat(text);
      return response.content;
    } on PocketClawException catch (e) {
      if (e.code == PocketClawVerifyCode.timeout) {
        // 自动重试 1 次
        await Future<void>.delayed(const Duration(milliseconds: 600));
        final response = await agent.chat(text);
        return response.content;
      }
      rethrow;
    }
  }

  /// 从模型输出中提取并校验 Emotion JSON。
  static Emotion? _extractEmotion(String content) {
    var raw = content.trim();
    if (raw.isEmpty) return null;
    // 去掉 markdown 代码围栏
    raw = raw.replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
    raw = raw.replaceFirst(RegExp(r'\s*```$'), '');
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is! Map<String, dynamic>) return null;
      final emoji = decoded['emoji'];
      final color = decoded['color'];
      final vibration = decoded['vibration'];
      if (emoji is! String || emoji.trim().isEmpty) return null;
      if (color is! String ||
          !RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(color.trim())) {
        return null;
      }
      final List<int> pattern;
      if (vibration is List) {
        pattern = vibration
            .whereType<num>()
            .map((n) => n.toInt().clamp(20, 1000))
            .toList();
        if (pattern.isEmpty) return null;
      } else {
        return null;
      }
      final suggestion = decoded['suggestion'] as String?;
      final normalized = suggestion?.trim();
      return Emotion(
        emoji: emoji.trim().substring(0, 4),
        colorHex: color.trim().startsWith('#')
            ? color.trim()
            : '#${color.trim()}',
        vibration: pattern,
        suggestion: normalized == null || normalized.isEmpty
            ? null
            : String.fromCharCodes(normalized.runes.take(10)),
      );
    } catch (_) {
      return null;
    }
  }

  String _ruleNameFor(Emotion emotion) {
    for (final rule in kLocalEmotionRules) {
      if (rule.emotion.emoji == emotion.emoji) return rule.name;
    }
    return '云端情绪';
  }
}

/// 测试连接校验结果。
class ConnectionTestResult {
  const ConnectionTestResult({
    required this.ok,
    required this.message,
    this.checkedAt,
  });

  final bool ok;
  final String message;
  final DateTime? checkedAt;

  static ConnectionTestResult success() => ConnectionTestResult(
        ok: true,
        message: '连接成功，模型可用',
        checkedAt: DateTime.now(),
      );
}

/// 测试连接：完整覆盖文档要求的 7 项校验。
class AgentConnectionTester {
  AgentConnectionTester({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<ConnectionTestResult> test({
    required LLMProvider provider,
    required String apiKey,
    required String model,
    required bool codingPlanEnabled,
  }) async {
    // 1. 网络连通性
    final connectivity = await _connectivity.checkConnectivity();
    if (connectivity.every((item) => item == ConnectivityResult.none)) {
      return const ConnectionTestResult(
        ok: false,
        message: '网络不可达，请检查网络连接',
      );
    }

    // 2. API Key 非空
    if (apiKey.trim().isEmpty) {
      return const ConnectionTestResult(
        ok: false,
        message: '请先输入 API Key',
      );
    }

    // 3. API Key 格式（长度 > 8，无空格换行）
    final normalizedKey = apiKey.trim();
    final hasWhitespace = normalizedKey.contains(RegExp(r'\s'));
    if (normalizedKey.length <= 8 || hasWhitespace) {
      return const ConnectionTestResult(
        ok: false,
        message: 'API Key 格式无效',
      );
    }

    // 模型 ID（火山方舟等需要用户部署接入点）
    if (provider.requiresCustomModelId && model.trim().isEmpty) {
      return const ConnectionTestResult(
        ok: false,
        message: '所选模型无效，请更换',
      );
    }

    // 4-7. 真实验证：Key 有效性 / 模型可用性 / 余额配额 / 超时（15s + 重试 1 次）
    try {
      final agent = AgentService.build(
        provider: provider,
        apiKey: apiKey,
        model: model,
        codingPlanEnabled: codingPlanEnabled,
      );
      var verify = await agent
          .verify(model: model.isEmpty ? null : model)
          .timeout(const Duration(seconds: 15));
      if (!verify.ok && verify.code == PocketClawVerifyCode.timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        verify = await agent
            .verify(model: model.isEmpty ? null : model)
            .timeout(const Duration(seconds: 15));
      }
      if (!verify.ok) {
        return ConnectionTestResult(
          ok: false,
          message: _messageFor(verify.code),
        );
      }
      return ConnectionTestResult.success();
    } on PocketClawException catch (e) {
      return ConnectionTestResult(ok: false, message: _messageFor(e.code));
    } on TimeoutException {
      return const ConnectionTestResult(
        ok: false,
        message: '连接超时，请稍后重试',
      );
    } catch (_) {
      return const ConnectionTestResult(
        ok: false,
        message: '连接超时，请稍后重试',
      );
    }
  }

  String _messageFor(PocketClawVerifyCode code) {
    return switch (code) {
      PocketClawVerifyCode.authError => 'API Key 无效，请重新输入',
      PocketClawVerifyCode.modelError => '所选模型无效，请更换',
      PocketClawVerifyCode.quotaError => 'API 余额不足，请充值',
      PocketClawVerifyCode.timeout => '连接超时，请稍后重试',
      PocketClawVerifyCode.networkError => '网络不可达，请检查网络连接',
      PocketClawVerifyCode.ok => '连接成功，模型可用',
      PocketClawVerifyCode.unknown => '连接失败，请检查配置',
    };
  }
}
