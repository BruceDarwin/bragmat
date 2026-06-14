import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../models/trip_media.dart';
import '../models/trip_journal.dart';
import '../models/journal_media.dart';
import '../services/current_trip_service.dart';

class BackupService {
  static const String _backupVersion = '1.0';
  
  static Future<Map<String, dynamic>> createBackup() async {
    final db = DatabaseHelper.instance;

    // Get all data
    final catches = await db.getCatches();
    final fishTypes = await db.getFishTypes();
    final fishingBuddies = await db.getFishingBuddies();
    final fishingTrips = await db.getFishingTrips();
    final currentTripId = await CurrentTripService.getCurrentTripId();

    // Get catch media for all catches
    final mediaMap = <String, List<Map<String, dynamic>>>{};
    for (final catchItem in catches) {
      if (catchItem.id != null) {
        final media = await db.getMediaForCatch(catchItem.id!);
        mediaMap[catchItem.id!.toString()] = media.map((m) => m.toMap()).toList();
      }
    }

    // Get trip media for all trips
    final tripMediaMap = <String, List<Map<String, dynamic>>>{};
    for (final trip in fishingTrips) {
      if (trip.id != null) {
        final media = await db.getMediaForTrip(trip.id!);
        tripMediaMap[trip.id!.toString()] = media.map((m) => m.toMap()).toList();
      }
    }

    // Get trip journal for all trips
    final tripJournalMap = <String, List<Map<String, dynamic>>>{};
    for (final trip in fishingTrips) {
      if (trip.id != null) {
        final journal = await db.getJournalForTrip(trip.id!);
        tripJournalMap[trip.id!.toString()] = journal.map((j) => j.toMap()).toList();
      }
    }

    // Get journal media for all journal entries
    final journalMediaMap = <String, List<Map<String, dynamic>>>{};
    for (final trip in fishingTrips) {
      if (trip.id != null) {
        final journal = await db.getJournalForTrip(trip.id!);
        for (final entry in journal) {
          if (entry.id != null) {
            final media = await db.getMediaForJournalEntry(entry.id!);
            journalMediaMap[entry.id!.toString()] = media.map((m) => m.toMap()).toList();
          }
        }
      }
    }

    // Create backup object
    final backup = {
      'version': _backupVersion,
      'timestamp': DateTime.now().toIso8601String(),
      'data': {
        'catches': catches.map((c) => c.toMap()).toList(),
        'catchMedia': mediaMap,
        'fishTypes': fishTypes,
        'fishingBuddies': fishingBuddies.map((b) => b.toMap()).toList(),
        'fishingTrips': fishingTrips.map((t) => t.toMap()).toList(),
        'tripMedia': tripMediaMap,
        'tripJournal': tripJournalMap,
        'journalMedia': journalMediaMap,
        'currentTripId': currentTripId,
      },
    };

    return backup;
  }
  
  static Future<String> exportBackup() async {
    final backup = await createBackup();
    final json = jsonEncode(backup);
    
    // Get downloads directory
    final directory = await getDownloadsDirectory();
    if (directory == null) {
      throw Exception('Could not access downloads directory');
    }
    
    // Generate filename with timestamp
    final timestamp = DateTime.now().toString().replaceAll(':', '-').replaceAll(' ', '_').split('.')[0];
    final filename = 'bragmat_backup_$timestamp.json';
    final filePath = '${directory.path}/$filename';
    
    // Write file
    final file = File(filePath);
    await file.writeAsString(json);
    
    return filePath;
  }
  
  static Future<void> shareBackup() async {
    final filePath = await exportBackup();
    await Share.shareXFiles(
      [XFile(filePath)],
      subject: 'Bragmat Backup',
      text: 'Bragmat data backup',
    );
  }
  
  static Future<void> restoreBackup(String filePath, {bool overwrite = false}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Backup file not found');
    }
    
    final json = await file.readAsString();
    final backup = jsonDecode(json) as Map<String, dynamic>;
    
    // Validate backup version
    final version = backup['version'] as String?;
    if (version == null) {
      throw Exception('Invalid backup file: missing version');
    }
    
    final data = backup['data'] as Map<String, dynamic>;
    final db = DatabaseHelper.instance;
    
    if (!overwrite) {
      // Check if there's existing data
      final existingCatches = await db.getCatches();
      if (existingCatches.isNotEmpty) {
        throw Exception('Database is not empty. Use overwrite option to replace existing data.');
      }
    } else {
      // Clear existing data
      await _clearAllData(db);
    }
    
    // Restore fish types
    final fishTypes = data['fishTypes'] as List<dynamic>?;
    if (fishTypes != null) {
      for (final type in fishTypes) {
        await db.insertFishType(type as String);
      }
    }
    
    // Restore fishing buddies
    final fishingBuddies = data['fishingBuddies'] as List<dynamic>?;
    if (fishingBuddies != null) {
      for (final buddyData in fishingBuddies) {
        final buddyMap = buddyData as Map<String, dynamic>;
        // Check if buddy already exists by name
        final existingBuddy = await db.getFishingBuddyByName(buddyMap['name'] as String);
        if (existingBuddy == null) {
          await db.insertFishingBuddy(buddyMap['name'] as String);
        }
      }
    }
    
