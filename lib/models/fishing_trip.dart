class FishingTrip {
  final int? id;
  final String name;
  final DateTime startDate;
  final DateTime? endDate;
  final String? location;
  final String? notes;
  final DateTime createdAt;

  FishingTrip({
    this.id,
    required this.name,
    required this.startDate,
    this.endDate,
    this.location,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory FishingTrip.fromMap(Map<String, dynamic> map) {
    return FishingTrip(
      id: map['id'] as int?,
      name: map['name'] as String,
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: map['end_date'] != null
          ? DateTime.parse(map['end_date'] as String)
          : null,
      location: map['location'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'location': location,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  FishingTrip copyWith({
    int? id,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    String? location,
    String? notes,
    DateTime? createdAt,
  }) {
    return FishingTrip(
      id: id ?? this.id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
