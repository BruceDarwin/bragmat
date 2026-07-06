import 'package:shared_preferences/shared_preferences.dart';

enum FishTypeSelectionMode {
  noDefault,
  defaultFishType,
  rememberLastUsed,
}

class PreferencesService {
  static const String _fishTypeSelectionModeKey = 'fish_type_selection_mode';
  static const String _defaultFishTypeKey = 'default_fish_type';
  static const String _lastUsedFishTypeKey = 'last_used_fish_type';
  static const String _worldTidesApiKeyKey = 'worldtides_api_key';

  static Future<SharedPreferences> get _prefs async {
    return await SharedPreferences.getInstance();
  }

  // Fish Type Selection Mode
  static Future<FishTypeSelectionMode> getFishTypeSelectionMode() async {
    final prefs = await _prefs;
    final modeIndex = prefs.getInt(_fishTypeSelectionModeKey) ?? 0;
    return FishTypeSelectionMode.values[modeIndex];
  }

  static Future<void> setFishTypeSelectionMode(FishTypeSelectionMode mode) async {
    final prefs = await _prefs;
    await prefs.setInt(_fishTypeSelectionModeKey, mode.index);
  }

  // Default Fish Type
  static Future<String?> getDefaultFishType() async {
    final prefs = await _prefs;
    return prefs.getString(_defaultFishTypeKey);
  }

  static Future<void> setDefaultFishType(String? fishType) async {
    final prefs = await _prefs;
    if (fishType == null || fishType.isEmpty) {
      await prefs.remove(_defaultFishTypeKey);
    } else {
      await prefs.setString(_defaultFishTypeKey, fishType);
    }
  }

  // Last Used Fish Type
  static Future<String?> getLastUsedFishType() async {
    final prefs = await _prefs;
    return prefs.getString(_lastUsedFishTypeKey);
  }

  static Future<void> setLastUsedFishType(String fishType) async {
    final prefs = await _prefs;
    await prefs.setString(_lastUsedFishTypeKey, fishType);
  }

  // Clear default fish type if it's deleted
  static Future<void> clearDefaultFishTypeIfDeleted(List<String> existingFishTypes) async {
    final defaultFishType = await getDefaultFishType();
    if (defaultFishType != null && !existingFishTypes.contains(defaultFishType)) {
      await setDefaultFishType(null);
      // If default is cleared, revert to No Default mode
      final currentMode = await getFishTypeSelectionMode();
      if (currentMode == FishTypeSelectionMode.defaultFishType) {
        await setFishTypeSelectionMode(FishTypeSelectionMode.noDefault);
      }
    }
  }

  // Clear last used fish type if it's deleted
  static Future<void> clearLastUsedFishTypeIfDeleted(List<String> existingFishTypes) async {
    final lastUsedFishType = await getLastUsedFishType();
    if (lastUsedFishType != null && !existingFishTypes.contains(lastUsedFishType)) {
      final prefs = await _prefs;
      await prefs.remove(_lastUsedFishTypeKey);
    }
  }

  // WorldTides API Key
  static Future<String?> getWorldTidesApiKey() async {
    final prefs = await _prefs;
    return prefs.getString(_worldTidesApiKeyKey);
  }

  static Future<void> setWorldTidesApiKey(String? apiKey) async {
    final prefs = await _prefs;
    if (apiKey == null || apiKey.isEmpty) {
      await prefs.remove(_worldTidesApiKeyKey);
    } else {
      await prefs.setString(_worldTidesApiKeyKey, apiKey);
    }
  }
}
