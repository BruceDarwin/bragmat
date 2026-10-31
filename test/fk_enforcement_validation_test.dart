import 'dart:io';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/models/catch.dart' as model;
import 'package:bragmat/services/media_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase C1: compatibility of `onConfigure: PRAGMA foreign_keys = ON`
/// with schema v30, real operations, migrations, restores and
/// pre-existing orphaned data. Synthetic databases only.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;
  late Directory mediaDir;

  setUp(() async {
    testDir = Directory.systemTemp.createTempSync('fk_enforce_');
    DatabaseHelper.setTestDatabasePath(p.join(testDir.path, 'bragmat.db'));
    MediaStorageService.setTestDirectory(testDir);
    mediaDir = Directory(p.joinAll([testDir.path, 'bragmat', 'media']));
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    MediaStorageService.clearTestDirectory();
    try {
      if (await testDir.exists()) await testDir.delete(recursive: true);
    } on PathAccessException {
      // Transient Windows locks; OS cleans temp dirs.
    }
  });

  Future<int> fkState() async {
    final db = await DatabaseHelper.instance.database;
    final r = await db.rawQuery('PRAGMA foreign_keys');
    return r.first.values.first as int;
  }

  Future<List<Map<String, Object?>>> fkCheck() async {
    final db = await DatabaseHelper.instance.database;
    return db.rawQuery('PRAGMA foreign_key_check');
  }

  Future<int> insertCatch({int? tripId}) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('catches', {
      'fish_type': 'Barra',
      'trip_id': tripId,
      'created_at': '2026-10-01T09:45:00.000',
    });
  }

  Future<int> insertTrip() async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('fishing_trips', {
      'name': 'T',
      'start_date': '2026-10-01',
      'created_at': '2026-10-01',
    });
  }

  /// Insert a declared-FK orphan by temporarily disabling enforcement —
  /// the only way such a row can exist, matching production history.
  Future<void> seedOrphanCatchMedia() async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.insert('catch_media', {
      'catch_id': 9999,
      'file_path': 'catches/orphan.jpg',
      'created_at': '2026-10-01',
    });
    await db.execute('PRAGMA foreign_keys = ON');
  }

  group('pragma state', () {
    test('fresh v30 database is created with enforcement ON', () async {
      expect(await fkState(), 1);
      final db = await DatabaseHelper.instance.database;
      expect((await db.rawQuery('PRAGMA user_version'))
          .first.values.first, 30);
    });

    test('enforcement is re-applied on reopen of a valid database',
        () async {
      await insertCatch();
      await DatabaseHelper.instance.closeDatabase();
      expect(await fkState(), 1);
      final db = await DatabaseHelper.instance.database;
      expect(await db.query('catches'), hasLength(1));
    });

    test('reopenDatabaseForRestore connection is also enforced',
        () async {
      await DatabaseHelper.instance.closeDatabase();
      final db = await DatabaseHelper.instance
          .reopenDatabaseForRestore();
      final r = await db.rawQuery('PRAGMA foreign_keys');
      expect(r.first.values.first, 1);
    });
  });

  group('enforcement active', () {
    test('inserting a declared-FK orphan now fails immediately',
        () async {
      final db = await DatabaseHelper.instance.database;
      await expectLater(
        db.insert('catch_media', {
          'catch_id': 9999,
          'file_path': 'catches/x.jpg',
          'created_at': '2026-10-01',
        }),
        throwsA(isA<DatabaseException>()),
      );
      expect(await fkCheck(), isEmpty);
    });

    test('valid parented inserts still succeed', () async {
      final catchId = await insertCatch();
      final db = await DatabaseHelper.instance.database;
      final mid = await db.insert('catch_media', {
        'catch_id': catchId,
        'file_path': 'catches/ok.jpg',
        'created_at': '2026-10-01',
      });
      expect(mid, greaterThan(0));
      expect(await fkCheck(), isEmpty);
    });
  });

  group('normal operations under enforcement', () {
    test('deleteCatch removes dependents, no violations', () async {
      final catchId = await insertCatch();
      final db = await DatabaseHelper.instance.database;
      await db.insert('catch_media', {
        'catch_id': catchId,
        'file_path': 'catches/m.jpg',
        'created_at': '2026-10-01',
      });
      await db.insert('environmental_conditions', {
        'catch_id': catchId,
        'observation_date_time': '2026-10-01T09:45:00.000',
        'created_at': '2026-10-01',
        'updated_at': '2026-10-01',
      });
      await DatabaseHelper.instance.deleteCatch(catchId);
      expect(await fkCheck(), isEmpty);
      expect(await db.query('catch_media'), isEmpty);
      expect(await db.query('environmental_conditions'), isEmpty);
    });

    test('deleteFishingTrip removes the whole dependency chain',
        () async {
      final tripId = await insertTrip();
      final db = await DatabaseHelper.instance.database;
      final journalId = await db.insert('trip_journal', {
        'trip_id': tripId,
        'journal_date_time': '2026-10-01T09:45:00.000',
        'title': 'J',
        'entry_text': 'e',
        'created_at': '2026-10-01',
        'updated_at': '2026-10-01',
      });
      await db.insert('journal_media', {
        'journal_entry_id': journalId,
        'file_path': 'journals/j.jpg',
        'created_at': '2026-10-01',
      });
      await db.insert('trip_media', {
        'trip_id': tripId,
        'file_path': 'trips/t.jpg',
        'created_at': '2026-10-01',
      });
      await db.insert('environmental_conditions', {
        'trip_id': tripId,
        'observation_date_time': '2026-10-01T09:45:00.000',
        'created_at': '2026-10-01',
        'updated_at': '2026-10-01',
      });
      await insertCatch(tripId: tripId);

      await DatabaseHelper.instance.deleteFishingTrip(tripId);
      expect(await fkCheck(), isEmpty);
      expect(await db.query('trip_journal'), isEmpty);
      expect(await db.query('trip_media'), isEmpty);
      // The catch survives, detached.
      final c = (await db.query('catches')).single;
      expect(c['trip_id'], isNull);
    });

    test('deleteTripJournal removes journal media', () async {
      final tripId = await insertTrip();
      final db = await DatabaseHelper.instance.database;
      final journalId = await db.insert('trip_journal', {
        'trip_id': tripId,
        'journal_date_time': '2026-10-01T09:45:00.000',
        'title': 'J',
        'entry_text': 'e',
        'created_at': '2026-10-01',
        'updated_at': '2026-10-01',
      });
      await db.insert('journal_media', {
        'journal_entry_id': journalId,
        'file_path': 'journals/j.jpg',
        'created_at': '2026-10-01',
      });
      await DatabaseHelper.instance.deleteTripJournal(journalId);
      expect(await fkCheck(), isEmpty);
      expect(await db.query('journal_media'), isEmpty);
    });

    test('single media deletes work under enforcement', () async {
      final catchId = await insertCatch();
      final db = await DatabaseHelper.instance.database;
      final mid = await db.insert('catch_media', {
        'catch_id': catchId,
        'file_path': 'catches/m.jpg',
        'created_at': '2026-10-01',
      });
      await DatabaseHelper.instance.deleteCatchMedia(mid);
      expect(await fkCheck(), isEmpty);
      expect(await db.query('catches'), hasLength(1));
    });

    test('lure and bait delete/update keep catches consistent',
        () async {
      final db = await DatabaseHelper.instance.database;
      final lureId = await db.insert('lures', {'name': 'L'});
      final baitId = await db.insert('baits', {'name': 'B'});
      final catchId = await db.insert('catches',
          {'fish_type': 'Barra', 'lure_id': lureId, 'bait_id': baitId});

      await DatabaseHelper.instance.deleteLure(lureId);
      await DatabaseHelper.instance.deleteBait(baitId);

      final c = (await db.query('catches',
              where: 'id = ?', whereArgs: [catchId]))
          .single;
      expect(c['lure_id'], isNull);
      expect(c['bait_id'], isNull);
      expect(await fkCheck(), isEmpty);
    });
  });

  group('pre-existing violations', () {
    test('database containing orphans opens and operates normally',
        () async {
      await insertCatch();
      await seedOrphanCatchMedia();
      await DatabaseHelper.instance.closeDatabase();

      // Reopen through the production path — enforcement re-applies.
      expect(await fkState(), 1);

      // The pre-existing violation is visible but does not block I/O.
      final violations = await fkCheck();
      expect(violations, hasLength(1));
      expect(violations.single['table'], 'catch_media');

      final db = await DatabaseHelper.instance.database;
      // Reads, inserts of valid rows, and updates all still work.
      expect(await db.query('catches'), hasLength(1));
      await insertCatch();
      await db.update('catches', {'notes': 'ok'},
          where: 'id = 1');

      // New violations are still rejected.
      await expectLater(
        db.insert('catch_media', {
          'catch_id': 8888,
          'file_path': 'x.jpg',
          'created_at': '2026-10-01',
        }),
        throwsA(isA<DatabaseException>()),
      );
      // Exactly the one historical violation remains — nothing was
      // silently repaired or deleted.
      expect(await fkCheck(), hasLength(1));
      expect(await db.query('catch_media'), hasLength(1));
    });

    test('deleting a different catch leaves historical orphans '
        'untouched', () async {
      final keepId = await insertCatch();
      await seedOrphanCatchMedia();
      final db = await DatabaseHelper.instance.database;
      await DatabaseHelper.instance.deleteCatch(keepId);
      expect(await fkCheck(), hasLength(1));
      expect(await db.query('catch_media'), hasLength(1));
    });
  });

  group('migration under enforcement', () {
    test('v1-stamped database upgrades to v30 with FK ON and no '
        'violations', () async {
      // Genuine v1 schema — a single catches table, as shipped.
      final path = p.join(testDir.path, 'v1.db');
      var db = await openDatabase(path, version: 1,
          onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE catches (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fish_type TEXT,
            length_cm INTEGER,
            notes TEXT,
            created_at TEXT
          )
        ''');
      });
      await db.insert('catches',
          {'fish_type': 'Barra', 'length_cm': 60});
      await db.close();

      // Open through the production path: onConfigure sets FK ON,
      // then the entire 1→30 migration chain runs under enforcement.
      DatabaseHelper.setTestDatabasePath(path);
      db = await DatabaseHelper.instance.database;

      expect(await fkState(), 1);
      expect((await db.rawQuery('PRAGMA user_version'))
          .first.values.first, 30);
      expect(await fkCheck(), isEmpty);
      // Pre-migration row survives; post-migration writes enforce.
      expect(await db.query('catches'), hasLength(1));
      await expectLater(
        db.insert('catch_media', {
          'catch_id': 7777,
          'file_path': 'x.jpg',
          'created_at': '2026-10-01',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('restore paths under enforcement', () {
    test('media directory is untouched by enforcement checks '
        '(read-only file ops unaffected)', () async {
      final f = File(p.joinAll([mediaDir.path, 'catches', 'a.jpg']));
      await f.parent.create(recursive: true);
      await f.writeAsBytes([1, 2, 3]);
      expect(await f.exists(), isTrue);
      expect(await fkState(), 1);
    });
  });

  group('post-commit achievement failure', () {
    test('catch save reports success and persists the row even when '
        'achievement evaluation throws after commit', () async {
      final db = await DatabaseHelper.instance.database;
      // Sabotage the achievement bookkeeping so evaluation genuinely
      // fails — the same class of post-commit error the lazy-seeding
      // defect produced under FK enforcement.
      await db.execute('DROP TABLE user_achievements');

      final id = await DatabaseHelper.instance.insertCatch(
        model.Catch(lengthCm: 0, createdAt: DateTime(2026, 10, 1)),
      );

      // insertCatch must return the committed row id rather than
      // throwing — a thrown error would surface as a failed save and
      // invite the user to retry, duplicating the already-saved catch.
      expect(id, greaterThan(0));
      expect(await db.query('catches'), hasLength(1));
    });
  });
}
