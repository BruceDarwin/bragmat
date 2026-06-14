class TripJournal {
  final int? id;
  final int tripId;
  final DateTime journalDateTime;
  final String journalType; // 'general', 'fishing_report', 'weather', 'tide', 'wildlife', 'campsite', 'boat_equipment', 'other'
  final String title;
  final String entryText;
  final DateTime createdAt;
  final DateTime updatedAt;

  TripJournal({
    this.id,
    required this.tripId,
    required this.journalDateTime,
    required this.journalType,
    required this.title,
    required this.entryText,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory TripJournal.fromMap(Map<String, dynamic> map) {
    return TripJournal(
      id: map['id'] as int?,
      tripId: map['trip_id'] as int,
      journalDateTime: DateTime.parse(map['journal_date_time'] as String),
      journalType: map['journal_type'] as String? ?? 'general',
      title: map['title'] as String,
      entryText: map['entry_text'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'trip_id': tripId,
      'journal_date_time': journalDateTime.toIso8601String(),
      'journal_type': journalType,
      'title': title,
      'entry_text': entryText,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  TripJournal copyWith({
    int? id,
    int? tripId,
    DateTime? journalDateTime,
    String? journalType,
    String? title,
    String? entryText,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TripJournal(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      journalDateTime: journalDateTime ?? this.journalDateTime,
      journalType: journalType ?? this.journalType,
      title: title ?? this.title,
      entryText: entryText ?? this.entryText,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String getJournalTypeDisplayName(String type) {
    switch (type) {
      case 'general':
        return 'General Note';
      case 'fishing_report':
        return 'Fishing Report';
      case 'weather':
        return 'Weather';
      case 'tide':
        return 'Tide';
      case 'wildlife':
        return 'Wildlife';
      case 'campsite':
        return 'Campsite';
      case 'boat_equipment':
        return 'Boat / Equipment';
      case 'other':
        return 'Other';
      default:
        return 'General Note';
    }
  }

  static String getJournalTypeIcon(String type) {
    switch (type) {
      case 'general':
        return 'note';
      case 'fishing_report':
        return 'report';
      case 'weather':
        return 'cloud';
      case 'tide':
        return 'water';
      case 'wildlife':
        return 'pets';
      case 'campsite':
        return 'cabin';
      case 'boat_equipment':
        return 'directions_boat';
      case 'other':
        return 'label';
      default:
        return 'note';
    }
  }
}
