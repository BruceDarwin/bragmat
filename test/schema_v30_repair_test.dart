// Schema v30 repair-migration test matrix.
//
// Covers docs/schema-v30-implementation-plan.md §5:
//   T1  v28-born parity: drifted v28 _createDB → real upgrade 28→30
//       reaches full-schema parity with a fresh v30 install
//   T2  v27→30 chain parity (v27 _createDB is identical to v28's)
//   T3  v1→30 full-chain parity
//   T4  idempotency: repair twice / applied to a healthy database
//   T5  data preservation across the repair
//   T6  writable-after-repair (new columns accept writes)
//   T7  rollback on injected failure — user_version stays 28, retry works
//   T8  fresh v30 install equals repaired databases
//   T9  restored drifted backup path (upgradeDatabase on a staged file)
//   T10 widened parity: ALL tables, indexes, triggers via PRAGMA dumps

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bragmat/database/database_helper.dart';

/// The genuine v28 `_createDB`, extracted verbatim from the v28 commit
/// (2b7c132 "Added Tide Station function"). The v27 _createDB body is
/// identical — both are missing the tide_cache table, the eight
/// tide-reference/WorldTides columns on environmental_conditions, and the
/// five lure/bait columns on catches.
Future<void> _createDriftedV28Schema(Database db) async {
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
  await db.insert('fish_types', {'name': 'Barramundi'});
  await db.insert('fish_types', {'name': 'Mangrove Jack'});
  await db.insert('fish_types', {'name': 'Saratoga'});
  await db.insert('fish_types', {'name': 'Jewfish'});
  await db.insert('fish_types', {'name': 'Queenfish'});
  await db.insert('fishing_buddies', {'name': 'Me'});
}

