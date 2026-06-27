class UserAchievement {
  final int? id;
  final String achievementId;
  final DateTime unlockedDate;
  final int? progressValue;

  UserAchievement({
    this.id,
    required this.achievementId,
    required this.unlockedDate,
    this.progressValue,
  });

  UserAchievement copyWith({
    int? id,
    String? achievementId,
    DateTime? unlockedDate,
    int? progressValue,
  }) {
    return UserAchievement(
      id: id ?? this.id,
      achievementId: achievementId ?? this.achievementId,
      unlockedDate: unlockedDate ?? this.unlockedDate,
      progressValue: progressValue ?? this.progressValue,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'achievement_id': achievementId,
      'unlocked_date': unlockedDate.toIso8601String(),
      'progress_value': progressValue,
    };
  }

  factory UserAchievement.fromMap(Map<String, dynamic> map) {
    return UserAchievement(
      id: map['id'] as int?,
      achievementId: map['achievement_id'] as String,
      unlockedDate: DateTime.parse(map['unlocked_date'] as String),
      progressValue: map['progress_value'] as int?,
    );
  }
}
