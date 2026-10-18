import 'dart:ffi';
import 'dart:io';

import 'package:bragmat/models/backup_manifest.dart';
import 'package:bragmat/screens/cloud_backup_screen.dart';
import 'package:bragmat/services/auth_service.dart';
import 'package:bragmat/services/backup_envelope.dart';
import 'package:bragmat/services/cloud_backup_service.dart';
import 'package:bragmat/services/zip_backup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sodium/sodium.ffi.dart' as sodium_ffi;

import 'fake_cloud_backup_backend.dart';

const _dll = r'C:\Users\bruce\libsodium-test\libsodium.dll';

BackupRestoreResult _stubResult() => BackupRestoreResult(
      manifest: BackupManifest.create(
        bragmatVersion: '1.0.0',
        databaseSchemaVersion: 29,
        platform: 'test',
        contents: BackupContents(
          database: true,
          media: BackupMediaCounts(
              catches: 0, trips: 0, journals: 0, lures: 0),
          settings: false,
        ),
        statistics: BackupStatistics(
            catches: 0, trips: 0, photos: 0, missingPhotos: 0),
      ),
      mediaFilesRestored: 0,
      mediaFilesSkipped: 0,
    );

void main() {
  late FakeCloudBackupBackend backend;
  late CloudBackupService service;
  late Directory workRoot;

  setUpAll(() async {
    final dll = Platform.environment['BRAGMAT_LIBSODIUM'] ?? _dll;
    BackupEnvelope.debugSodium =
        await sodium_ffi.SodiumSumoInit.init(() => DynamicLibrary.open(dll));
    BackupEnvelope.debugChunkSize = 4096;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    backend = FakeCloudBackupBackend();
    service = CloudBackupService.forBackend(backend);
    workRoot = await Directory.systemTemp.createTemp('cloud_ui_test_');
    CloudBackupService.debugWorkDir = workRoot;
    // Approved owner — the fake backend's uid doubles as the local owner.
    CloudBackupService.debugAuthStatus = AuthStatus.signedIn;
    CloudBackupService.debugLocalOwnerIdReader = () async => backend.uid;
    CloudBackupService.debugCreateBackup = (dir) async {
      final f = File('$dir/bragmat_backup_2026-10-17T12-00-01.zip');
      await f.writeAsBytes(List.generate(3000, (i) => i % 251));
      return f.path;
    };
    CloudBackupService.debugRestoreOverride = (_) async => _stubResult();
  });

  tearDown(() async {
    CloudBackupService.debugCreateBackup = null;
    CloudBackupService.debugRestoreOverride = null;
    CloudBackupService.debugWorkDir = null;
    CloudBackupService.debugAuthStatus = null;
    CloudBackupService.debugLocalOwnerIdReader = null;
    if (await workRoot.exists()) await workRoot.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
        MaterialApp(home: CloudBackupScreen(service: service)));
    await tester.pumpAndSettle();
  }

  /// pumpAndSettle does NOT await real async I/O (encryption, file ops).
  /// This polls in real time until [finder] matches — required after any
  /// action that runs the backup pipeline.
  Future<void> waitFor(WidgetTester tester, Finder finder,
      {Duration timeout = const Duration(seconds: 20)}) async {
    final sw = Stopwatch()..start();
    while (sw.elapsed < timeout) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('timed out waiting for $finder');
  }

  /// CheckboxListTile sits inside scrollable dialogs — scroll to it
  /// first. Scoped to the last (topmost) dialog so a checkbox in a
  /// closing route can't collide.
  Future<void> tapCheckbox(WidgetTester tester) async {
    final finder = find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.byType(CheckboxListTile));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Seed consent + stored credentials → screen opens in enabled state.
  Future<void> seedEnabled() async {
    SharedPreferences.setMockInitialValues({
      'cloud_backup_enabled': true,
      'cloud_backup_consent_version': '1.0',
    });
    FlutterSecureStorage.setMockInitialValues({
      'cloud_backup_passphrase': 'test-passphrase',
      'cloud_backup_recovery_code':
          'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-GGGG-HHHH',
    });
  }

  /// Seed an encrypted backup object in the fake backend. Real I/O must
  /// run inside runAsync — awaiting it in the fake-async test zone
  /// deadlocks.
  Future<String> seedBackup(WidgetTester tester) async =>
      (await tester.runAsync(() => service.uploadNow(
              passphrase: 'pw',
              recoveryCode:
                  'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-GGGG-HHHH')))!
          .remoteName;

  // ── Disabled state ────────────────────────────────────────────────────

  testWidgets('disabled by default; no backend contact', (tester) async {
    await pump(tester);
    expect(find.text('Cloud Backup is off'), findsOneWidget);
    expect(find.text('Enable Cloud Backup'), findsOneWidget);
    expect(backend.uploadCalls, 0);
    expect(backend.listCalls, 0);
  });

  testWidgets('consent gate: Enable stays disabled until the checkbox',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Enable Cloud Backup'));
    await tester.pumpAndSettle();

    expect(find.textContaining('encrypted on your device'),
        findsOneWidget);
    // Enable button disabled before consent is ticked.
    final enable = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Enable'));
    expect(enable.onPressed, isNull);

    await tapCheckbox(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Enable'));
    await waitFor(tester, find.text('Create Backup Passphrase'));
  });

  testWidgets('cancelled consent touches nothing', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Enable Cloud Backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(await CloudBackupService.isEnabled, false);
    expect(backend.uploadCalls, 0);
  });

  // ── Credential setup ──────────────────────────────────────────────────

  Future<void> toPassphraseDialog(WidgetTester tester) async {
    await tester.tap(find.text('Enable Cloud Backup'));
    await tester.pumpAndSettle();
    await tapCheckbox(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Enable'));
    await waitFor(tester, find.text('Create Backup Passphrase'));
  }

  testWidgets('passphrase validation rejects short and mismatched',
      (tester) async {
    await pump(tester);
    await toPassphraseDialog(tester);

    await tester.enterText(find.byType(TextField).at(0), 'short');
    await tester.enterText(find.byType(TextField).at(1), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 8 characters'), findsOneWidget);

    await tester.enterText(
        find.byType(TextField).at(0), 'long-enough-passphrase');
    await tester.enterText(
        find.byType(TextField).at(1), 'different-passphrase');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Passphrases do not match'), findsOneWidget);
  });

  testWidgets(
      'recovery code is displayed and requires explicit confirmation',
      (tester) async {
    await pump(tester);
    await toPassphraseDialog(tester);
    await tester.enterText(
        find.byType(TextField).at(0), 'a-good-passphrase');
    await tester.enterText(
        find.byType(TextField).at(1), 'a-good-passphrase');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await waitFor(tester, find.text('Your Recovery Code'));

    // A standard Base32 grouped code is displayed.
    final shown =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(
        RegExp(r'^[A-Z2-7]{4}(-[A-Z2-7]{4}){7}$').hasMatch(shown), true);
    // Continue blocked until the user confirms they recorded it.
    final cont = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue'));
    expect(cont.onPressed, isNull);

    await tapCheckbox(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await waitFor(tester, find.text('Cloud Backup is on'));

    expect(await CloudBackupService.isEnabled, true);
    expect(backend.uploadCalls, 0); // nothing uploaded yet
  });

  // ── Enabled state ─────────────────────────────────────────────────────

  testWidgets('enabled screen shows actions and empty list',
      (tester) async {
    await seedEnabled();
    await pump(tester);
    expect(find.text('Cloud Backup is on'), findsOneWidget);
    expect(find.text('Back Up Now'), findsOneWidget);
    expect(find.text('No cloud backups yet.'), findsOneWidget);
    expect(find.text('Disable Cloud Backup'), findsOneWidget);
    expect(find.text('Delete All Cloud Backups'), findsOneWidget);
  });

  testWidgets('Back Up Now encrypts, uploads and reports success',
      (tester) async {
    await seedEnabled();
    await pump(tester);
    await tester.tap(find.text('Back Up Now'));
    await waitFor(tester, find.textContaining('uploaded and verified'));

    expect(backend.objects.length, 1);
    expect(find.text('backup from 2026-10-17 12:00:01'), findsOneWidget);
  });

  testWidgets('upload failure is reported, nothing stored',
      (tester) async {
    await seedEnabled();
    await pump(tester);
    backend.failUpload = true;
    await tester.tap(find.text('Back Up Now'));
    await waitFor(tester, find.textContaining('Cloud backup failed'));
    expect(backend.objects, isEmpty);
  });

  testWidgets('quota failure explains the local-backup fallback',
      (tester) async {
    await seedEnabled();
    await pump(tester);
    backend.quotaExceeded = true;
    await tester.tap(find.text('Back Up Now'));
    await waitFor(tester, find.textContaining('cloud storage limit'));
  });

  testWidgets('missing recovery code never silently regenerates',
      (tester) async {
    await seedEnabled();
    FlutterSecureStorage.setMockInitialValues(
        {'cloud_backup_passphrase': 'test-passphrase'}); // code absent
    await pump(tester);
    await tester.tap(find.text('Back Up Now'));
    await waitFor(tester, find.text('Recovery Code Needed'));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(backend.uploadCalls, 0); // aborted — no silent new code
  });

  testWidgets('busy overlay offers cancel during upload', (tester) async {
    await seedEnabled();
    await pump(tester);
    backend.uploadDelay = const Duration(seconds: 5);
    await tester.tap(find.text('Back Up Now'));
    // The pipeline reaches a progress stage → busy overlay visible.
    await waitFor(tester, find.byType(CircularProgressIndicator));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await waitFor(tester, find.textContaining('cancelled'),
        timeout: const Duration(seconds: 15));
  });

  // ── List & restore ────────────────────────────────────────────────────

  testWidgets('backup list shows date and size', (tester) async {
    await seedEnabled();
    backend.objects['bragmat_backup_2026-10-17T12-00-01.bzp'] =
        List.filled(3000, 1);
    await pump(tester);
    expect(find.text('backup from 2026-10-17 12:00:01'), findsOneWidget);
    expect(find.text('3 KB'), findsOneWidget);
  });

  testWidgets('restore warns, then wrong passphrase fails safely',
      (tester) async {
    await seedEnabled();
    final name = await seedBackup(tester);
    await pump(tester);

    await tester.tap(find.byTooltip('Restore this backup'));
    await tester.pumpAndSettle();
    expect(find.textContaining('REPLACE all fishing records'),
        findsOneWidget);

    await tester.enterText(find.byType(TextField), 'wrong-passphrase');
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await waitFor(tester, find.textContaining('Incorrect passphrase'));
    // The remote object is untouched by a failed restore.
    expect(backend.objects.containsKey(name), true);
  });

  testWidgets('tapping the backup row opens the restore dialog',
      (tester) async {
    await seedEnabled();
    await seedBackup(tester);
    await pump(tester);

    await tester.tap(find.text('backup from 2026-10-17 12:00:01'));
    await tester.pumpAndSettle();
    expect(find.text('Restore Cloud Backup'), findsOneWidget);
    expect(find.textContaining('REPLACE all fishing records'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('restore happy path reports completion', (tester) async {
    await seedEnabled();
    await seedBackup(tester);
    await pump(tester);

    await tester.tap(find.byTooltip('Restore this backup'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await waitFor(tester, find.text('Restore Complete'));
  });

  // ── Delete & disable ──────────────────────────────────────────────────

  testWidgets('single delete requires confirmation', (tester) async {
    await seedEnabled();
    await seedBackup(tester);
    await pump(tester);

    await tester.tap(find.byTooltip('Delete this backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(backend.objects.length, 1); // cancel kept it

    await tester.tap(find.byTooltip('Delete this backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('No cloud backups yet.'));
    expect(backend.objects, isEmpty);
  });

  testWidgets('Delete All goes through the Edge Function path',
      (tester) async {
    await seedEnabled();
    await seedBackup(tester);
    await pump(tester);

    await tester.tap(find.text('Delete All Cloud Backups'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete All'));
    await waitFor(tester, find.textContaining('Deleted 1 cloud backup'));
    expect(backend.deleteAllCalls, 1);
    expect(backend.objects, isEmpty);
  });

  testWidgets('disable without deletion keeps remote backups',
      (tester) async {
    await seedEnabled();
    await seedBackup(tester);
    await pump(tester);

    await tester.tap(find.text('Disable Cloud Backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Disable'));
    await waitFor(tester, find.text('Cloud Backup is off'));

    expect(await CloudBackupService.isEnabled, false);
    expect(backend.objects.length, 1); // remote untouched
  });

  testWidgets('disable with deletion clears remote and credentials',
      (tester) async {
    await seedEnabled();
    await seedBackup(tester);
    await pump(tester);

    await tester.tap(find.text('Disable Cloud Backup'));
    await tester.pumpAndSettle();
    await tapCheckbox(tester); // "also permanently delete"
    await tester.tap(find.widgetWithText(FilledButton, 'Disable'));
    await waitFor(tester, find.text('Cloud Backup is off'));

    expect(await CloudBackupService.isEnabled, false);
    expect(backend.deleteAllCalls, 1);
    expect(backend.objects, isEmpty);
  });
}
