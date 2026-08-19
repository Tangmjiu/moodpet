/// Share-payload codec for custom provider configurations.
///
/// Encodes a [ProviderConfig] into a portable, human-pasteable string suitable
/// for QR codes and plain-text sharing, and decodes such a string back into a
/// fresh [ProviderConfig]. Only the fields needed to reproduce the endpoint
/// shape travel in the payload; secrets and local device state stay behind.
library;

import 'dart:convert';

import 'package:moodpet/core/models/provider_config.dart';
import 'package:uuid/uuid.dart';

/// Payload prefix for shared provider configuration strings.
const String kProviderSharePrefix = 'moodpet-provider:v1:';

/// Encode [provider] into a shareable `moodpet-provider:v1:<base64-json>` string.
///
/// Only endpoint-shape fields are written: `name`, `baseUrl`, `protocol`,
/// `modelsEndpoint`, `defaultModel` and `chatCompletionsPath`. The `apiKey`,
/// `modelOverride`, `enabled`, `iconAsset`, `brandColor`, `id` and `isCustom`
/// are deliberately omitted — secrets and local state stay on the device, and
/// the recipient's app assigns a fresh local id on import.
String encodeProviderShare(ProviderConfig provider) {
  final map = <String, Object?>{
    'v': 1,
    'name': provider.name,
    'baseUrl': provider.baseUrl,
    'protocol': provider.protocol.jsonValue,
    'modelsEndpoint': provider.modelsEndpoint,
    'defaultModel': provider.defaultModel,
    'chatCompletionsPath': provider.chatCompletionsPath,
  };
  return kProviderSharePrefix + base64Encode(utf8.encode(jsonEncode(map)));
}

/// Decode a share string produced by [encodeProviderShare] back into a
/// [ProviderConfig].
///
/// Returns `null` for any malformed input: a missing/wrong prefix, a corrupt
/// base64 segment, a non-JSON body, a JSON body that is not a map, or a map
/// missing a non-empty `name` or `baseUrl`. Unknown protocol strings fall back
/// to [LlmProtocol.openai]. The returned config always has a fresh [Uuid].v4()
/// id, `isCustom` true, and empty `apiKey`/`iconAsset`/`brandColor` — the
/// recipient owns those local fields.
ProviderConfig? decodeProviderShare(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.startsWith(kProviderSharePrefix)) return null;

  final b64 = trimmed.substring(kProviderSharePrefix.length);
  List<int> bytes;
  try {
    bytes = base64Decode(b64);
  } catch (_) {
    return null;
  }

  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } catch (_) {
    return null;
  }

  if (decoded is! Map<String, Object?>) return null;
  final map = decoded;

  final name = map['name'];
  final baseUrl = map['baseUrl'];
  if (name is! String || name.isEmpty) return null;
  if (baseUrl is! String || baseUrl.isEmpty) return null;

  final protocol = LlmProtocol.fromJsonValue(map['protocol'] as String?);

  return ProviderConfig(
    id: const Uuid().v4(),
    name: name,
    baseUrl: baseUrl,
    defaultModel: (map['defaultModel'] as String?) ?? '',
    apiKey: '',
    iconAsset: '',
    brandColor: '',
    protocol: protocol,
    modelsEndpoint: map['modelsEndpoint'] as String?,
    chatCompletionsPath:
        (map['chatCompletionsPath'] as String?) ?? '/chat/completions',
    isCustom: true,
  );
}
