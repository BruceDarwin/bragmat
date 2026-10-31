import 'dart:io';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/services/integrity_diagnostics.dart';
import 'package:bragmat/services/media_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase B diagnostics: every integrity problem class is detected on
/// synthetic data, valid shared files are never flagged, and the whole
/// scan is provably read-only.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;
  late Directory mediaDir;

  setUp(() async {
    testDir = Directory.systemTemp.createTempSync('integrity_diag_');
    DatabaseHelper.setTestDatabasePath(p.join(testDir.path, 'bragmat.db'));
    MediaStorageService.setTestDirectory(testDir);
    mediaDir = Directory(
        p.joinAll([testDir.path, 'bragmat', 'media']));
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

  Future<File> makeMediaFile(String relPath) async {
    final file =
        File(p.joinAll([mediaDir.path, ...relPath.split('/')]));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(8, 0x42));
    return file;
  }

  Future<int> insertCatch(
      {int? lureId, int? baitId, int? buddyId, int? tripId}) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('catches', {
      'fish_type': 'Barra',
      'lure_id': lureId,
      'bait_id': baitId,
      'fishing_buddy_id': buddyId,
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

  test('clean database and media produce zero findings', () async {
    final report = await IntegrityDiagnostics.run();
    expect(report.findingCount, 0);
    expect(report.foreignKeyViolations, isEmpty);
    expect(report.softReferenceCount, 0);
    expect(report.missingMediaFiles, isEmpty);
    expect(report.unreferencedMediaFiles, isEmpty);
    expect(report.quarantinedFiles, isEmpty);
  });

  test('declared-FK orphans are reported via foreign_key_check',
      () async {
    final db = await DatabaseHelper.instance.database;
    // Orphan: parent catch 999 does not exist.
    await db.insert('catch_media', {
      'catch_id': 999,
      'file_path': 'catches/orphan.jpg',
      'created_at': '2026-10-01',
    });

    final report = await IntegrityDiagnostics.run();
    expect(report.foreignKeyViolations, hasLength(1));
    expect(report.foreignKeyViolations.single,
        contains('catch_media'));
    expect(report.foreignKeyViolations.single, contains('catches'));
  });

  test('dangling soft references are reported per column', () async {
    await insertCatch(lureId: 41, baitId: 42, buddyId: 43, tripId: 44);

    final report = await IntegrityDiagnostics.run();
    expect(report.softReferenceCount, 4);
    expect(report.softReferenceProblems['lure_id'], hasLength(1));
    expect(report.softReferenceProblems['bait_id'], hasLength(1));
    expect(
        report.softReferenceProblems['fishing_buddy_id'], hasLength(1));
    expect(report.softReferenceProblems['trip_id'], hasLength(1));
  });

  test('valid soft references are not reported', () async {
    final db = await DatabaseHelper.instance.database;
    final lureId = await db.insert('lures', {'name': 'L'});
    final baitId = await db.insert('baits', {'name': 'B'});
    final buddyId = await db.insert('fishing_buddies', {'name': 'Dave'});
    final tripId = await insertTrip();
    await insertCatch(
        lureId: lureId, baitId: baitId, buddyId: buddyId, tripId: tripId);

    final report = await IntegrityDiagnostics.run();
    expect(report.softReferenceCount, 0);
  });

  test('media rows pointing at missing files are reported', () async {
    final catchId = await insertCatch();
    final db = await DatabaseHelper.instance.database;
    await db.insert('catch_media', {
      'catch_id': catchId,
      'file_path': 'catches/absent.jpg',
      'created_at': '2026-10-01',
    });

    final report = await IntegrityDiagnostics.run();
    expect(report.missingMediaFiles, hasLength(1));
    expect(report.missingMediaFiles.single, contains('absent.jpg'));
    // A missing file is not a disk-side orphan — no unreferenced entry.
    expect(report.unreferencedMediaFiles, isEmpty);
  });

  test('files on disk with no referencing row are reported', () async {
    await makeMediaFile('catches/stray.jpg');

    final report = await IntegrityDiagnostics.run();
    expect(report.unreferencedMediaFiles, ['catches/stray.jpg']);
  });

  test('referenced files are never flagged — incl. legacy spellings',
      () async {
    final catchId = await insertCatch();
    final db = await DatabaseHelper.instance.database;
    await makeMediaFile('catches/used.jpg');
    await makeMediaFile('catches/legacy.jpg');
    await db.insert('catch_media', {
      'catch_id': catchId,
      'file_path': 'catches/used.jpg',
      'created_at': '2026-10-01',
    });
    // Stored with the legacy singular prefix; file lives at canonical.
    await db.insert('catch_media', {
      'catch_id': catchId,
      'file_path': 'catch/legacy.jpg',
      'created_at': '2026-10-01',
    });
    // catches.image_path / lure_photo_path references count too.
    await db.update('catches', {'image_path': 'catches/used.jpg'},
        where: 'id = ?', whereArgs: [catchId]);

    final report = await IntegrityDiagnostics.run();
    expect(report.unreferencedMediaFiles, isEmpty);
    expect(report.missingMediaFiles, isEmpty);
  });

  test('quarantine contents are inventoried, not flagged as orphans',
      () async {
    final qDir = Directory(
        p.join(mediaDir.parent.path, 'quarantine', '20261101'));
    await qDir.create(recursive: true);
    await File(p.join(qDir.path, 'catches', 'old.jpg'))
        .create(recursive: true);

    final report = await IntegrityDiagnostics.run();
    expect(report.quarantinedFiles, hasLength(1));
    expect(report.quarantinedFiles.single,
        contains('old.jpg'));
    expect(report.unreferencedMediaFiles, isEmpty);
  });

  test('malformed references are handled safely', () async {
    final catchId = await insertCatch();
    final db = await DatabaseHelper.instance.database;
    // NULL and empty paths are skipped silently.
    await db.insert('catch_media', {
      'catch_id': catchId,
      'file_path': '',
      'created_at': '2026-10-01',
    });
    // Absolute out-of-media path that does not exist → missing, and the
    // report must not leak the absolute directory (basename only).
    final outside = p.join(testDir.path, 'elsewhere', 'gone.jpg');
    await db.insert('catch_media', {
      'catch_id': catchId,
      'file_path': outside,
      'created_at': '2026-10-01',
    });

    final report = await IntegrityDiagnostics.run();
    expect(report.missingMediaFiles, hasLength(1));
    expect(report.missingMediaFiles.single, endsWith('gone.jpg'));
    expect(report.missingMediaFiles.single,
        isNot(contains('elsewhere')));
  });

  test('the scan is read-only for database and filesystem', () async {
    await insertCatch();
    final db = await DatabaseHelper.instance.database;
    await db.insert('catch_media', {
      'catch_id': 9999, // deliberate orphan for the scan to find
      'file_path': 'catches/orphan_media.jpg',
      'created_at': '2026-10-01',
    });
    await makeMediaFile('catches/stray.jpg');

    // Snapshot state.
    Future<int> rowCount(String t) async => (await db
            .rawQuery('SELECT COUNT(*) AS n FROM $t'))
        .first['n'] as int;
    Future<List<String>> diskFiles() async {
      final files = <String>[];
      if (await mediaDir.exists()) {
        await for (final e in mediaDir.list(recursive: true)) {
          if (e is File) files.add(e.path);
        }
      }
      return files..sort();
    }

    final countsBefore = {
      for (final t in [
        'catches',
        'catch_media',
        'fishing_trips',
        'journal_media'
      ])
        t: await rowCount(t)
    };
    final filesBefore = await diskFiles();

    final report = await IntegrityDiagnostics.run();
    expect(report.findingCount, greaterThan(0));

    for (final entry in countsBefore.entries) {
      expect(await rowCount(entry.key), entry.value,
          reason: '${entry.key} row count changed');
    }
    expect(await diskFiles(), filesBefore,
        reason: 'media directory contents changed');
  });

  test('summary() reports every category', () async {
    await insertCatch(lureId: 7);
    await makeMediaFile('trips/stray.jpg');

    final report = await IntegrityDiagnostics.run();
    final text = report.summary();
    expect(text, contains('Declared-FK violations'));
    expect(text, contains('Soft-reference problems'));
    expect(text, contains('Media rows with missing files'));
    expect(text, contains('Unreferenced media files'));
    expect(text, contains('Quarantine inventory'));
    expect(text, contains('catches.lure_id'));
  });
}
