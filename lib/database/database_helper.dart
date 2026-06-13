import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/catch.dart';
import '../models/fishing_buddy.dart';
import '../models/catch_media.dart';
import '../models/fishing_trip.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('bragmat.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 10,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE catches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fish_type TEXT,
        length_cm INTEGER,
        notes TEXT,
        created_at TEXT,
        date_caught TEXT,
        image_path TEXT,
        photo_datetime TEXT,
        latitude REAL,
        longitude REAL,
        location TEXT,
        fishing_buddy_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE fish_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE fishing_buddies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE catch_media (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        catch_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        media_type TEXT NOT NULL DEFAULT 'photo',
        role TEXT NOT NULL DEFAULT 'other',
        date_taken TEXT,
        latitude REAL,
        longitude REAL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (catch_id) REFERENCES catches (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE fishing_trips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT,
        location TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Insert default fish types
    await db.insert('fish_types', {'name': 'Barramundi'});
    await db.insert('fish_types', {'name': 'Mangrove Jack'});
    await db.insert('fish_types', {'name': 'Saratoga'});
    await db.insert('fish_types', {'name': 'Jewfish'});
    await db.insert('fish_types', {'name': 'Queenfish'});

    // Insert default "Me" fishing buddy
    await db.insert('fishing_buddies', {'name': 'Me'});
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE catches ADD COLUMN date_caught TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE catches ADD COLUMN image_path TEXT');
      await db.execute('ALTER TABLE catches ADD COLUMN photo_datetime TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE catches ADD COLUMN latitude REAL');
      await db.execute('ALTER TABLE catches ADD COLUMN longitude REAL');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE fish_types (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT UNIQUE NOT NULL
        )
      ''');
      await db.insert('fish_types', {'name': 'Barramundi'});
      await db.insert('fish_types', {'name': 'Mangrove Jack'});
      await db.insert('fish_types', {'name': 'Saratoga'});
      await db.insert('fish_types', {'name': 'Jewfish'});
      await db.insert('fish_types', {'name': 'Queenfish'});
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE catches ADD COLUMN location TEXT');
    }
    if (oldVersion < 7) {
      // Add location column if it doesn't exist (for databases at version 6 without location)
      try {
        await db.execute('ALTER TABLE catches ADD COLUMN location TEXT');
      } catch (e) {
        // Column might already exist, ignore error
      }
    }
    if (oldVersion < 8) {
      // Add fishing_buddies table
      await db.execute('''
        CREATE TABLE fishing_buddies (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT UNIQUE NOT NULL
        )
      ''');
      // Insert default "Me" fishing buddy
      await db.insert('fishing_buddies', {'name': 'Me'});
      // Add fishing_buddy_id column to catches table
      try {
        await db.execute('ALTER TABLE catches ADD COLUMN fishing_buddy_id INTEGER');
      } catch (e) {
        // Column might already exist, ignore error
      }
    }
    if (oldVersion < 9) {
      // Add catch_media table
      await db.execute('''
        CREATE TABLE catch_media (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          catch_id INTEGER NOT NULL,
          file_path TEXT NOT NULL,
          media_type TEXT NOT NULL DEFAULT 'photo',
          role TEXT NOT NULL DEFAULT 'other',
          date_taken TEXT,
          latitude REAL,
          longitude REAL,
          created_at TEXT NOT NULL,
          FOREIGN KEY (catch_id) REFERENCES catches (id) ON DELETE CASCADE
        )
      ''');
      
      // Migrate existing photo paths from catches table to catch_media table
      final catches = await db.query('catches', where: 'image_path IS NOT NULL');
      for (final catchData in catches) {
        final catchId = catchData['id'] as int;
        final imagePath = catchData['image_path'] as String?;
        final photoDateTime = catchData['photo_datetime'] as String?;
        final latitude = catchData['latitude'] as double?;
        final longitude = catchData['longitude'] as double?;
        
        if (imagePath != null && imagePath.isNotEmpty) {
          await db.insert('catch_media', {
            'catch_id': catchId,
            'file_path': imagePath,
            'media_type': 'photo',
            'role': 'primary',
            'date_taken': photoDateTime,
            'latitude': latitude,
            'longitude': longitude,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }
    }
    if (oldVersion < 10) {
      // Add fishing_trips table
      await db.execute('''
        CREATE TABLE fishing_trips (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          start_date TEXT NOT NULL,
          end_date TEXT,
          location TEXT,
          notes TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      
      // Add trip_id column to catches table
      try {
        await db.execute('ALTER TABLE catches ADD COLUMN trip_id INTEGER');
      } catch (e) {
        // Column might already exist, ignore error
      }
    }
  }

  // INSERT
  Future<int> insertCatch(Catch catchItem) async {
    final db = await instance.database;
    return await db.insert('catches', catchItem.toMap());
  }

  // READ
  Future<List<Catch>> getCatches() async {
    final db = await instance.database;
    final result = await db.query('catches');

    return result.map((json) => Catch.fromMap(json)).toList();
  }

  // UPDATE
  Future<int> updateCatch(Catch catchItem) async {
    final db = await instance.database;
    return await db.update(
      'catches',
      catchItem.toMap(),
      where: 'id = ?',
      whereArgs: [catchItem.id],
    );
  }

  // DELETE
  Future<int> deleteCatch(int id) async {
    final db = await instance.database;
    return await db.delete(
      'catches',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // FISH TYPES
  Future<List<String>> getFishTypes() async {
    final db = await instance.database;
    final result = await db.query('fish_types', orderBy: 'name');
    return result.map((json) => json['name'] as String).toList();
  }

  Future<int> insertFishType(String name) async {
    final db = await instance.database;
    try {
      return await db.insert('fish_types', {'name': name});
    } catch (e) {
      // If fish type already exists, return -1
      return -1;
    }
  }

  Future<bool> isFishTypeUsed(String name) async {
    final db = await instance.database;
    final result = await db.query(
      'catches',
      where: 'fish_type = ?',
      whereArgs: [name],
    );
    return result.isNotEmpty;
  }

  Future<int> updateFishType(String oldName, String newName) async {
    final db = await instance.database;
    // Update the fish type name in fish_types table
    final fishTypeResult = await db.update(
      'fish_types',
      {'name': newName},
      where: 'name = ?',
      whereArgs: [oldName],
    );
    // Update all catches that use this fish type
    await db.update(
      'catches',
      {'fish_type': newName},
      where: 'fish_type = ?',
      whereArgs: [oldName],
    );
    return fishTypeResult;
  }

  Future<int> deleteFishType(String name) async {
    final db = await instance.database;
    return await db.delete(
      'fish_types',
      where: 'name = ?',
      whereArgs: [name],
    );
  }

  // FISHING BUDDIES
  Future<List<FishingBuddy>> getFishingBuddies() async {
    final db = await instance.database;
    final result = await db.query('fishing_buddies', orderBy: 'name');
    return result.map((json) => FishingBuddy.fromMap(json)).toList();
  }

  Future<int> insertFishingBuddy(String name) async {
    final db = await instance.database;
    try {
      return await db.insert('fishing_buddies', {'name': name});
    } catch (e) {
      // If fishing buddy already exists, return -1
      return -1;
    }
  }

  Future<bool> isFishingBuddyUsed(int id) async {
    final db = await instance.database;
    final result = await db.query(
      'catches',
      where: 'fishing_buddy_id = ?',
      whereArgs: [id],
    );
    return result.isNotEmpty;
  }

  Future<int> updateFishingBuddy(int id, String newName) async {
    final db = await instance.database;
    return await db.update(
      'fishing_buddies',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteFishingBuddy(int id) async {
    final db = await instance.database;
    return await db.delete(
      'fishing_buddies',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<FishingBuddy?> getFishingBuddyByName(String name) async {
    final db = await instance.database;
    final result = await db.query(
      'fishing_buddies',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return FishingBuddy.fromMap(result.first);
  }

  Future<FishingBuddy?> getMeFishingBuddy() async {
    return await getFishingBuddyByName('Me');
  }

  // STATISTICS
  Future<Map<String, dynamic>> getStatistics() async {
    final db = await instance.database;
    final catches = await getCatches();
    final buddies = await getFishingBuddies();
    
    // Create buddy ID to name map
    final buddyMap = {for (var buddy in buddies) buddy.id!: buddy.name};
    
    // Total catches
    final totalCatches = catches.length;
    
    if (totalCatches == 0) {
      return {
        'totalCatches': 0,
        'largestFish': null,
        'averageLength': 0.0,
        'mostCommonFishType': null,
        'mostCommonFishingBuddy': null,
        'mostRecentCatch': null,
        'totalTrips': 0,
        'mostProductiveTrip': null,
        'largestFishByTrip': null,
        'averageCatchesPerTrip': 0.0,
      };
    }
    
    // Largest fish
    final largestFish = catches.reduce((a, b) => a.lengthCm > b.lengthCm ? a : b);
    final largestFishBuddy = largestFish.fishingBuddyId != null
        ? buddyMap[largestFish.fishingBuddyId]
        : null;
    
    // Average length
    final totalLength = catches.fold<int>(0, (sum, c) => sum + c.lengthCm);
    final averageLength = totalLength / totalCatches;
    
    // Most common fish type
    final fishTypeCounts = <String, int>{};
    for (final catch_ in catches) {
      fishTypeCounts[catch_.fishType] = (fishTypeCounts[catch_.fishType] ?? 0) + 1;
    }
    final mostCommonFishType = fishTypeCounts.entries
        .reduce((a, b) => a.value > b.value ? a : b).key;
    
    // Most common fishing buddy
    final buddyCounts = <String, int>{};
    for (final catch_ in catches) {
      if (catch_.fishingBuddyId != null) {
        final buddyName = buddyMap[catch_.fishingBuddyId] ?? 'Unknown';
        buddyCounts[buddyName] = (buddyCounts[buddyName] ?? 0) + 1;
      }
    }
    String? mostCommonFishingBuddy;
    if (buddyCounts.isNotEmpty) {
      mostCommonFishingBuddy = buddyCounts.entries
          .reduce((a, b) => a.value > b.value ? a : b).key;
    }
    
    // Most recent catch
    final mostRecentCatch = catches.reduce((a, b) {
      final aDate = a.dateCaught ?? a.createdAt;
      final bDate = b.dateCaught ?? b.createdAt;
      return aDate.isAfter(bDate) ? a : b;
    });
    final mostRecentCatchBuddy = mostRecentCatch.fishingBuddyId != null
        ? buddyMap[mostRecentCatch.fishingBuddyId]
        : null;
    
    // Trip statistics
    final trips = await getFishingTrips();
    final totalTrips = trips.length;
    
    // Calculate catches per trip
    final tripCatches = <int, int>{};
    for (final catch_ in catches) {
      if (catch_.tripId != null) {
        tripCatches[catch_.tripId!] = (tripCatches[catch_.tripId!] ?? 0) + 1;
      }
    }
    
    // Most productive trip
    String? mostProductiveTrip;
    if (tripCatches.isNotEmpty) {
      final mostProductiveTripId = tripCatches.entries
          .reduce((a, b) => a.value > b.value ? a : b).key;
      final trip = trips.firstWhere(
        (t) => t.id == mostProductiveTripId,
        orElse: () => trips.first,
      );
      mostProductiveTrip = trip.name;
    }
    
    // Largest fish by trip (find the trip with the largest fish)
    String? largestFishByTrip;
    if (largestFish.tripId != null) {
      final trip = trips.firstWhere(
        (t) => t.id == largestFish.tripId,
        orElse: () => trips.first,
      );
      largestFishByTrip = trip.name;
    }
    
    // Average catches per trip (only count catches assigned to trips)
    final catchesWithTrips = tripCatches.values.fold<int>(0, (sum, count) => sum + count);
    final averageCatchesPerTrip = totalTrips > 0 
        ? catchesWithTrips / totalTrips 
        : 0.0;
    
    return {
      'totalCatches': totalCatches,
      'largestFish': {
        'fishType': largestFish.fishType,
        'length': largestFish.lengthCm,
        'fishingBuddy': largestFishBuddy,
      },
      'averageLength': averageLength,
      'mostCommonFishType': mostCommonFishType,
      'mostCommonFishingBuddy': mostCommonFishingBuddy,
      'mostRecentCatch': {
        'fishType': mostRecentCatch.fishType,
        'length': mostRecentCatch.lengthCm,
        'date': mostRecentCatch.dateCaught ?? mostRecentCatch.createdAt,
        'fishingBuddy': mostRecentCatchBuddy,
      },
      'totalTrips': totalTrips,
      'mostProductiveTrip': mostProductiveTrip,
      'largestFishByTrip': largestFishByTrip,
      'averageCatchesPerTrip': averageCatchesPerTrip,
    };
  }

  // CATCH MEDIA CRUD
  Future<int> insertCatchMedia(CatchMedia media) async {
    final db = await instance.database;
    return await db.insert('catch_media', media.toMap());
  }

  Future<List<CatchMedia>> getMediaForCatch(int catchId) async {
    final db = await instance.database;
    final result = await db.query(
      'catch_media',
      where: 'catch_id = ?',
      whereArgs: [catchId],
      orderBy: 'created_at DESC',
    );
    return result.map((json) => CatchMedia.fromMap(json)).toList();
  }

  Future<CatchMedia?> getPrimaryMediaForCatch(int catchId) async {
    final db = await instance.database;
    final result = await db.query(
      'catch_media',
      where: 'catch_id = ? AND role = ?',
      whereArgs: [catchId, 'primary'],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return CatchMedia.fromMap(result.first);
  }

  Future<int> updateCatchMedia(CatchMedia media) async {
    final db = await instance.database;
    return await db.update(
      'catch_media',
      media.toMap(),
      where: 'id = ?',
      whereArgs: [media.id],
    );
  }

  Future<int> deleteCatchMedia(int id) async {
    final db = await instance.database;
    return await db.delete(
      'catch_media',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAllMediaForCatch(int catchId) async {
    final db = await instance.database;
    return await db.delete(
      'catch_media',
      where: 'catch_id = ?',
      whereArgs: [catchId],
    );
  }

  Future<int> setPrimaryMedia(int mediaId) async {
    final db = await instance.database;
    // First, get the media item to find its catch_id
    final mediaResult = await db.query(
      'catch_media',
      where: 'id = ?',
      whereArgs: [mediaId],
      limit: 1,
    );
    if (mediaResult.isEmpty) return 0;
    
    final catchId = mediaResult.first['catch_id'] as int;
    
    // Remove primary role from all media for this catch
    await db.update(
      'catch_media',
      {'role': 'other'},
      where: 'catch_id = ? AND role = ?',
      whereArgs: [catchId, 'primary'],
    );
    
    // Set the new primary
    return await db.update(
      'catch_media',
      {'role': 'primary'},
      where: 'id = ?',
      whereArgs: [mediaId],
    );
  }

  // FISHING TRIP CRUD
  Future<int> insertFishingTrip(FishingTrip trip) async {
    final db = await instance.database;
    return await db.insert('fishing_trips', trip.toMap());
  }

  Future<List<FishingTrip>> getFishingTrips() async {
    final db = await instance.database;
    final result = await db.query(
      'fishing_trips',
      orderBy: 'start_date DESC',
    );
    return result.map((json) => FishingTrip.fromMap(json)).toList();
  }

  Future<FishingTrip?> getFishingTrip(int id) async {
    final db = await instance.database;
    final result = await db.query(
      'fishing_trips',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return FishingTrip.fromMap(result.first);
  }

  Future<int> updateFishingTrip(FishingTrip trip) async {
    final db = await instance.database;
    return await db.update(
      'fishing_trips',
      trip.toMap(),
      where: 'id = ?',
      whereArgs: [trip.id],
    );
  }

  Future<int> deleteFishingTrip(int id) async {
    final db = await instance.database;
    // First, set trip_id to NULL for all catches associated with this trip
    await db.update(
      'catches',
      {'trip_id': null},
      where: 'trip_id = ?',
      whereArgs: [id],
    );
    // Then delete the trip
    return await db.delete(
      'fishing_trips',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Catch>> getCatchesForTrip(int tripId) async {
    final db = await instance.database;
    final result = await db.query(
      'catches',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'date_caught DESC, created_at DESC',
    );
    return result.map((json) => Catch.fromMap(json)).toList();
  }

  Future<int> getCatchCountForTrip(int tripId) async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM catches WHERE trip_id = ?',
      [tripId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}