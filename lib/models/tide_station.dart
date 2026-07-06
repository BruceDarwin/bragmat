/// Tide Station Model
/// 
/// Represents a tide station from WorldTides API or similar official source.
/// Contains station metadata for calculating tide context.
class TideStation {
  final String? stationId;
  final String name;
  final double latitude;
  final double longitude;
  final double? distanceKm; // Distance from observation point
  final String? country;
  final String? timezone;

  TideStation({
    this.stationId,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.distanceKm,
    this.country,
    this.timezone,
  });

  Map<String, dynamic> toMap() {
    return {
      'stationId': stationId,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'distanceKm': distanceKm,
      'country': country,
      'timezone': timezone,
    };
  }

  factory TideStation.fromMap(Map<String, dynamic> map) {
    return TideStation(
      stationId: map['stationId'] as String?,
      name: map['name'] as String,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      distanceKm: map['distanceKm'] as double?,
      country: map['country'] as String?,
      timezone: map['timezone'] as String?,
    );
  }

  TideStation copyWith({
    String? stationId,
    String? name,
    double? latitude,
    double? longitude,
    double? distanceKm,
    String? country,
    String? timezone,
  }) {
    return TideStation(
      stationId: stationId ?? this.stationId,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      distanceKm: distanceKm ?? this.distanceKm,
      country: country ?? this.country,
      timezone: timezone ?? this.timezone,
    );
  }
}
