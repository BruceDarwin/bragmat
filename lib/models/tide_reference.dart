/// Tide Reference Model
/// 
/// Represents a fixed tide reference location that can be selected by the user
/// for tide data requests, regardless of the actual catch location.
class TideReference {
  final String id;
  final String displayName;
  final double latitude;
  final double longitude;
  final bool isUserCreated;

  const TideReference({
    required this.id,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    this.isUserCreated = false,
  });

  /// Copy with method for creating modified copies
  TideReference copyWith({
    String? id,
    String? displayName,
    double? latitude,
    double? longitude,
    bool? isUserCreated,
  }) {
    return TideReference(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isUserCreated: isUserCreated ?? this.isUserCreated,
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
    );
  }
}
