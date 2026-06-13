class CatchMedia {
  final int? id;
  final int catchId;
  final String filePath;
  final String mediaType; // 'photo' or 'video' (for future use)
  final String role; // 'primary', 'bragmat', 'hero', 'other'
  final DateTime? dateTaken;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  CatchMedia({
    this.id,
    required this.catchId,
    required this.filePath,
    this.mediaType = 'photo',
    this.role = 'other',
    this.dateTaken,
    this.latitude,
    this.longitude,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory CatchMedia.fromMap(Map<String, dynamic> map) {
    return CatchMedia(
      id: map['id'] as int?,
      catchId: map['catch_id'] as int,
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
      'catch_id': catchId,
      'file_path': filePath,
      'media_type': mediaType,
      'role': role,
      'date_taken': dateTaken?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt.toIso8601String(),
    };
  }

  CatchMedia copyWith({
    int? id,
    int? catchId,
    String? filePath,
    String? mediaType,
    String? role,
    DateTime? dateTaken,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
  }) {
    return CatchMedia(
      id: id ?? this.id,
      catchId: catchId ?? this.catchId,
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
