import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'dart:convert';

void main() {
  // Initialize FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Cache Integration Test', () {
    late Database db;
    late String dbPath;

    setUp(() async {
      // Create a temporary database file
      final tempDir = Directory.systemTemp;
      dbPath = join(tempDir.path, 'test_cache.db');
      
      // Delete if exists
      if (File(dbPath).existsSync()) {
        File(dbPath).deleteSync();
      }

      // Create version 28 database schema
      db = await openDatabase(
        dbPath,
        version: 28,
        onCreate: (Database db, int version) async {
          // Create tide_cache table (version 28 schema)
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
              worldtides_station TEXT,
              worldtides_atlas TEXT,
              worldtides_response_lat REAL,
              worldtides_response_lon REAL,
              UNIQUE(latitude, longitude, date, datum)
            )
          ''');

          // Create environmental_conditions table (version 28 schema)
          await db.execute('''
            CREATE TABLE environmental_conditions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              catch_id INTEGER,
              observation_date_time TEXT NOT NULL,
              latitude REAL,
              longitude REAL,
              tide_reference_mode TEXT,
              tide_reference_name TEXT,
              tide_request_lat REAL,
              tide_request_lon REAL,
              worldtides_station TEXT,
              worldtides_atlas TEXT,
              worldtides_response_lat REAL,
              worldtides_response_lon REAL,
              tide_context_phrase TEXT,
              tide_context_data_source TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        },
      );
    });

    tearDown(() async {
      await db.close();
      if (File(dbPath).existsSync()) {
        File(dbPath).deleteSync();
      }
    });

    test('Fresh WorldTides result stores metadata in tide_cache', () async {
      // Simulate a fresh WorldTides API response for Darwin
      final darwinExtremes = [
        {'dt': 1785602016, 'date': '2026-08-01T16:33+0000', 'height': 1.278, 'type': 'Low'},
        {'dt': 1785625290, 'date': '2026-08-01T23:01+0000', 'height': 7.054, 'type': 'High'},
      ];

      // Cache the result with metadata
      await db.insert(
        'tide_cache',
        {
          'latitude': -12.4634,
          'longitude': 130.8456,
          'date': '2026-08-01',
          'datum': 'CD',
          'extremes_json': jsonEncode(darwinExtremes),
          'cached_at': DateTime.now().toIso8601String(),
          'expires_at': DateTime.now().add(Duration(days: 7)).toIso8601String(),
          'worldtides_station': 'Darwin',
          'worldtides_atlas': 'Australia',
          'worldtides_response_lat': -12.4667,
          'worldtides_response_lon': 130.85,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Verify metadata was stored
      final cachedResults = await db.query('tide_cache');
      expect(cachedResults.length, 1);
      
      final cached = cachedResults.first;
      expect(cached['worldtides_station'], 'Darwin');
      expect(cached['worldtides_atlas'], 'Australia');
      expect(cached['worldtides_response_lat'], -12.4667);
      expect(cached['worldtides_response_lon'], 130.85);
    });

    test('Retrieval from tide_cache returns same metadata', () async {
      // Store cached data with metadata
      final dundeeExtremes = [
        {'dt': 1785600780, 'date': '2026-08-01T16:13+0000', 'height': 1.291, 'type': 'Low'},
        {'dt': 1785623250, 'date': '2026-08-01T22:27+0000', 'height': 6.454, 'type': 'High'},
      ];

      await db.insert(
        'tide_cache',
        {
          'latitude': -12.65,
          'longitude': 130.68,
          'date': '2026-08-01',
          'datum': 'CD',
          'extremes_json': jsonEncode(dundeeExtremes),
          'cached_at': DateTime.now().toIso8601String(),
          'expires_at': DateTime.now().add(Duration(days: 7)).toIso8601String(),
          'worldtides_station': null,
          'worldtides_atlas': 'FES2022',
          'worldtides_response_lat': -12.5,
          'worldtides_response_lon': 130.5,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Retrieve the cached data
      final cachedResults = await db.query(
        'tide_cache',
        where: 'latitude = ? AND longitude = ? AND date = ?',
        whereArgs: [-12.65, 130.68, '2026-08-01'],
      );

      expect(cachedResults.length, 1);
      
      final cached = cachedResults.first;
      expect(cached['worldtides_station'], null);
      expect(cached['worldtides_atlas'], 'FES2022');
      expect(cached['worldtides_response_lat'], -12.5);
      expect(cached['worldtides_response_lon'], 130.5);

      // Verify extremes are preserved
      final retrievedExtremes = jsonDecode(cached['extremes_json'] as String) as List;
      expect(retrievedExtremes.length, 2);
      expect(retrievedExtremes[0]['height'], 1.291);
    });

    test('Environmental record from cached data contains same fields as fresh API', () async {
      // Store cached data with metadata (simulating fresh API result)
      final extremes = [
        {'dt': 1785602016, 'date': '2026-08-01T16:33+0000', 'height': 1.278, 'type': 'Low'},
        {'dt': 1785625290, 'date': '2026-08-01T23:01+0000', 'height': 7.054, 'type': 'High'},
      ];

      await db.insert(
        'tide_cache',
        {
          'latitude': -12.4634,
          'longitude': 130.8456,
          'date': '2026-08-01',
          'datum': 'CD',
          'extremes_json': jsonEncode(extremes),
          'cached_at': DateTime.now().toIso8601String(),
          'expires_at': DateTime.now().add(Duration(days: 7)).toIso8601String(),
          'worldtides_station': 'Darwin',
          'worldtides_atlas': 'Australia',
          'worldtides_response_lat': -12.4667,
          'worldtides_response_lon': 130.85,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Retrieve cached data
      final cachedResults = await db.query(
        'tide_cache',
        where: 'latitude = ? AND longitude = ? AND date = ?',
        whereArgs: [-12.4634, 130.8456, '2026-08-01'],
      );

      final cached = cachedResults.first;

      // Create environmental_conditions record from cached data (simulating what the service does)
      await db.insert(
        'environmental_conditions',
        {
          'catch_id': 1,
          'observation_date_time': DateTime(2026, 8, 1, 10, 0).toIso8601String(),
          'latitude': -12.4634,
          'longitude': 130.8456,
          // Tide reference fields (from cached data)
          'tide_reference_mode': 'automatic',
          'tide_reference_name': null,
          'tide_request_lat': -12.4634,
          'tide_request_lon': 130.8456,
          // WorldTides source fields (from cached metadata)
          'worldtides_station': cached['worldtides_station'],
          'worldtides_atlas': cached['worldtides_atlas'],
          'worldtides_response_lat': cached['worldtides_response_lat'],
          'worldtides_response_lon': cached['worldtides_response_lon'],
          'tide_context_phrase': '2 hr 15 min before the Darwin high tide of 7.05 m at 11:01 PM',
          'tide_context_data_source': 'WorldTides',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      // Verify environmental record contains same metadata as cached data
      final envResults = await db.query('environmental_conditions');
      expect(envResults.length, 1);
      
      final env = envResults.first;
      expect(env['tide_reference_mode'], 'automatic');
      expect(env['tide_request_lat'], -12.4634);
      expect(env['tide_request_lon'], 130.8456);
      expect(env['worldtides_station'], 'Darwin');
      expect(env['worldtides_atlas'], 'Australia');
      expect(env['worldtides_response_lat'], -12.4667);
      expect(env['worldtides_response_lon'], 130.85);
    });

    test('Cached data with NULL metadata is handled correctly', () async {
      // Store cached data without station (like Dundee Beach)
      final extremes = [
        {'dt': 1785600780, 'date': '2026-08-01T16:13+0000', 'height': 1.291, 'type': 'Low'},
      ];

      await db.insert(
        'tide_cache',
        {
          'latitude': -12.65,
          'longitude': 130.68,
          'date': '2026-08-01',
          'datum': 'CD',
          'extremes_json': jsonEncode(extremes),
          'cached_at': DateTime.now().toIso8601String(),
          'expires_at': DateTime.now().add(Duration(days: 7)).toIso8601String(),
          'worldtides_station': null,
          'worldtides_atlas': 'FES2022',
          'worldtides_response_lat': -12.5,
          'worldtides_response_lon': 130.5,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Retrieve and create environmental record
      final cachedResults = await db.query('tide_cache');
      final cached = cachedResults.first;

      await db.insert(
        'environmental_conditions',
        {
          'catch_id': 2,
          'observation_date_time': DateTime(2026, 8, 1, 10, 0).toIso8601String(),
          'latitude': -12.65,
          'longitude': 130.68,
          'tide_reference_mode': 'automatic',
          'tide_request_lat': -12.65,
          'tide_request_lon': 130.68,
          'worldtides_station': cached['worldtides_station'],
          'worldtides_atlas': cached['worldtides_atlas'],
          'worldtides_response_lat': cached['worldtides_response_lat'],
          'worldtides_response_lon': cached['worldtides_response_lon'],
          'tide_context_phrase': '2 hr 15 min before the nearest high tide of 6.45 m at 10:27 PM',
          'tide_context_data_source': 'WorldTides',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      // Verify NULL values are preserved
      final envResults = await db.query('environmental_conditions');
      final env = envResults.last; // Get the second record
      
      expect(env['worldtides_station'], null);
      expect(env['worldtides_atlas'], 'FES2022');
      expect(env['worldtides_response_lat'], -12.5);
      expect(env['worldtides_response_lon'], 130.5);
    });
  });
}