    // Restore fishing trips
    final fishingTrips = data['fishingTrips'] as List<dynamic>?;
    final tripIdMap = <int, int>{}; // Maps old trip IDs to new trip IDs
    if (fishingTrips != null) {
      for (final tripData in fishingTrips) {
        final tripMap = tripData as Map<String, dynamic>;
        final oldTripId = tripMap['id'] as int;
        // Remove old ID for insertion
        tripMap.remove('id');
        final newTripId = await db.insertFishingTripFromMap(tripMap);
        tripIdMap[oldTripId] = newTripId;
      }
    }
    
    // Restore catches
    final catches = data['catches'] as List<dynamic>?;
    final catchIdMap = <int, int>{}; // Maps old catch IDs to new catch IDs
    if (catches != null) {
      for (final catchData in catches) {
        final catchMap = catchData as Map<String, dynamic>;
        final oldCatchId = catchMap['id'] as int;
        final oldTripId = catchMap['trip_id'] as int?;
        
        // Map old trip ID to new trip ID
        if (oldTripId != null && tripIdMap.containsKey(oldTripId)) {
          catchMap['trip_id'] = tripIdMap[oldTripId];
        } else {
          catchMap['trip_id'] = null;
        }
        
        // Remove old ID for insertion
        catchMap.remove('id');
        final newCatchId = await db.insertCatchFromMap(catchMap);
        catchIdMap[oldCatchId] = newCatchId;
      }
    }
    
    // Restore catch media
    final catchMedia = data['catchMedia'] as Map<String, dynamic>?;
    if (catchMedia != null) {
      for (final entry in catchMedia.entries) {
        final oldCatchId = int.parse(entry.key);
        final newCatchId = catchIdMap[oldCatchId];
        if (newCatchId != null) {
          final mediaList = entry.value as List<dynamic>;
          for (final mediaData in mediaList) {
            final mediaMap = mediaData as Map<String, dynamic>;
            mediaMap['catch_id'] = newCatchId;
            mediaMap.remove('id');
            await db.insertCatchMediaFromMap(mediaMap);
          }
        }
      }
    }

    // Restore trip media
    final tripMedia = data['tripMedia'] as Map<String, dynamic>?;
    if (tripMedia != null) {
      for (final entry in tripMedia.entries) {
        final oldTripId = int.parse(entry.key);
        final newTripId = tripIdMap[oldTripId];
        if (newTripId != null) {
          final mediaList = entry.value as List<dynamic>;
          for (final mediaData in mediaList) {
            final mediaMap = mediaData as Map<String, dynamic>;
            mediaMap['trip_id'] = newTripId;
            mediaMap.remove('id');
            await db.insertTripMedia(TripMedia.fromMap(mediaMap));
          }
        }
      }
    }

    // Restore trip journal
    final tripJournal = data['tripJournal'] as Map<String, dynamic>?;
    final journalIdMap = <int, int>{}; // Maps old journal IDs to new journal IDs
    if (tripJournal != null) {
      for (final entry in tripJournal.entries) {
        final oldTripId = int.parse(entry.key);
        final newTripId = tripIdMap[oldTripId];
        if (newTripId != null) {
          final journalList = entry.value as List<dynamic>;
          for (final journalData in journalList) {
            final journalMap = journalData as Map<String, dynamic>;
            final oldJournalId = journalMap['id'] as int;
            journalMap['trip_id'] = newTripId;
            journalMap.remove('id');
            final newJournalId = await db.insertTripJournal(TripJournal.fromMap(journalMap));
            journalIdMap[oldJournalId] = newJournalId;
          }
        }
      }
    }

    // Restore journal media
    final journalMedia = data['journalMedia'] as Map<String, dynamic>?;
    if (journalMedia != null) {
      for (final entry in journalMedia.entries) {
        final oldJournalId = int.parse(entry.key);
        final newJournalId = journalIdMap[oldJournalId];
        if (newJournalId != null) {
          final mediaList = entry.value as List<dynamic>;
          for (final mediaData in mediaList) {
            final mediaMap = mediaData as Map<String, dynamic>;
            mediaMap['journal_entry_id'] = newJournalId;
            mediaMap.remove('id');
            await db.insertJournalMedia(JournalMedia.fromMap(mediaMap));
          }
        }
      }
    }

    // Restore current trip setting
    final currentTripId = data['currentTripId'] as int?;
    if (currentTripId != null && tripIdMap.containsKey(currentTripId)) {
      await CurrentTripService.setCurrentTrip(tripIdMap[currentTripId]);
    } else {
      await CurrentTripService.clearCurrentTrip();
    }
  }
  
  static Future<void> _clearAllData(DatabaseHelper db) async {
    // Delete in reverse order of dependencies
    final catches = await db.getCatches();
    for (final catchItem in catches) {
      if (catchItem.id != null) {
        await db.deleteAllMediaForCatch(catchItem.id!);
      }
    }

    final trips = await db.getFishingTrips();
    for (final trip in trips) {
      if (trip.id != null) {
        await db.deleteAllMediaForTrip(trip.id!);
        final journal = await db.getJournalForTrip(trip.id!);
        for (final entry in journal) {
          if (entry.id != null) {
            await db.deleteAllMediaForJournalEntry(entry.id!);
          }
        }
        await db.deleteAllJournalForTrip(trip.id!);
      }
    }

    await db.deleteAllCatches();
    await db.deleteAllFishingTrips();
    await db.deleteAllFishingBuddies();
    await db.deleteAllFishTypes();
    await CurrentTripService.clearCurrentTrip();
  }
}
