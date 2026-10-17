import 'dart:ffi';
import 'dart:io';

import 'package:bragmat/models/backup_manifest.dart';
import 'package:bragmat/services/backup_envelope.dart';
import 'package:bragmat/services/cloud_backup_service.dart';
import 'package:bragmat/services/zip_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sodium/sodium.ffi.dart' as sodium_ffi;

const _dll = r'C:\Users\bruce\libsodium-test\libsodium.dll';

/// In-memory cloud backend — no network. Fault injection covers every
/// failure mode the service must survive.
class FakeCloudBackupBackend implements CloudBackupBackend {
  String? uid = 'user-A';
  final objects = <String, List<int>>{};
  final metadata = <String, Map<String, String>>{};
  final deleteCalls = <List<String>>[];
  var deleteAllCalls = 0;

  // Fault injection.
  var failUpload = false;
  var failDownload = false;
  var failDelete = false;
  var failList = false;
  var quotaExceeded = false;
  var failEdgeFunction = false;

  /// Deliver tampered bytes on the next download (integrity check bait).
  List<int>? downloadOverride;

  @override
  String? get userId => uid;

  @override
  Future<void> upload(String remoteName, File file,
      {required Map<String, String> metadata}) async {
    if (quotaExceeded) throw CloudQuotaExceededException();
    if (failUpload) throw const SocketException('offline');
    if (objects.containsKey(remoteName)) {
      throw RemoteObjectExistsException(remoteName);
    }
    objects[remoteName] = await file.readAsBytes();
    this.metadata[remoteName] = metadata;
  }

  @override
  Future<List<RemoteBackupInfo>> list() async {
    if (failList) throw const SocketException('offline');
    return [
      for (final e in objects.entries)
        RemoteBackupInfo(
          name: e.key,
          size: e.value.length,
          sha256Hex: metadata[e.key]?['sha256'],
          createdAt: DateTime(2026),
        ),
    ];
  }

