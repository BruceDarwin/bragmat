/// Tide Reference Model
///
/// Represents a fixed tide reference location that can be selected by the user
/// for tide data requests, regardless of the actual catch location.
library;

/// The kind of source a tide reference resolves to in WorldTides.
///
/// [station] — a real tide gauge/harmonic station carried by WorldTides
///             (the API response includes a `station` name).
/// [model]   — a named location with no gauge; predictions come from the
///             WorldTides background atlas (e.g. FES2022).
enum TideReferenceSource { station, model }

class TideReference {
  final String id;
  final String displayName;
  final double latitude;
  final double longitude;
  final bool isUserCreated;

  /// Whether this reference is a real tide station or a model-only
  /// location. Null for the automatic (catch-location) sentinel and for
  /// references reconstructed from historical records where the source
  /// kind is unknown.
  final TideReferenceSource? source;

  const TideReference({
    required this.id,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    this.isUserCreated = false,
    this.source,
  });

  /// True when this reference is backed by a real tide station.
  bool get isStation => source == TideReferenceSource.station;

  /// True when this reference is a named location served by the
  /// WorldTides background model rather than a physical gauge.
  bool get isModelLocation => source == TideReferenceSource.model;

  /// Copy with method for creating modified copies
  TideReference copyWith({
    String? id,
    String? displayName,
    double? latitude,
    double? longitude,
    bool? isUserCreated,
    TideReferenceSource? source,
  }) {
    return TideReference(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isUserCreated: isUserCreated ?? this.isUserCreated,
      source: source ?? this.source,
    );
  }

  /// Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'latitude': latitude,
      'longitude': longitude,
      'isUserCreated': isUserCreated ? 1 : 0,
      'source': source?.name,
    };
  }

  /// Create from map
  factory TideReference.fromMap(Map<String, dynamic> map) {
    return TideReference(
      id: map['id'] as String,
      displayName: map['displayName'] as String,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      isUserCreated: (map['isUserCreated'] as int?) == 1,
      source: _parseSource(map['source'] as String?),
    );
  }

  static TideReferenceSource? _parseSource(String? value) {
    switch (value) {
      case 'station':
        return TideReferenceSource.station;
      case 'model':
        return TideReferenceSource.model;
      default:
        return null;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TideReference && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
