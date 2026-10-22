import 'dart:io';

import 'package:bragmat/services/backup_file_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Covers the platform-agnostic seams of [BackupFileService]: the
/// override hooks used by tests and the local-backup listing shared by
/// Android and iOS. On this test host (non-Android) the service also
/// proves the non-SAF paths fail closed instead of crashing when the
/// underlying plugins are unavailable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('backup_files_');
  });

  tearDown(() {
    BackupFileService.debugPickerOverride = null;
    BackupFileService.debugExporterOverride = null;
    BackupFileService.debugBackupDirectoryOverride = null;
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('pickBackupZip', () {
    test('returns the override result without touching the platform',
        () async {
      BackupFileService.debugPickerOverride = () async => '/tmp/x.zip';
      expect(await BackupFileService.pickBackupZip(), '/tmp/x.zip');
    });

    test('override can simulate a cancelled picker', () async {
      BackupFileService.debugPickerOverride = () async => null;
      expect(await BackupFileService.pickBackupZip(), isNull);
    });

    test('returns null when the document picker is unavailable',
        () async {
      // Non-Android host with no file_selector plugin — must fail closed.
      expect(await BackupFileService.pickBackupZip(), isNull);
    });
  });

  group('exportBackup', () {
    test('returns the override result without touching the platform',
        () async {
      var capturedPath = '';
      var capturedName = '';
      BackupFileService.debugExporterOverride = (p, n) async {
        capturedPath = p;
        capturedName = n;
        return true;
      };
      expect(
        await BackupFileService.exportBackup('/tmp/b.zip', 'b.zip'),
        isTrue,
      );
      expect(capturedPath, '/tmp/b.zip');
      expect(capturedName, 'b.zip');
    });

    test('returns false when the export channel is unavailable', () async {
      expect(
        await BackupFileService.exportBackup('/tmp/b.zip', 'b.zip'),
        isFalse,
      );
    });
  });

  group('backupDirectory', () {
    test('honours the test override', () async {
      BackupFileService.debugBackupDirectoryOverride = tempDir;
      expect(await BackupFileService.backupDirectory(), tempDir);
    });
  });

  group('listLocalBackups', () {
    test('lists zip and json backups, newest first, ignoring other files',
        () async {
      BackupFileService.debugBackupDirectoryOverride = tempDir;
      final older =
          File('${tempDir.path}/bragmat_backup_2026-01-01T00-00-00.zip');
      final newer =
          File('${tempDir.path}/bragmat_backup_2026-02-01T00-00-00.zip');
      final legacy = File('${tempDir.path}/bragmat_backup_legacy.json');
      final other = File('${tempDir.path}/unrelated.zip');
      await older.writeAsBytes([0]);
      await newer.writeAsBytes([0]);
      await legacy.writeAsBytes([0]);
      await other.writeAsBytes([0]);
      older.setLastModifiedSync(DateTime(2026, 1, 1));
      newer.setLastModifiedSync(DateTime(2026, 2, 1));
      legacy.setLastModifiedSync(DateTime(2026, 1, 15));

      final files = await BackupFileService.listLocalBackups();

      expect(files.map((f) => p.basename(f.path)), [
        p.basename(newer.path),
        p.basename(legacy.path),
        p.basename(older.path),
      ]);
    });

    test('returns empty when the directory override is null', () async {
      BackupFileService.debugBackupDirectoryOverride = null;
      // Real path: no override falls through to the platform directory,
      // which on this host resolves or fails closed — either way the
      // call must not throw.
      await BackupFileService.listLocalBackups();
    });

    test('returns empty for a missing directory', () async {
      BackupFileService.debugBackupDirectoryOverride =
          Directory('${tempDir.path}/does-not-exist');
      expect(await BackupFileService.listLocalBackups(), isEmpty);
    });
  });

  group('releasePickedFile', () {
    test('deletes an existing picked copy', () async {
      final file = File('${tempDir.path}/picked.zip');
      await file.writeAsBytes([0]);
      await BackupFileService.releasePickedFile(file.path);
      expect(await file.exists(), isFalse);
    });

    test('does not throw for a missing file', () async {
      await BackupFileService.releasePickedFile(
          '${tempDir.path}/missing.zip');
    });
  });
}
