class Catch {
  final int? id;
  final String fishType;
  final int lengthCm;
  final String? notes;
  final DateTime createdAt;
  final DateTime? dateCaught;
  final String? imagePath;
  final DateTime? photoDateTime;
  final double? latitude;
  final double? longitude;
  final String? location;
  final int? fishingBuddyId;
  final int? tripId;

  Catch({
    this.id,
    required this.fishType,
    required this.lengthCm,
    this.notes,
    required this.createdAt,
    this.dateCaught,
    this.imagePath,
    this.photoDateTime,
    this.latitude,
    this.longitude,
    this.location,
    this.fishingBuddyId,
    this.tripId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fish_type': fishType,
      'length_cm': lengthCm,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'date_caught': dateCaught?.toIso8601String(),
      'image_path': imagePath,
      'photo_datetime': photoDateTime?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'location': location,
      'fishing_buddy_id': fishingBuddyId,
      'trip_id': tripId,
    };
  }

factory Catch.fromMap(Map<String, dynamic> map) {
  return Catch(
    id: map['id'] as int?,
    fishType: map['fish_type'] as String? ?? '',
    lengthCm: (map['length_cm'] as num?)?.toInt() ?? 0,
    notes: map['notes'] as String? ?? '',
    createdAt: map['created_at'] != null
        ? DateTime.parse(map['created_at'] as String)
        : DateTime.now(),
    dateCaught: map['date_caught'] != null
        ? DateTime.parse(map['date_caught'] as String)
        : null,
    imagePath: map['image_path'] as String?,
    photoDateTime: map['photo_datetime'] != null
        ? DateTime.parse(map['photo_datetime'] as String)
        : null,
    latitude: map['latitude'] as double?,
    longitude: map['longitude'] as double?,
    location: map['location'] as String?,
    fishingBuddyId: map['fishing_buddy_id'] as int?,
    tripId: map['trip_id'] as int?,
  );
}

  Catch copyWith({
    int? id,
    String? fishType,
    int? lengthCm,
    String? notes,
    DateTime? createdAt,
    DateTime? dateCaught,
    String? imagePath,
    DateTime? photoDateTime,
    double? latitude,
    double? longitude,
    String? location,
    int? fishingBuddyId,
    int? tripId,
  }) {
    return Catch(
      id: id ?? this.id,
      fishType: fishType ?? this.fishType,
      lengthCm: lengthCm ?? this.lengthCm,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      dateCaught: dateCaught ?? this.dateCaught,
      imagePath: imagePath ?? this.imagePath,
      photoDateTime: photoDateTime ?? this.photoDateTime,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      location: location ?? this.location,
      fishingBuddyId: fishingBuddyId ?? this.fishingBuddyId,
      tripId: tripId ?? this.tripId,
    );
  }
}