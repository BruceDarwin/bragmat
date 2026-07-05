class Lure {
  final int? id;
  final String make;
  final String model;
  final String? lureType;
  final String? notes;

  Lure({
    this.id,
    required this.make,
    required this.model,
    this.lureType,
    this.notes,
  });

  // Get combined display name (e.g., "Zerek Fish Trap")
  String get displayName {
    if (make.isEmpty && model.isEmpty) {
      return 'Unknown Lure';
    }
    if (make.isEmpty) {
      return model;
    }
    if (model.isEmpty) {
      return make;
    }
    return '$make $model';
  }

  // Convert to map for database
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'make': make,
      'model': model,
      'lure_type': lureType,
      'notes': notes,
    };
  }

  // Create from map from database
  factory Lure.fromMap(Map<String, dynamic> map) {
    return Lure(
      id: map['id'] as int?,
      make: map['make'] as String? ?? '',
      model: map['model'] as String? ?? '',
      lureType: map['lure_type'] as String?,
      notes: map['notes'] as String?,
    );
  }

  // Create a copy with updated fields
  Lure copyWith({
    int? id,
    String? make,
    String? model,
    String? lureType,
    String? notes,
  }) {
    return Lure(
      id: id ?? this.id,
      make: make ?? this.make,
      model: model ?? this.model,
      lureType: lureType ?? this.lureType,
      notes: notes ?? this.notes,
    );
  }
}
