class Lure {
  final int? id;
  final String name;

  Lure({
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
  factory Lure.fromMap(Map<String, dynamic> map) {
    return Lure(
      id: map['id'] as int?,
      name: map['name'] as String,
    );
  }

  // Create a copy with updated fields
  Lure copyWith({
    int? id,
    String? name,
  }) {
    return Lure(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }
}
