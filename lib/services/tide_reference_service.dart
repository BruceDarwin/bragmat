import 'package:shared_preferences/shared_preferences.dart';
import '../data/tide_reference_catalogue.dart';
import '../models/tide_reference.dart';

/// Tide Reference Service
///
/// Manages user-selected tide reference locations for tide data requests.
/// Supports automatic mode (catch location) and fixed references from a
/// curated catalogue of Northern Territory tide stations and named
/// model-based locations.
///
/// Catalogue entries are verified against the WorldTides API before being
/// offered to users — see tool/verify_tide_stations.dart. Stations are
/// only added once their identity and coordinates are confirmed.
class TideReferenceService {
  static const String _prefMode = 'tide_reference_mode';
  static const String _prefReferenceId = 'tide_reference_id';

  static const String _modeAutomatic = 'automatic';
  static const String _modeFixed = 'fixed';

  /// The automatic-mode sentinel reference. Coordinates are unused —
  /// catch coordinates are sent to the API instead.
  static const TideReference _automatic = TideReference(
    id: 'automatic',
    displayName: 'Automatic (catch location)',
    latitude: 0.0,
    longitude: 0.0,
  );

  // Verified catalogue of fixed tide references — the published tier of
  // lib/data/tide_reference_catalogue.dart. Every entry must be verified
  // against the WorldTides API before being added there; unverified
  // candidates live in kTideReferenceCandidates and are never offered.
  static final Map<String, TideReference> _predefinedReferences = {
    for (final ref in kTideReferenceCatalogue) ref.id: ref,
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
      return _automatic;
    }

    // Fixed mode
    final referenceId = prefs.getString(_prefReferenceId);
    if (referenceId != null && _predefinedReferences.containsKey(referenceId)) {
      return _predefinedReferences[referenceId]!;
    }

    // Fallback to automatic if reference not found
    return _automatic;
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
    references.add(_automatic);

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

  /// Short description of how a reference resolves, for UI display.
  /// e.g. 'tide station' for gauge-backed references,
  /// 'model prediction' for named locations without a gauge.
  static String describeSource(TideReference reference) {
    if (isAutomatic(reference)) return 'catch location';
    switch (reference.source) {
      case TideReferenceSource.station:
        return 'tide station';
      case TideReferenceSource.model:
        return 'model prediction';
      case null:
        return 'tide reference';
    }
  }

  /// Resolve the tide reference recorded on an existing catch's
  /// environmental condition into a TideReference.
  ///
  /// Historical records store only a mode string ('automatic'/'fixed'),
  /// the reference display name and the coordinates actually sent to the
  /// API — never a stable ID — so resolution is deliberately tolerant:
  ///
  /// 1. `mode` empty/null → returns null (nothing was recorded).
  /// 2. `mode == 'automatic'` → the automatic sentinel.
  /// 3. Fixed mode → catalogue lookup by ID, then by display name
  ///    (legacy rows store e.g. 'Darwin'), then reconstruction from the
  ///    recorded request coordinates so the catch's original reference
  ///    point is preserved even if the catalogue no longer lists it.
  /// 4. Fixed mode that cannot be resolved → null. Callers must treat
  ///    this as "unresolved" — an unresolved fixed reference must never
  ///    be silently substituted with automatic.
  static TideReference? resolveRecordedReference({
    String? mode,
    String? name,
    double? requestLat,
    double? requestLon,
  }) {
    if (mode == null || mode.isEmpty) {
      return null;
    }

    if (mode == _modeAutomatic) {
      return _automatic;
    }

    // Fixed mode — try catalogue by ID, then by display name.
    if (name != null && name.isNotEmpty) {
      final byId = _predefinedReferences[name.toLowerCase()];
      if (byId != null) return byId;

      final lowerName = name.toLowerCase();
      for (final ref in _predefinedReferences.values) {
        if (ref.displayName.toLowerCase() == lowerName ||
            ref.altNames.any((a) => a.toLowerCase() == lowerName)) {
          return ref;
        }
      }
    }

    // Catalogue miss — reconstruct the recorded reference from the
    // coordinates that were actually sent to the API. This keeps an
    // honest, stable identity for the catch even if the reference is no
    // longer in the catalogue, rather than silently treating it as
    // automatic.
    if (requestLat != null && requestLon != null) {
      final displayName =
          (name != null && name.isNotEmpty) ? name : 'Recorded reference';
      return TideReference(
        id: 'recorded_${_slugify(displayName)}',
        displayName: displayName,
        latitude: requestLat,
        longitude: requestLon,
      );
    }

    return null;
  }

  /// Slugify a display name into a stable ID suffix.
  static String _slugify(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'unnamed' : slug;
  }
}
