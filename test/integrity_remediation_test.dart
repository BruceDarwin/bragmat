import 'dart:convert';
import 'dart:io';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/models/bait.dart';
import 'package:bragmat/models/lure.dart';
import 'package:bragmat/services/backup_service.dart';
import 'package:bragmat/services/media_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regression tests for the Phase A integrity remediation:
///   - deleteFishingTrip / deleteTripJournal remove dependents in one
///     transaction and quarantine newly unreferenced media files
///   - single-media deletes sweep their file the same way
///   - lure/bait deletes clear soft references; renames preserve them
///   - the legacy JSON restore remaps environmental-condition parents
/// Every test verifies PRAGMA foreign_key_check stays clean.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testDir = Directory.systemTemp.createTempSync('integrity_remed_');
    DatabaseHelper.setTestDatabasePath(p.join(testDir.path, 'bragmat.db'));
    MediaStorageService.setTestDirectory(testDir);
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    MediaStorageService.clearTestDirectory();
    try {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    } on PathAccessException {
      // Transient Windows file locks are fine — temp dirs are OS-cleaned.
    }
  });

  // ---------- seed helpers ----------

  Future<File> makeMediaFile(String relPath) async {
    final file = File(p.joinAll(
        [testDir.path, 'bragmat', 'media', ...relPath.split('/')]));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(8, 0x42));
    return file;
  }

  Future<int> insertTrip({String name = 'Trip'}) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('fishing_trips', {
      'name': name,
      'start_date': '2026-10-01T00:00:00.000',
      'created_at': '2026-10-01T00:00:00.000',
    });
  }

  Future<int> insertJournal(int tripId) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('trip_journal', {
      'trip_id': tripId,
      'journal_date_time': '2026-10-01T08:00:00.000',
      'title': 'Entry',
      'entry_text': 'text',
      'created_at': '2026-10-01T08:00:00.000',
      'updated_at': '2026-10-01T08:00:00.000',
    });
  }

  Future<int> insertTripMedia(int tripId, String relPath) async {
    await makeMediaFile(relPath);
    final db = await DatabaseHelper.instance.database;
    return db.insert('trip_media', {
      'trip_id': tripId,
      'file_path': relPath,
      'media_type': 'photo',
      'role': 'other',
      'created_at': '2026-10-01T08:00:00.000',
    });
  }

  Future<int> insertJournalMedia(int journalId, String relPath) async {
    await makeMediaFile(relPath);
    final db = await DatabaseHelper.instance.database;
    return db.insert('journal_media', {
      'journal_entry_id': journalId,
      'file_path': relPath,
      'media_type': 'photo',
      'created_at': '2026-10-01T08:00:00.000',
    });
  }

  Future<int> insertCatch({int? tripId}) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('catches', {
      'fish_type': 'Barramundi',
      'trip_id': tripId,
      'created_at': '2026-10-01T09:45:00.000',
    });
  }

  Future<int> insertCatchMedia(int catchId, String relPath,
      {bool makeFile = true}) async {
    if (makeFile) await makeMediaFile(relPath);
    final db = await DatabaseHelper.instance.database;
    return db.insert('catch_media', {
      'catch_id': catchId,
      'file_path': relPath,
      'media_type': 'photo',
      'role': 'primary',
      'created_at': '2026-10-01T09:45:00.000',
    });
  }

  Future<int> insertEnv({int? catchId, int? tripId}) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('environmental_conditions', {
      'catch_id': catchId,
      'trip_id': tripId,
      'observation_date_time': '2026-10-01T09:45:00.000',
      'created_at': '2026-10-01T09:45:00.000',
      'updated_at': '2026-10-01T09:45:00.000',
    });
  }

  // ---------- assertion helpers ----------

  Future<int> countWhere(
      String table, String column, Object? value) async {
    final db = await DatabaseHelper.instance.database;
    final r = value == null
        ? await db.rawQuery(
            'SELECT COUNT(*) AS n FROM $table WHERE $column IS NULL')
        : await db.rawQuery(
            'SELECT COUNT(*) AS n FROM $table WHERE $column = ?', [value]);
    return r.first['n'] as int;
  }

  Future<void> expectNoFkViolations() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('PRAGMA foreign_key_check');
    expect(rows, isEmpty,
        reason: 'foreign_key_check reported violations: $rows');
  }

  Future<bool> fileExists(String relPath) =>
      MediaStorageService.fileExists(relPath);

  Future<bool> inQuarantine(String relPath) async {
    final mediaDir = await MediaStorageService.getMediaDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 10)
        .replaceAll('-', '');
    return File(p.joinAll([
      mediaDir.parent.path,
      'quarantine',
      stamp,
      ...relPath.split('/')
    ])).exists();
  }

  // ---------- deleteFishingTrip ----------

  group('deleteFishingTrip', () {
    test('removes all dependents and produces no FK violations', () async {
      final trip = await insertTrip();
      final journal = await insertJournal(trip);
      await insertTripMedia(trip, 'trips/t${trip}_a.jpg');
      await insertJournalMedia(journal, 'journals/j${journal}_a.jpg');
      await insertEnv(tripId: trip);

      await DatabaseHelper.instance.deleteFishingTrip(trip);

      expect(await countWhere('fishing_trips', 'id', trip), 0);
      expect(await countWhere('trip_media', 'trip_id', trip), 0);
      expect(await countWhere('trip_journal', 'trip_id', trip), 0);
      expect(
          await countWhere('journal_media', 'journal_entry_id', journal), 0);
      expect(
          await countWhere('environmental_conditions', 'trip_id', trip), 0);
      await expectNoFkViolations();
    });

    test('detaches catches without deleting them', () async {
      final trip = await insertTrip();
      final catchId = await insertCatch(tripId: trip);

      await DatabaseHelper.instance.deleteFishingTrip(trip);

      expect(await countWhere('catches', 'id', catchId), 1);
      expect(await countWhere('catches', 'trip_id', null), greaterThan(0));
      final db = await DatabaseHelper.instance.database;
      final row = (await db
              .query('catches', where: 'id = ?', whereArgs: [catchId]))
          .first;
      expect(row['trip_id'], isNull);
      await expectNoFkViolations();
    });

    test('quarantines unreferenced trip and journal media files', () async {
      final trip = await insertTrip();
      final journal = await insertJournal(trip);
      final tripRel = 'trips/t${trip}_q.jpg';
      final jRel = 'journals/j${journal}_q.jpg';
      await insertTripMedia(trip, tripRel);
      await insertJournalMedia(journal, jRel);

      await DatabaseHelper.instance.deleteFishingTrip(trip);

      expect(await fileExists(tripRel), isFalse);
      expect(await fileExists(jRel), isFalse);
      expect(await inQuarantine(tripRel), isTrue);
      expect(await inQuarantine(jRel), isTrue);
    });

    test('preserves a file still referenced by a surviving catch_media row',
        () async {
      final trip = await insertTrip();
      final catchId = await insertCatch();
      const shared = 'trips/shared_with_catch.jpg';
      await insertTripMedia(trip, shared);
      await insertCatchMedia(catchId, shared, makeFile: false);

      await DatabaseHelper.instance.deleteFishingTrip(trip);

      expect(await fileExists(shared), isTrue);
      expect(await inQuarantine(shared), isFalse);
    });

    test('tolerates media rows whose files are already missing', () async {
      final trip = await insertTrip();
      final db = await DatabaseHelper.instance.database;
      await db.insert('trip_media', {
        'trip_id': trip,
        'file_path': 'trips/never_existed.jpg',
        'media_type': 'photo',
        'role': 'other',
        'created_at': '2026-10-01T08:00:00.000',
      });

      await DatabaseHelper.instance.deleteFishingTrip(trip);

      expect(await countWhere('fishing_trips', 'id', trip), 0);
      await expectNoFkViolations();
    });

    test('deleting a nonexistent trip is a harmless no-op', () async {
      await DatabaseHelper.instance.deleteFishingTrip(9999);
      await expectNoFkViolations();
    });

    test('a failed transaction removes no rows and touches no files',
        () async {
      final trip = await insertTrip();
      final journal = await insertJournal(trip);
      final rel = 'journals/j${journal}_txn.jpg';
      await insertJournalMedia(journal, rel);
      final catchId = await insertCatch(tripId: trip);

      // Inject a mid-transaction failure after catches are detached.
      final db = await DatabaseHelper.instance.database;
      await db.execute('''
        CREATE TRIGGER fail_journal_media_delete
        BEFORE DELETE ON journal_media
        BEGIN SELECT RAISE(ABORT, 'injected failure'); END
      ''');

      await expectLater(
          DatabaseHelper.instance.deleteFishingTrip(trip), throwsA(anything));

      // Everything rolled back — trip, journal, media, env, catch link.
      expect(await countWhere('fishing_trips', 'id', trip), 1);
      expect(await countWhere('trip_journal', 'id', journal), 1);
      expect(
          await countWhere('journal_media', 'journal_entry_id', journal), 1);
      final row = (await db
              .query('catches', where: 'id = ?', whereArgs: [catchId]))
          .first;
      expect(row['trip_id'], trip);
      expect(await fileExists(rel), isTrue);
      expect(await inQuarantine(rel), isFalse);
      await expectNoFkViolations();
    });
  });

  // ---------- deleteTripJournal ----------

  group('deleteTripJournal', () {
    test('removes journal_media and quarantines unreferenced files',
        () async {
      final trip = await insertTrip();
      final journal = await insertJournal(trip);
      final rel = 'journals/j${journal}_del.jpg';
      await insertJournalMedia(journal, rel);

      await DatabaseHelper.instance.deleteTripJournal(journal);

      expect(await countWhere('trip_journal', 'id', journal), 0);
      expect(
          await countWhere('journal_media', 'journal_entry_id', journal), 0);
      expect(await fileExists(rel), isFalse);
      expect(await inQuarantine(rel), isTrue);
      await expectNoFkViolations();
    });

    test('preserves a file still referenced by catch_media', () async {
      final trip = await insertTrip();
      final journal = await insertJournal(trip);
      final catchId = await insertCatch();
      const shared = 'journals/shared_j.jpg';
      await insertJournalMedia(journal, shared);
      await insertCatchMedia(catchId, shared, makeFile: false);

      await DatabaseHelper.instance.deleteTripJournal(journal);

      expect(await fileExists(shared), isTrue);
      await expectNoFkViolations();
    });

    test('a failed transaction removes no rows and touches no files',
        () async {
      final trip = await insertTrip();
      final journal = await insertJournal(trip);
      final rel = 'journals/j${journal}_txn.jpg';
      await insertJournalMedia(journal, rel);

      final db = await DatabaseHelper.instance.database;
      await db.execute('''
        CREATE TRIGGER fail_jm_delete BEFORE DELETE ON journal_media
        BEGIN SELECT RAISE(ABORT, 'injected failure'); END
      ''');

      await expectLater(
          DatabaseHelper.instance.deleteTripJournal(journal),
          throwsA(anything));

      expect(await countWhere('trip_journal', 'id', journal), 1);
      expect(
          await countWhere('journal_media', 'journal_entry_id', journal), 1);
      expect(await fileExists(rel), isTrue);
      await expectNoFkViolations();
    });
  });

  // ---------- single-media deletes ----------

  group('single-media deletes', () {
    test('deleteCatchMedia removes the row and quarantines the file',
        () async {
      final catchId = await insertCatch();
      final rel = 'catches/c${catchId}_single.jpg';
      final mediaId = await insertCatchMedia(catchId, rel);

      await DatabaseHelper.instance.deleteCatchMedia(mediaId);

      expect(await countWhere('catch_media', 'id', mediaId), 0);
      expect(await fileExists(rel), isFalse);
      expect(await inQuarantine(rel), isTrue);
    });

    test('deleteCatchMedia preserves a file referenced by another row',
        () async {
      final a = await insertCatch();
      final b = await insertCatch();
      const shared = 'catches/shared_sm.jpg';
      final mediaId = await insertCatchMedia(a, shared);
      await insertCatchMedia(b, shared, makeFile: false);

      await DatabaseHelper.instance.deleteCatchMedia(mediaId);

      expect(await fileExists(shared), isTrue);
    });

    test('deleteTripMedia removes the row and quarantines the file',
        () async {
      final trip = await insertTrip();
      final rel = 'trips/t${trip}_single.jpg';
      final mediaId = await insertTripMedia(trip, rel);

      await DatabaseHelper.instance.deleteTripMedia(mediaId);

      expect(await countWhere('trip_media', 'id', mediaId), 0);
      expect(await fileExists(rel), isFalse);
      expect(await inQuarantine(rel), isTrue);
    });

    test('deleteJournalMedia removes the row and quarantines the file',
        () async {
      final trip = await insertTrip();
      final journal = await insertJournal(trip);
      final rel = 'journals/j${journal}_single.jpg';
      final mediaId = await insertJournalMedia(journal, rel);

      await DatabaseHelper.instance.deleteJournalMedia(mediaId);

      expect(await countWhere('journal_media', 'id', mediaId), 0);
      expect(await fileExists(rel), isFalse);
      expect(await inQuarantine(rel), isTrue);
    });

    test('deleteCatchMedia tolerates a row whose file is already missing',
        () async {
      final catchId = await insertCatch();
      final mediaId =
          await insertCatchMedia(catchId, 'catches/gone.jpg',
              makeFile: false);

      await DatabaseHelper.instance.deleteCatchMedia(mediaId);

      expect(await countWhere('catch_media', 'id', mediaId), 0);
    });
  });

  // ---------- edit/resave sweep ----------

  group('catch edit resave media sweep', () {
    test('kept photos survive; removed photos are quarantined', () async {
      final catchId = await insertCatch();
      const kept = 'catches/kept.jpg';
      const removed = 'catches/removed.jpg';
      await insertCatchMedia(catchId, kept);
      await insertCatchMedia(catchId, removed);

      // Mirror the add_catch_screen resave: collect, wipe, re-add kept.
      final db = await DatabaseHelper.instance.database;
      final previous = (await db.query('catch_media',
              columns: ['file_path'],
              where: 'catch_id = ?',
              whereArgs: [catchId]))
          .map((r) => r['file_path'] as String)
          .toList();
      await DatabaseHelper.instance.deleteAllMediaForCatch(catchId);
      await insertCatchMedia(catchId, kept, makeFile: false);
      await DatabaseHelper.instance.quarantineUnreferencedMedia(previous);

      expect(await countWhere('catch_media', 'catch_id', catchId), 1);
      expect(await fileExists(kept), isTrue);
      expect(await fileExists(removed), isFalse);
      expect(await inQuarantine(removed), isTrue);
      await expectNoFkViolations();
    });
  });

  // ---------- lure / bait references ----------

  group('lure/bait reference handling', () {
    test('deleteLure clears lure_id on catches', () async {
      final db = await DatabaseHelper.instance.database;
      final lureId = await db.insert('lures', {'name': 'Soft Plastic'});
      final catchId = await db
          .insert('catches', {'fish_type': 'Barra', 'lure_id': lureId});

      await DatabaseHelper.instance.deleteLure(lureId);

      expect(await countWhere('lures', 'id', lureId), 0);
      final row = (await db
              .query('catches', where: 'id = ?', whereArgs: [catchId]))
          .first;
      expect(row['lure_id'], isNull);
      expect(await countWhere('catches', 'id', catchId), 1);
    });

    test('deleteBait clears bait_id on catches', () async {
      final db = await DatabaseHelper.instance.database;
      final baitId = await db.insert('baits', {'name': 'Mullet'});
      final catchId = await db
          .insert('catches', {'fish_type': 'Barra', 'bait_id': baitId});

      await DatabaseHelper.instance.deleteBait(baitId);

      expect(await countWhere('baits', 'id', baitId), 0);
      final row = (await db
              .query('catches', where: 'id = ?', whereArgs: [catchId]))
          .first;
      expect(row['bait_id'], isNull);
    });

    test('updateLure renames in place so references survive', () async {
      final db = await DatabaseHelper.instance.database;
      final lureId = await db.insert('lures', {'name': 'Old Name'});
      final catchId = await db
          .insert('catches', {'fish_type': 'Barra', 'lure_id': lureId});

      await DatabaseHelper.instance
          .updateLure(Lure(id: lureId, name: 'New Name'));

      final row = (await db
              .query('catches', where: 'id = ?', whereArgs: [catchId]))
          .first;
      expect(row['lure_id'], lureId);
      final lure =
          (await db.query('lures', where: 'id = ?', whereArgs: [lureId]))
              .first;
      expect(lure['name'], 'New Name');
    });

    test('updateBait renames in place so references survive', () async {
      final db = await DatabaseHelper.instance.database;
      final baitId = await db.insert('baits', {'name': 'Old Bait'});
      final catchId = await db
          .insert('catches', {'fish_type': 'Barra', 'bait_id': baitId});

      await DatabaseHelper.instance
          .updateBait(Bait(id: baitId, name: 'New Bait'));

      final row = (await db
              .query('catches', where: 'id = ?', whereArgs: [catchId]))
          .first;
      expect(row['bait_id'], baitId);
    });
  });

  // ---------- legacy JSON restore remapping ----------

  group('legacy JSON restore environmental remap', () {
    Future<File> writeBackup(Map<String, dynamic> data,
        {String version = '1.0.0'}) async {
      final file = File(p.join(testDir.path, 'backup.json'));
      await file.writeAsString(
          jsonEncode({'version': version, 'data': data}));
      return file;
    }

    test('env conditions remap catch_id/trip_id to restored parent IDs',
        () async {
      final backup = await writeBackup({
        'fishingTrips': [
          {
            'id': 30,
            'name': 'Trip A',
            'start_date': '2026-10-01T00:00:00.000',
            'created_at': '2026-10-01T00:00:00.000',
          }
        ],
        'catches': [
          {'id': 50, 'fish_type': 'A', 'trip_id': 30},
          {'id': 90, 'fish_type': 'B'},
        ],
        'environmentalConditions': [
          {
            'id': 1,
            'catch_id': 50,
            'observation_date_time': '2026-10-01T09:45:00.000',
            'created_at': '2026-10-01T09:45:00.000',
            'updated_at': '2026-10-01T09:45:00.000',
          },
          {
            'id': 2,
            'catch_id': 90,
            'observation_date_time': '2026-10-01T09:45:00.000',
            'created_at': '2026-10-01T09:45:00.000',
            'updated_at': '2026-10-01T09:45:00.000',
          },
          {
            'id': 3,
            'trip_id': 30,
            'observation_date_time': '2026-10-01T09:45:00.000',
            'created_at': '2026-10-01T09:45:00.000',
            'updated_at': '2026-10-01T09:45:00.000',
          },
          // Parent absent from the backup — must become NULL, not dangling.
          {
            'id': 4,
            'catch_id': 777,
            'observation_date_time': '2026-10-01T09:45:00.000',
            'created_at': '2026-10-01T09:45:00.000',
            'updated_at': '2026-10-01T09:45:00.000',
          },
        ],
      });

      await BackupService.restoreBackup(backup.path);

      final db = await DatabaseHelper.instance.database;
      final catches =
          await db.query('catches', orderBy: 'id');
      final trips = await db.query('fishing_trips');
      expect(catches.length, 2);
      expect(trips.length, 1);
      final newCatchIds = catches.map((c) => c['id'] as int).toList();
      final newTripId = trips.first['id'] as int;
      // Old IDs must NOT have been preserved.
      expect(newCatchIds, isNot(containsAll([50, 90])));
      expect(newTripId, isNot(30));

      final envs = await db.query('environmental_conditions',
          orderBy: 'id');
      expect(envs.length, 4);
      // Each env row attached to the correct restored parent by position.
      expect(envs[0]['catch_id'], newCatchIds[0]);
      expect(envs[1]['catch_id'], newCatchIds[1]);
      expect(envs[2]['trip_id'], newTripId);
      expect(envs[3]['catch_id'], isNull);
      await expectNoFkViolations();
    });

    test('a malformed backup throws and leaves the database untouched',
        () async {
      final file = File(p.join(testDir.path, 'bad.json'));
      await file.writeAsString('{"not_a_backup": true}');

      await expectLater(
          BackupService.restoreBackup(file.path), throwsA(anything));

      final db = await DatabaseHelper.instance.database;
      expect(
          (await db.rawQuery('SELECT COUNT(*) AS n FROM catches'))
              .first['n'],
          0);
    });
  });
}
