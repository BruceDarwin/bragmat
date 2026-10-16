// Schema v29 migration tests — upgrade path, fresh install, triggers,
// identity backfill, interruption recovery, idempotency and the
// bounded sync queue.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/database/migration_v29.dart';
import 'package:bragmat/services/ownership_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;
  late String dbPath;

  setUp(() async {
    testDir = Directory.systemTemp.createTempSync('bragmat_v29_test_');
    dbPath = path.join(testDir.path, 'bragmat.db');
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    DatabaseHelper.setDataAccessDenied(false);
    OwnershipService.invalidate();
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  /// Representative v28 schema — enough tables/columns to exercise the
  /// upgrade without duplicating the full _createDB.
  Future<void> createV28Database(String path,
      {int catchCount = 2, bool populate = true}) async {
    final db = await openDatabase(path, version: 28,
        onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE catches (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          fish_type TEXT, created_at TEXT, trip_id INTEGER,
          fishing_buddy_id INTEGER, lure_id INTEGER, bait_id INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE catch_media (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          catch_id INTEGER NOT NULL, file_path TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE fishing_trips (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, start_date TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE fishing_buddies (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE lures (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE favourite_spots (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, latitude REAL, longitude REAL
        )
      ''');
      await db.execute('''
        CREATE TABLE trip_journal (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          trip_id INTEGER NOT NULL, title TEXT NOT NULL,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE trip_media (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          trip_id INTEGER NOT NULL, file_path TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE journal_media (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          journal_entry_id INTEGER NOT NULL, file_path TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE environmental_conditions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          catch_id INTEGER, observation_date_time TEXT NOT NULL,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE user_achievements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          achievement_id TEXT NOT NULL, unlocked_date TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE baits (
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL
        )
      ''');
      if (populate) {
        for (var i = 0; i < catchCount; i++) {
          await db.insert('catches',
              {'fish_type': 'Fish $i', 'created_at': '2025-01-0$i'});
        }
        await db.insert('catch_media',
            {'catch_id': 1, 'file_path': 'catches/a.jpg',
             'created_at': '2025-01-01'});
        await db.insert('fishing_trips',
            {'name': 'Trip', 'start_date': '2025-01-01',
             'created_at': '2025-01-01'});
        await db.insert('fishing_buddies', {'name': 'Me'});
        await db.insert('lures', {'name': 'Spoon'});
        await db.insert('favourite_spots',
            {'name': 'Spot', 'latitude': 1.0, 'longitude': 2.0});
        await db.insert('trip_journal',
            {'trip_id': 1, 'title': 'Day 1', 'created_at': '2025-01-01',
             'updated_at': '2025-01-01'});
        await db.insert('trip_media',
            {'trip_id': 1, 'file_path': 'trips/t.jpg',
             'created_at': '2025-01-01'});
        await db.insert('journal_media',
            {'journal_entry_id': 1, 'file_path': 'journal/j.jpg',
             'created_at': '2025-01-01'});
        await db.insert('environmental_conditions',
            {'catch_id': 1, 'observation_date_time': '2025-01-01',
             'created_at': '2025-01-01', 'updated_at': '2025-01-01'});
        await db.insert('user_achievements',
            {'achievement_id': 'first-catch',
             'unlocked_date': '2025-01-01'});
        await db.insert('baits', {'name': 'Worm'});
      }
    });
    await db.close();
  }

  /// Open [dbPath] through DatabaseHelper (version 29 — triggers
  /// onUpgrade when the file is older).
  Future<Database> openLive() async {
    DatabaseHelper.setTestDatabasePath(dbPath);
    return DatabaseHelper.instance.systemDatabase;
  }

  Future<int> userVersion(Database db) async {
    final r = await db.rawQuery('PRAGMA user_version');
    return r.first.values.first as int;
  }

  Future<List<String>> triggerNames(Database db) async {
    final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger'");
    return rows.map((r) => r['name'] as String).toList();
  }

  group('v28 -> v29 upgrade', () {
    test('adds identity columns, preserves data, bumps version', () async {
      await createV28Database(dbPath);
      final db = await openLive();

      expect(await userVersion(db), 29);

      final catches = await db.query('catches');
      expect(catches.length, 2);
      expect(catches.first['fish_type'], 'Fish 0');
      for (final row in catches) {
        expect(row['uuid'], isNotNull);
        expect(row['owner_id'], isNull);
        expect(row['updated_at'], isNotNull);
      }
      final uuids = catches.map((r) => r['uuid']).toSet();
      expect(uuids.length, catches.length);

      for (final t in MigrationV29.userOwnedTables) {
        if (!await MigrationV29.tableExists(db, t)) continue;
        final cols = await db.rawQuery('PRAGMA table_info($t)');
        final names = cols.map((c) => c['name']).toSet();
        expect(names, containsAll(['uuid', 'owner_id', 'updated_at']),
            reason: '$t missing identity columns');
      }

      // Ownership + queue tables exist; unclaimed.
      expect(await MigrationV29.tableExists(db, 'local_account'), isTrue);
      expect(await MigrationV29.tableExists(db, 'sync_queue'), isTrue);
      expect(await OwnershipService.ownerIdFrom(db), isNull);

      // All four triggers installed on every one of the 12 tables.
      final triggers = await triggerNames(db);
      for (final t in MigrationV29.userOwnedTables) {
        for (final s in ['ai', 'touch', 'qu', 'qd']) {
          expect(triggers, contains('trg_${t}_$s'),
              reason: 'missing trg_${t}_$s');
        }
      }
    });

    test('identity triggers fire on all 12 user-owned tables', () async {
      await createV28Database(dbPath);
      final db = await openLive();
      await db.update('local_account', {'owner_id': 'user-A'},
          where: 'id = 1');

      const inserts = <String, Map<String, Object?>>{
        'catches': {'fish_type': 'x', 'created_at': 't'},
        'catch_media': {'catch_id': 1, 'file_path': 'x',
                        'created_at': 't'},
        'fishing_trips': {'name': 'x', 'start_date': 't',
                          'created_at': 't'},
        'trip_media': {'trip_id': 1, 'file_path': 'x',
                       'created_at': 't'},
        'trip_journal': {'trip_id': 1, 'title': 'x',
                         'created_at': 't', 'updated_at': 't'},
        'journal_media': {'journal_entry_id': 1, 'file_path': 'x',
                          'created_at': 't'},
        'favourite_spots': {'name': 'x'},
        'environmental_conditions': {
          'observation_date_time': 't', 'created_at': 't',
          'updated_at': 't'},
        'user_achievements': {'achievement_id': 'x',
                              'unlocked_date': 't'},
        'lures': {'name': 'x'},
        'baits': {'name': 'x'},
        'fishing_buddies': {'name': 'x'},
      };
      expect(inserts.keys.toSet(),
          MigrationV29.userOwnedTables.toSet());

      for (final t in MigrationV29.userOwnedTables) {
        final id = await db.insert(t, inserts[t]!);
        final row =
            (await db.query(t, where: 'id = ?', whereArgs: [id])).first;
        expect(row['uuid'], isNotNull, reason: '$t uuid not filled');
        expect(row['owner_id'], 'user-A',
            reason: '$t owner not stamped');
        expect(row['updated_at'], isNotNull,
            reason: '$t updated_at not filled');

        // Deletion writes a uuid-bearing tombstone.
        await db.delete(t, where: 'id = ?', whereArgs: [id]);
        final tomb = await db.query('sync_queue',
            where: "table_name = '$t' AND operation = 'delete' "
                'AND local_id = ?',
            whereArgs: [id]);
        expect(tomb.length, 1, reason: '$t delete tombstone missing');
        expect(tomb.first['record_uuid'], row['uuid']);
      }
    });

    test('uuid backfill produces distinct v4 uuids at scale', () async {
      await createV28Database(dbPath, catchCount: 200);
      final db = await openLive();
      final uuids = (await db.query('catches', columns: ['uuid']))
          .map((r) => r['uuid'] as String)
          .toSet();
      expect(uuids.length, 200);
      final v4 = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(uuids.every((u) => v4.hasMatch(u)), isTrue);
    });

    test('repeated migration is a no-op', () async {
      await createV28Database(dbPath);
      final db = await openLive();
      final before = (await db.query('catches'))
          .map((r) => r['uuid'])
          .toList();
      await MigrationV29.migrate(db); // run again directly
      final after = (await db.query('catches'))
          .map((r) => r['uuid'])
          .toList();
      expect(after, before);
    });

    test('interrupted migration leaves file at v28; retry completes',
        () async {
      await createV28Database(dbPath);

      // Simulate a crash inside the upgrade transaction.
      Database? failed;
      expect(() async {
        failed = await openDatabase(dbPath, version: 29,
            onUpgrade: (db, oldV, newV) async {
          await MigrationV29.migrate(db);
          throw StateError('simulated crash mid-migration');
        });
      }, throwsA(isA<StateError>()));
      await failed?.close();

      // File survived and reports the old version.
      final check = await openDatabase(dbPath, readOnly: true);
      expect(await userVersion(check), 28);
      await check.close();

      // Retry succeeds.
      final db = await openLive();
      expect(await userVersion(db), 29);
      expect((await db.query('catches')).length, 2);
    });
  });

  group('fresh v29 install', () {
    test('_createDB emits full schema incl. tide_cache + triggers',
        () async {
      final db = await openLive(); // no file -> _createDB runs
      expect(await userVersion(db), 29);
      for (final t in [
        'catches', 'catch_media', 'fishing_trips', 'trip_media',
        'trip_journal', 'journal_media', 'favourite_spots',
        'environmental_conditions', 'user_achievements', 'lures',
        'baits', 'fishing_buddies', 'fish_types', 'achievements',
        'tide_cache', 'local_account', 'sync_queue'
      ]) {
        expect(await MigrationV29.tableExists(db, t), isTrue,
            reason: '$t missing on fresh install');
      }
      final triggers = await triggerNames(db);
      expect(triggers.length,
          MigrationV29.userOwnedTables.length * 4);
    });
  });

  group('ownership triggers', () {
    setUp(() async {
      await createV28Database(dbPath);
    });

    test('insert fills uuid + updated_at; owner stays NULL unclaimed',
        () async {
      final db = await openLive();
      final id = await db
          .insert('catches', {'fish_type': 'New', 'created_at': 't'});
      final row = (await db
              .query('catches', where: 'id = ?', whereArgs: [id]))
          .first;
      expect(row['uuid'], isNotNull);
      expect(row['updated_at'], isNotNull);
      expect(row['owner_id'], isNull);
    });

    test('insert after owner set stamps owner_id', () async {
      final db = await openLive();
      await db.update('local_account', {'owner_id': 'user-A'},
          where: 'id = 1');
      final id = await db
          .insert('catches', {'fish_type': 'New', 'created_at': 't'});
      final row = (await db
              .query('catches', where: 'id = ?', whereArgs: [id]))
          .first;
      expect(row['owner_id'], 'user-A');
    });

    test('caller-supplied uuid and owner_id are preserved', () async {
      final db = await openLive();
      await db.update('local_account', {'owner_id': 'user-A'},
          where: 'id = 1');
      final id = await db.insert('catches', {
        'fish_type': 'New',
        'uuid': 'fixed-uuid-1234',
        'owner_id': 'other-owner',
      });
      final row = (await db
              .query('catches', where: 'id = ?', whereArgs: [id]))
          .first;
      expect(row['uuid'], 'fixed-uuid-1234');
      expect(row['owner_id'], 'other-owner');
    });

    test('update maintains updated_at and queues a change event',
        () async {
      final db = await openLive();
      final row = (await db.query('catches', where: 'id = 1')).first;
      final before = row['updated_at'] as String;
      await Future.delayed(const Duration(milliseconds: 20));
      await db.update('catches', {'fish_type': 'Changed'},
          where: 'id = 1');
      final after = (await db.query('catches', where: 'id = 1'))
          .first['updated_at'] as String;
      expect(after, isNot(before));

      final events = await db.query('sync_queue',
          where: "table_name = 'catches' AND local_id = 1");
      expect(events, isNotEmpty);
      expect(events.last['operation'], 'update');
      expect(events.last['record_uuid'], row['uuid']);
    });

    test('delete writes a uuid tombstone', () async {
      final db = await openLive();
      final uuid = (await db.query('catches', where: 'id = 1'))
          .first['uuid'];
      await db.delete('catches', where: 'id = 1');
      final tombstone = await db.query('sync_queue',
          where: "table_name = 'catches' AND operation = 'delete'");
      expect(tombstone.length, 1);
      expect(tombstone.first['record_uuid'], uuid);
    });
  });

  group('sync_queue', () {
    test('events recorded on insert/update/delete', () async {
      await createV28Database(dbPath);
      final db = await openLive();
      await db.insert('lures', {'name': 'New Lure'});
      final events = await db.query('sync_queue',
          where: "table_name = 'lures'");
      expect(events.any((e) => e['operation'] == 'insert'), isTrue);
    });

    test('compaction coalesces updates but keeps every tombstone',
        () async {
      await createV28Database(dbPath);
      final db = await openLive();
      // Generate several events for catch id=1.
      await db.update('catches', {'fish_type': 'A'}, where: 'id = 1');
      await db.update('catches', {'fish_type': 'B'}, where: 'id = 1');
      await db.delete('catches', where: 'id = 2');
      // A second record fully created and deleted.
      final newId = await db.insert('lures', {'name': 'Temp'});
      await db.delete('lures', where: 'id = ?', whereArgs: [newId]);
      final before = (await db.query('sync_queue')).length;
      expect(before, greaterThan(2));

      await MigrationV29.compactSyncQueue(db);
      final rows = await db.query('sync_queue');

      // Catch 1: superseded update events coalesced to the latest.
      final catch1 = rows
          .where((r) => r['table_name'] == 'catches' && r['local_id'] == 1)
          .toList();
      expect(catch1.length, 1);
      expect(catch1.single['operation'], 'update');

      // Both tombstones survive compaction unconditionally.
      final deletes =
          rows.where((r) => r['operation'] == 'delete').toList();
      expect(deletes.length, greaterThanOrEqualTo(2));
      expect(
          deletes.any((r) =>
              r['table_name'] == 'catches' && r['local_id'] == 2),
          isTrue);
      expect(
          deletes.any((r) =>
              r['table_name'] == 'lures' && r['local_id'] == newId),
          isTrue);
    });
  });

  group('orphan audit', () {
    test('reports dangling references', () async {
      await createV28Database(dbPath);
      final db = await openLive();
      // Insert a media row pointing at a nonexistent catch.
      await db.insert('catch_media',
          {'catch_id': 999, 'file_path': 'x.jpg', 'created_at': 't'});
      final findings = await MigrationV29.orphanAudit(db);
      expect(findings.any((f) => f.contains('catch_media.catch_id')),
          isTrue);
    });
  });
}
