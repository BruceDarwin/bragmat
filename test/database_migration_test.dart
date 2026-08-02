import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:path/path.dart';
import 'dart:io';

void main() {
  // Initialize FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Database Migration v27 to v28', () {
    late Database db;
    late String dbPath;

    setUp(() async {
      // Create a temporary database file
      final tempDir = Directory.systemTemp;
      dbPath = join(tempDir.path, 'test_bragmat_v27.db');
      
      // Delete if exists
      if (File(dbPath).existsSync()) {
        File(dbPath).deleteSync();
      }

      // Create version 27 database schema
      db = await openDatabase(
        dbPath,
        version: 27,
        onCreate: (Database db, int version) async {
          // Create catches table (simplified for test)
          await db.execute('''
            CREATE TABLE catches (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              fish_type TEXT,
              date_time TEXT NOT NULL,
              latitude REAL,
              longitude REAL
            )
          ''');

          // Create environmental_conditions table (version 27 schema)
          await db.execute('''
            CREATE TABLE environmental_conditions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              catch_id INTEGER,
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
              updated_at TEXT NOT NULL
            )
          ''');

          // Create tide_cache table (version 27 schema)
          await db.execute('''
            CREATE TABLE tide_cache (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              latitude REAL NOT NULL,
              longitude REAL NOT NULL,
              date TEXT NOT NULL,
              datum TEXT NOT NULL DEFAULT 'CD',
              extremes_json TEXT NOT NULL,
              cached_at TEXT NOT NULL,
              expires_at TEXT NOT NULL,
              UNIQUE(latitude, longitude, date, datum)
            )
          ''');
        },
      );

      // Insert test data
      await db.insert('catches', {
        'fish_type': 'Barramundi',
        'date_time': DateTime(2026, 8, 1, 10, 0).toIso8601String(),
        'latitude': -12.4634,
        'longitude': 130.8456,
      });

      await db.insert('environmental_conditions', {
        'catch_id': 1,
        'observation_date_time': DateTime(2026, 8, 1, 10, 0).toIso8601String(),
        'latitude': -12.4634,
        'longitude': 130.8456,
        'tide_context_phrase': '2 hr 15 min before the nearest high tide of 6.50 m at 3:45 PM',
        'tide_context_data_source': 'WorldTides',
        'tide_station_name': null,
        'tide_station_distance_km': null,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      await db.insert('tide_cache', {
        'latitude': -12.4634,
        'longitude': 130.8456,
        'date': '2026-08-01',
        'datum': 'CD',
        'extremes_json': '[{"dt": 1785602016, "height": 1.278, "type": "Low"}]',
        'cached_at': DateTime.now().toIso8601String(),
        'expires_at': DateTime.now().add(Duration(days: 7)).toIso8601String(),
      });

      // Close database to simulate fresh open
      await db.close();
    });

    tearDown(() async {
      await db.close();
      if (File(dbPath).existsSync()) {
        File(dbPath).deleteSync();
      }
    });

    test('Migration from v27 to v28 succeeds', () async {
      // Reopen database with version 28
      db = await openDatabase(
        dbPath,
        version: 28,
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 28) {
            // Add tide reference and WorldTides source metadata to environmental_conditions
            final tideReferenceColumns = [
              'tide_reference_mode TEXT',
              'tide_reference_name TEXT',
              'tide_request_lat REAL',
              'tide_request_lon REAL',
              'worldtides_station TEXT',
              'worldtides_atlas TEXT',
              'worldtides_response_lat REAL',
              'worldtides_response_lon REAL',
            ];
            
            for (final column in tideReferenceColumns) {
              try {
                await db.execute('ALTER TABLE environmental_conditions ADD COLUMN $column');
              } catch (e) {
                // Column might already exist
              }
            }
            
            // Add WorldTides metadata to tide_cache
            final tideCacheColumns = [
              'worldtides_station TEXT',
              'worldtides_atlas TEXT',
              'worldtides_response_lat REAL',
              'worldtides_response_lon REAL',
            ];
            
            for (final column in tideCacheColumns) {
              try {
                await db.execute('ALTER TABLE tide_cache ADD COLUMN $column');
              } catch (e) {
                // Column might already exist
              }
            }
          }
        },
      );

      // Verify migration succeeded
      expect(db.isOpen, true);
    });

    test('Existing records are preserved after migration', () async {
      // Reopen with migration
      db = await openDatabase(
        dbPath,
        version: 28,
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 28) {
            final tideReferenceColumns = [
              'tide_reference_mode TEXT',
              'tide_reference_name TEXT',
              'tide_request_lat REAL',
              'tide_request_lon REAL',
              'worldtides_station TEXT',
              'worldtides_atlas TEXT',
              'worldtides_response_lat REAL',
              'worldtides_response_lon REAL',
            ];
            
            for (final column in tideReferenceColumns) {
              try {
                await db.execute('ALTER TABLE environmental_conditions ADD COLUMN $column');
              } catch (e) {}
            }
            
            final tideCacheColumns = [
              'worldtides_station TEXT',
              'worldtides_atlas TEXT',
              'worldtides_response_lat REAL',
              'worldtides_response_lon REAL',
            ];
            
            for (final column in tideCacheColumns) {
              try {
                await db.execute('ALTER TABLE tide_cache ADD COLUMN $column');
              } catch (e) {}
            }
          }
        },
      );

      // Verify catch record preserved
      final catches = await db.query('catches');
      expect(catches.length, 1);
      expect(catches.first['fish_type'], 'Barramundi');
      expect(catches.first['latitude'], -12.4634);

      // Verify environmental_conditions record preserved
      final envConditions = await db.query('environmental_conditions');
      expect(envConditions.length, 1);
      expect(envConditions.first['tide_context_phrase'], '2 hr 15 min before the nearest high tide of 6.50 m at 3:45 PM');
      expect(envConditions.first['tide_context_data_source'], 'WorldTides');

      // Verify tide_cache record preserved
      final tideCache = await db.query('tide_cache');
      expect(tideCache.length, 1);
      expect(tideCache.first['latitude'], -12.4634);
    });

    test('New columns exist and contain NULL for historical data', () async {
      // Reopen with migration
      db = await openDatabase(
        dbPath,
        version: 28,
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 28) {
            final tideReferenceColumns = [
              'tide_reference_mode TEXT',
              'tide_reference_name TEXT',
              'tide_request_lat REAL',
              'tide_request_lon REAL',
              'worldtides_station TEXT',
              'worldtides_atlas TEXT',
              'worldtides_response_lat REAL',
              'worldtides_response_lon REAL',
            ];
            
            for (final column in tideReferenceColumns) {
              try {
                await db.execute('ALTER TABLE environmental_conditions ADD COLUMN $column');
              } catch (e) {}
            }
            
            final tideCacheColumns = [
              'worldtides_station TEXT',
              'worldtides_atlas TEXT',
              'worldtides_response_lat REAL',
              'worldtides_response_lon REAL',
            ];
            
            for (final column in tideCacheColumns) {
              try {
                await db.execute('ALTER TABLE tide_cache ADD COLUMN $column');
              } catch (e) {}
            }
          }
        },
      );

      // Check environmental_conditions new columns
      final envConditions = await db.query('environmental_conditions');
      final envRecord = envConditions.first;

      expect(envRecord.containsKey('tide_reference_mode'), true);
      expect(envRecord['tide_reference_mode'], null);

      expect(envRecord.containsKey('tide_reference_name'), true);
      expect(envRecord['tide_reference_name'], null);

      expect(envRecord.containsKey('tide_request_lat'), true);
      expect(envRecord['tide_request_lat'], null);

      expect(envRecord.containsKey('tide_request_lon'), true);
      expect(envRecord['tide_request_lon'], null);

      expect(envRecord.containsKey('worldtides_station'), true);
      expect(envRecord['worldtides_station'], null);

      expect(envRecord.containsKey('worldtides_atlas'), true);
      expect(envRecord['worldtides_atlas'], null);

      expect(envRecord.containsKey('worldtides_response_lat'), true);
      expect(envRecord['worldtides_response_lat'], null);

      expect(envRecord.containsKey('worldtides_response_lon'), true);
      expect(envRecord['worldtides_response_lon'], null);

      // Check tide_cache new columns
      final tideCache = await db.query('tide_cache');
      final cacheRecord = tideCache.first;

      expect(cacheRecord.containsKey('worldtides_station'), true);
      expect(cacheRecord['worldtides_station'], null);

      expect(cacheRecord.containsKey('worldtides_atlas'), true);
      expect(cacheRecord['worldtides_atlas'], null);

      expect(cacheRecord.containsKey('worldtides_response_lat'), true);
      expect(cacheRecord['worldtides_response_lat'], null);

      expect(cacheRecord.containsKey('worldtides_response_lon'), true);
      expect(cacheRecord['worldtides_response_lon'], null);
    });
  });
}
