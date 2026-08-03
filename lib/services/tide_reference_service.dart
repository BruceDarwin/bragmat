import 'package:shared_preferences/shared_preferences.dart';
import '../models/tide_reference.dart';

/// Tide Reference Service
/// 
/// Manages user-selected tide reference locations for tide data requests.
/// Supports automatic mode (catch location) and fixed references (e.g., Darwin).
class TideReferenceService {
  static const String _prefMode = 'tide_reference_mode';
  static const String _prefReferenceId = 'tide_reference_id';
  
  static const String _modeAutomatic = 'automatic';
  static const String _modeFixed = 'fixed';
  
  // Predefined references using actual WorldTides station coordinates
  static const Map<String, TideReference> _predefinedReferences = {
    'darwin': TideReference(
      id: 'darwin',
      displayName: 'Darwin',
      latitude: -12.4667,
      longitude: 130.8500,
    ),
  };
  
  /// Get the current tide reference based on user preferences
  /// 
  /// Returns a TideReference object with mode and coordinates.
  /// For automatic mode, coordinates will be null (use catch coordinates).
  /// For fixed mode, coordinates are from the selected reference.
  static Future<TideReference> getCurrentReference() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_prefMode) ?? _modeAutomatic;
    
    if (mode == _modeAutomatic) {
      return TideReference(
        id: 'automatic',
        displayName: 'Automatic',
        latitude: 0.0, // Will use catch coordinates
        longitude: 0.0, // Will use catch coordinates
      );
    }
    
    // Fixed mode
    final referenceId = prefs.getString(_prefReferenceId);
    if (referenceId != null && _predefinedReferences.containsKey(referenceId)) {
      return _predefinedReferences[referenceId]!;
    }
    
    // Fallback to automatic if reference not found
    return TideReference(
      id: 'automatic',
      displayName: 'Automatic',
      latitude: 0.0,
      longitude: 0.0,
    );
  }
  
  /// Get the mode string ('automatic' or 'fixed')
  static Future<String> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefMode) ?? _modeAutomatic;
  }
  
  /// Set the tide reference mode
  static Future<void> setMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefMode, mode);
  }
  
  /// Set the fixed reference by ID
  static Future<void> setFixedReference(String referenceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefMode, _modeFixed);
    await prefs.setString(_prefReferenceId, referenceId);
  }
  
  /// Set automatic mode
  static Future<void> setAutomaticMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefMode, _modeAutomatic);
    await prefs.remove(_prefReferenceId);
  }
  
  /// Get a predefined reference by ID
  static TideReference? getReferenceById(String id) {
    return _predefinedReferences[id];
  }
  
  /// Get all predefined references
  static Map<String, TideReference> getPredefinedReferences() {
    return Map.from(_predefinedReferences);
  }
  
  /// Get all available references for dropdown selection
  /// Includes Automatic mode and all predefined fixed references
  static List<TideReference> getAllReferences() {
    final references = <TideReference>[];
    
    // Add Automatic option first
    references.add(TideReference(
      id: 'automatic',
      displayName: 'Automatic (catch location)',
      latitude: 0.0,
      longitude: 0.0,
    ));
    
    // Add all predefined references
    references.addAll(_predefinedReferences.values);
    
    return references;
  }
  
  /// Check if a reference is automatic mode
  static bool isAutomatic(TideReference reference) {
    return reference.id == 'automatic';
  }
  
  /// Check if a reference is fixed mode
  static bool isFixed(TideReference reference) {
    return reference.id != 'automatic';
  }
}
