import '../database/database_helper.dart';
import '../models/trip_summary.dart';
import '../models/fishing_trip.dart';
import '../models/catch.dart';
import '../models/trip_journal.dart';
import '../models/achievement.dart';
import 'achievement_service.dart';

class TripSummaryService {
  static final TripSummaryService _instance = TripSummaryService._internal();
  factory TripSummaryService() => _instance;
  TripSummaryService._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;
  final AchievementService _achievementService = AchievementService();

  Future<TripSummary> generateTripSummary(int tripId) async {
    final trip = await _db.getFishingTrip(tripId);
    if (trip == null) {
      throw Exception('Trip not found');
    }

    final catches = await _db.getCatchesForTrip(tripId);
    final tripMedia = await _db.getMediaForTrip(tripId);
    final journalEntries = await _db.getJournalForTrip(tripId);
    
    // Get primary trip photo
    String? primaryPhotoPath;
    if (tripMedia.isNotEmpty) {
      final primary = tripMedia.firstWhere(
        (m) => m.role == 'primary',
        orElse: () => tripMedia.first,
      );
      primaryPhotoPath = primary.filePath;
    }

    // Calculate statistics
    final totalCatches = catches.length;
    final speciesCount = catches.map((c) => c.fishType).toSet().length;
    
    Catch? largestFish;
    if (catches.isNotEmpty) {
      largestFish = catches.reduce((a, b) => a.lengthCm > b.lengthCm ? a : b);
    }
    
    final totalLength = catches.fold<int>(0, (sum, c) => sum + c.lengthCm);
    final averageLength = totalCatches > 0 ? totalLength / totalCatches : 0.0;
    
    // Count photos (trip media + catch media)
    int totalPhotos = tripMedia.length;
    for (final catchItem in catches) {
      if (catchItem.id != null) {
        final catchMedia = await _db.getMediaForCatch(catchItem.id!);
        totalPhotos += catchMedia.length;
      }
    }

    final journalEntryCount = journalEntries.length;

    // Catch highlights
    CatchHighlight? largestFishHighlight;
    if (largestFish != null) {
      final primaryMedia = largestFish.id != null 
          ? await _db.getPrimaryMediaForCatch(largestFish.id!)
          : null;
      largestFishHighlight = CatchHighlight(
        species: largestFish.fishType,
        length: largestFish.lengthCm,
        date: largestFish.dateCaught ?? largestFish.createdAt,
        photoPath: primaryMedia?.filePath,
        catchId: largestFish.id,
      );
    }

    CatchHighlight? mostCommonSpeciesHighlight;
    if (catches.isNotEmpty) {
      final speciesCounts = <String, int>{};
      for (final catchItem in catches) {
        speciesCounts[catchItem.fishType] = (speciesCounts[catchItem.fishType] ?? 0) + 1;
      }
      
      final uniqueSpecies = speciesCounts.length;
      final maxCount = speciesCounts.values.reduce((a, b) => a > b ? a : b);
      final speciesWithMaxCount = speciesCounts.entries.where((e) => e.value == maxCount).toList();
      
      String highlightType;
      String displaySpecies;
      int displayCount;
      
      if (uniqueSpecies == 1) {
        // Only one species caught
        highlightType = 'only_species';
        displaySpecies = speciesCounts.keys.first;
        displayCount = maxCount;
      } else if (speciesWithMaxCount.length == 1) {
        // Clear winner for most common
        highlightType = 'most_common';
        displaySpecies = speciesWithMaxCount.first.key;
        displayCount = maxCount;
      } else {
        // Tie for most common - show species mix
        highlightType = 'species_mix';
        displaySpecies = '$uniqueSpecies species';
        displayCount = maxCount;
      }
      
      // Get first catch for photo/date - use first catch overall for species_mix
      final firstCatch = catches.reduce((a, b) {
        final aDate = a.dateCaught ?? a.createdAt;
        final bDate = b.dateCaught ?? b.createdAt;
        return aDate.isBefore(bDate) ? a : b;
      });
      final primaryMedia = firstCatch.id != null
          ? await _db.getPrimaryMediaForCatch(firstCatch.id!)
          : null;
      
      mostCommonSpeciesHighlight = CatchHighlight(
        species: displaySpecies,
        length: displayCount,
        date: firstCatch.dateCaught ?? firstCatch.createdAt,
        photoPath: primaryMedia?.filePath,
        catchId: firstCatch.id,
        highlightType: highlightType,
      );
    }

    CatchHighlight? firstCatchHighlight;
    CatchHighlight? lastCatchHighlight;
    if (catches.isNotEmpty) {
      final sortedByDate = List<Catch>.from(catches)..sort((a, b) {
        final aDate = a.dateCaught ?? a.createdAt;
        final bDate = b.dateCaught ?? b.createdAt;
        return aDate.compareTo(bDate);
      });
      
      final firstCatch = sortedByDate.first;
      final firstMedia = firstCatch.id != null
          ? await _db.getPrimaryMediaForCatch(firstCatch.id!)
          : null;
      firstCatchHighlight = CatchHighlight(
        species: firstCatch.fishType,
        length: firstCatch.lengthCm,
        date: firstCatch.dateCaught ?? firstCatch.createdAt,
        photoPath: firstMedia?.filePath,
        catchId: firstCatch.id,
      );

      final lastCatch = sortedByDate.last;
      final lastMedia = lastCatch.id != null
          ? await _db.getPrimaryMediaForCatch(lastCatch.id!)
          : null;
      lastCatchHighlight = CatchHighlight(
        species: lastCatch.fishType,
        length: lastCatch.lengthCm,
        date: lastCatch.dateCaught ?? lastCatch.createdAt,
        photoPath: lastMedia?.filePath,
        catchId: lastCatch.id,
      );
    }

    // Location highlights
    LocationHighlight? productiveLocation;
    List<LocationHighlight>? locations;
    if (catches.isNotEmpty) {
      final locationCounts = <String, int>{};
      for (final catchItem in catches) {
        if (catchItem.location != null && catchItem.location!.isNotEmpty) {
          locationCounts[catchItem.location!] = (locationCounts[catchItem.location!] ?? 0) + 1;
        }
      }
      
      if (locationCounts.isNotEmpty) {
        final sortedLocations = locationCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        
        productiveLocation = LocationHighlight(
          location: sortedLocations.first.key,
          catchCount: sortedLocations.first.value,
        );
        
        locations = sortedLocations.take(3).map((e) => 
          LocationHighlight(location: e.key, catchCount: e.value)
        ).toList();
      }
    }

    // Journal summary
    TripJournalSummary? journalSummary;
    if (journalEntries.isNotEmpty) {
      final sortedEntries = List<TripJournal>.from(journalEntries)
        ..sort((a, b) => b.journalDateTime.compareTo(a.journalDateTime));
      
      final latest = sortedEntries.first;
      final entryTypes = journalEntries.map((e) => e.journalType).toSet().toList();
      
      journalSummary = TripJournalSummary(
        entryCount: journalEntries.length,
        latestEntryTitle: latest.title,
        latestEntryPreview: latest.entryText.length > 100 
            ? '${latest.entryText.substring(0, 100)}...'
            : latest.entryText,
        latestEntryDate: latest.journalDateTime,
        entryTypes: entryTypes,
      );
    }

    // Achievements unlocked during trip
    final unlockedAchievements = <String>[];
    if (trip.startDate != null) {
      // Calculate effective end date for filtering
      DateTime effectiveEndDate;
      if (trip.endDate != null) {
        effectiveEndDate = trip.endDate!;
      } else {
        // For trips with no end date, use the latest activity date from the trip
        DateTime? latestActivityDate;
        
        // Check catches for latest date
        for (final catchItem in catches) {
          final catchDate = catchItem.dateCaught ?? catchItem.createdAt;
          if (latestActivityDate == null || catchDate.isAfter(latestActivityDate)) {
            latestActivityDate = catchDate;
          }
        }
        
        // Check journal entries for latest date
        for (final entry in journalEntries) {
          if (latestActivityDate == null || entry.journalDateTime.isAfter(latestActivityDate)) {
            latestActivityDate = entry.journalDateTime;
          }
        }
        
        // If no activity, treat as single-day trip
        effectiveEndDate = latestActivityDate ?? trip.startDate!;
      }
      
      // Debug logging
      print('=== Achievement Filtering for Trip ===');
      print('Trip ID: $tripId');
      print('Trip Name: ${trip.name}');
      print('Trip Start Date: ${trip.startDate.toIso8601String()}');
      print('Trip End Date: ${trip.endDate?.toIso8601String() ?? "null"}');
      print('Effective End Date for filtering: ${effectiveEndDate.toIso8601String()}');
      
      final allAchievements = await _achievementService.getAllAchievements();
      print('Total achievements checked: ${allAchievements.length}');
      
      for (final achievement in allAchievements) {
        if (achievement.isUnlocked && achievement.unlockedDate != null) {
          final unlockDate = achievement.unlockedDate!;
          print('  Achievement: ${achievement.name}, Unlocked: ${unlockDate.toIso8601String()}');
          
          // Check if unlock date is within trip date range (inclusive)
          if ((unlockDate.isAfter(trip.startDate) || unlockDate.isAtSameMomentAs(trip.startDate)) &&
              (unlockDate.isBefore(effectiveEndDate) || unlockDate.isAtSameMomentAs(effectiveEndDate))) {
            unlockedAchievements.add(achievement.name);
            print('    -> INCLUDED in trip summary');
          } else {
            print('    -> EXCLUDED (outside trip date range)');
          }
        }
      }
      
      print('Achievements included in trip summary: ${unlockedAchievements.length}');
      print('Achievement names: ${unlockedAchievements.join(", ")}');
      print('=== End Achievement Filtering ===');
    }

    return TripSummary(
      tripName: trip.name,
      startDate: trip.startDate,
      endDate: trip.endDate,
      location: trip.location,
      primaryPhotoPath: primaryPhotoPath,
      totalCatches: totalCatches,
      speciesCount: speciesCount,
      largestFishLength: largestFish?.lengthCm,
      largestFishSpecies: largestFish?.fishType,
      averageLength: averageLength,
      totalPhotos: totalPhotos,
      journalEntryCount: journalEntryCount,
      largestFish: largestFishHighlight,
      mostCommonSpecies: mostCommonSpeciesHighlight,
      firstCatch: firstCatchHighlight,
      lastCatch: lastCatchHighlight,
      journalSummary: journalSummary,
      unlockedAchievements: unlockedAchievements,
    );
  }