  @override
  Future<void> download(String remoteName, File dest) async {
    if (failDownload) throw const SocketException('offline');
    final bytes = downloadOverride ?? objects[remoteName];
    if (bytes == null) {
      throw const FileSystemException('not found');
    }
    downloadOverride = null;
    await dest.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<int> delete(List<String> remoteNames) async {
    if (failDelete) throw const SocketException('offline');
    deleteCalls.add(remoteNames);
    var n = 0;
    for (final name in remoteNames) {
      if (objects.remove(name) != null) {
        metadata.remove(name);
        n++;
      }
    }
    return n;
  }

  @override
  Future<int> deleteAll() async {
    if (failEdgeFunction) throw const SocketException('offline');
    deleteAllCalls++;
    final n = objects.length;
    objects.clear();
    metadata.clear();
    return n;
  }
}

void main() {
  late FakeCloudBackupBackend backend;
  late CloudBackupService service;
  late Directory workRoot;

  /// Synthetic plaintext standing in for a real ZIP — the envelope and
  /// service only ever see bytes.
  List<int> zipBytes(String tag) =>
      List.generate(3000, (i) => (i + tag.hashCode) % 251);

  setUpAll(() async {
    final dll = Platform.environment['BRAGMAT_LIBSODIUM'] ?? _dll;
    BackupEnvelope.debugSodium =
        await sodium_ffi.SodiumSumoInit.init(() => DynamicLibrary.open(dll));
    BackupEnvelope.debugChunkSize = 4096;
  });

  var zipCounter = 0;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = FakeCloudBackupBackend();
    service = CloudBackupService.forBackend(backend);
    workRoot =
        await Directory.systemTemp.createTemp('cloud_backup_test_');
    CloudBackupService.debugWorkDir = workRoot;

    zipCounter = 0;
    CloudBackupService.debugCreateBackup = (dir) async {
      zipCounter++;
      final f = File('$dir/bragmat_backup_2026-10-17T12-00-0'
          '$zipCounter.zip');
      await f.writeAsBytes(zipBytes('z$zipCounter'));
      return f.path;
    };
    CloudBackupService.debugRestoreOverride = (zipPath) async =>
        BackupRestoreResult(
          manifest: BackupManifest.create(
            bragmatVersion: '1.0.0',
            databaseSchemaVersion: 29,
            platform: 'test',
            contents:
                BackupContents(database: true, media: BackupMediaCounts(
                    catches: 0, trips: 0, journals: 0, lures: 0),
                settings: false),
            statistics: BackupStatistics(
                catches: 0, trips: 0, photos: 0, missingPhotos: 0),
          ),
          mediaFilesRestored: 0,
          mediaFilesSkipped: 0,
        );
  });

  tearDown(() async {
    CloudBackupService.debugCreateBackup = null;
    CloudBackupService.debugRestoreOverride = null;
    CloudBackupService.debugWorkDir = null;
    if (await workRoot.exists()) await workRoot.delete(recursive: true);
  });

  int looseFiles() =>
      workRoot.existsSync() ? workRoot.listSync(recursive: true).length : 0;

  group('consent', () {
    test('disabled by default — upload refused before any work', () async {
      await expectLater(service.uploadNow(passphrase: 'p'),
          throwsA(isA<CloudBackupNotEnabledException>()));
      expect(backend.objects, isEmpty);
      expect(zipCounter, 0);
    });

    test('grantConsent records enabled, version and timestamp', () async {
      await CloudBackupService.grantConsent();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('cloud_backup_enabled'), true);
      expect(prefs.getString('cloud_backup_consent_version'), '1.0');
      expect(prefs.getInt('cloud_backup_consent_at'), isNotNull);
    });

    test('disable without deleteRemote keeps remote objects', () async {
      await CloudBackupService.grantConsent();
      await service.uploadNow(passphrase: 'p');
      expect(backend.objects, isNotEmpty);
      await service.disable();
      expect(await CloudBackupService.isEnabled, false);
      expect(backend.deleteAllCalls, 0);
      expect(backend.objects, isNotEmpty);
    });

    test('disable(deleteRemote) goes through the Edge Function', () async {
      await CloudBackupService.grantConsent();
      await service.uploadNow(passphrase: 'p');
      await service.disable(deleteRemote: true);
      expect(backend.deleteAllCalls, 1);
      expect(backend.objects, isEmpty);
    });

    test('disabled service also blocks list/restore/delete', () async {
      await expectLater(service.listBackups(),
          throwsA(isA<CloudBackupNotEnabledException>()));
      await expectLater(
          service.restoreFromCloud(remoteName: 'x.bzp', passphrase: 'p'),
          throwsA(isA<CloudBackupNotEnabledException>()));
      await expectLater(service.deleteBackup('x.bzp'),
          throwsA(isA<CloudBackupNotEnabledException>()));
    });
  });

  group('upload', () {
    setUp(() => CloudBackupService.grantConsent());

    test('happy path: encrypts, uploads, verifies, returns metadata',
        () async {
      final result = await service.uploadNow(passphrase: 'pw');
      expect(result.remoteName, endsWith('.bzp'));
      expect(result.recoveryCode, isNotEmpty);
      expect(result.size, greaterThan(0));
      expect(backend.objects.keys.single, result.remoteName);
      expect(backend.metadata[result.remoteName]!['sha256'],
          result.sha256Hex);
      expect(looseFiles(), 0); // temp dir cleaned
    });

    test('uploaded object is ciphertext, not the plaintext zip', () async {
      await service.uploadNow(passphrase: 'pw');
      final bytes = backend.objects.values.single;
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'BRGZ');
    });

    test('duplicate remote name fails without overwriting', () async {
      // Force identical remote names (same zip basename) so the second
      // upload collides — upsert is never used.
      CloudBackupService.debugCreateBackup = (dir) async {
        final f = File('$dir/bragmat_backup_dup.zip');
        await f.writeAsBytes(zipBytes('dup'));
        return f.path;
      };
      final first = await service.uploadNow(passphrase: 'pw');
      final original = backend.objects[first.remoteName]!.toList();
      await expectLater(
        service.uploadNow(passphrase: 'pw'),
        throwsA(isA<RemoteObjectExistsException>()),
      );
      expect(backend.objects[first.remoteName], original);
      expect(looseFiles(), 0);
    });

    test('network failure mid-upload: nothing stored, temp cleaned',
        () async {
      backend.failUpload = true;
      await expectLater(service.uploadNow(passphrase: 'pw'),
          throwsA(isA<SocketException>()));
      expect(backend.objects, isEmpty);
      expect(backend.deleteCalls, isEmpty); // no prune attempted
      expect(looseFiles(), 0);
    });

    test('quota failure surfaces as CloudQuotaExceededException',
        () async {
      backend.quotaExceeded = true;
      await expectLater(service.uploadNow(passphrase: 'pw'),
          throwsA(isA<CloudQuotaExceededException>()));
      expect(backend.objects, isEmpty);
    });

    test('unverified upload is deleted and never prunes', () async {
      // Seed two older verified backups.
      await service.uploadNow(passphrase: 'pw');
      await service.uploadNow(passphrase: 'pw');
      expect(backend.objects.length, 2);

      // Third upload: backend returns corrupted bytes on read-back.
      backend.downloadOverride = [0xDE, 0xAD];
      await expectLater(service.uploadNow(passphrase: 'pw'),
          throwsA(isA<CloudIntegrityException>()));

      // The unverified object was removed; the older two survive —
      // pruning never ran.
      expect(backend.objects.length, 2);
      expect(backend.deleteCalls, hasLength(1));
      expect(backend.deleteCalls.single.single, isNot(isIn(
          backend.objects.keys.toList())));
      expect(looseFiles(), 0);
    });

    test('retention keeps the newest three verified backups', () async {
      for (var i = 0; i < 4; i++) {
        await service.uploadNow(passphrase: 'pw');
      }
      expect(backend.objects.length, 3);
      final result = await service.uploadNow(passphrase: 'pw');
      expect(result.pruned, hasLength(1));
      expect(backend.objects.length, 3);
      // Newest survives; the deleted name is the oldest.
      final names = backend.objects.keys.toList()..sort();
      expect(result.remoteName, names.last);
    });

    test('signed-out user is refused', () async {
      backend.uid = null;
      await expectLater(service.uploadNow(passphrase: 'pw'),
          throwsA(isA<CloudBackupAuthException>()));
      expect(backend.objects, isEmpty);
    });

    test('cancellation stops the pipeline and cleans up', () async {
      final token = CloudBackupCancelToken()..cancel();
      await expectLater(
          service.uploadNow(passphrase: 'pw', cancellation: token),
          throwsA(isA<CloudBackupCancelledException>()));
      expect(looseFiles(), 0);
    });
  });

  group('restore', () {
    setUp(() => CloudBackupService.grantConsent());

    Future<String> seedBackup(String passphrase) async =>
        (await service.uploadNow(passphrase: passphrase)).remoteName;

    test('happy path: download → digest → decrypt → staged restore',
        () async {
      final name = await seedBackup('pw');
      var restoredPath = '';
      CloudBackupService.debugRestoreOverride = (zipPath) async {
        restoredPath = zipPath;
        // Decrypted artifact must be a real ZIP-shaped payload.
        expect(await File(zipPath).readAsBytes(), zipBytes('z1'));
        return BackupRestoreResult(
          manifest: BackupManifest.create(
            bragmatVersion: '1.0.0',
            databaseSchemaVersion: 29,
            platform: 'test',
            contents: BackupContents(
                database: true,
                media: BackupMediaCounts(
                    catches: 0, trips: 0, journals: 0, lures: 0),
                settings: false),
            statistics: BackupStatistics(
                catches: 0, trips: 0, photos: 0, missingPhotos: 0),
          ),
          mediaFilesRestored: 0,
          mediaFilesSkipped: 0,
        );
      };
      await service.restoreFromCloud(remoteName: name, passphrase: 'pw');
      expect(restoredPath, isNotEmpty);
      expect(looseFiles(), 0);
    });

    test('recovery code decrypts without the passphrase', () async {
      final result = await service.uploadNow(passphrase: 'pw');
      var sawBytes = false;
      CloudBackupService.debugRestoreOverride = (zipPath) async {
        sawBytes = true;
        return BackupRestoreResult(
          manifest: BackupManifest.create(
            bragmatVersion: '1.0.0', databaseSchemaVersion: 29,
            platform: 'test',
            contents: BackupContents(
                database: true,
                media: BackupMediaCounts(
                    catches: 0, trips: 0, journals: 0, lures: 0),
                settings: false),
            statistics: BackupStatistics(
                catches: 0, trips: 0, photos: 0, missingPhotos: 0),
          ),
          mediaFilesRestored: 0,
          mediaFilesSkipped: 0,
        );
      };
      await service.restoreFromCloud(
          remoteName: result.remoteName,
          recoveryCode: result.recoveryCode);
      expect(sawBytes, isTrue);
    });

    test('wrong passphrase: no restore, temp cleaned', () async {
      final name = await seedBackup('right');
      var restoreCalled = false;
      CloudBackupService.debugRestoreOverride =
          (p) async { restoreCalled = true; throw StateError('never'); };
      await expectLater(
          service.restoreFromCloud(remoteName: name, passphrase: 'wrong'),
          throwsA(isA<IncorrectSecretException>()));
      expect(restoreCalled, false);
      expect(looseFiles(), 0);
    });

    test('tampered download aborts before decrypt/restore', () async {
      final name = await seedBackup('pw');
      // Simulate a storage-side bit flip: next download returns
      // corrupted bytes → recorded digest mismatch.
      backend.downloadOverride =
          backend.objects[name]!.toList()..first ^= 0xFF;
      var restoreCalled = false;
      CloudBackupService.debugRestoreOverride =
          (p) async { restoreCalled = true; throw StateError('never'); };
      await expectLater(
          service.restoreFromCloud(remoteName: name, passphrase: 'pw'),
          throwsA(isA<CloudIntegrityException>()));
      expect(restoreCalled, false);
      expect(looseFiles(), 0);
    });

    test('ownership denial propagates; temps still cleaned', () async {
      final name = await seedBackup('pw');
      CloudBackupService.debugRestoreOverride = (p) async =>
          throw Exception(
              'Restore refused: this backup belongs to a different '
              'account.');
      await expectLater(
          service.restoreFromCloud(remoteName: name, passphrase: 'pw'),
          throwsA(predicate(
              (e) => e.toString().contains('different account'))));
      expect(looseFiles(), 0);
    });

    test('restore rollback propagates; temps still cleaned', () async {
      final name = await seedBackup('pw');
      CloudBackupService.debugRestoreOverride = (p) async =>
          throw Exception('Failed to restore database: disk full');
      await expectLater(
          service.restoreFromCloud(remoteName: name, passphrase: 'pw'),
          throwsA(predicate(
              (e) => e.toString().contains('Failed to restore'))));
      expect(looseFiles(), 0);
    });

    test('download failure: nothing decrypted or restored', () async {
      final name = await seedBackup('pw');
      backend.failDownload = true;
      await expectLater(
          service.restoreFromCloud(remoteName: name, passphrase: 'pw'),
          throwsA(isA<SocketException>()));
      expect(looseFiles(), 0);
    });
  });

  group('delete / list', () {
    setUp(() => CloudBackupService.grantConsent());

    test('listBackups returns own objects newest-first', () async {
      await service.uploadNow(passphrase: 'pw');
      await service.uploadNow(passphrase: 'pw');
      final list = await service.listBackups();
      expect(list, hasLength(2));
      expect(list.first.name.compareTo(list.last.name) > 0, true);
      expect(list.every((b) => b.sha256Hex != null), true);
    });

    test('deleteBackup removes via the Storage API path', () async {
      final name = (await service.uploadNow(passphrase: 'pw')).remoteName;
      expect(await service.deleteBackup(name), 1);
      expect(backend.objects, isEmpty);
      expect(backend.deleteCalls.single.single, name);
    });

    test('deleteAllBackups routes to the Edge Function', () async {
      await service.uploadNow(passphrase: 'pw');
      await service.uploadNow(passphrase: 'pw');
      expect(await service.deleteAllBackups(), 2);
      expect(backend.deleteAllCalls, 1);
      expect(backend.objects, isEmpty);
    });
  });
}
