import 'package:pocketclaw/pocketclaw.dart' show PocketClawAuthType;

import 'llm_provider.dart';

/// 将 MoodPet 的鉴权配置翻译为 PocketClaw 可执行的请求策略。
class AuthConfig {
  const AuthConfig({
    required this.type,
    required this.pocketClawType,
    this.headerName,
    this.queryParam,
    this.requiresSecretKey = false,
    this.hint,
  });

  final AuthType type;
  final PocketClawAuthType pocketClawType;
  final String? headerName;
  final String? queryParam;
  final bool requiresSecretKey;
  final String? hint;

  factory AuthConfig.of(LLMProvider provider) {
    return switch (provider.authType) {
      AuthType.bearer => const AuthConfig(
          type: AuthType.bearer,
          pocketClawType: PocketClawAuthType.bearer,
          hint: '粘贴以 sk- / Bearer Token 形式提供的 API Key',
        ),
      AuthType.apiKeyHeader => AuthConfig(
          type: AuthType.apiKeyHeader,
          pocketClawType: PocketClawAuthType.apiKeyHeader,
          headerName: provider.authHeaderName ?? 'x-api-key',
          hint: '粘贴 Anthropic Console 生成的 API Key',
        ),
      AuthType.queryParam => AuthConfig(
          type: AuthType.queryParam,
          pocketClawType: PocketClawAuthType.queryParam,
          queryParam: provider.authQueryParam ?? 'key',
          hint: '粘贴 Google AI Studio 生成的 API Key',
        ),
      AuthType.custom => AuthConfig(
          type: AuthType.custom,
          pocketClawType: PocketClawAuthType.custom,
          requiresSecretKey: provider.requiresSecretKey,
          hint: provider.requiresSecretKey
              ? '格式：APIKey:APISecret（英文冒号分隔）'
              : '粘贴平台提供的 Access Token / API Key',
        ),
    };
  }
}

/// 特殊鉴权（文心 / 讯飞）使用的双密钥拆分。
class AuthKeyParts {
  const AuthKeyParts(this.apiKey, [this.secretKey]);

  final String apiKey;
  final String? secretKey;

  factory AuthKeyParts.parse(String input) {
    final trimmed = input.trim();
    final index = trimmed.indexOf(':');
    if (index > 0) {
      return AuthKeyParts(
        trimmed.substring(0, index).trim(),
        trimmed.substring(index + 1).trim(),
      );
    }
    return AuthKeyParts(trimmed);
  }
}
