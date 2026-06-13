class FishingBuddy {
  final int? id;
  final String name;

  FishingBuddy({
    this.id,
    required this.name,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }

  factory FishingBuddy.fromMap(Map<String, dynamic> map) {
    return FishingBuddy(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
    );
  }

  FishingBuddy copyWith({
    int? id,
    String? name,
  }) {
    return FishingBuddy(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }
}
