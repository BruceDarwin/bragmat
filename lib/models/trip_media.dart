class TripMedia {
  final int? id;
  final int tripId;
  final String filePath;
  final String mediaType; // 'photo' or 'video' (for future use)
  final String role; // 'primary', 'cover', 'other'
  final DateTime? dateTaken;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  TripMedia({
    this.id,
    required this.tripId,
    required this.filePath,
    this.mediaType = 'photo',
    this.role = 'other',
    this.dateTaken,
    this.latitude,
    this.longitude,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory TripMedia.fromMap(Map<String, dynamic> map) {
    return TripMedia(
      id: map['id'] as int?,
      tripId: map['trip_id'] as int,
      filePath: map['file_path'] as String,
      mediaType: map['media_type'] as String? ?? 'photo',
      role: map['role'] as String? ?? 'other',
      dateTaken: map['date_taken'] != null
          ? DateTime.parse(map['date_taken'] as String)
          : null,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'trip_id': tripId,
      'file_path': filePath,
      'media_type': mediaType,
      'role': role,
      'date_taken': dateTaken?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt.toIso8601String(),
    };
  }

  TripMedia copyWith({
    int? id,
    int? tripId,
    String? filePath,
    String? mediaType,
    String? role,
    DateTime? dateTaken,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
  }) {
    return TripMedia(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      filePath: filePath ?? this.filePath,
      mediaType: mediaType ?? this.mediaType,
      role: role ?? this.role,
      dateTaken: dateTaken ?? this.dateTaken,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
