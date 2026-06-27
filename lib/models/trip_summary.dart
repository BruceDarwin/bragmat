class TripSummary {
  final String tripName;
  final DateTime startDate;
  final DateTime? endDate;
  final String? location;
  final String? primaryPhotoPath;
  
  // Statistics
  final int totalCatches;
  final int speciesCount;
  final int? largestFishLength;
  final String? largestFishSpecies;
  final double averageLength;
  final int totalPhotos;
  final int journalEntryCount;
  
  // Catch highlights
  final CatchHighlight? largestFish;
  final CatchHighlight? mostCommonSpecies;
  final CatchHighlight? firstCatch;
  final CatchHighlight? lastCatch;
  
  // Journal summary
  final TripJournalSummary? journalSummary;
  
  // Achievements
  final List<String> unlockedAchievements;
  
  TripSummary._({
    required this.tripName,
    required this.startDate,
    this.endDate,
    this.location,
    this.primaryPhotoPath,
    required this.totalCatches,
    required this.speciesCount,
    this.largestFishLength,
    this.largestFishSpecies,
    required this.averageLength,
    required this.totalPhotos,
    required this.journalEntryCount,
    this.largestFish,
    this.mostCommonSpecies,
    this.firstCatch,
    this.lastCatch,
    this.journalSummary,
    this.unlockedAchievements = const [],
  });
  
  factory TripSummary({
    required String tripName,
    required DateTime startDate,
    DateTime? endDate,
    String? location,
    String? primaryPhotoPath,
    required int totalCatches,
    required int speciesCount,
    int? largestFishLength,
    String? largestFishSpecies,
    required double averageLength,
    required int totalPhotos,
    required int journalEntryCount,
    CatchHighlight? largestFish,
    CatchHighlight? mostCommonSpecies,
    CatchHighlight? firstCatch,
    CatchHighlight? lastCatch,
    TripJournalSummary? journalSummary,
    List<String> unlockedAchievements = const [],
  }) {
    return TripSummary._(
      tripName: tripName,
      startDate: startDate,
      endDate: endDate,
      location: location,
      primaryPhotoPath: primaryPhotoPath,
      totalCatches: totalCatches,
      speciesCount: speciesCount,
      largestFishLength: largestFishLength,
      largestFishSpecies: largestFishSpecies,
      averageLength: averageLength,
      totalPhotos: totalPhotos,
      journalEntryCount: journalEntryCount,
      largestFish: largestFish,
      mostCommonSpecies: mostCommonSpecies,
      firstCatch: firstCatch,
      lastCatch: lastCatch,
      journalSummary: journalSummary,
      unlockedAchievements: unlockedAchievements,
    );
  }
  
  
  int get tripDuration {
    if (endDate == null) return 1;
    return endDate!.difference(startDate).inDays + 1;
  }
  
  String get durationText {
    final days = tripDuration;
    return '$days Day${days > 1 ? 's' : ''}';
  }
}

class CatchHighlight {
  final String species;
  final int length;
  final DateTime date;
  final String? photoPath;
  final int? catchId;
  final String highlightType; // 'most_common', 'only_species', 'species_mix'
  
  CatchHighlight({
    required this.species,
    required this.length,
    required this.date,
    this.photoPath,
    this.catchId,
    this.highlightType = 'most_common',
  });
}

class LocationHighlight {
  final String location;
  final int catchCount;
  
  LocationHighlight({
    required this.location,
    required this.catchCount,
  });
}

class TripJournalSummary {
  final int entryCount;
  final String? latestEntryTitle;
  final String? latestEntryPreview;
  final DateTime? latestEntryDate;
  final List<String> entryTypes;
  
  TripJournalSummary({
    required this.entryCount,
    this.latestEntryTitle,
    this.latestEntryPreview,
    this.latestEntryDate,
    this.entryTypes = const [],
  });
}
