class FavouriteSpot {
  final int? id;
  final String name;
  final double latitude;
  final double longitude;
  final String? notes;

  FavouriteSpot({
    this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'notes': notes,
    };
  }

  factory FavouriteSpot.fromMap(Map<String, dynamic> map) {
    return FavouriteSpot(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      latitude: map['latitude'] as double? ?? 0.0,
      longitude: map['longitude'] as double? ?? 0.0,
      notes: map['notes'] as String?,
    );
  }

  FavouriteSpot copyWith({
    int? id,
    String? name,
    double? latitude,
    double? longitude,
    String? notes,
  }) {
    return FavouriteSpot(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      notes: notes ?? this.notes,
    );
  }
}
