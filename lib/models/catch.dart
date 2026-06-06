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
  );
}
}