/// The genuine v1 `_createDB` (initial commit cc91aaf).
Future<void> _createV1Schema(Database db) async {
  await db.execute('''
    CREATE TABLE catches (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      fish_type TEXT,
      length_cm INTEGER,
      notes TEXT,
      created_at TEXT
    )
  ''');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('schema_v30_');
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

  /// Create a database file at [version] using [onCreate], close it, and
  /// return its path — a faithful on-disk historical database.
  Future<String> makeHistoricalDb(String name, int version,
      Future<void> Function(Database) onCreate,
      {Future<void> Function(Database)? afterCreate}) async {
    final path = p.join(testDir.path, name);
    final db = await openDatabase(path, version: version,
        onCreate: (db, v) => onCreate(db));
    if (afterCreate != null) await afterCreate(db);
    await db.close();
    return path;
  }

  /// Open [path] through the real production upgrade path (version 30,
  /// _createDB/_onUpgrade inside sqflite's upgrade transaction).
  Future<Database> openViaProduction(String path) async {
    DatabaseHelper.setTestDatabasePath(path);
    return DatabaseHelper.instance.systemDatabase;
  }

  Future<Database> openFreshV30(String path) => openViaProduction(path);

  /// Full schema snapshot: every user table's columns
  /// (name|type|notnull|default|pk) plus its indexes (name|unique), and
  /// every trigger/view definition. Column order is deliberately ignored.
  Future<Map<String, Set<String>>> schemaSnapshot(Database db) async {
    final snapshot = <String, Set<String>>{};
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' "
        'ORDER BY name');
    for (final t in tables) {
      final name = t['name'] as String;
      final cols = (await db.rawQuery('PRAGMA table_info("$name")'))
          .map((c) =>
              'col:${c['name']}|${c['type']}|${c['notnull']}|'
              '${c['dflt_value']}|${c['pk']}')
          .toSet();
      final indexes = (await db.rawQuery('PRAGMA index_list("$name")'))
          .map((i) =>
              'idx:${(i['name'] as String).replaceAll(RegExp(r'_\d+$'), '')}'
              '|${i['unique']}')
          .toSet();
      snapshot[name] = {...cols, ...indexes};
    }
    final others = await db.rawQuery(
        "SELECT name, sql FROM sqlite_master "
        "WHERE type IN ('trigger','view') ORDER BY name");
    snapshot[r'$triggers_views'] = others
        .map((r) =>
            '${r['name']}|${(r['sql'] as String).replaceAll(RegExp(r'\\s+'), ' ')}')
        .toSet();
    return snapshot;
  }

  /// Assert full parity of [actual] against a fresh v30 database.
  /// Snapshots [actual] first because the fresh database is opened
  /// through the same DatabaseHelper singleton.
  Future<void> expectFreshParity(Database actual) async {
    final actualSnapshot = await schemaSnapshot(actual);
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();

    final fresh = await openFreshV30(p.join(testDir.path, 'fresh_v30.db'));
    final freshSnapshot = await schemaSnapshot(fresh);
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();

    expect(actualSnapshot.keys.toSet(), freshSnapshot.keys.toSet(),
        reason: 'table/trigger/view names differ');
    for (final name in freshSnapshot.keys) {
      expect(actualSnapshot[name], freshSnapshot[name],
          reason: 'schema objects differ on $name');
    }
  }

  Future<int> userVersion(String path) async {
    // singleInstance: false — a default open would return (and then
    // close) the DatabaseHelper's shared handle for the same path.
    final db = await openDatabase(path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    final v = (await db.rawQuery('PRAGMA user_version')).first.values.first;
    await db.close();
    return v as int;
  }

  group('v30 repair migration', () {
    test('T1: drifted v28-born database reaches full v30 parity', () async {
      final path = await makeHistoricalDb('v28.db', 28, _createDriftedV28Schema);
      expect(await userVersion(path), 28);

      final db = await openViaProduction(path);
      expect(await userVersion(path), 30);
      await expectFreshParity(db);
    });

    test('T2: v27→30 chain reaches full parity', () async {
      final path = await makeHistoricalDb('v27.db', 27, _createDriftedV28Schema);
      final db = await openViaProduction(path);
      expect(await userVersion(path), 30);
      await expectFreshParity(db);
    });

    test('T3: v1→30 full chain reaches full parity', () async {
      final path = await makeHistoricalDb('v1.db', 1, _createV1Schema);
      final db = await openViaProduction(path);
      expect(await userVersion(path), 30);
      await expectFreshParity(db);
    });

    test('T4: repair is idempotent and a no-op on healthy databases',
        () async {
      final path = await makeHistoricalDb('v28b.db', 28, _createDriftedV28Schema);
      final db = await openViaProduction(path);
      final first = await schemaSnapshot(db);

      // Second repair run on the already-repaired handle: must be a no-op.
      await DatabaseHelper.instance.upgradeDatabase(db, 29, 30);
      expect(await schemaSnapshot(db), first);
      await DatabaseHelper.instance.closeDatabase();
      DatabaseHelper.clearTestDatabasePath();

      // Repair applied to a healthy fresh v30 DB: no errors, unchanged.
      final healthy = await openFreshV30(
          p.join(testDir.path, 'healthy.db'));
      final healthyBefore = await schemaSnapshot(healthy);
      await DatabaseHelper.instance.upgradeDatabase(healthy, 29, 30);
      expect(await schemaSnapshot(healthy), healthyBefore);
    });

    test('T5: existing rows survive the repair untouched', () async {
      final path = await makeHistoricalDb('v28data.db', 28, _createDriftedV28Schema,
          afterCreate: (db) async {
        await db.insert('catches', {
          'fish_type': 'Barramundi',
          'length_cm': 62,
          'created_at': '2026-06-01T08:00:00.000',
          'date_caught': '2026-06-01T08:00:00.000',
          'latitude': -12.4,
          'longitude': 130.8,
        });
        await db.insert('environmental_conditions', {
          'catch_id': 1,
          'observation_date_time': '2026-06-01T08:00:00.000',
          'latitude': -12.4,
          'longitude': 130.8,
          'tide_stage': 'Rising',
          'created_at': '2026-06-01T08:00:00.000',
          'updated_at': '2026-06-01T08:00:00.000',
        });
      });

      final db = await openViaProduction(path);

      final catches = await db.query('catches');
      expect(catches, hasLength(1));
      expect(catches.first['fish_type'], 'Barramundi');
      expect(catches.first['latitude'], -12.4);

      final env = await db.query('environmental_conditions');
      expect(env, hasLength(1));
      expect(env.first['tide_stage'], 'Rising');
    });

    test('T6: repaired columns are writable', () async {
      final path = await makeHistoricalDb('v28w.db', 28, _createDriftedV28Schema);
      final db = await openViaProduction(path);

      final catchId = await db.insert('catches', {
        'fish_type': 'Jewfish',
        'lure_id': 3,
        'lure_size': '90mm',
        'created_at': '2026-10-01T09:00:00.000',
      });
      final row = (await db
              .query('catches', where: 'id = ?', whereArgs: [catchId]))
          .first;
      expect(row['lure_id'], 3);
      expect(row['lure_size'], '90mm');

      final envId = await db.insert('environmental_conditions', {
        'catch_id': catchId,
        'observation_date_time': '2026-10-01T09:00:00.000',
        'tide_reference_mode': 'fixed',
        'tide_reference_name': 'Darwin',
        'worldtides_station': 'Darwin',
        'created_at': '2026-10-01T09:00:00.000',
        'updated_at': '2026-10-01T09:00:00.000',
      });
      final env = (await db.query('environmental_conditions',
              where: 'id = ?', whereArgs: [envId]))
          .first;
      expect(env['tide_reference_name'], 'Darwin');
      expect(env['worldtides_station'], 'Darwin');
    });

    test('T7: injected failure rolls back and a retry succeeds', () async {
      // Sabotage: a view named tide_cache makes the index creation fail
      // mid-repair (CREATE INDEX on a view is illegal).
      final path = await makeHistoricalDb('v28fail.db', 28, _createDriftedV28Schema,
          afterCreate: (db) async {
        await db.execute('CREATE VIEW tide_cache AS SELECT 1 AS stub');
      });

      DatabaseHelper.setTestDatabasePath(path);
      await expectLater(
          DatabaseHelper.instance.systemDatabase, throwsA(anything));
      DatabaseHelper.clearTestDatabasePath();

      // The failed upgrade left the file at v28 — nothing half-applied.
      expect(await userVersion(path), 28);
      final probe = await openDatabase(path);
      expect(
          (await probe.rawQuery("PRAGMA table_info(environmental_conditions)"))
              .any((c) => c['name'] == 'tide_reference_mode'),
          isFalse);
      // Drop the sabotage, then the real upgrade completes the repair.
      await probe.execute('DROP VIEW tide_cache');
      await probe.close();

      final db = await openViaProduction(path);
      expect(await userVersion(path), 30);
      await expectFreshParity(db);
    });

    test('T9: restore-pipeline upgrade of a staged drifted file reaches '
        'parity', () async {
      // Mirrors the restore path: a staged backup file is upgraded in
      // place through upgradeDatabase before promotion.
      final path = await makeHistoricalDb('staged.db', 28, _createDriftedV28Schema);
      final staged = await openDatabase(path);
      await DatabaseHelper.instance.upgradeDatabase(staged, 28, 30);
      await expectFreshParity(staged);
      await staged.close();
    });

    test('missing core table fails closed instead of fabricating data',
        () async {
      // A v28-stamped database without environmental_conditions is not
      // legitimate drift — the table has existed since v18. The repair
      // must abort the whole upgrade transaction, not create an empty
      // replacement that masks data loss.
      final path = p.join(testDir.path, 'corrupt.db');
      final db = await openDatabase(path, version: 28,
          onCreate: (db, _) async {
        await db.execute(
            'CREATE TABLE catches (id INTEGER PRIMARY KEY AUTOINCREMENT,'
            ' fish_type TEXT)');
      });
      await db.close();

      DatabaseHelper.setTestDatabasePath(path);
      await expectLater(
          DatabaseHelper.instance.systemDatabase, throwsA(anything));
      DatabaseHelper.clearTestDatabasePath();

      // The failed upgrade left the file untouched at v28.
      expect(await userVersion(path), 28);
    });

    test('partial tide_cache is topped up to parity', () async {
      // Theoretical: a drifted DB that somehow already has a bare
      // tide_cache without the WorldTides columns.
      final path = await makeHistoricalDb('v28partial.db', 28, _createDriftedV28Schema,
          afterCreate: (db) async {
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
      });

      final db = await openViaProduction(path);
      await expectFreshParity(db);
    });
  });
}
