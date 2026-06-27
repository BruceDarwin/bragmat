class Achievement {
  final String id;
  final String name;
  final String description;
  final String icon;
  final String category;
  final int? targetValue;
  final bool isUnlocked;
  final DateTime? unlockedDate;

  Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.category,
    this.targetValue,
    this.isUnlocked = false,
    this.unlockedDate,
  });

  Achievement copyWith({
    String? id,
    String? name,
    String? description,
    String? icon,
    String? category,
    int? targetValue,
    bool? isUnlocked,
    DateTime? unlockedDate,
  }) {
    return Achievement(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      category: category ?? this.category,
      targetValue: targetValue ?? this.targetValue,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      unlockedDate: unlockedDate ?? this.unlockedDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'category': category,
      'target_value': targetValue,
      'is_unlocked': isUnlocked ? 1 : 0,
      'unlocked_date': unlockedDate?.toIso8601String(),
    };
  }

  // Map for inserting into achievements table (definitions only)
  Map<String, dynamic> toDefinitionMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'category': category,
      'target_value': targetValue,
    };
  }

  factory Achievement.fromMap(Map<String, dynamic> map) {
    return Achievement(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      icon: map['icon'] as String,
      category: map['category'] as String,
      targetValue: map['target_value'] as int?,
      isUnlocked: (map['is_unlocked'] as int?) == 1,
      unlockedDate: map['unlocked_date'] != null
          ? DateTime.parse(map['unlocked_date'] as String)
          : null,
    );
  }
}
