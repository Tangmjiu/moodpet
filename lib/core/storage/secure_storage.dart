import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API Key 加密存储（flutter_secure_storage / Android Keystore）。
class SecureStorageService {
  SecureStorageService([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const String apiKeyKey = 'apiKey';

  final FlutterSecureStorage _storage;

  Future<String?> readApiKey() async {
    try {
      return await _storage.read(key: apiKeyKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeApiKey(String value) async {
    await _storage.write(key: apiKeyKey, value: value.trim());
  }

  Future<void> deleteApiKey() async {
    await _storage.delete(key: apiKeyKey);
  }
}
