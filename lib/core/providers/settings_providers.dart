import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../llm/llm_provider.dart';
import '../storage/memory_repository.dart';
import '../storage/secure_storage.dart';

/// 由 main.dart 在 runApp 前 override。
final sharedPreferencesProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());

final secureStorageProvider =
    Provider<SecureStorageService>((ref) => SecureStorageService());

final memoryRepositoryProvider =
    Provider<MemoryRepository>((ref) => MemoryRepository.instance);

final apiKeyProvider = FutureProvider<String?>((ref) async {
  return ref.watch(secureStorageProvider).readApiKey();
});

/// 持久化的应用设置。
class AppSettings {
  const AppSettings({
    required this.hasCompletedOnboarding,
    this.selectedProviderId,
    this.selectedModel,
    this.codingPlanEnabled = false,
    this.vibrationEnabled = true,
    this.proactivePushEnabled = false,
  });

  final bool hasCompletedOnboarding;
  final String? selectedProviderId;
  final String? selectedModel;
  final bool codingPlanEnabled;
  final bool vibrationEnabled;
  final bool proactivePushEnabled;

  AppSettings copyWith({
    bool? hasCompletedOnboarding,
    String? selectedProviderId,
    String? selectedModel,
    bool? codingPlanEnabled,
    bool? vibrationEnabled,
    bool? proactivePushEnabled,
  }) {
    return AppSettings(
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      selectedProviderId: selectedProviderId ?? this.selectedProviderId,
      selectedModel: selectedModel ?? this.selectedModel,
      codingPlanEnabled: codingPlanEnabled ?? this.codingPlanEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      proactivePushEnabled: proactivePushEnabled ?? this.proactivePushEnabled,
    );
  }

  factory AppSettings.fromPrefs(SharedPreferences prefs) => AppSettings(
        hasCompletedOnboarding:
            prefs.getBool('hasCompletedOnboarding') ?? false,
        selectedProviderId: prefs.getString('selectedProvider'),
        selectedModel: prefs.getString('selectedModel'),
        codingPlanEnabled: prefs.getBool('codingPlanEnabled') ?? false,
        vibrationEnabled: prefs.getBool('vibrationEnabled') ?? true,
        proactivePushEnabled: prefs.getBool('proactivePushEnabled') ?? false,
      );
}

class SettingsController extends AsyncNotifier<AppSettings> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);
  SecureStorageService get _secure => ref.read(secureStorageProvider);

  @override
  Future<AppSettings> build() async {
    final prefs = ref.read(sharedPreferencesProvider);
    return AppSettings.fromPrefs(prefs);
  }

  AppSettings? get current => state.valueOrNull;

  /// Onboarding 完成保存：与文档示例字段一一对应。
  Future<void> completeOnboarding({
    required String providerId,
    required String apiKey,
    required String model,
    required bool codingPlanEnabled,
  }) async {
    try {
      await _prefs.setBool('hasCompletedOnboarding', true);
      await _prefs.setString('selectedProvider', providerId);
      await _secure.writeApiKey(apiKey);
      await _prefs.setString('selectedModel', model);
      await _prefs.setBool('codingPlanEnabled', codingPlanEnabled);
      state = AsyncData(AppSettings(
        hasCompletedOnboarding: true,
        selectedProviderId: providerId,
        selectedModel: model,
        codingPlanEnabled: codingPlanEnabled,
        vibrationEnabled: current?.vibrationEnabled ?? true,
        proactivePushEnabled: current?.proactivePushEnabled ?? false,
      ));
    } catch (e, stack) {
      state = AsyncError(e, stack);
      rethrow;
    }
  }

  Future<void> setSelectedProvider(String providerId, {String? model}) async {
    await _prefs.setString('selectedProvider', providerId);
    final effectiveModel =
        model ?? llmProviderById(providerId)?.defaultModel ?? '';
    if (effectiveModel.isNotEmpty) {
      await _prefs.setString('selectedModel', effectiveModel);
    }
    state = AsyncData(AppSettings(
      hasCompletedOnboarding: current?.hasCompletedOnboarding ?? true,
      selectedProviderId: providerId,
      selectedModel: effectiveModel.isEmpty ? null : effectiveModel,
      codingPlanEnabled: current?.codingPlanEnabled ?? false,
      vibrationEnabled: current?.vibrationEnabled ?? true,
      proactivePushEnabled: current?.proactivePushEnabled ?? false,
    ));
  }

  Future<void> setSelectedModel(String model) async {
    await _prefs.setString('selectedModel', model);
    state = AsyncData((current ?? state.requireValue).copyWith(
      selectedModel: model,
    ));
  }

  Future<void> setCodingPlanEnabled(bool value) async {
    await _prefs.setBool('codingPlanEnabled', value);
    state = AsyncData(
        (current ?? state.requireValue).copyWith(codingPlanEnabled: value));
  }

  Future<void> setVibrationEnabled(bool value) async {
    await _prefs.setBool('vibrationEnabled', value);
    state = AsyncData(
        (current ?? state.requireValue).copyWith(vibrationEnabled: value));
  }

  Future<void> setProactivePushEnabled(bool value) async {
    await _prefs.setBool('proactivePushEnabled', value);
    state = AsyncData((current ?? state.requireValue)
        .copyWith(proactivePushEnabled: value));
  }

  Future<void> updateApiKey(String value) async {
    await _secure.writeApiKey(value);
    ref.invalidate(apiKeyProvider);
  }

  Future<void> deleteAllMemories() async {
    await ref.read(memoryRepositoryProvider).deleteAll();
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// 当前选择的 LLMProvider（可能为 null）。
final selectedProviderProvider = Provider<LLMProvider?>((ref) {
  final settings = ref.watch(settingsControllerProvider).valueOrNull;
  return llmProviderById(settings?.selectedProviderId);
});
