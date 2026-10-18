// LIVE end-to-end cloud backup validation — runs the REAL pipeline
// (createBackup → BRGZ encrypt → upload → read-back verify → download →
// decrypt → ownership-protected staged restore) against the deployed
// bragmat-dev project. Synthetic data only; every remote object is
// deleted by the cleanup test and the session is signed out afterwards.
//
// Opt-in — skipped unless a credentials file is supplied:
//   flutter test test/cloud_live_e2e_test.dart \
//     --dart-define-from-file=.env \
//     --dart-define=CLOUD_E2E_CREDS_FILE=C:/path/creds.json
// The creds file contains {"email": "...", "password": "..."} for an
// approved TEST account and is created by the operator — it is NEVER
// committed. The test signs in a fresh, independent session (password
// grant) so emulator sessions are never disturbed, and signs it out
// afterwards.
//
// Covered live:
//   real createBackup → encrypt → upload → verify → prune (keep-last-3)
//   download → decrypt → restore → DB integrity/row counts
//   wrong passphrase / corrupted object → abort, DB untouched
//   duplicate remote name → refused (no overwrite)
//   cancelled upload → nothing reaches the bucket
//   disable(deleteRemote) → Edge Function empties the caller's prefix

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/models/backup_manifest.dart';
import 'package:bragmat/services/auth_service.dart';
import 'package:bragmat/services/backup_envelope.dart';
import 'package:bragmat/services/cloud_backup_service.dart';
import 'package:bragmat/services/media_storage_service.dart';
import 'package:bragmat/services/ownership_service.dart';
import 'package:bragmat/services/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sodium/sodium.ffi.dart' as sodium_ffi;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _dll = r'C:\Users\bruce\libsodium-test\libsodium.dll';
const _credsFile =
    String.fromEnvironment('CLOUD_E2E_CREDS_FILE', defaultValue: '');

