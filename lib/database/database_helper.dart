import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/catch.dart';
import '../models/fishing_buddy.dart';
import '../models/catch_media.dart';
import '../models/fishing_trip.dart';
import '../models/trip_media.dart';
import '../models/trip_journal.dart';
import '../models/journal_media.dart';
import '../models/favourite_spot.dart';
import '../models/achievement.dart';
import '../models/user_achievement.dart';
import '../models/environmental_condition.dart';
import '../models/lure.dart';
import '../models/bait.dart';
import '../services/achievement_service.dart';

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
      version: 26,
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
        fishing_buddy_id INTEGER,
        trip_id INTEGER,
        coordinate_source TEXT
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
      CREATE TABLE lures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE baits (
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

    await db.execute('''
      CREATE TABLE trip_media (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        media_type TEXT NOT NULL DEFAULT 'photo',
        role TEXT NOT NULL DEFAULT 'other',
        date_taken TEXT,
        latitude REAL,
        longitude REAL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (trip_id) REFERENCES fishing_trips (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE trip_journal (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id INTEGER NOT NULL,
        journal_date_time TEXT NOT NULL,
        journal_type TEXT NOT NULL DEFAULT 'general',
        title TEXT NOT NULL,
        entry_text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (trip_id) REFERENCES fishing_trips (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE journal_media (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        journal_entry_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        media_type TEXT NOT NULL DEFAULT 'photo',
        is_primary INTEGER NOT NULL DEFAULT 0,
        date_taken TEXT,
        latitude REAL,
        longitude REAL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (journal_entry_id) REFERENCES trip_journal (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE favourite_spots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE achievements (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        icon TEXT NOT NULL,
        category TEXT NOT NULL,
        target_value INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE user_achievements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        achievement_id TEXT NOT NULL,
        unlocked_date TEXT NOT NULL,
        progress_value INTEGER,
        FOREIGN KEY (achievement_id) REFERENCES achievements(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE environmental_conditions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        catch_id INTEGER,
        trip_id INTEGER,
        observation_date_time TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        moon_phase TEXT,
        moon_illumination REAL,
        sunrise_time TEXT,
        sunset_time TEXT,
        tide_stage TEXT,
        tide_strength TEXT,
        tide_notes TEXT,
        tide_height REAL,
        tide_movement TEXT,
        tide_station TEXT,
        tide_data_source TEXT,
        tide_confidence TEXT,
        derived_tide_stage TEXT,
        tide_observed_or_estimated TEXT,
        tide_diagnostics TEXT,
        tide_station_name TEXT,
        tide_station_distance_km REAL,
        reference_tide_event_type TEXT,
        reference_tide_event_time TEXT,
        reference_tide_event_height REAL,
        reference_tide_event_relation TEXT,
        minutes_from_reference_tide_event INTEGER,
        previous_tide_event_type TEXT,
        previous_tide_event_time TEXT,
        previous_tide_event_height REAL,
        next_tide_event_type TEXT,
        next_tide_event_time TEXT,
        next_tide_event_height REAL,
        tide_context_phrase TEXT,
        tide_context_data_source TEXT,
        tide_context_confidence TEXT,
        weather_condition TEXT,
        temperature REAL,
        humidity REAL,
        cloud_cover REAL,
        wind_speed REAL,
        wind_direction TEXT,
        barometric_pressure REAL,
        rainfall REAL,
        river_flow TEXT,
        water_clarity TEXT,
        data_source TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (catch_id) REFERENCES catches (id) ON DELETE CASCADE,
        FOREIGN KEY (trip_id) REFERENCES fishing_trips (id) ON DELETE CASCADE
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
    if (oldVersion < 11) {
      // Add trip_media table
      await db.execute('''
        CREATE TABLE trip_media (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          trip_id INTEGER NOT NULL,
          file_path TEXT NOT NULL,
          media_type TEXT NOT NULL DEFAULT 'photo',
          role TEXT NOT NULL DEFAULT 'other',
          date_taken TEXT,
          latitude REAL,
          longitude REAL,
          created_at TEXT NOT NULL,
          FOREIGN KEY (trip_id) REFERENCES fishing_trips (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 12) {
      // Add trip_journal table
      await db.execute('''
        CREATE TABLE trip_journal (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          trip_id INTEGER NOT NULL,
          journal_date_time TEXT NOT NULL,
          journal_type TEXT NOT NULL DEFAULT 'general',
          title TEXT NOT NULL,
          entry_text TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (trip_id) REFERENCES fishing_trips (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 13) {
      // Add journal_media table
      await db.execute('''
        CREATE TABLE journal_media (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          journal_entry_id INTEGER NOT NULL,
          file_path TEXT NOT NULL,
          media_type TEXT NOT NULL DEFAULT 'photo',
          is_primary INTEGER NOT NULL DEFAULT 0,
          date_taken TEXT,
          latitude REAL,
          longitude REAL,
          created_at TEXT NOT NULL,
          FOREIGN KEY (journal_entry_id) REFERENCES trip_journal (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 15) {
      // Add coordinate_source column to catches table
      try {
        await db.execute('ALTER TABLE catches ADD COLUMN coordinate_source TEXT');
      } catch (e) {
        // Column might already exist, ignore error
      }
    }
    if (oldVersion < 16) {
      // Add favourite_spots table
      await db.execute('''
        CREATE TABLE favourite_spots (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          notes TEXT
        )
      ''');
    }
    if (oldVersion < 17) {
      // Add achievements table
      await db.execute('''
        CREATE TABLE achievements (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT NOT NULL,
          icon TEXT NOT NULL,
          category TEXT NOT NULL,
          target_value INTEGER
        )
      ''');
      // Add user_achievements table
      await db.execute('''
        CREATE TABLE user_achievements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          achievement_id TEXT NOT NULL,
          unlocked_date TEXT NOT NULL,
          progress_value INTEGER,
          FOREIGN KEY (achievement_id) REFERENCES achievements(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 18) {
      // Add environmental_conditions table
      await db.execute('''
        CREATE TABLE environmental_conditions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          catch_id INTEGER,
          trip_id INTEGER,
          observation_date_time TEXT NOT NULL,
          latitude REAL,
          longitude REAL,
          moon_phase TEXT,
          moon_illumination REAL,
          sunrise_time TEXT,
          sunset_time TEXT,
          tide_stage TEXT,
          tide_height REAL,
          tide_movement TEXT,
          tide_station TEXT,
          tide_data_source TEXT,
          tide_confidence TEXT,
          derived_tide_stage TEXT,
          tide_observed_or_estimated TEXT,
          weather_condition TEXT,
          temperature REAL,
          humidity REAL,
          cloud_cover REAL,
          wind_speed REAL,
          wind_direction TEXT,
          barometric_pressure REAL,
          rainfall REAL,
          river_flow TEXT,
          water_clarity TEXT,
          data_source TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (catch_id) REFERENCES catches (id) ON DELETE CASCADE,
          FOREIGN KEY (trip_id) REFERENCES fishing_trips (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 19) {
      // Add tide_strength and tide_notes columns to environmental_conditions
      try {
        await db.execute('ALTER TABLE environmental_conditions ADD COLUMN tide_strength TEXT');
      } catch (e) {
        // Column might already exist
      }
      try {
        await db.execute('ALTER TABLE environmental_conditions ADD COLUMN tide_notes TEXT');
      } catch (e) {
        // Column might already exist
      }
    }
    if (oldVersion < 20) {
      // Add humidity and cloud_cover columns to environmental_conditions
      try {
        await db.execute('ALTER TABLE environmental_conditions ADD COLUMN humidity REAL');
      } catch (e) {
        // Column might already exist
      }
      try {
        await db.execute('ALTER TABLE environmental_conditions ADD COLUMN cloud_cover REAL');
      } catch (e) {
        // Column might already exist
      }
    }
    if (oldVersion < 21) {
      // Add automated tide data columns to environmental_conditions
      try {
        await db.execute('ALTER TABLE environmental_conditions ADD COLUMN tide_data_source TEXT');
      } catch (e) {
        // Column might already exist
      }
      try {
        await db.execute('ALTER TABLE environmental_conditions ADD COLUMN tide_confidence TEXT');
      } catch (e) {
        // Column might already exist
      }
      try {
        await db.execute('ALTER TABLE environmental_conditions ADD COLUMN derived_tide_stage TEXT');
      } catch (e) {
        // Column might already exist
      }
      try {
        await db.execute('ALTER TABLE environmental_conditions ADD COLUMN tide_observed_or_estimated TEXT');
      } catch (e) {
        // Column might already exist
      }
    }
    if (oldVersion < 22) {
      // Add tide_diagnostics column to environmental_conditions
      try {
        await db.execute('ALTER TABLE environmental_conditions ADD COLUMN tide_diagnostics TEXT');
      } catch (e) {
        // Column might already exist
      }
    }
    if (oldVersion < 23) {
      // Add tide context columns to environmental_conditions
      final tideContextColumns = [
        'tide_station_name TEXT',
        'tide_station_distance_km REAL',
        'reference_tide_event_type TEXT',
        'reference_tide_event_time TEXT',
        'reference_tide_event_height REAL',
        'reference_tide_event_relation TEXT',
        'minutes_from_reference_tide_event INTEGER',
        'previous_tide_event_type TEXT',
        'previous_tide_event_time TEXT',
        'previous_tide_event_height REAL',
        'next_tide_event_type TEXT',
        'next_tide_event_time TEXT',
        'next_tide_event_height REAL',
        'tide_context_phrase TEXT',
        'tide_context_data_source TEXT',
        'tide_context_confidence TEXT',
      ];
      
      for (final column in tideContextColumns) {
        try {
          await db.execute('ALTER TABLE environmental_conditions ADD COLUMN $column');
        } catch (e) {
          // Column might already exist
        }
      }
    }
    if (oldVersion < 24) {
      // Create lures and baits tables
      await db.execute('''
        CREATE TABLE IF NOT EXISTS lures (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT UNIQUE NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS baits (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT UNIQUE NOT NULL
        )
      ''');
      // Add lure_id and bait_id to catches table
      try {
        await db.execute('ALTER TABLE catches ADD COLUMN lure_id INTEGER');
      } catch (e) {
        // Column might already exist
      }
      try {
        await db.execute('ALTER TABLE catches ADD COLUMN bait_id INTEGER');
      } catch (e) {
        // Column might already exist
      }
    }
    if (oldVersion < 25) {
      // Migrate lures table from simple name to make/model structure
      // First, create the new lures table with the new schema
      await db.execute('''
        CREATE TABLE IF NOT EXISTS lures_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          make TEXT NOT NULL DEFAULT '',
          model TEXT NOT NULL DEFAULT '',
          lure_type TEXT,
          notes TEXT,
          UNIQUE(make, model)
        )
      ''');
      
      // Migrate existing lures: split name into make/model if possible
      final existingLures = await db.query('lures');
      for (final lure in existingLures) {
        final oldName = lure['name'] as String;
        String make = '';
        String model = oldName;
        
        // Try to split on first space
        final parts = oldName.split(' ');
        if (parts.length >= 2) {
          make = parts[0];
          model = parts.sublist(1).join(' ');
        }
        
        // Insert into new table
        try {
          await db.insert('lures_new', {
            'make': make,
            'model': model,
            'lure_type': null,
            'notes': null,
          });
        } catch (e) {
          // Handle duplicate make/model combinations
          // Add a suffix to make it unique
          int suffix = 1;
          while (true) {
            try {
              await db.insert('lures_new', {
                'make': '$make ($suffix)',
                'model': model,
                'lure_type': null,
                'notes': null,
              });
              break;
            } catch (e2) {
              suffix++;
            }
          }
        }
      }
      
      // Drop old table and rename new table
      await db.execute('DROP TABLE IF EXISTS lures');
      await db.execute('ALTER TABLE lures_new RENAME TO lures');
      
      // Add lure_size and lure_colour to catches table
      try {
        await db.execute('ALTER TABLE catches ADD COLUMN lure_size TEXT');
      } catch (e) {
        // Column might already exist
      }
      try {
        await db.execute('ALTER TABLE catches ADD COLUMN lure_colour TEXT');
      } catch (e) {
        // Column might already exist
      }
    }
    if (oldVersion < 26) {
      // Revert lures table from make/model back to simple name
      // First, create the new lures table with the simple schema
      await db.execute('''
        CREATE TABLE IF NOT EXISTS lures_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT UNIQUE NOT NULL
        )
      ''');
      
      // Migrate existing lures: combine make/model back to name
      final existingLures = await db.query('lures');
      for (final lure in existingLures) {
        final make = lure['make'] as String? ?? '';
        final model = lure['model'] as String? ?? '';
        String name = model.isEmpty ? make : '$make $model';
        
        // Insert into new table
        try {
          await db.insert('lures_new', {
            'name': name,
          });
        } catch (e) {
          // Handle duplicate names
          // Add a suffix to make it unique
          int suffix = 1;
          while (true) {
            try {
              await db.insert('lures_new', {
                'name': '$name ($suffix)',
              });
              break;
            } catch (e2) {
              suffix++;
            }
          }
        }
      }
      
      // Drop old table and rename new table
      await db.execute('DROP TABLE IF EXISTS lures');
      await db.execute('ALTER TABLE lures_new RENAME TO lures');
      
      // Add lure_photo_path to catches table
      try {
        await db.execute('ALTER TABLE catches ADD COLUMN lure_photo_path TEXT');
      } catch (e) {
        // Column might already exist
      }
    }
    
    // Safety check: Ensure trip_id column exists in catches table
    // This handles cases where a database might be at a higher version but missing the column
    try {
      final columns = await db.rawQuery("PRAGMA table_info(catches)");
      final hasTripId = columns.any((col) => col['name'] == 'trip_id');
      if (!hasTripId) {
        await db.execute('ALTER TABLE catches ADD COLUMN trip_id INTEGER');
      }
    } catch (e) {
      // Ignore errors during safety check
    }
    
    // Safety check: Ensure fishing_buddy_id column exists in catches table
    try {
      final columns = await db.rawQuery("PRAGMA table_info(catches)");
      final hasFishingBuddyId = columns.any((col) => col['name'] == 'fishing_buddy_id');
      if (!hasFishingBuddyId) {
        await db.execute('ALTER TABLE catches ADD COLUMN fishing_buddy_id INTEGER');
      }
    } catch (e) {
      // Ignore errors during safety check
    }
    
    // Safety check: Ensure location column exists in catches table
    try {
      final columns = await db.rawQuery("PRAGMA table_info(catches)");
      final hasLocation = columns.any((col) => col['name'] == 'location');
      if (!hasLocation) {
        await db.execute('ALTER TABLE catches ADD COLUMN location TEXT');
      }
    } catch (e) {
      // Ignore errors during safety check
    }
    
    // Safety check: Ensure latitude column exists in catches table
    try {
      final columns = await db.rawQuery("PRAGMA table_info(catches)");
      final hasLatitude = columns.any((col) => col['name'] == 'latitude');
      if (!hasLatitude) {
        await db.execute('ALTER TABLE catches ADD COLUMN latitude REAL');
      }
    } catch (e) {
      // Ignore errors during safety check
    }
    
    // Safety check: Ensure longitude column exists in catches table
    try {
      final columns = await db.rawQuery("PRAGMA table_info(catches)");
      final hasLongitude = columns.any((col) => col['name'] == 'longitude');
      if (!hasLongitude) {
        await db.execute('ALTER TABLE catches ADD COLUMN longitude REAL');
      }
    } catch (e) {
      // Ignore errors during safety check
    }
    
    if (oldVersion < 14) {
      // Force ensure all required columns exist in catches table
      // This is a safety migration to fix any databases that might be missing columns
      try {
        final columns = await db.rawQuery("PRAGMA table_info(catches)");
        final columnNames = columns.map((col) => col['name'] as String).toSet();
        
        if (!columnNames.contains('trip_id')) {
          await db.execute('ALTER TABLE catches ADD COLUMN trip_id INTEGER');
        }
        if (!columnNames.contains('fishing_buddy_id')) {
          await db.execute('ALTER TABLE catches ADD COLUMN fishing_buddy_id INTEGER');
        }
        if (!columnNames.contains('location')) {
          await db.execute('ALTER TABLE catches ADD COLUMN location TEXT');
        }
        if (!columnNames.contains('latitude')) {
          await db.execute('ALTER TABLE catches ADD COLUMN latitude REAL');
        }
        if (!columnNames.contains('longitude')) {
          await db.execute('ALTER TABLE catches ADD COLUMN longitude REAL');
        }
      } catch (e) {
        // Ignore errors during safety check
      }
    }
  }

  // INSERT
  Future<int> insertCatch(Catch catchItem) async {
    final db = await instance.database;
    final id = await db.insert('catches', catchItem.toMap());
    
    // Evaluate achievements
    await AchievementService().evaluateCatchAchievements();
    if (catchItem.lengthCm > 0) {
      await AchievementService().evaluatePersonalBest(catchItem.lengthCm);
    }
    
    return id;
  }

  Future<int> insertCatchFromMap(Map<String, dynamic> map) async {
    final db = await instance.database;
    return await db.insert('catches', map);
  }

  // READ
  Future<List<Catch>> getCatches() async {
    final db = await instance.database;
    final result = await db.query('catches');

    return result.map((json) => Catch.fromMap(json)).toList();
  }

  Future<Catch?> getCatch(int id) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'catches',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Catch.fromMap(maps.first);
  }

  // UPDATE
  Future<int> updateCatch(Catch catchItem) async {
    final db = await instance.database;
    final map = catchItem.toMap();
    debugPrint('DATABASE UPDATE - lure_size: ${map['lure_size']}, lure_colour: ${map['lure_colour']}, lure_photo_path: ${map['lure_photo_path']}');
    final result = await db.update(
      'catches',
      map,
      where: 'id = ?',
      whereArgs: [catchItem.id],
    );
    
    // Verify the update by reading back
    final updated = await db.query(
      'catches',
      where: 'id = ?',
      whereArgs: [catchItem.id],
    );
    if (updated.isNotEmpty) {
      final row = updated.first;
      debugPrint('DATABASE AFTER UPDATE - lure_size: ${row['lure_size']}, lure_colour: ${row['lure_colour']}, lure_photo_path: ${row['lure_photo_path']}');
    }
    
    // Evaluate achievements
    await AchievementService().evaluateCatchAchievements();
    if (catchItem.lengthCm > 0) {
      await AchievementService().evaluatePersonalBest(catchItem.lengthCm);
    }
    
    return result;
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

  // LURES
  Future<List<Lure>> getLures() async {
    final db = await instance.database;
    final result = await db.query('lures', orderBy: 'name');
    return result.map((json) => Lure.fromMap(json)).toList();
  }

  Future<int> insertLure(String name) async {
    final db = await instance.database;
    try {
      return await db.insert('lures', {'name': name});
    } catch (e) {
      // If lure already exists, return -1
      return -1;
    }
  }

  Future<void> updateLure(Lure lure) async {
    final db = await instance.database;
    await db.update(
      'lures',
      lure.toMap(),
      where: 'id = ?',
      whereArgs: [lure.id],
    );
  }

  Future<bool> isLureUsed(int lureId) async {
    final db = await instance.database;
    final result = await db.query(
      'catches',
      where: 'lure_id = ?',
      whereArgs: [lureId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> deleteLure(int id) async {
    final db = await instance.database;
    await db.delete('lures', where: 'id = ?', whereArgs: [id]);
  }

  // BAITS
  Future<List<Bait>> getBaits() async {
    final db = await instance.database;
    final result = await db.query('baits', orderBy: 'name');
    return result.map((json) => Bait.fromMap(json)).toList();
  }

  Future<int> insertBait(String name) async {
    final db = await instance.database;
    try {
      return await db.insert('baits', {'name': name});
    } catch (e) {
      // If bait already exists, return -1
      return -1;
    }
  }

  Future<bool> isBaitUsed(int baitId) async {
    final db = await instance.database;
    final result = await db.query(
      'catches',
      where: 'bait_id = ?',
      whereArgs: [baitId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> deleteBait(int id) async {
    final db = await instance.database;
    await db.delete('baits', where: 'id = ?', whereArgs: [id]);
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

  Future<int> deleteAllFishTypes() async {
    final db = await instance.database;
    return await db.delete('fish_types');
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

  Future<int> deleteAllFishingBuddies() async {
    final db = await instance.database;
    return await db.delete('fishing_buddies');
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

  // FAVOURITE SPOTS
  Future<List<FavouriteSpot>> getFavouriteSpots() async {
    final db = await instance.database;
    final result = await db.query('favourite_spots', orderBy: 'name ASC');
    return result.map((map) => FavouriteSpot.fromMap(map)).toList();
  }

  Future<int> insertFavouriteSpot(FavouriteSpot spot) async {
    final db = await instance.database;
    final id = await db.insert('favourite_spots', spot.toMap());
    
    // Evaluate achievements
    await AchievementService().evaluateExplorationAchievements();
    
    return id;
  }

  Future<int> updateFavouriteSpot(FavouriteSpot spot) async {
    final db = await instance.database;
    return await db.update(
      'favourite_spots',
      spot.toMap(),
      where: 'id = ?',
      whereArgs: [spot.id],
    );
  }

  Future<int> deleteFavouriteSpot(int id) async {
    final db = await instance.database;
    return await db.delete(
      'favourite_spots',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<FavouriteSpot?> getFavouriteSpot(int id) async {
    final db = await instance.database;
    final result = await db.query(
      'favourite_spots',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return FavouriteSpot.fromMap(result.first);
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
    
    // Fish type statistics (count and average length)
    final fishTypeStats = <String, Map<String, int>>{};
    for (final catch_ in catches) {
      final stats = fishTypeStats[catch_.fishType] ?? {'count': 0, 'totalLength': 0};
      stats['count'] = stats['count']! + 1;
      stats['totalLength'] = stats['totalLength']! + catch_.lengthCm;
      fishTypeStats[catch_.fishType] = stats;
    }
    
    // Most common fish type (for backward compatibility)
    final sortedFishTypes = fishTypeStats.entries.toList()
      ..sort((a, b) => b.value['count']!.compareTo(a.value['count']!));
    final mostCommonFishType = sortedFishTypes.isNotEmpty 
        ? sortedFishTypes.first.key 
        : null;
    
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
    
    // Get primary photo for most recent catch
    String? mostRecentCatchPhotoPath;
    if (mostRecentCatch.id != null) {
      final media = await getPrimaryMediaForCatch(mostRecentCatch.id!);
      mostRecentCatchPhotoPath = media?.filePath;
    }
    
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
    int? mostProductiveTripId;
    String? mostProductiveTrip;
    String? mostProductiveTripPhotoPath;
    if (tripCatches.isNotEmpty) {
      mostProductiveTripId = tripCatches.entries
          .reduce((a, b) => a.value > b.value ? a : b).key;
      final trip = trips.firstWhere(
        (t) => t.id == mostProductiveTripId,
        orElse: () => trips.first,
      );
      mostProductiveTrip = trip.name;
      
      // Get cover photo for most productive trip
      final tripMedia = await getPrimaryMediaForTrip(mostProductiveTripId!);
      mostProductiveTripPhotoPath = tripMedia?.filePath;
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
    
    // Get primary photo for largest fish
    String? largestFishPhotoPath;
    if (largestFish.id != null) {
      final media = await getPrimaryMediaForCatch(largestFish.id!);
      largestFishPhotoPath = media?.filePath;
    }
    
    // Species records (largest and smallest fish per species)
    final speciesRecords = <String, Map<String, dynamic>>{};
    final speciesSmallest = <String, Map<String, dynamic>>{};
    for (final catch_ in catches) {
      // Track largest
      final currentRecord = speciesRecords[catch_.fishType];
      if (currentRecord == null || catch_.lengthCm > (currentRecord['length'] as int)) {
        String? photoPath;
        if (catch_.id != null) {
          final media = await getPrimaryMediaForCatch(catch_.id!);
          photoPath = media?.filePath;
        }
        speciesRecords[catch_.fishType] = {
          'id': catch_.id,
          'fishType': catch_.fishType,
          'length': catch_.lengthCm,
          'photoPath': photoPath,
          'dateCaught': catch_.dateCaught ?? catch_.createdAt,
          'location': catch_.location,
        };
      }
      // Track smallest
      final currentSmallest = speciesSmallest[catch_.fishType];
      if (currentSmallest == null || catch_.lengthCm < (currentSmallest['length'] as int)) {
        speciesSmallest[catch_.fishType] = {
          'id': catch_.id,
          'length': catch_.lengthCm,
        };
      }
    }
    
    // Add smallest length to fish type stats
    final fishTypeStatsWithSmallest = <String, Map<String, dynamic>>{};
    for (final entry in fishTypeStats.entries) {
      final fishType = entry.key;
      final stats = entry.value;
      final smallest = speciesSmallest[fishType];
      fishTypeStatsWithSmallest[fishType] = {
        ...stats,
        'smallestLength': smallest?['length'] as int?,
      };
    }
    
    // Get top 5 fish types by count with average length
    final topFishTypes = sortedFishTypes.take(5).map((entry) {
      final count = entry.value['count']!;
      final avgLength = entry.value['totalLength']! / count;
      final statsWithSmallest = fishTypeStatsWithSmallest[entry.key];
      return {
        'fishType': entry.key,
        'count': count,
        'averageLength': avgLength,
        'smallestLength': statsWithSmallest?['smallestLength'] as int?,
      };
    }).toList();
    
    // Convert species records to list and sort by length descending
    final speciesRecordsList = speciesRecords.values.toList()
      ..sort((a, b) => (b['length'] as int).compareTo(a['length'] as int));
    
    // Location statistics
    final locationCounts = <String, int>{};
    final locationLargestFish = <String, Map<String, dynamic>>{};
    for (final catch_ in catches) {
      final location = catch_.location ?? 'Unknown';
      locationCounts[location] = (locationCounts[location] ?? 0) + 1;
      
      final currentLargest = locationLargestFish[location];
      if (currentLargest == null || catch_.lengthCm > (currentLargest['length'] as int)) {
        locationLargestFish[location] = {
          'id': catch_.id,
          'fishType': catch_.fishType,
          'length': catch_.lengthCm,
        };
      }
    }
    
    String? mostProductiveLocation;
    int? mostProductiveLocationCount;
    if (locationCounts.isNotEmpty) {
      final mostProductive = locationCounts.entries
          .reduce((a, b) => a.value > b.value ? a : b);
      mostProductiveLocation = mostProductive.key;
      mostProductiveLocationCount = mostProductive.value;
    }
    
    String? largestFishLocation;
    if (largestFish.location != null) {
      largestFishLocation = largestFish.location;
    }
    
    // Total unique locations
    final totalLocations = locationCounts.length;
    
    // Total species
    final totalSpecies = fishTypeStats.length;
    
    // Total photos (count all media items)
    final allMedia = await db.query('catch_media');
    final totalPhotos = allMedia.length;
    
    // Catches with coordinates
    final catchesWithCoords = catches.where((c) => c.latitude != null && c.longitude != null).length;
    final locationPercentage = totalCatches > 0 ? (catchesWithCoords / totalCatches * 100).toStringAsFixed(1) : '0.0';
    
    return {
      'totalCatches': totalCatches,
      'largestFish': {
        'id': largestFish.id,
        'fishType': largestFish.fishType,
        'length': largestFish.lengthCm,
        'fishingBuddy': largestFishBuddy,
        'photoPath': largestFishPhotoPath,
        'dateCaught': largestFish.dateCaught ?? largestFish.createdAt,
        'location': largestFish.location,
      },
      'averageLength': averageLength,
      'mostCommonFishType': mostCommonFishType,
      'mostCommonFishingBuddy': mostCommonFishingBuddy,
      'mostRecentCatch': {
        'id': mostRecentCatch.id,
        'fishType': mostRecentCatch.fishType,
        'length': mostRecentCatch.lengthCm,
        'date': mostRecentCatch.dateCaught ?? mostRecentCatch.createdAt,
        'fishingBuddy': mostRecentCatchBuddy,
        'photoPath': mostRecentCatchPhotoPath,
        'location': mostRecentCatch.location,
      },
      'totalTrips': totalTrips,
      'mostProductiveTrip': {
        'id': mostProductiveTripId,
        'name': mostProductiveTrip,
        'photoPath': mostProductiveTripPhotoPath,
        'location': mostProductiveTripId != null 
            ? trips.firstWhere((t) => t.id == mostProductiveTripId, orElse: () => trips.first).location 
            : null,
        'catchCount': mostProductiveTripId != null ? tripCatches[mostProductiveTripId] : 0,
      },
      'largestFishByTrip': largestFishByTrip,
      'averageCatchesPerTrip': averageCatchesPerTrip,
      'topFishTypes': topFishTypes,
      'speciesRecords': speciesRecordsList,
      'totalLocations': totalLocations,
      'mostProductiveLocation': mostProductiveLocation,
      'mostProductiveLocationCount': mostProductiveLocationCount,
      'largestFishLocation': largestFishLocation,
      'totalSpecies': totalSpecies,
      'totalPhotos': totalPhotos,
      'totalBuddies': buddies.length,
      'catchesWithCoordinates': catchesWithCoords,
      'locationPercentage': locationPercentage,
    };
  }

  // CATCH MEDIA CRUD
  Future<int> insertCatchMedia(CatchMedia media) async {
    final db = await instance.database;
    return await db.insert('catch_media', media.toMap());
  }

  Future<int> insertCatchMediaFromMap(Map<String, dynamic> map) async {
    final db = await instance.database;
    return await db.insert('catch_media', map);
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

  // TRIP MEDIA
  Future<int> insertTripMedia(TripMedia media) async {
    final db = await instance.database;
    return await db.insert('trip_media', media.toMap());
  }

  Future<int> insertTripMediaFromMap(Map<String, dynamic> map) async {
    final db = await instance.database;
    return await db.insert('trip_media', map);
  }

  Future<List<TripMedia>> getMediaForTrip(int tripId) async {
    final db = await instance.database;
    final result = await db.query(
      'trip_media',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'created_at DESC',
    );
    return result.map((json) => TripMedia.fromMap(json)).toList();
  }

  Future<TripMedia?> getPrimaryMediaForTrip(int tripId) async {
    final db = await instance.database;
    final result = await db.query(
      'trip_media',
      where: 'trip_id = ? AND role = ?',
      whereArgs: [tripId, 'primary'],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return TripMedia.fromMap(result.first);
  }

  Future<TripMedia?> getCoverMediaForTrip(int tripId) async {
    final db = await instance.database;
    final result = await db.query(
      'trip_media',
      where: 'trip_id = ? AND (role = ? OR role = ?)',
      whereArgs: [tripId, 'primary', 'cover'],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return TripMedia.fromMap(result.first);
  }

  Future<int> updateTripMedia(TripMedia media) async {
    final db = await instance.database;
    return await db.update(
      'trip_media',
      media.toMap(),
      where: 'id = ?',
      whereArgs: [media.id],
    );
  }

  Future<int> deleteTripMedia(int id) async {
    final db = await instance.database;
    return await db.delete(
      'trip_media',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAllMediaForTrip(int tripId) async {
    final db = await instance.database;
    return await db.delete(
      'trip_media',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
  }

  Future<int> setPrimaryTripMedia(int mediaId) async {
    final db = await instance.database;
    // First, get the media item to find its trip_id
    final mediaResult = await db.query(
      'trip_media',
      where: 'id = ?',
      whereArgs: [mediaId],
      limit: 1,
    );
    if (mediaResult.isEmpty) return 0;
    
    final tripId = mediaResult.first['trip_id'] as int;
    
    // Remove primary role from all media for this trip
    await db.update(
      'trip_media',
      {'role': 'other'},
      where: 'trip_id = ? AND role = ?',
      whereArgs: [tripId, 'primary'],
    );
    
    // Set the new primary
    return await db.update(
      'trip_media',
      {'role': 'primary'},
      where: 'id = ?',
      whereArgs: [mediaId],
    );
  }

  // TRIP JOURNAL CRUD
  Future<int> insertTripJournal(TripJournal journal) async {
    final db = await instance.database;
    final id = await db.insert('trip_journal', journal.toMap());
    
    // Evaluate achievements
    await AchievementService().evaluateJournalAchievements();
    
    return id;
  }

  Future<int> insertTripJournalFromMap(Map<String, dynamic> map) async {
    final db = await instance.database;
    return await db.insert('trip_journal', map);
  }

  Future<List<TripJournal>> getJournalForTrip(int tripId) async {
    final db = await instance.database;
    final result = await db.query(
      'trip_journal',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'journal_date_time DESC',
    );
    return result.map((json) => TripJournal.fromMap(json)).toList();
  }

  Future<List<TripJournal>> searchJournalForTrip(int tripId, String query) async {
    final db = await instance.database;
    final result = await db.query(
      'trip_journal',
      where: 'trip_id = ? AND (title LIKE ? OR entry_text LIKE ?)',
      whereArgs: [tripId, '%$query%', '%$query%'],
      orderBy: 'journal_date_time DESC',
    );
    return result.map((json) => TripJournal.fromMap(json)).toList();
  }

  Future<TripJournal?> getTripJournal(int id) async {
    final db = await instance.database;
    final result = await db.query(
      'trip_journal',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return TripJournal.fromMap(result.first);
  }

  Future<int> updateTripJournal(TripJournal journal) async {
    final db = await instance.database;
    return await db.update(
      'trip_journal',
      journal.toMap(),
      where: 'id = ?',
      whereArgs: [journal.id],
    );
  }

  Future<int> deleteTripJournal(int id) async {
    final db = await instance.database;
    return await db.delete(
      'trip_journal',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAllJournalForTrip(int tripId) async {
    final db = await instance.database;
    return await db.delete(
      'trip_journal',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
  }

  Future<int> getJournalCountForTrip(int tripId) async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM trip_journal WHERE trip_id = ?',
      [tripId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<TripJournal?> getMostRecentJournalForTrip(int tripId) async {
    final db = await instance.database;
    final result = await db.query(
      'trip_journal',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'journal_date_time DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return TripJournal.fromMap(result.first);
  }

  // JOURNAL MEDIA CRUD
  Future<int> insertJournalMedia(JournalMedia media) async {
    final db = await instance.database;
    return await db.insert('journal_media', media.toMap());
  }

  Future<int> insertJournalMediaFromMap(Map<String, dynamic> map) async {
    final db = await instance.database;
    return await db.insert('journal_media', map);
  }

  Future<List<JournalMedia>> getMediaForJournalEntry(int journalEntryId) async {
    final db = await instance.database;
    final result = await db.query(
      'journal_media',
      where: 'journal_entry_id = ?',
      whereArgs: [journalEntryId],
      orderBy: 'created_at DESC',
    );
    return result.map((json) => JournalMedia.fromMap(json)).toList();
  }

  Future<JournalMedia?> getPrimaryMediaForJournalEntry(int journalEntryId) async {
    final db = await instance.database;
    final result = await db.query(
      'journal_media',
      where: 'journal_entry_id = ? AND is_primary = ?',
      whereArgs: [journalEntryId, 1],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return JournalMedia.fromMap(result.first);
  }

  Future<int> updateJournalMedia(JournalMedia media) async {
    final db = await instance.database;
    return await db.update(
      'journal_media',
      media.toMap(),
      where: 'id = ?',
      whereArgs: [media.id],
    );
  }

  Future<int> deleteJournalMedia(int id) async {
    final db = await instance.database;
    return await db.delete(
      'journal_media',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAllMediaForJournalEntry(int journalEntryId) async {
    final db = await instance.database;
    return await db.delete(
      'journal_media',
      where: 'journal_entry_id = ?',
      whereArgs: [journalEntryId],
    );
  }

  Future<int> setPrimaryJournalMedia(int mediaId) async {
    final db = await instance.database;
    // First, get the media item to find its journal_entry_id
    final mediaResult = await db.query(
      'journal_media',
      where: 'id = ?',
      whereArgs: [mediaId],
      limit: 1,
    );
    if (mediaResult.isEmpty) return 0;
    
    final journalEntryId = mediaResult.first['journal_entry_id'] as int;
    
    // Remove primary flag from all media for this journal entry
    await db.update(
      'journal_media',
      {'is_primary': 0},
      where: 'journal_entry_id = ? AND is_primary = ?',
      whereArgs: [journalEntryId, 1],
    );
    
    // Set the new primary
    return await db.update(
      'journal_media',
      {'is_primary': 1},
      where: 'id = ?',
      whereArgs: [mediaId],
    );
  }

  // FISHING TRIP CRUD
  Future<int> insertFishingTrip(FishingTrip trip) async {
    final db = await instance.database;
    final id = await db.insert('fishing_trips', trip.toMap());
    
    // Evaluate achievements
    await AchievementService().evaluateTripAchievements();
    
    return id;
  }

  Future<int> insertFishingTripFromMap(Map<String, dynamic> map) async {
    final db = await instance.database;
    return await db.insert('fishing_trips', map);
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

  Future<int> deleteAllCatches() async {
    final db = await instance.database;
    return await db.delete('catches');
  }

  Future<int> deleteAllFishingTrips() async {
    final db = await instance.database;
    return await db.delete('fishing_trips');
  }
}