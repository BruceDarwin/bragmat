class Catch {
  final int? id;
  final String fishType;
  final int lengthCm;
  final String? notes;
  final DateTime createdAt;

  Catch({
    this.id,
    required this.fishType,
    required this.lengthCm,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fish_type': fishType,
      'length_cm': lengthCm,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
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
  );
}
}