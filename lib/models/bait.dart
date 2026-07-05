class Bait {
  final int? id;
  final String name;

  Bait({
    this.id,
    required this.name,
  });

  // Convert to map for database
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }

  // Create from map from database
  factory Bait.fromMap(Map<String, dynamic> map) {
    return Bait(
      id: map['id'] as int?,
      name: map['name'] as String,
    );
  }

  // Create a copy with updated fields
  Bait copyWith({
    int? id,
    String? name,
  }) {
    return Bait(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }
}