  String generateTripStory(TripSummary summary) {
    final buffer = StringBuffer();
    
    // Duration
    final duration = summary.durationText;
    
    // Location
    final location = summary.location ?? 'this location';
    
    // Basic stats
    final catches = summary.totalCatches;
    final species = summary.speciesCount;
    
    buffer.write('This $duration trip to $location ');
    
    if (catches == 0) {
      buffer.write('had no catches recorded.');
      return buffer.toString();
    }
    
    // Build the story based on species highlight type
    if (summary.mostCommonSpecies != null) {
      final common = summary.mostCommonSpecies!;
      switch (common.highlightType) {
        case 'only_species':
          buffer.write('produced $catches catch${catches > 1 ? 'es' : ''}, all ${common.species}. ');
          break;
        case 'species_mix':
          if (common.length == 1) {
            buffer.write('produced $catches catch${catches > 1 ? 'es' : ''} across $species spec${species > 1 ? 'ies' : 'ies'}, with one of each recorded. ');
          } else {
            buffer.write('produced $catches catch${catches > 1 ? 'es' : ''} across $species spec${species > 1 ? 'ies' : 'ies'}, with no single species dominating the trip. ');
          }
          break;
        case 'most_common':
        default:
          buffer.write('produced $catches catch${catches > 1 ? 'es' : ''} across $species spec${species > 1 ? 'ies' : 'ies'}. ');
          buffer.write('${common.species} was the most common species with ${common.length} catch${common.length > 1 ? 'es' : ''} recorded. ');
          break;
      }
    } else {
      // Fallback if no species highlight (shouldn't happen with catches)
      buffer.write('produced $catches catch${catches > 1 ? 'es' : ''}');
      if (species > 0) {
        buffer.write(' across $species spec${species > 1 ? 'ies' : 'ies'}');
      }
      buffer.write('. ');
    }
    
    // Largest fish
    if (summary.largestFish != null) {
      final largest = summary.largestFish!;
      buffer.write('The largest fish was a ${largest.length}cm ${largest.species}');
      
      // Add day info if we have start/end dates
      if (summary.endDate != null && summary.startDate != summary.endDate) {
        final dayDiff = largest.date.difference(summary.startDate).inDays + 1;
        buffer.write(' caught on day $dayDiff');
      }
      buffer.write('. ');
    }
    
    // Photos
    if (summary.totalPhotos > 0) {
      buffer.write('${summary.totalPhotos} photo${summary.totalPhotos > 1 ? 's were' : ' was'} taken during the trip. ');
    }
    
    // Journal
    if (summary.journalEntryCount > 0) {
      buffer.write('${summary.journalEntryCount} journal entr${summary.journalEntryCount > 1 ? 'ies were' : 'y was'} written. ');
    }
    
    // Achievements
    if (summary.unlockedAchievements.isNotEmpty) {
      buffer.write('Achievements unlocked during the trip: ');
      buffer.write(summary.unlockedAchievements.join(', '));
      buffer.write('. ');
    }
    
    return buffer.toString();
  }

