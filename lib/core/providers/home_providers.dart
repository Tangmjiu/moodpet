import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../agent/agent_service.dart';
import '../agent/emotion_rules.dart';
import '../llm/llm_provider.dart';
import '../models/emotion.dart';
import '../models/memory.dart';
import '../utils/speech_service.dart';
import '../utils/vibration_engine.dart';
import 'settings_providers.dart';

final speechServiceProvider = Provider<SpeechService>((ref) => SpeechService());

final vibrationEngineProvider =
    Provider<VibrationEngine>((ref) => const VibrationEngine());

/// 使用用户所选提供商初始化好的 PocketClaw Agent。
final agentServiceProvider = FutureProvider<AgentService?>((ref) async {
  final settings = await ref.watch(settingsControllerProvider.future);
  if (!settings.hasCompletedOnboarding) return null;
  final provider = llmProviderById(settings.selectedProviderId);
  if (provider == null) return null;

  final apiKey = await ref.watch(apiKeyProvider.future);
  final key = apiKey?.trim();
  if (key == null || key.isEmpty) return null;

  final model = (settings.selectedModel?.isNotEmpty ?? false)
      ? settings.selectedModel!
      : provider.defaultModel;
  return AgentService(
    providerId: provider.id,
    agent: AgentService.build(
      provider: provider,
      apiKey: key,
      model: model,
      codingPlanEnabled: settings.codingPlanEnabled,
    ),
  );
});

class HomeState {
  const HomeState({
    required this.emotion,
    required this.ruleName,
    required this.statusPhrase,
    this.suggestion,
    this.isListening = false,
    this.isThinking = false,
    this.lastError,
  });

  factory HomeState.initial() {
    const defaultRule = EmotionRule(
      name: '开心',
      emotion: Emotion(
        emoji: '😊',
        colorHex: '#FFD93D',
        vibration: [100, 80, 100, 80, 100],
        suggestion: '我在听，说说吧',
      ),
      keywords: [],
      statusPhrase: '今天心情不错哦',
    );
    return HomeState(
      emotion: defaultRule.emotion,
      ruleName: defaultRule.name,
      statusPhrase: defaultRule.statusPhrase,
    );
  }

  final Emotion emotion;
  final String ruleName;
  final String statusPhrase;
  final String? suggestion;
  final bool isListening;
  final bool isThinking;
  final String? lastError;

  HomeState copyWith({
    Emotion? emotion,
    String? ruleName,
    String? statusPhrase,
    String? suggestion,
    bool? isListening,
    bool? isThinking,
    String? lastError,
    bool clearError = false,
  }) {
    return HomeState(
      emotion: emotion ?? this.emotion,
      ruleName: ruleName ?? this.ruleName,
      statusPhrase: statusPhrase ?? this.statusPhrase,
      suggestion: suggestion ?? this.suggestion,
      isListening: isListening ?? this.isListening,
      isThinking: isThinking ?? this.isThinking,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

class HomeController extends Notifier<HomeState> {
  @override
  HomeState build() => HomeState.initial();

  Future<void> toggleListening() async {
    if (state.isListening) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  Future<void> startListening() async {
    if (state.isListening) return;
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      state = state.copyWith(
        clearError: true,
        lastError: '需要麦克风权限才能听你说话',
      );
      return;
    }

    state = state.copyWith(isListening: true, clearError: true);
    try {
      await ref.read(speechServiceProvider).start(
            onFinalText: (text) => unawaited(processText(text)),
            onStatus: (status) {
              if (status == SpeechToTextStatus.done ||
                  status == SpeechToTextStatus.notListening) {
                state = state.copyWith(isListening: false);
              }
            },
            onError: (error) {
              state = state.copyWith(
                isListening: false,
                clearError: true,
                lastError: '语音识别失败：${error.errorMsg}',
              );
            },
          );
    } catch (e) {
      state = state.copyWith(
        isListening: false,
        clearError: true,
        lastError: '语音识别失败：$e',
      );
    }
  }

  Future<void> stopListening() async {
    await ref.read(speechServiceProvider).stop();
    state = state.copyWith(isListening: false);
  }

  Future<void> processText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(isThinking: true, clearError: true);

    AgentAnalysis analysis;
    final service = await ref.read(agentServiceProvider.future);
    if (service == null) {
      final local = resolveLocalEmotion(trimmed);
      analysis = AgentAnalysis(
        emotion: local.emotion,
        ruleName: local.name,
        isLocal: true,
        note: '尚未配置 LLM 提供商，使用本地规则',
      );
    } else {
      analysis = await service.analyze(trimmed);
    }

    final rule = emotionRuleByName(analysis.ruleName);
    state = state.copyWith(
      emotion: analysis.emotion,
      ruleName: analysis.ruleName,
      statusPhrase: analysis.isLocal
          ? rule.statusPhrase
          : '${rule.name} · ${analysis.isLocal ? '本地' : '云端'}',
      suggestion: analysis.emotion.suggestion,
      isThinking: false,
      clearError: true,
    );

    // 三重响应：Emoji 切换（state）+ 背景色渐变（UI）+ 震动。
    final settings = ref.read(settingsControllerProvider).valueOrNull;
    if (settings?.vibrationEnabled != false) {
      await ref
          .read(vibrationEngineProvider)
          .vibratePattern(analysis.emotion.vibration);
    }

    // 记忆落库。
    unawaited(
      ref.read(memoryRepositoryProvider).insertAndReturn(
            Memory(
              id: 0,
              userText: trimmed,
              emoji: analysis.emotion.emoji,
              suggestion: analysis.emotion.suggestion,
              timestamp: DateTime.now(),
              isLocal: analysis.isLocal,
            ),
          ),
    );
  }

  void dismissError() => state = state.copyWith(clearError: true);
}

final homeControllerProvider =
    NotifierProvider<HomeController, HomeState>(HomeController.new);

/// SpeechToText 状态常量（避免依赖插件内部字符串）。
class SpeechToTextStatus {
  static const String listening = 'listening';
  static const String notListening = 'notListening';
  static const String done = 'done';
}
