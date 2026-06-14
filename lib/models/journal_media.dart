class JournalMedia {
  final int? id;
  final int journalEntryId;
  final String filePath;
  final String mediaType; // 'photo' or 'video' (future)
  final bool isPrimary;
  final DateTime? dateTaken;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  JournalMedia({
    this.id,
    required this.journalEntryId,
    required this.filePath,
    required this.mediaType,
    this.isPrimary = false,
    this.dateTaken,
    this.latitude,
    this.longitude,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory JournalMedia.fromMap(Map<String, dynamic> map) {
    return JournalMedia(
      id: map['id'] as int?,
      journalEntryId: map['journal_entry_id'] as int,
      filePath: map['file_path'] as String,
      mediaType: map['media_type'] as String? ?? 'photo',
      isPrimary: (map['is_primary'] as int?) == 1,
      dateTaken: map['date_taken'] != null ? DateTime.parse(map['date_taken'] as String) : null,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'journal_entry_id': journalEntryId,
      'file_path': filePath,
      'media_type': mediaType,
      'is_primary': isPrimary ? 1 : 0,
      'date_taken': dateTaken?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt.toIso8601String(),
    };
  }

  JournalMedia copyWith({
    int? id,
    int? journalEntryId,
    String? filePath,
    String? mediaType,
    bool? isPrimary,
    DateTime? dateTaken,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
  }) {
    return JournalMedia(
      id: id ?? this.id,
      journalEntryId: journalEntryId ?? this.journalEntryId,
      filePath: filePath ?? this.filePath,
      mediaType: mediaType ?? this.mediaType,
      isPrimary: isPrimary ?? this.isPrimary,
      dateTaken: dateTaken ?? this.dateTaken,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
