import 'dart:io';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/services/media_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regression tests for catch-deletion orphan records (pre-beta hardening,
/// Workstream B).
///
/// These tests encode the DESIRED post-fix behaviour:
///   - deleting a catch removes its catch_media and
///     environmental_conditions rows,
///   - the physical media files it referenced are deleted,
///   - files still referenced by other catches are preserved,
///   - other catches' rows and files are untouched.
///
/// They FAIL against the current implementation: `PRAGMA foreign_keys`
/// is never enabled so the declared ON DELETE CASCADE clauses are inert,
/// and no code deletes media files. That failure is the defect evidence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;

  setUp(() async {
    testDir = Directory.systemTemp.createTempSync('catch_delete_');
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

  Future<int> insertCatch() async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('catches', {
      'fish_type': 'Barramundi',
      'length_cm': 45,
      'created_at': '2026-10-01T09:45:00.000',
      'date_caught': '2026-10-01T09:45:00.000',
    });
  }

  /// Create a real file under the test media dir at [relPath]
  /// (e.g. 'catches/catch_1_primary_x.jpg') and register a catch_media row.
  Future<int> insertMedia(int catchId, String relPath,
      {String role = 'primary'}) async {
    final file = File(p.joinAll(
        [testDir.path, 'bragmat', 'media', ...relPath.split('/')]));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(8, 0x42));
    final db = await DatabaseHelper.instance.database;
    return db.insert('catch_media', {
      'catch_id': catchId,
      'file_path': relPath,
      'media_type': 'photo',
      'role': role,
      'created_at': '2026-10-01T09:45:00.000',
    });
  }

  Future<void> insertEnv(int catchId) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('environmental_conditions', {
      'catch_id': catchId,
      'observation_date_time': '2026-10-01T09:45:00.000',
      'tide_reference_mode': 'fixed',
      'tide_reference_name': 'Darwin',
      'created_at': '2026-10-01T09:45:00.000',
    });
  }

  Future<int> countWhere(String table, int catchId) async {
    final db = await DatabaseHelper.instance.database;
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM $table WHERE catch_id = ?', [catchId]);
    return r.first['n'] as int;
  }

  Future<bool> fileExists(String relPath) =>
      MediaStorageService.fileExists(relPath);

  test('deleteCatch removes its catch_media rows', () async {
    final id = await insertCatch();
    await insertMedia(id, 'catches/catch_${id}_primary_a1.jpg');
    await insertMedia(id, 'catches/catch_${id}_other_b2.jpg',
        role: 'other');

    await DatabaseHelper.instance.deleteCatch(id);

    expect(await countWhere('catches', id), 0);
    expect(await countWhere('catch_media', id), 0);
  });

  test('deleteCatch removes its environmental_conditions row', () async {
    final id = await insertCatch();
    await insertEnv(id);

    await DatabaseHelper.instance.deleteCatch(id);

    expect(await countWhere('catches', id), 0);
    expect(await countWhere('environmental_conditions', id), 0);
  });

  test('deleteCatch deletes its physical media files', () async {
    final id = await insertCatch();
    const rel = 'catches/catch_unique_primary_z9.jpg';
    await insertMedia(id, rel);
    expect(await fileExists(rel), isTrue);

    await DatabaseHelper.instance.deleteCatch(id);

    expect(await countWhere('catch_media', id), 0);
    expect(await fileExists(rel), isFalse);
  });

  test('deleteCatch preserves a file still referenced by another catch',
      () async {
    final a = await insertCatch();
    final b = await insertCatch();
    const shared = 'catches/shared_photo.jpg';
    await insertMedia(a, shared);
    await insertMedia(b, shared);

    await DatabaseHelper.instance.deleteCatch(a);

    expect(await countWhere('catch_media', a), 0);
    expect(await countWhere('catch_media', b), 1);
    // The file must survive — catch B still references it.
    expect(await fileExists(shared), isTrue);
  });

  test('deleteCatch leaves other catches untouched', () async {
    final a = await insertCatch();
    final b = await insertCatch();
    await insertMedia(a, 'catches/a_photo.jpg');
    await insertMedia(b, 'catches/b_photo.jpg');
    await insertEnv(a);
    await insertEnv(b);

    await DatabaseHelper.instance.deleteCatch(a);

    expect(await countWhere('catches', b), 1);
    expect(await countWhere('catch_media', b), 1);
    expect(await countWhere('environmental_conditions', b), 1);
    expect(await fileExists('catches/b_photo.jpg'), isTrue);
  });
}
