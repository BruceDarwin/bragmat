// Restore ownership tests — a restore must never silently bypass the
// installation's account controls:
//   unowned backup + unclaimed install  -> restores, stays unowned
//   unowned backup + claimed install    -> restored rows stamped owner
//   v29 matching owner                  -> allowed
//   v29 different owner                 -> refused, target untouched
//   ambiguous ownership                 -> refused, controlled recovery

import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/database/migration_v29.dart';
import 'package:bragmat/models/backup_manifest.dart';
import 'package:bragmat/services/media_storage_service.dart';
import 'package:bragmat/services/zip_backup_service.dart';
import 'package:bragmat/services/ownership_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;
  late String targetDbPath;
  int counter = 0;

  setUp(() async {
    testDir = Directory.systemTemp.createTempSync('bragmat_ro_test_');
    MediaStorageService.setTestDirectory(testDir);
    await MediaStorageService.getMediaDirectory();
    targetDbPath = path.join(testDir.path, 'target.db');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    DatabaseHelper.setDataAccessDenied(false);
    OwnershipService.invalidate();
    MediaStorageService.clearTestDirectory();
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  /// Minimal v28 database file (pre-ownership schema).
  Future<void> writeV28File(String filePath, List<String> fish) async {
    final db = await openDatabase(filePath, version: 28,
        onCreate: (db, version) async {
      await db.execute(
          'CREATE TABLE catches (id INTEGER PRIMARY KEY AUTOINCREMENT,'
          ' fish_type TEXT)');
      for (final f in fish) {
        await db.insert('catches', {'fish_type': f});
      }
    });
    await db.close();
  }

  /// Minimal v29 database file carrying ownership state.
  Future<void> writeV29File(
    String filePath, {
    String? accountOwner,
    String? rowOwner,
    List<String> fish = const [],
  }) async {
    final db = await openDatabase(filePath, version: 29,
        onCreate: (db, version) async {
      await db.execute(
          'CREATE TABLE catches (id INTEGER PRIMARY KEY AUTOINCREMENT,'
          ' fish_type TEXT, uuid TEXT, owner_id TEXT, updated_at TEXT)');
      await MigrationV29.createOwnershipTables(db);
      for (final f in fish) {
        await db.insert('catches',
            {'fish_type': f, 'uuid': 'u-$f', 'owner_id': rowOwner});
      }
      if (accountOwner != null) {
        await db.update('local_account', {'owner_id': accountOwner},
            where: 'id = 1');
      }
    });
    await db.close();
  }

  Future<String> buildZip(String dbFilePath, int schemaVersion) async {
    counter++;
    final archive = Archive();
    final manifest = BackupManifest.create(
      bragmatVersion: '1.0.0+8',
      databaseSchemaVersion: schemaVersion,
      platform: 'android',
      contents: BackupContents(
        database: true,
        media: BackupMediaCounts(
            catches: 0, trips: 0, journals: 0, lures: 0),
        settings: false,
      ),
      statistics: BackupStatistics(
          catches: 0, trips: 0, photos: 0, missingPhotos: 0),
      settings: null,
    );
    final manifestBytes = utf8.encode(jsonEncode(manifest.toMap()));
    archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
    final dbBytes = await File(dbFilePath).readAsBytes();
    archive.addFile(
        ArchiveFile('database.sqlite', dbBytes.length, dbBytes));
    final zipPath = path.join(testDir.path, 'backup_$counter.zip');
    await File(zipPath).writeAsBytes(ZipEncoder().encode(archive)!);
    return zipPath;
  }

  Future<List<Map<String, Object?>>> readTargetCatches() async {
    final db = await openDatabase(targetDbPath, readOnly: true);
    try {
      return await db.query('catches');
    } finally {
      await db.close();
    }
  }

  Future<String?> targetOwner() async {
    final db = await openDatabase(targetDbPath, readOnly: true);
    try {
      return await OwnershipService.ownerIdFrom(db);
    } finally {
      await db.close();
    }
  }

  test('unowned v28 backup restores unowned on an unclaimed install',
      () async {
    await writeV28File(targetDbPath, ['Old']);
    final src = path.join(testDir.path, 'src.db');
    await writeV28File(src, ['Restored']);
    final zip = await buildZip(src, 28);

    await ZipBackupService.restoreBackup(
        zipPath: zip, databasePathOverride: targetDbPath);

    final catches = await readTargetCatches();
    expect(catches.single['fish_type'], 'Restored');
    // Upgraded to v29 columns, still unowned.
    expect(catches.single['owner_id'], isNull);
    expect(catches.single['uuid'], isNotNull);
    expect(await targetOwner(), isNull);
  });

  test('unowned backup on a claimed install requires owner sign-in, '
      'explicit confirmation and a verified safety backup — and still '
      'restores unowned', () async {
    await writeV29File(targetDbPath,
        accountOwner: 'user-A', fish: ['Owned']);
    final src = path.join(testDir.path, 'src.db');
    await writeV28File(src, ['FromBackup']);
    final zip = await buildZip(src, 28);

    var confirmCalled = false;
    var safetyCalled = false;
    final result = await ZipBackupService.restoreBackup(
      zipPath: zip,
      databasePathOverride: targetDbPath,
      currentUserId: 'user-A',
      confirmUnownedRestore: () async {
        confirmCalled = true;
        return true;
      },
      createSafetyBackup: () async {
        safetyCalled = true;
        return 'safety_backup.zip';
      },
    );

    expect(confirmCalled, isTrue);
    expect(safetyCalled, isTrue);
    expect(result.safetyBackupName, 'safety_backup.zip');
    final catches = await readTargetCatches();
    expect(catches.single['fish_type'], 'FromBackup');
    // Restored data stays unowned — claiming is always explicit.
    expect(catches.single['owner_id'], isNull);
    expect(await targetOwner(), isNull);
  });

  test('unowned backup on a claimed install is refused when a '
      'non-owner is signed in', () async {
    await writeV29File(targetDbPath,
        accountOwner: 'user-A', fish: ['Mine']);
    final src = path.join(testDir.path, 'src.db');
    await writeV28File(src, ['FromBackup']);
    final zip = await buildZip(src, 28);

    await expectLater(
        ZipBackupService.restoreBackup(
          zipPath: zip,
          databasePathOverride: targetDbPath,
          currentUserId: 'user-B',
          confirmUnownedRestore: () async => true,
          createSafetyBackup: () async => 'safety.zip',
        ),
        throwsA(predicate(
            (e) => e.toString().contains('owning account'))));

    expect((await readTargetCatches()).single['fish_type'], 'Mine');
    expect(await targetOwner(), 'user-A');
  });

  test('unowned backup on a claimed install cancels cleanly without '
      'confirmation — nothing touched', () async {
    await writeV29File(targetDbPath,
        accountOwner: 'user-A', fish: ['Mine']);
    final src = path.join(testDir.path, 'src.db');
    await writeV28File(src, ['FromBackup']);
    final zip = await buildZip(src, 28);

    await expectLater(
        ZipBackupService.restoreBackup(
          zipPath: zip,
          databasePathOverride: targetDbPath,
          currentUserId: 'user-A',
          confirmUnownedRestore: () async => false,
        ),
        throwsA(isA<RestoreCancelledException>()));

    expect((await readTargetCatches()).single['fish_type'], 'Mine');
    expect(await targetOwner(), 'user-A');
  });

  test('unowned backup on a claimed install aborts when the safety '
      'backup cannot be created', () async {
    await writeV29File(targetDbPath,
        accountOwner: 'user-A', fish: ['Mine']);
    final src = path.join(testDir.path, 'src.db');
    await writeV28File(src, ['FromBackup']);
    final zip = await buildZip(src, 28);

    await expectLater(
        ZipBackupService.restoreBackup(
          zipPath: zip,
          databasePathOverride: targetDbPath,
          currentUserId: 'user-A',
          confirmUnownedRestore: () async => true,
          createSafetyBackup: () async => null,
        ),
        throwsA(predicate(
            (e) => e.toString().contains('safety backup'))));

    expect((await readTargetCatches()).single['fish_type'], 'Mine');
    expect(await targetOwner(), 'user-A');
  });

  test('v29 backup with matching owner restores', () async {
    await writeV29File(targetDbPath,
        accountOwner: 'user-A', rowOwner: 'user-A', fish: ['Old']);
    final src = path.join(testDir.path, 'src.db');
    await writeV29File(src,
        accountOwner: 'user-A', rowOwner: 'user-A', fish: ['Restored']);
    final zip = await buildZip(src, 29);

    await ZipBackupService.restoreBackup(
        zipPath: zip, databasePathOverride: targetDbPath);

    final catches = await readTargetCatches();
    expect(catches.single['fish_type'], 'Restored');
    expect(catches.single['owner_id'], 'user-A');
  });

  test('v29 backup with a different owner is refused and leaves the '
      'target untouched', () async {
    await writeV29File(targetDbPath,
        accountOwner: 'user-A', rowOwner: 'user-A', fish: ['Mine']);
    final src = path.join(testDir.path, 'src.db');
    await writeV29File(src,
        accountOwner: 'user-B', rowOwner: 'user-B', fish: ['Theirs']);
    final zip = await buildZip(src, 29);

    await expectLater(
        ZipBackupService.restoreBackup(
            zipPath: zip, databasePathOverride: targetDbPath),
        throwsA(predicate((e) =>
            e.toString().contains('different account'))));

    final catches = await readTargetCatches();
    expect(catches.single['fish_type'], 'Mine');
    expect(await targetOwner(), 'user-A');
  });

  test('ambiguous backup (owned rows, no account record) is refused',
      () async {
    await writeV29File(targetDbPath,
        accountOwner: 'user-A', rowOwner: 'user-A', fish: ['Mine']);
    final src = path.join(testDir.path, 'src.db');
    await writeV29File(src,
        accountOwner: null, rowOwner: 'user-B', fish: ['Partial']);
    final zip = await buildZip(src, 29);

    await expectLater(
        ZipBackupService.restoreBackup(
            zipPath: zip, databasePathOverride: targetDbPath),
        throwsA(predicate((e) =>
            e.toString().contains('inconsistent'))));

    expect((await readTargetCatches()).single['fish_type'], 'Mine');
  });

  test('v29 backup owned by an account restores onto an unclaimed '
      'install — ownership travels with the data', () async {
    await writeV28File(targetDbPath, ['Old']);
    final src = path.join(testDir.path, 'src.db');
    await writeV29File(src,
        accountOwner: 'user-B', rowOwner: 'user-B', fish: ['Theirs']);
    final zip = await buildZip(src, 29);

    await ZipBackupService.restoreBackup(
        zipPath: zip, databasePathOverride: targetDbPath);

    expect((await readTargetCatches()).single['fish_type'], 'Theirs');
    expect(await targetOwner(), 'user-B');
  });

  test('schemaVersionOf reports the file\'s real user_version', () async {
    final v28 = path.join(testDir.path, 'v28.db');
    await writeV28File(v28, ['x']);
    expect(await ZipBackupService.schemaVersionOf(v28), 28);

    final v29 = path.join(testDir.path, 'v29.db');
    await writeV29File(v29, accountOwner: null, fish: ['x']);
    expect(await ZipBackupService.schemaVersionOf(v29), 29);
  });
}