void main() {
  if (_credsFile.isEmpty) {
    // Not wired for a live run — report a single passing placeholder so
    // the file is inert inside the ordinary suite.
    test('skipped (no CLOUD_E2E_CREDS_FILE)', () {}, skip: true);
    return;
  }

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late SupabaseClient client;
  late SupabaseCloudBackupBackend backend;
  late CloudBackupService service;
  late Directory testDir;
  late Directory workRoot;
  late String targetDbPath;
  late String uid;

  setUpAll(() async {
    final dll = Platform.environment['BRAGMAT_LIBSODIUM'] ?? _dll;
    BackupEnvelope.debugSodium =
        await sodium_ffi.SodiumSumoInit.init(() => DynamicLibrary.open(dll));
    BackupEnvelope.debugChunkSize = 4096;

    // Real authenticated client — a fresh, independent session via the
    // password grant. Emulator sessions are never touched or rotated.
    final creds =
        jsonDecode(await File(_credsFile).readAsString()) as Map;
    client = SupabaseClient(SupabaseConfig.url, SupabaseConfig.anonKey);
    final auth = await client.auth.signInWithPassword(
        email: creds['email'], password: creds['password']);
    expect(auth.session, isNotNull);
    uid = client.auth.currentUser!.id;
    backend = SupabaseCloudBackupBackend(client);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testDir = Directory.systemTemp.createTempSync('bragmat_live_e2e_');
    workRoot = await Directory.systemTemp.createTemp('cloud_live_work_');
    MediaStorageService.setTestDirectory(testDir);
    await MediaStorageService.getMediaDirectory();
    targetDbPath = path.join(testDir.path, 'target.db');
    DatabaseHelper.setTestDatabasePath(targetDbPath);

    service = CloudBackupService.forBackend(backend);
    CloudBackupService.debugWorkDir = workRoot;
    CloudBackupService.debugAuthStatus = AuthStatus.signedIn;
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
    // No remote residue between tests — backend calls bypass the
    // consent gate so cleanup works even after E2E-7 disables it.
    try {
      final leftovers = await backend.list();
      if (leftovers.isNotEmpty) {
        await backend.delete([for (final b in leftovers) b.name]);
      }
    } catch (_) {}
  });

  tearDownAll(() async {
    // Nothing may survive in the bucket; the minted session is revoked.
    try {
      await client.storage.from('backups').remove(
          [for (final o in await client.storage.from('backups').list(path: '$uid/')) '$uid/${o.name}']);
    } catch (_) {}
    await client.auth.signOut();
    await client.dispose();
  });

  /// Live DB owned by the test account with [fish] synthetic catches.
  Future<void> seedLiveDb(List<String> fish) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('local_account',
        {'id': 1, 'owner_id': uid},
        conflictAlgorithm: ConflictAlgorithm.replace);
    for (final f in fish) {
      await db.insert('catches', {
        'fish_type': f,
        'uuid': 'live-$f',
        'owner_id': uid,
        'created_at': 'x',
      });
    }
  }

  Future<List<Map<String, Object?>>> readTargetCatches() async {
    final db = await openDatabase(targetDbPath, readOnly: true);
    try {
      return await db.query('catches');
    } finally {
      await db.close();
    }
  }

  Future<String> targetQuickCheck() async {
    final db = await openDatabase(targetDbPath, readOnly: true);
    try {
      final rows = await db.rawQuery('PRAGMA quick_check');
      return rows.first.values.first.toString();
    } finally {
      await db.close();
    }
  }

  /// Build a backup ZIP containing [dbFile] (mirrors the restore test
  /// fixtures) — for multi-object scenarios; the happy-path test uses
  /// the REAL createBackup.
  Future<String> buildZip(String dbFilePath, int schemaVersion,
      String name) async {
    final archive = Archive();
    final manifest = BackupManifest.create(
      bragmatVersion: '1.0.0+8',
      databaseSchemaVersion: schemaVersion,
      platform: 'android',
      contents: BackupContents(
        database: true,
        media:
            BackupMediaCounts(catches: 0, trips: 0, journals: 0, lures: 0),
        settings: false,
      ),
      statistics:
          BackupStatistics(catches: 0, trips: 0, photos: 0, missingPhotos: 0),
      settings: null,
    );
    final manifestBytes = utf8.encode(jsonEncode(manifest.toMap()));
    archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
    final dbBytes = await File(dbFilePath).readAsBytes();
    archive.addFile(ArchiveFile('database.sqlite', dbBytes.length, dbBytes));
    final zipPath = path.join(testDir.path, name);
    await File(zipPath).writeAsBytes(ZipEncoder().encode(archive)!);
    return zipPath;
  }

  Future<String> uploadZipAsBackup(String zipPath, String name) async {
    CloudBackupService.debugCreateBackup = (dir) async {
      final copy = File('${dir.trim()}/$name');
      await copy.writeAsBytes(await File(zipPath).readAsBytes());
      return copy.path;
    };
    return (await service.uploadNow(passphrase: 'pw')).remoteName;
  }

  test('E2E-1 real backup round-trip: create → encrypt → upload → '
      'verify → download → decrypt → restore → integrity', () async {
    await seedLiveDb(['LiveSnapper', 'LiveBream']);

    final uploaded = await service.uploadNow(passphrase: 'pw');
    expect(uploaded.remoteName, endsWith('.bzp'));
    expect(uploaded.sha256Hex, hasLength(64));
    expect(uploaded.recoveryCode, isNotNull);

    // Verify remotely — object exists; the recorded digest is readable
    // via the info endpoint (custom metadata is absent from list()).
    final remote = (await service.listBackups())
        .singleWhere((b) => b.name == uploaded.remoteName);
    expect(remote.size, greaterThan(0));
    expect(await backend.recordedSha256(uploaded.remoteName),
        uploaded.sha256Hex);

    // Restore the live object's own DB back over itself — same owner,
    // no hooks needed — then verify integrity and counts.
    final result = await service.restoreFromCloud(
        remoteName: uploaded.remoteName, passphrase: 'pw');
    expect(result.mediaFilesRestored, 0);
    expect(await targetQuickCheck(), 'ok');
    final catches = await readTargetCatches();
    expect(catches.map((c) => c['fish_type']),
        containsAll(['LiveSnapper', 'LiveBream']));
    expect(catches.every((c) => c['owner_id'] == uid), isTrue);
  });

  test('E2E-2 wrong passphrase aborts before restore; DB untouched',
      () async {
    await seedLiveDb(['BeforeWrongPw']);
    final remote = await uploadZipAsBackup(
        await buildZip(targetDbPath, 29, 'live_wp.zip'), 'live_wp.zip');

    // Change the live DB so an accidental restore would be observable.
    final db = await DatabaseHelper.instance.systemDatabase;
    await db.delete('catches');
    await db.insert('catches', {
      'fish_type': 'AfterWrongPw',
      'uuid': 'live-after',
      'owner_id': uid,
      'created_at': 'x',
    });

    await expectLater(
      service.restoreFromCloud(
          remoteName: remote, passphrase: 'definitely-wrong'),
      throwsA(anything),
    );
    final catches = await readTargetCatches();
    expect(catches.single['fish_type'], 'AfterWrongPw');
  });

  test('E2E-3 corrupted remote object aborts; DB untouched', () async {
    await seedLiveDb(['CorruptGuard']);
    // Plant a non-envelope blob directly — it has no sha metadata, so
    // the digest check fails closed before decryption or restore.
    final garbage =
        File(path.join(workRoot.path, 'corrupt.bzp'));
    await garbage.writeAsBytes(List.generate(64, (i) => i));
    await backend.upload('corrupt.bzp', garbage, metadata: {});

    await expectLater(
      service.restoreFromCloud(
          remoteName: 'corrupt.bzp', passphrase: 'pw'),
      throwsA(anything),
    );
    final catches = await readTargetCatches();
    expect(catches.single['fish_type'], 'CorruptGuard');
    await backend.delete(['corrupt.bzp']);
  });

  test('E2E-4 duplicate remote name refused (no overwrite)', () async {
    await seedLiveDb(['Dup']);
    final remote = await uploadZipAsBackup(
        await buildZip(targetDbPath, 29, 'live_dup.zip'), 'live_dup.zip');

    final extra = File(path.join(workRoot.path, 'extra.bzp'));
    await extra.writeAsBytes([1, 2, 3]);
    await expectLater(
      backend.upload(remote, extra, metadata: {}),
      throwsA(isA<RemoteObjectExistsException>()),
    );
  });

  test('E2E-5 retention keeps the newest 3 verified backups', () async {
    await seedLiveDb(['Ret']);
    final srcZip = await buildZip(targetDbPath, 29, 'live_ret.zip');
    for (final n in ['a', 'b', 'c', 'd']) {
      await uploadZipAsBackup(srcZip, 'live_ret_$n.zip');
    }
    final names =
        (await service.listBackups()).map((b) => b.name).toList()..sort();
    // Sorted desc by name — 'd' newest ... 'a' oldest must be gone.
    expect(names, hasLength(CloudBackupService.keepBackups));
    expect(names, isNot(contains('live_ret_a.bzp')));
    expect(names, containsAll(
        ['live_ret_b.bzp', 'live_ret_c.bzp', 'live_ret_d.bzp']));
    // Clean up for later tests.
    for (final n in names) {
      await backend.delete([n]);
    }
  });

  test('E2E-6 cancelled upload leaves nothing remotely', () async {
    await seedLiveDb(['Cancel']);
    final token = CloudBackupCancelToken()..cancel();
    await expectLater(
      service.uploadNow(passphrase: 'pw', cancellation: token),
      throwsA(anything),
    );
    expect(await service.listBackups(), isEmpty);
  });

  test('E2E-7 disable(deleteRemote) empties the bucket via the Edge '
      'Function and turns consent off', () async {
    await seedLiveDb(['Del']);
    await uploadZipAsBackup(
        await buildZip(targetDbPath, 29, 'live_del.zip'), 'live_del.zip');
    expect(await service.listBackups(), isNotEmpty);

    final deleted = await service.disable(deleteRemote: true);
    expect(deleted, greaterThanOrEqualTo(1));
    expect(await CloudBackupService.isEnabled, isFalse);
    // Ordinary ops now fail closed — consent revoked.
    await expectLater(service.listBackups(),
        throwsA(isA<CloudBackupNotEnabledException>()));
    // Verify physically empty via raw backend (bypasses consent gate).
    expect(await backend.list(), isEmpty);
  });
}
