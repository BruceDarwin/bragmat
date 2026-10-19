// Verifies the CLOUD_BACKUP_AVAILABLE build-time gate. The flag is read
// at COMPILE time and fails closed: a missing or non-'true' value makes
// the whole feature unavailable at the service layer, regardless of
// saved consent or preferences — the beta-1 requirement.
//
// flutter test runs without the dart-define, so the compile-time
// default (unavailable) is itself exercised by these tests.

import 'package:bragmat/services/auth_service.dart';
import 'package:bragmat/services/cloud_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_cloud_backup_backend.dart';

void main() {
  late FakeCloudBackupBackend backend;
  late CloudBackupService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = FakeCloudBackupBackend();
    service = CloudBackupService.forBackend(backend);
    CloudBackupService.debugAuthStatus = AuthStatus.signedIn;
    CloudBackupService.debugLocalOwnerIdReader = () async => backend.uid;
    // Simulate prior consent — the gate must override even this.
    await CloudBackupService.grantConsent();
  });

  tearDown(() {
    CloudBackupService.debugAvailable = null;
    CloudBackupService.debugAuthStatus = null;
    CloudBackupService.debugLocalOwnerIdReader = null;
    CloudBackupService.debugWorkDir = null;
    CloudBackupService.debugCreateBackup = null;
    CloudBackupService.debugRestoreOverride = null;
  });

  group('unavailable build (flag absent — beta-1 behaviour)', () {
    test('isAvailable is false when the flag is not compiled in', () {
      expect(CloudBackupService.isAvailable, isFalse);
    });

    test('isEnabled is false even with recorded consent', () async {
      expect(await CloudBackupService.isEnabled, isFalse);
    });

    test('uploadNow is rejected before any backend contact', () async {
      expect(
        () => service.uploadNow(passphrase: 'test-passphrase-123'),
        throwsA(isA<CloudBackupNotEnabledException>()),
      );
      expect(backend.uploadCalls, isZero);
    });

    test('listBackups is rejected before any backend contact', () async {
      expect(
        () => service.listBackups(),
        throwsA(isA<CloudBackupNotEnabledException>()),
      );
      expect(backend.listCalls, isZero);
    });

    test('restoreFromCloud is rejected before any download', () async {
      expect(
        () => service.restoreFromCloud(remoteName: 'x.bzp'),
        throwsA(isA<CloudBackupNotEnabledException>()),
      );
    });

    test('deleteBackup is rejected before any backend contact', () async {
      expect(
        () => service.deleteBackup('x.bzp'),
        throwsA(isA<CloudBackupNotEnabledException>()),
      );
      expect(backend.deleteCalls, isEmpty);
    });
  });

  group('available build (debugAvailable=true simulates the flag)', () {
    setUp(() => CloudBackupService.debugAvailable = true);

    test('isEnabled honours recorded consent', () async {
      expect(CloudBackupService.isAvailable, isTrue);
      expect(await CloudBackupService.isEnabled, isTrue);
    });

    test('isEnabled is still false without consent', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await CloudBackupService.isEnabled, isFalse);
    });
  });
}
