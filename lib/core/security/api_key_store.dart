import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the user's Wallhaven API key in platform secure storage
/// (iOS Keychain / Android EncryptedSharedPreferences).
///
/// Security contract:
/// - Values never appear in logs, analytics, or crash reports.
/// - Nothing is ever written to plaintext preferences or files.
/// - [storageKey] is stable across releases so saved keys survive upgrades.
final class SecureApiKeyStore {
  static const storageKey = 'wallhaven_api_key';

  final FlutterSecureStorage _storage;

  SecureApiKeyStore()
    // Android v11 defaults to AES-GCM encryption with RSA-OAEP key
    // wrapping (API 23+) — the strongest non-biometric option.
    : _storage = const FlutterSecureStorage(aOptions: AndroidOptions());

  /// Reads the stored key, or `null` when none was saved.
  Future<String?> read() => _storage.read(key: storageKey);

  /// Saves (overwriting any previous) key.
  Future<void> save(String apiKey) =>
      _storage.write(key: storageKey, value: apiKey);

  /// Deletes the stored key.
  Future<void> delete() => _storage.delete(key: storageKey);
}