  String generateShareableText(TripSummary summary) {
    final buffer = StringBuffer();
    
    buffer.writeln('🎣 ${summary.tripName}');
    buffer.writeln('');
    
    // Dates
    final startStr = '${summary.startDate.day}/${summary.startDate.month}/${summary.startDate.year}';
    if (summary.endDate != null) {
      final endStr = '${summary.endDate!.day}/${summary.endDate!.month}/${summary.endDate!.year}';
      buffer.writeln('📅 $startStr - $endStr');
    } else {
      buffer.writeln('📅 $startStr');
    }
    
    if (summary.location != null) {
      buffer.writeln('📍 ${summary.location}');
    }
    
    buffer.writeln('');
    buffer.writeln('--- Trip Statistics ---');
    buffer.writeln('🎣 Total Catches: ${summary.totalCatches}');
    buffer.writeln('🐟 Species: ${summary.speciesCount}');
    buffer.writeln('📏 Largest Fish: ${summary.largestFishSpecies ?? 'N/A'} (${summary.largestFishLength ?? 0}cm)');
    buffer.writeln('📊 Average Length: ${summary.averageLength.toStringAsFixed(1)}cm');
    buffer.writeln('📸 Photos: ${summary.totalPhotos}');
    buffer.writeln('📝 Journal Entries: ${summary.journalEntryCount}');
    
    // Species highlights
    if (summary.mostCommonSpecies != null) {
      buffer.writeln('');
      buffer.writeln('--- Species Highlights ---');
      final common = summary.mostCommonSpecies!;
      switch (common.highlightType) {
        case 'only_species':
          buffer.writeln('🐟 Only Species: ${common.species} (${common.length} caught)');
          break;
        case 'species_mix':
          buffer.writeln('🐟 Species Mix: ${common.species} (${common.length} each)');
          break;
        case 'most_common':
        default:
          buffer.writeln('🐟 Most Common: ${common.species} (${common.length} caught)');
          break;
      }
    }
    
    // Location highlights temporarily disabled
    // if (summary.bestLocation != null) {
    //   buffer.writeln('');
    //   buffer.writeln('--- Highlights ---');
    //   buffer.writeln('📍 Most Productive Location: ${summary.bestLocation.location} (${summary.bestLocation.catchCount} catches)');
    // }
    
    if (summary.unlockedAchievements.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('--- Achievements ---');
      for (final achievement in summary.unlockedAchievements) {
        buffer.writeln('🏆 $achievement');
      }
    }
    
    buffer.writeln('');
    buffer.writeln('Generated by Bragmat');
    
    return buffer.toString();
  }
}
