// Schema parity: a database freshly created at v29 must expose the same
// table columns as a database upgraded to v29 through the real
// _onUpgrade chain. Guards against onCreate/onUpgrade drift (the class
// of defect that left fresh installs missing the v28 tide-reference
// columns).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/services/environmental_conditions_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('schema_parity_');
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    try {
      if (await testDir.exists()) await testDir.delete(recursive: true);
    } on PathAccessException {
      // Windows transient locks; OS cleans temp dirs.
    }
  });

  /// Columns of [table] as `name TYPE` strings, sorted.
  Future<List<String>> columnDefs(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final defs = rows
        .map((r) => '${r['name']} ${r['type']}')
        .toList()
      ..sort();
    return defs;
  }

  /// A faithful v27 database: environmental_conditions and tide_cache at
  /// their pre-v28 shape (i.e. fresh v29 minus the v28 tide-reference /
  /// WorldTides columns and the v29 uuid/owner_id columns).
  Future<Database> openV27Database(String dbPath) {
    return openDatabase(
      dbPath,
      version: 27,
      onCreate: (db, version) async {
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
            updated_at TEXT NOT NULL
          )
        ''');
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
  }

  Future<Database> openFreshV29(String dbPath) async {
    DatabaseHelper.setTestDatabasePath(dbPath);
    return DatabaseHelper.instance.systemDatabase;
  }

  group('v29 schema parity (fresh vs upgraded)', () {
    test('environmental_conditions columns match after real upgrade',
        () async {
      // Fresh v29.
      final fresh = await openFreshV29(
          path.join(testDir.path, 'fresh.db'));
      final freshCols = await columnDefs(fresh, 'environmental_conditions');
      await DatabaseHelper.instance.closeDatabase();
      DatabaseHelper.clearTestDatabasePath();

      // Upgraded: v27 DB, then the real _onUpgrade chain 27 -> 29.
      final upgraded = await openV27Database(
          path.join(testDir.path, 'upgraded.db'));
      await DatabaseHelper.instance.upgradeDatabase(upgraded, 27, 29);
      final upgradedCols =
          await columnDefs(upgraded, 'environmental_conditions');
      await upgraded.close();

      expect(upgradedCols, freshCols);
      // Spot-check the v28 additions that were missing from onCreate.
      expect(freshCols, containsAll([
        'tide_reference_mode TEXT',
        'tide_reference_name TEXT',
        'tide_request_lat REAL',
        'tide_request_lon REAL',
        'worldtides_station TEXT',
        'worldtides_atlas TEXT',
        'worldtides_response_lat REAL',
        'worldtides_response_lon REAL',
        'uuid TEXT',
        'owner_id TEXT',
      ]));
    });

    test('tide_cache columns match after real upgrade', () async {
      final fresh = await openFreshV29(path.join(testDir.path, 'fresh.db'));
      final freshCols = await columnDefs(fresh, 'tide_cache');
      await DatabaseHelper.instance.closeDatabase();
      DatabaseHelper.clearTestDatabasePath();

      final upgraded =
          await openV27Database(path.join(testDir.path, 'upgraded.db'));
      await DatabaseHelper.instance.upgradeDatabase(upgraded, 27, 29);
      final upgradedCols = await columnDefs(upgraded, 'tide_cache');
      await upgraded.close();

      expect(upgradedCols, freshCols);
      expect(freshCols, containsAll([
        'worldtides_station TEXT',
        'worldtides_atlas TEXT',
        'worldtides_response_lat REAL',
        'worldtides_response_lon REAL',
      ]));
    });

    test('environmental condition save succeeds on a clean v29 install',
        () async {
      await openFreshV29(path.join(testDir.path, 'fresh.db'));

      // The exact write path a fresh install executes on catch save —
      // this threw "no column named tide_reference_mode" before the
      // onCreate fix.
      final id = await EnvironmentalConditionsService()
          .saveEnvironmentalConditionForCatch(
        1,
        DateTime(2026, 10, 1, 9, 45),
        -33.8688,
        151.2093,
      );
      expect(id, greaterThan(0));

      final saved = await EnvironmentalConditionsService()
          .getEnvironmentalConditionForCatch(1);
      expect(saved, isNotNull);
      expect(saved!.latitude, closeTo(-33.8688, 1e-9));
    });
  });
}
