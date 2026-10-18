import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure storage service for sensitive data like API keys
/// Uses flutter_secure_storage for secure key-value storage
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );
  
  static const String _worldTidesApiKeyKey = 'worldtides_api_key';
  
  /// Get the WorldTides API key from secure storage
  static Future<String?> getWorldTidesApiKey() async {
    try {
      return await _storage.read(key: _worldTidesApiKeyKey);
    } catch (e) {
      // Fallback to SharedPreferences for migration
      return await _migrateFromSharedPreferences();
    }
  }
  
  /// Save the WorldTides API key to secure storage
  static Future<void> setWorldTidesApiKey(String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) {
      await _storage.delete(key: _worldTidesApiKeyKey);
    } else {
      await _storage.write(key: _worldTidesApiKeyKey, value: apiKey);
    }
  }
  
  /// Delete the WorldTides API key from secure storage
  static Future<void> deleteWorldTidesApiKey() async {
    await _storage.delete(key: _worldTidesApiKeyKey);
  }
  
  /// Check if API key exists
  static Future<bool> hasWorldTidesApiKey() async {
    final key = await getWorldTidesApiKey();
    return key != null && key.isNotEmpty;
  }
  
  /// Mask the API key for display (show first 4 and last 4 characters)
  static String maskApiKey(String? apiKey) {
    if (apiKey == null || apiKey.isEmpty) return '';
    if (apiKey.length <= 8) return '****';
    final start = apiKey.substring(0, 4);
    final end = apiKey.substring(apiKey.length - 4);
    final middle = '*' * (apiKey.length - 8);
    return '$start$middle$end';
  }
  
  /// Migrate API key from SharedPreferences to secure storage
  /// Called automatically if secure storage is empty but SharedPreferences has a key
  static Future<String?> _migrateFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final oldKey = prefs.getString('worldtides_api_key');
      
      if (oldKey != null && oldKey.isNotEmpty) {
        // Migrate to secure storage
        await setWorldTidesApiKey(oldKey);
        // Remove from SharedPreferences
        await prefs.remove('worldtides_api_key');
        return oldKey;
      }
    } catch (e) {
      // Migration failed, return null
    }
    return null;
  }
  
  /// Explicitly trigger migration from SharedPreferences to secure storage
  /// Useful for app startup or settings screen initialization
  static Future<void> migrateApiKey() async {
    await _migrateFromSharedPreferences();
  }

  // ── Cloud backup credentials (Stage 4C) ──────────────────────────────
  // Passphrase and recovery code live ONLY in device secure storage —
  // never transmitted, never logged. Either secret alone can restore any
  // backup that was encrypted with it.

  static const String _cloudBackupPassphraseKey = 'cloud_backup_passphrase';
  static const String _cloudBackupRecoveryCodeKey =
      'cloud_backup_recovery_code';

  static Future<String?> getCloudBackupPassphrase() async {
    try {
      return await _storage.read(key: _cloudBackupPassphraseKey);
    } catch (e) {
      return null;
    }
  }

  static Future<void> setCloudBackupPassphrase(String passphrase) async {
    await _storage.write(key: _cloudBackupPassphraseKey, value: passphrase);
  }

  static Future<String?> getCloudBackupRecoveryCode() async {
    try {
      return await _storage.read(key: _cloudBackupRecoveryCodeKey);
    } catch (e) {
      return null;
    }
  }

  static Future<void> setCloudBackupRecoveryCode(String code) async {
    await _storage.write(key: _cloudBackupRecoveryCodeKey, value: code);
  }

  /// Remove both cloud-backup secrets from this device (disable flow).
  /// Remote backups are unaffected — they still decrypt with the
  /// credentials the user recorded at setup.
  static Future<void> clearCloudBackupCredentials() async {
    await _storage.delete(key: _cloudBackupPassphraseKey);
    await _storage.delete(key: _cloudBackupRecoveryCodeKey);
  }
}
