// Cloud restore end-to-end ownership tests — a REAL encrypted cloud
// object is downloaded, decrypted and pushed through the real
// ZipBackupService staged pipeline, so the ownership gate fires exactly
// as it does on-device:
//   unowned cloud backup + owned install -> owner confirmation +
//     verified safety backup, restored rows stay unowned
//   same-owner cloud backup              -> restores untouched
//   different-owner cloud backup         -> refused, target untouched
//   cancelled confirmation               -> nothing changed
//   missing safety backup                -> aborted, nothing changed
//   offline download                     -> propagates, nothing changed
// The upload side is also covered end-to-end: the upload ownership gate
// reads the live local_account row through systemDatabase.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/database/migration_v29.dart';
import 'package:bragmat/models/backup_manifest.dart';
import 'package:bragmat/services/auth_service.dart';
import 'package:bragmat/services/backup_envelope.dart';
import 'package:bragmat/services/cloud_backup_service.dart';
import 'package:bragmat/services/media_storage_service.dart';
import 'package:bragmat/services/ownership_service.dart';
import 'package:bragmat/services/zip_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sodium/sodium.ffi.dart' as sodium_ffi;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_cloud_backup_backend.dart';

const _dll = r'C:\Users\bruce\libsodium-test\libsodium.dll';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late FakeCloudBackupBackend backend;
  late CloudBackupService service;
  late Directory testDir;
  late Directory workRoot;
  late String targetDbPath;
  int counter = 0;

  setUpAll(() async {
    final dll = Platform.environment['BRAGMAT_LIBSODIUM'] ?? _dll;
    BackupEnvelope.debugSodium =
        await sodium_ffi.SodiumSumoInit.init(() => DynamicLibrary.open(dll));
    BackupEnvelope.debugChunkSize = 4096;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testDir = Directory.systemTemp.createTempSync('bragmat_cro_test_');
    workRoot =
        await Directory.systemTemp.createTemp('cloud_cro_work_');
    MediaStorageService.setTestDirectory(testDir);
    await MediaStorageService.getMediaDirectory();
    targetDbPath = path.join(testDir.path, 'target.db');
    DatabaseHelper.setTestDatabasePath(targetDbPath);

    backend = FakeCloudBackupBackend(); // uid defaults to 'user-A'
    service = CloudBackupService.forBackend(backend);
    CloudBackupService.debugWorkDir = workRoot;
    CloudBackupService.debugAuthStatus = AuthStatus.signedIn;
    // Real owner lookup: read local_account from the live test DB.
    CloudBackupService.debugLocalOwnerIdReader = () async =>
        OwnershipService.ownerIdFrom(
            await DatabaseHelper.instance.systemDatabase);
    await CloudBackupService.grantConsent();
  });

  tearDown(() async {
    CloudBackupService.debugCreateBackup = null;
    CloudBackupService.debugRestoreOverride = null;
    CloudBackupService.debugWorkDir = null;
    CloudBackupService.debugAuthStatus = null;
    CloudBackupService.debugLocalOwnerIdReader = null;
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    DatabaseHelper.setDataAccessDenied(false);
    OwnershipService.invalidate();
    MediaStorageService.clearTestDirectory();
    if (await testDir.exists()) await testDir.delete(recursive: true);
    if (await workRoot.exists()) await workRoot.delete(recursive: true);
  });

  // ── fixtures (same shapes as restore_ownership_test.dart) ──────────

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

  /// Encrypt-upload [zipPath] through the service and return the remote
  /// object name, as if it had been uploaded from another device.
  Future<String> uploadZipAsBackup(String zipPath, String name) async {
    CloudBackupService.debugCreateBackup = (dir) async {
      final copy = File('${dir.trim()}/$name');
      await copy.writeAsBytes(await File(zipPath).readAsBytes());
      return copy.path;
    };
    return (await service.uploadNow(passphrase: 'pw')).remoteName;
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

  // ── tests ───────────────────────────────────────────────────────────

  test('same-owner cloud backup downloads, decrypts and restores '
      'through the real pipeline', () async {
    await writeV29File(targetDbPath,
        accountOwner: 'user-A', rowOwner: 'user-A', fish: ['Old']);
    final src = path.join(testDir.path, 'src.db');
    await writeV29File(src,
        accountOwner: 'user-A', rowOwner: 'user-A', fish: ['Cloud']);
    final remote =
        await uploadZipAsBackup(await buildZip(src, 29), 'same_owner.zip');

    final result = await service.restoreFromCloud(
        remoteName: remote, passphrase: 'pw');

    expect(result.mediaFilesRestored, 0);
    expect((await readTargetCatches()).single['fish_type'], 'Cloud');
    expect((await readTargetCatches()).single['owner_id'], 'user-A');
    expect(await targetOwner(), 'user-A');
  });

  test('unowned cloud backup onto an owned install requires the '
      'confirmation + safety-backup hooks and restores unowned',
      () async {
    await writeV29File(targetDbPath,
        accountOwner: 'user-A', fish: ['Mine']);
    final src = path.join(testDir.path, 'src.db');
    await writeV28File(src, ['LegacyCatch']);
    final remote =
        await uploadZipAsBackup(await buildZip(src, 28), 'legacy.zip');

    var confirmCalled = false;
    var safetyCalled = false;
    final result = await service.restoreFromCloud(
      remoteName: remote,
      passphrase: 'pw',
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
    expect(catches.single['fish_type'], 'LegacyCatch');
    // Restored rows stay unowned — explicit claim is still required.
    expect(catches.single['owner_id'], isNull);
    expect(await targetOwner(), isNull);
  });

  test('unowned cloud backup cancels cleanly when the owner declines',
      () async {
    await writeV29File(targetDbPath,
        accountOwner: 'user-A', fish: ['Mine']);
    final src = path.join(testDir.path, 'src.db');
    await writeV28File(src, ['LegacyCatch']);
    final remote =
        await uploadZipAsBackup(await buildZip(src, 28), 'legacy.zip');

    var safetyCalled = false;
    await expectLater(
      service.restoreFromCloud(
        remoteName: remote,
        passphrase: 'pw',
        confirmUnownedRestore: () async => false,
        createSafetyBackup: () async {
          safetyCalled = true;
          return 'safety.zip';
        },
      ),
      throwsA(isA<RestoreCancelledException>()),
    );

    expect(safetyCalled, isFalse); // cancel happens before backup
    expect((await readTargetCatches()).single['fish_type'], 'Mine');
    expect(await targetOwner(), 'user-A');
  });

  test('unowned cloud backup aborts when the safety backup cannot be '
      'created — nothing is replaced', () async {
    await writeV29File(targetDbPath,
        accountOwner: 'user-A', fish: ['Mine']);
    final src = path.join(testDir.path, 'src.db');
    await writeV28File(src, ['LegacyCatch']);
    final remote =
        await uploadZipAsBackup(await buildZip(src, 28), 'legacy.zip');

    await expectLater(
      service.restoreFromCloud(
        remoteName: remote,
        passphrase: 'pw',
        confirmUnownedRestore: () async => true,
        createSafetyBackup: () async => null,
      ),
      throwsA(predicate(
          (e) => e.toString().contains('safety backup'))),
    );

    expect((await readTargetCatches()).single['fish_type'], 'Mine');
    expect(await targetOwner(), 'user-A');
  });

  test('different-owner cloud backup is refused and the target is '
      'untouched', () async {
    await writeV29File(targetDbPath,
        accountOwner: 'user-A', rowOwner: 'user-A', fish: ['Mine']);
    final src = path.join(testDir.path, 'src.db');
    await writeV29File(src,
        accountOwner: 'user-B', rowOwner: 'user-B', fish: ['Theirs']);
    final remote =
        await uploadZipAsBackup(await buildZip(src, 29), 'foreign.zip');

    await expectLater(
      service.restoreFromCloud(remoteName: remote, passphrase: 'pw'),
      throwsA(predicate(
          (e) => e.toString().contains('different account'))),
    );

    expect((await readTargetCatches()).single['fish_type'], 'Mine');
    expect(await targetOwner(), 'user-A');
  });

  test('offline download propagates and changes nothing', () async {
    await writeV29File(targetDbPath,
        accountOwner: 'user-A', fish: ['Mine']);
    final src = path.join(testDir.path, 'src.db');
    await writeV29File(src,
        accountOwner: 'user-A', rowOwner: 'user-A', fish: ['Cloud']);
    final remote =
        await uploadZipAsBackup(await buildZip(src, 29), 'off.zip');

    backend.failDownload = true;
    await expectLater(
      service.restoreFromCloud(remoteName: remote, passphrase: 'pw'),
      throwsA(isA<SocketException>()),
    );

    expect((await readTargetCatches()).single['fish_type'], 'Mine');
    expect(await targetOwner(), 'user-A');
  });

  test('upload is refused when the live DB belongs to another account '
      '(real systemDatabase owner read)', () async {
    await writeV29File(targetDbPath,
        accountOwner: 'user-B', rowOwner: 'user-B', fish: ['Theirs']);
    final src = path.join(testDir.path, 'src.db');
    await writeV28File(src, ['X']);

    await expectLater(
      uploadZipAsBackup(await buildZip(src, 28), 'nope.zip'),
      throwsA(predicate((e) =>
          e is CloudBackupOwnershipException &&
          e.reason.contains('different account'))),
    );
    expect(backend.objects, isEmpty);
  });

  test('upload is refused while local data is unclaimed', () async {
    await writeV29File(targetDbPath,
        accountOwner: null, fish: ['Unclaimed']);
    final src = path.join(testDir.path, 'src.db');
    await writeV28File(src, ['X']);

    await expectLater(
      uploadZipAsBackup(await buildZip(src, 28), 'nope.zip'),
      throwsA(predicate((e) =>
          e is CloudBackupOwnershipException &&
          e.reason.contains('unclaimed'))),
    );
    expect(backend.objects, isEmpty);
  });
}
