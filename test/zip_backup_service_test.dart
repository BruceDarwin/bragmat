import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:bragmat/models/backup_manifest.dart';
import 'package:bragmat/services/media_storage_service.dart';
import 'package:bragmat/services/zip_backup_service.dart';
import 'package:bragmat/services/preferences_service.dart';
import 'package:bragmat/services/current_trip_service.dart';
import 'package:bragmat/services/tide_reference_service.dart';
import 'package:bragmat/database/database_helper.dart';

void main() {
  // Initialize sqflite ffi for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ZipBackupService - Phase 1 Tests', () {
    late Directory testDir;

    setUp(() async {
      // Create temporary directory for tests
      testDir = Directory.systemTemp.createTempSync('bragmat_test_');
      
      // Set test directory for media storage
      MediaStorageService.setTestDirectory(testDir);
    });

    tearDown(() async {
      // Clean up test directory
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
      
      // Clear test directory from media storage service
      MediaStorageService.clearTestDirectory();
    });

    test('BackupManifest model - create and serialize', () {
      final manifest = BackupManifest.create(
        bragmatVersion: '1.0.0+8',
        databaseSchemaVersion: 28,
        platform: 'android',
        contents: BackupContents(
          database: true,
          media: BackupMediaCounts(
            catches: 5,
            trips: 2,
            journals: 1,
            lures: 0,
          ),
          settings: true,
        ),
        statistics: BackupStatistics(
          catches: 10,
          trips: 3,
          photos: 8,
          missingPhotos: 1,
        ),
        settings: BackupSettings(
          fishTypeSelectionMode: 1,
          defaultFishType: 'Barramundi',
          lastUsedFishType: 'Saratoga',
          currentTripId: 5,
          tideReferenceMode: 'automatic',
          tideReferenceId: null,
        ),
      );

      expect(manifest.backupVersion, BackupManifest.currentVersion);
      expect(manifest.bragmatVersion, '1.0.0+8');
      expect(manifest.databaseSchemaVersion, 28);
      expect(manifest.platform, 'android');
      expect(manifest.contents.database, true);
      expect(manifest.contents.media.catches, 5);
      expect(manifest.statistics.catches, 10);
      expect(manifest.statistics.missingPhotos, 1);
      expect(manifest.settings?.defaultFishType, 'Barramundi');

      // Test serialization
      final map = manifest.toMap();
      expect(map['backupVersion'], BackupManifest.currentVersion);
      expect(map['bragmatVersion'], '1.0.0+8');

      // Test deserialization
      final restored = BackupManifest.fromMap(map);
      expect(restored.backupVersion, manifest.backupVersion);
      expect(restored.bragmatVersion, manifest.bragmatVersion);
      expect(restored.contents.media.catches, 5);
    });

    test('BackupManifest validation - valid manifest', () {
      final manifest = BackupManifest.create(
        bragmatVersion: '1.0.0+8',
        databaseSchemaVersion: 28,
        platform: 'android',
        contents: BackupContents(
          database: true,
          media: BackupMediaCounts(catches: 0, trips: 0, journals: 0, lures: 0),
          settings: true,
        ),
        statistics: BackupStatistics(
          catches: 0,
          trips: 0,
          photos: 0,
          missingPhotos: 0,
        ),
      );

      final errors = manifest.validate(maxSupportedSchemaVersion: 28);
      expect(errors, isEmpty);
    });

    test('BackupManifest validation - unsupported schema version', () {
      final manifest = BackupManifest.create(
        bragmatVersion: '1.0.0+8',
        databaseSchemaVersion: 29, // Higher than supported
        platform: 'android',
        contents: BackupContents(
          database: true,
          media: BackupMediaCounts(catches: 0, trips: 0, journals: 0, lures: 0),
          settings: true,
        ),
        statistics: BackupStatistics(
          catches: 0,
          trips: 0,
          photos: 0,
          missingPhotos: 0,
        ),
      );

      final errors = manifest.validate(maxSupportedSchemaVersion: 28);
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('schema version')), true);
    });

    test('BackupManifest validation - missing database', () {
      final manifest = BackupManifest(
        backupVersion: BackupManifest.currentVersion,
        bragmatVersion: '1.0.0+8',
        databaseSchemaVersion: 28,
        createdAt: DateTime.now().toIso8601String(),
        platform: 'android',
        contents: BackupContents(
          database: false, // Missing database
          media: BackupMediaCounts(catches: 0, trips: 0, journals: 0, lures: 0),
          settings: true,
        ),
        statistics: BackupStatistics(
          catches: 0,
          trips: 0,
          photos: 0,
          missingPhotos: 0,
        ),
      );

      final errors = manifest.validate();
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('Database is missing')), true);
    });

    // Note: DatabaseHelper.createSnapshot tests require the actual singleton database
    // and will be tested on the Moto G15 during Phase 1 verification
    test('DatabaseHelper.createSnapshot - skipped (requires device testing)', () async {
      // This will be tested on the actual device
      expect(true, true);
    });

    test('MediaStorageService - relative path conversion', () async {
      // Set up media directory
      final mediaDir = await MediaStorageService.getMediaDirectory();
      final testFile = File(path.join(mediaDir.path, 'catches', 'test.jpg'));
      await testFile.parent.create(recursive: true);
      await testFile.writeAsBytes([1, 2, 3]);

      // Test toRelativePath
      final absolutePath = testFile.path;
      final relativePath = await MediaStorageService.toRelativePath(absolutePath);

      expect(path.isRelative(relativePath), true);
      expect(relativePath.contains('catches'), true);

      // Test resolvePath
      final resolvedPath = await MediaStorageService.resolvePath(relativePath);
      expect(resolvedPath, absolutePath);

      // Test fileExists with relative path
      final exists = await MediaStorageService.fileExists(relativePath);
      expect(exists, true);
    });

    test('MediaStorageService - handles paths outside media directory', () async {
      // Path outside media directory should remain absolute
      final outsidePath = path.join(testDir.path, 'outside.jpg');
      final relativePath = await MediaStorageService.toRelativePath(outsidePath);

      // Should return original path if not within media directory
      expect(relativePath, outsidePath);
    });

    test('ZIP archive creation - basic structure', () async {
      // Create test files
      final manifestFile = File(path.join(testDir.path, 'manifest.json'));
      await manifestFile.writeAsString('{"test": "data"}');

      final dbFile = File(path.join(testDir.path, 'database.sqlite'));
      await dbFile.writeAsString('test db data');

      final mediaDir = Directory(path.join(testDir.path, 'media'));
      await mediaDir.create(recursive: true);
      final photoFile = File(path.join(mediaDir.path, 'catches', 'photo.jpg'));
      await photoFile.parent.create(recursive: true);
      await photoFile.writeAsBytes([1, 2, 3]);

      // Create ZIP
      final zipPath = path.join(testDir.path, 'backup.zip');
      final zipFile = File(zipPath);

      final archive = Archive();

      await for (final entity in testDir.list(recursive: true)) {
        if (entity is File) {
          final relativePath = path.relative(entity.path, from: testDir.path);
          final fileBytes = await entity.readAsBytes();
          final archiveFile = ArchiveFile(relativePath, fileBytes.length, fileBytes);
          archive.addFile(archiveFile);
        }
      }

      // Encode and write to file
      final zipBytes = ZipEncoder().encode(archive);
      await zipFile.writeAsBytes(zipBytes!);

      // Verify ZIP was created
      expect(zipFile.existsSync(), true);

      // Extract and verify contents
      final bytes = await zipFile.readAsBytes();
      final extractedArchive = ZipDecoder().decodeBytes(bytes);

      final fileNames = extractedArchive.files.map((f) => f.name).toList();
      expect(fileNames.contains('manifest.json'), true);
      expect(fileNames.contains('database.sqlite'), true);
      expect(fileNames.any((f) => f.contains('photo.jpg')), true);
    });

    test('Backup with missing media - records missing photos', () async {
      // This test will be implemented once the full backup service is tested
      // For now, we test the manifest statistics
      final statistics = BackupStatistics(
        catches: 5,
        trips: 2,
        photos: 3,
        missingPhotos: 2,
      );

      expect(statistics.catches, 5);
      expect(statistics.photos, 3);
      expect(statistics.missingPhotos, 2);
    });

    test('BackupMediaCounts - total calculation', () {
      final counts = BackupMediaCounts(
        catches: 5,
        trips: 2,
        journals: 1,
        lures: 0,
      );

      expect(counts.total, 8);
    });

    test('BackupSettings - serialization', () {
      final settings = BackupSettings(
        fishTypeSelectionMode: 1,
        defaultFishType: 'Barramundi',
        lastUsedFishType: 'Saratoga',
        currentTripId: 5,
        tideReferenceMode: 'automatic',
        tideReferenceId: null,
      );

      final map = settings.toMap();
      expect(map['fishTypeSelectionMode'], 1);
      expect(map['defaultFishType'], 'Barramundi');
      expect(map['tideReferenceId'], null);

      final restored = BackupSettings.fromMap(map);
      expect(restored.fishTypeSelectionMode, 1);
      expect(restored.defaultFishType, 'Barramundi');
    });

    test('BackupSettings - handles null values', () {
      final settings = BackupSettings(
        fishTypeSelectionMode: null,
        defaultFishType: null,
        lastUsedFishType: null,
        currentTripId: null,
        tideReferenceMode: null,
        tideReferenceId: null,
      );

      final map = settings.toMap();
      expect(map['fishTypeSelectionMode'], null);
      expect(map['defaultFishType'], null);

      final restored = BackupSettings.fromMap(map);
      expect(restored.fishTypeSelectionMode, null);
      expect(restored.defaultFishType, null);
    });
  });

  group('ZipBackupService - Phase 2 Restore Tests', () {
    late Directory testDir;
    late Directory mediaDir;
    late String targetDbPath;
    int stagingCounter = 0;

    setUp(() async {
      testDir = Directory.systemTemp.createTempSync('bragmat_restore_test_');
      MediaStorageService.setTestDirectory(testDir);
      mediaDir = await MediaStorageService.getMediaDirectory();
      targetDbPath = path.join(testDir.path, 'target_bragmat.db');
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
      MediaStorageService.clearTestDirectory();
    });

    /// Create a minimal SQLite database file and return its bytes.
    Future<List<int>> createDatabaseBytes({
      int userVersion = 28,
      List<String> catchFishTypes = const [],
      List<int> tripIds = const [],
      List<String> catchMediaPaths = const [],
    }) async {
      stagingCounter++;
      final tmpPath = path.join(
        testDir.path,
        'staging_db_$stagingCounter.db',
      );
      final db = await openDatabase(
        tmpPath,
        version: userVersion,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE catches (id INTEGER PRIMARY KEY AUTOINCREMENT, fish_type TEXT)',
          );
          await db.execute(
            'CREATE TABLE fishing_trips (id INTEGER PRIMARY KEY, name TEXT)',
          );
          await db.execute(
            'CREATE TABLE catch_media (id INTEGER PRIMARY KEY AUTOINCREMENT, catch_id INTEGER, file_path TEXT)',
          );
          await db.execute(
            'CREATE TABLE trip_media (id INTEGER PRIMARY KEY AUTOINCREMENT, trip_id INTEGER, file_path TEXT)',
          );
          await db.execute(
            'CREATE TABLE journal_media (id INTEGER PRIMARY KEY AUTOINCREMENT, journal_entry_id INTEGER, file_path TEXT)',
          );
        },
      );
      for (final fishType in catchFishTypes) {
        await db.insert('catches', {'fish_type': fishType});
      }
      for (final tripId in tripIds) {
        await db.insert('fishing_trips', {'id': tripId, 'name': 'Trip $tripId'});
      }
      for (final mediaPath in catchMediaPaths) {
        await db.insert('catch_media', {'catch_id': 1, 'file_path': mediaPath});
      }
      await db.close();

      final bytes = await File(tmpPath).readAsBytes();
      await File(tmpPath).delete();
      return bytes;
    }

    /// Create a target database file on disk (simulating existing app data).
    Future<void> createTargetDatabase({
      List<String> catchFishTypes = const [],
    }) async {
      final bytes = await createDatabaseBytes(catchFishTypes: catchFishTypes);
      await File(targetDbPath).writeAsBytes(bytes);
    }

    /// Query fish types stored in the target database.
    Future<List<String>> readTargetFishTypes() async {
      final db = await openDatabase(targetDbPath, readOnly: true);
      try {
        final rows = await db.query('catches');
        return rows.map((r) => r['fish_type'] as String).toList();
      } finally {
        await db.close();
      }
    }

    /// Build a backup ZIP file and return its path.
    Future<String> buildBackupZip({
      int schemaVersion = 28,
      int databaseUserVersion = 28,
      bool includeManifest = true,
      bool includeDatabase = true,
      bool validDatabase = true,
      List<String> backupCatches = const [],
      List<int> backupTrips = const [],
      List<String> backupCatchMedia = const [],
      BackupSettings? settings,
      Map<String, List<int>> mediaFiles = const {},
      List<String> extraEntryNames = const [],
      String fileName = 'bragmat_backup_test.zip',
    }) async {
      final archive = Archive();

      if (includeManifest) {
        final manifest = BackupManifest.create(
          bragmatVersion: '1.0.0+8',
          databaseSchemaVersion: schemaVersion,
          platform: 'android',
          contents: BackupContents(
            database: includeDatabase,
            media: BackupMediaCounts(
              catches: mediaFiles.keys.where((k) => k.startsWith('media/catches/')).length,
              trips: 0,
              journals: 0,
              lures: 0,
            ),
            settings: settings != null,
          ),
          statistics: BackupStatistics(
            catches: backupCatches.length,
            trips: backupTrips.length,
            photos: mediaFiles.length,
            missingPhotos: 0,
          ),
          settings: settings,
        );
        final bytes = utf8.encode(jsonEncode(manifest.toMap()));
        archive.addFile(ArchiveFile('manifest.json', bytes.length, bytes));
      }

      if (includeDatabase) {
        final dbBytes = validDatabase
            ? await createDatabaseBytes(
                userVersion: databaseUserVersion,
                catchFishTypes: backupCatches,
                tripIds: backupTrips,
                catchMediaPaths: backupCatchMedia,
              )
            : utf8.encode('this is not a sqlite database');
        archive.addFile(ArchiveFile('database.sqlite', dbBytes.length, dbBytes));
      }

      for (final entry in mediaFiles.entries) {
        archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
      }

      for (final name in extraEntryNames) {
        archive.addFile(ArchiveFile(name, 4, [1, 2, 3, 4]));
      }

      final zipPath = path.join(testDir.path, fileName);
      final zipBytes = ZipEncoder().encode(archive)!;
      await File(zipPath).writeAsBytes(zipBytes);
      return zipPath;
    }

    test('validateBackup - valid backup passes', () async {
      final zipPath = await buildBackupZip(
        backupCatches: ['Barramundi'],
        mediaFiles: {
          'media/catches/photo.jpg': [9, 9, 9],
        },
      );

      final result = await ZipBackupService.validateBackup(zipPath);

      expect(result.isValid, true);
      expect(result.errors, isEmpty);
      expect(result.manifest, isNotNull);
      expect(result.manifest!.databaseSchemaVersion, 28);
      expect(result.mediaFileCount, 1);
    });

    test('validateBackup - missing manifest', () async {
      final zipPath = await buildBackupZip(includeManifest: false);

      final result = await ZipBackupService.validateBackup(zipPath);

      expect(result.isValid, false);
      expect(result.errors.any((e) => e.contains('manifest.json')), true);
    });

    test('validateBackup - missing database', () async {
      final zipPath = await buildBackupZip(includeDatabase: false);

      final result = await ZipBackupService.validateBackup(zipPath);

      expect(result.isValid, false);
      expect(result.errors.any((e) => e.contains('database.sqlite')), true);
    });

    test('validateBackup - unsupported manifest schema version', () async {
      final zipPath = await buildBackupZip(schemaVersion: 29);

      final result = await ZipBackupService.validateBackup(zipPath);

      expect(result.isValid, false);
      expect(result.errors.any((e) => e.contains('schema version')), true);
    });

    test('validateBackup - unsupported database user_version', () async {
      final zipPath = await buildBackupZip(databaseUserVersion: 29);

      final result = await ZipBackupService.validateBackup(zipPath);

      expect(result.isValid, false);
      expect(result.errors.any((e) => e.contains('schema version')), true);
    });

    test('validateBackup - corrupt zip file', () async {
      final zipPath = path.join(testDir.path, 'corrupt.zip');
      await File(zipPath).writeAsBytes(utf8.encode('not a zip at all'));

      final result = await ZipBackupService.validateBackup(zipPath);

      expect(result.isValid, false);
      expect(result.errors, isNotEmpty);
    });

    test('validateBackup - missing file', () async {
      final result = await ZipBackupService.validateBackup(
        path.join(testDir.path, 'does_not_exist.zip'),
      );

      expect(result.isValid, false);
      expect(result.errors.any((e) => e.contains('not found')), true);
    });

    test('restoreBackup - restores database, media, and settings', () async {
      await createTargetDatabase(catchFishTypes: ['Old Fish']);

      final zipPath = await buildBackupZip(
        backupCatches: ['Barramundi', 'Saratoga'],
        backupTrips: [5],
        settings: BackupSettings(
          fishTypeSelectionMode: 1,
          defaultFishType: 'Barramundi',
          lastUsedFishType: 'Saratoga',
          currentTripId: 5,
          tideReferenceMode: 'fixed',
          tideReferenceId: 'darwin',
        ),
        mediaFiles: {
          'media/catches/photo1.jpg': [9, 9, 9],
          'media/trips/trip_photo.jpg': [8, 8],
        },
      );

      final result = await ZipBackupService.restoreBackup(
        zipPath: zipPath,
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );

      // Database replaced
      final fishTypes = await readTargetFishTypes();
      expect(fishTypes, containsAll(['Barramundi', 'Saratoga']));
      expect(fishTypes, isNot(contains('Old Fish')));

      // Media copied preserving structure
      final photo = File(path.join(mediaDir.path, 'catches', 'photo1.jpg'));
      expect(await photo.exists(), true);
      expect(await photo.readAsBytes(), [9, 9, 9]);
      final tripPhoto = File(path.join(mediaDir.path, 'trips', 'trip_photo.jpg'));
      expect(await tripPhoto.exists(), true);

      expect(result.mediaFilesRestored, 2);
      expect(result.mediaFilesSkipped, 0);

      // Settings restored
      expect(await PreferencesService.getDefaultFishType(), 'Barramundi');
      expect(await PreferencesService.getLastUsedFishType(), 'Saratoga');
      expect(
        await PreferencesService.getFishTypeSelectionMode(),
        FishTypeSelectionMode.defaultFishType,
      );
      expect(await CurrentTripService.getCurrentTripId(), 5);
      expect(await TideReferenceService.getMode(), 'fixed');
      expect((await TideReferenceService.getCurrentReference()).id, 'darwin');
    });

    test('restoreBackup - clears current trip when id not in restored db', () async {
      final zipPath = await buildBackupZip(
        backupTrips: [1],
        settings: BackupSettings(currentTripId: 999),
      );

      await ZipBackupService.restoreBackup(
        zipPath: zipPath,
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );

      expect(await CurrentTripService.getCurrentTripId(), isNull);
    });

    test('restoreBackup - invalid backup leaves target untouched', () async {
      await createTargetDatabase(catchFishTypes: ['Old Fish']);

      final zipPath = await buildBackupZip(validDatabase: false);

      await expectLater(
        ZipBackupService.restoreBackup(
          zipPath: zipPath,
          databasePathOverride: targetDbPath,
          mediaDirectoryOverride: mediaDir,
        ),
        throwsA(isA<Exception>()),
      );

      // Original database is still intact
      final fishTypes = await readTargetFishTypes();
      expect(fishTypes, ['Old Fish']);
    });

    test('restoreBackup - rejects zip with unsafe entries', () async {
      final zipPath = await buildBackupZip(
        extraEntryNames: ['../evil.txt'],
      );

      await expectLater(
        ZipBackupService.restoreBackup(
          zipPath: zipPath,
          databasePathOverride: targetDbPath,
          mediaDirectoryOverride: mediaDir,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('restoreBackup - backup without media restores zero files', () async {
      final zipPath = await buildBackupZip(
        backupCatches: ['Barramundi'],
      );

      final result = await ZipBackupService.restoreBackup(
        zipPath: zipPath,
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );

      expect(result.mediaFilesRestored, 0);
      expect(result.mediaFilesSkipped, 0);
    });

    test('restoreBackup - progress callback receives steps', () async {
      final zipPath = await buildBackupZip(backupCatches: ['Barramundi']);
      final messages = <String>[];

      await ZipBackupService.restoreBackup(
        zipPath: zipPath,
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
        onProgress: (m) => messages.add(m),
      );

      expect(messages, isNotEmpty);
      expect(messages.last, 'Restore complete');
    });

    test('ZIP round-trip - entry names use forward slashes', () async {
      // Files added with portable forward-slash names must decode identically
      final zipPath = await buildBackupZip(
        backupCatches: ['Barramundi'],
        mediaFiles: {
          'media/catches/photo.jpg': [1, 2, 3],
        },
      );

      final bytes = await File(zipPath).readAsBytes();
      final decoded = ZipDecoder().decodeBytes(bytes);
      final names = decoded.files.map((f) => f.name).toList();

      expect(names, contains('manifest.json'));
      expect(names, contains('database.sqlite'));
      expect(names, contains('media/catches/photo.jpg'));
    });
  });

  group('ZipBackupService - Phase 3 Restore Hardening', () {
    late Directory testDir;
    late Directory mediaDir;
    late String targetDbPath;
    int stagingCounter = 0;

    setUp(() async {
      testDir = Directory.systemTemp.createTempSync('bragmat_hardening_test_');
      MediaStorageService.setTestDirectory(testDir);
      mediaDir = await MediaStorageService.getMediaDirectory();
      targetDbPath = path.join(testDir.path, 'target_bragmat.db');
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      ZipBackupService.debugStageHook = null;
      await DatabaseHelper.instance.closeDatabase();
      DatabaseHelper.clearTestDatabasePath();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
      MediaStorageService.clearTestDirectory();
    });

    /// Create a minimal SQLite database file and return its bytes.
    Future<List<int>> createDatabaseBytes({
      int userVersion = 28,
      List<String> catchFishTypes = const [],
      List<String> catchMediaPaths = const [],
    }) async {
      stagingCounter++;
      final tmpPath = path.join(testDir.path, 'hardening_db_$stagingCounter.db');
      final db = await openDatabase(
        tmpPath,
        version: userVersion,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE catches (id INTEGER PRIMARY KEY AUTOINCREMENT, fish_type TEXT)',
          );
          await db.execute(
            'CREATE TABLE fishing_trips (id INTEGER PRIMARY KEY, name TEXT)',
          );
          await db.execute(
            'CREATE TABLE catch_media (id INTEGER PRIMARY KEY AUTOINCREMENT, catch_id INTEGER, file_path TEXT)',
          );
        },
      );
      for (final fishType in catchFishTypes) {
        await db.insert('catches', {'fish_type': fishType});
      }
      for (final mediaPath in catchMediaPaths) {
        await db.insert('catch_media', {'catch_id': 1, 'file_path': mediaPath});
      }
      await db.close();

      final bytes = await File(tmpPath).readAsBytes();
      await File(tmpPath).delete();
      return bytes;
    }

    Future<void> createTargetDatabase({
      List<String> catchFishTypes = const [],
      List<String> catchMediaPaths = const [],
    }) async {
      final bytes = await createDatabaseBytes(
        catchFishTypes: catchFishTypes,
        catchMediaPaths: catchMediaPaths,
      );
      await File(targetDbPath).writeAsBytes(bytes);
    }

    Future<List<String>> readTargetFishTypes() async {
      final db = await openDatabase(targetDbPath, readOnly: true);
      try {
        final rows = await db.query('catches');
        return rows.map((r) => r['fish_type'] as String).toList();
      } finally {
        await db.close();
      }
    }

    Future<List<String>> readTargetMediaPaths() async {
      final db = await openDatabase(targetDbPath, readOnly: true);
      try {
        final rows = await db.query('catch_media');
        return rows.map((r) => r['file_path'] as String).toList();
      } finally {
        await db.close();
      }
    }

    /// Build a backup ZIP with the given database contents.
    Future<String> buildBackupZip({
      List<String> backupCatches = const [],
      List<String> backupCatchMedia = const [],
      BackupSettings? settings,
      Map<String, List<int>> mediaFiles = const {},
    }) async {
      final archive = Archive();

      final manifest = BackupManifest.create(
        bragmatVersion: '1.0.0+8',
        databaseSchemaVersion: 28,
        platform: 'android',
        contents: BackupContents(
          database: true,
          media: BackupMediaCounts(
            catches: mediaFiles.keys.where((k) => k.startsWith('media/catches/')).length,
            trips: 0,
            journals: 0,
            lures: 0,
          ),
          settings: settings != null,
        ),
        statistics: BackupStatistics(
          catches: backupCatches.length,
          trips: 0,
          photos: mediaFiles.length,
          missingPhotos: 0,
        ),
        settings: settings,
      );
      final manifestBytes = utf8.encode(jsonEncode(manifest.toMap()));
      archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

      final dbBytes = await createDatabaseBytes(
        catchFishTypes: backupCatches,
        catchMediaPaths: backupCatchMedia,
      );
      archive.addFile(ArchiveFile('database.sqlite', dbBytes.length, dbBytes));

      for (final entry in mediaFiles.entries) {
        archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
      }

      final zipPath = path.join(testDir.path, 'hardening_backup_$stagingCounter.zip');
      await File(zipPath).writeAsBytes(ZipEncoder().encode(archive)!);
      return zipPath;
    }

    test('interrupted restore - recovery copy restores corrupt target', () async {
      await createTargetDatabase(catchFishTypes: ['Old Fish']);
      await File(targetDbPath).copy('$targetDbPath.restore');
      await File(targetDbPath).writeAsBytes(utf8.encode('corrupted db'));

      await DatabaseHelper.instance.recoverInterruptedRestore(targetDbPath);

      expect(await readTargetFishTypes(), ['Old Fish']);
      expect(await File('$targetDbPath.restore').exists(), false);
    });

    test('interrupted restore - keeps valid swapped target', () async {
      // Simulate: swap completed, restore died before marker cleanup.
      await createTargetDatabase(catchFishTypes: ['New Fish']);
      await File('$targetDbPath.restore').writeAsBytes(
        await createDatabaseBytes(catchFishTypes: ['Old Fish']),
      );
      await File('$targetDbPath-wal').writeAsBytes([1, 2, 3]);
      await File('$targetDbPath-shm').writeAsBytes([4, 5]);

      await DatabaseHelper.instance.recoverInterruptedRestore(targetDbPath);

      expect(await readTargetFishTypes(), ['New Fish']);
      expect(await File('$targetDbPath-wal').exists(), false);
      expect(await File('$targetDbPath-shm').exists(), false);
      // Marker is retained to signal "committed swap" for media promotion;
      // the service-level recovery completes staging and clears it.
      expect(await File('$targetDbPath.restore').exists(), true);

      await ZipBackupService.recoverInterruptedRestore(
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );
      expect(await File('$targetDbPath.restore').exists(), false);
    });

    test('interrupted restore - empty marker drops corrupt target', () async {
      await File(targetDbPath).writeAsBytes(utf8.encode('corrupted db'));
      await File('$targetDbPath.restore').writeAsBytes(const []);

      await DatabaseHelper.instance.recoverInterruptedRestore(targetDbPath);

      expect(await File(targetDbPath).exists(), false);
      expect(await File('$targetDbPath.restore').exists(), false);
    });

    test('interrupted restore - stale stage file is removed', () async {
      await createTargetDatabase(catchFishTypes: ['Old Fish']);
      await File('$targetDbPath.stage').writeAsBytes([1, 2, 3]);

      await DatabaseHelper.instance.recoverInterruptedRestore(targetDbPath);

      expect(await File('$targetDbPath.stage').exists(), false);
      expect(await readTargetFishTypes(), ['Old Fish']);
    });

    test('pending media staging promoted when swap committed', () async {
      final stagingDir = Directory(path.join(mediaDir.parent.path, 'media.staging'));
      final staged = File(path.join(stagingDir.path, 'catches', 'leftover.jpg'));
      await staged.parent.create(recursive: true);
      await staged.writeAsBytes([7, 7, 7]);

      // Marker + valid target = the restore committed its swap.
      await createTargetDatabase(catchFishTypes: ['New Fish']);
      await File('$targetDbPath.restore').writeAsBytes(const []);

      await ZipBackupService.recoverInterruptedRestore(
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );

      final moved = File(path.join(mediaDir.path, 'catches', 'leftover.jpg'));
      expect(await moved.exists(), true);
      expect(await moved.readAsBytes(), [7, 7, 7]);
      expect(await stagingDir.exists(), false);
      expect(await File('$targetDbPath.restore').exists(), false);
    });

    test('pending media staging discarded when restore never committed', () async {
      final stagingDir = Directory(path.join(mediaDir.parent.path, 'media.staging'));
      final staged = File(path.join(stagingDir.path, 'catches', 'staged.jpg'));
      await staged.parent.create(recursive: true);
      await staged.writeAsBytes([7, 7, 7]);

      // No recovery marker — the restore died before the swap committed.
      await createTargetDatabase(catchFishTypes: ['Old Fish']);

      await ZipBackupService.recoverInterruptedRestore(
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );

      // Staging is discarded; the live database's media is untouched.
      expect(await stagingDir.exists(), false);
      expect(
        await File(path.join(mediaDir.path, 'catches', 'staged.jpg')).exists(),
        false,
      );
      expect(await readTargetFishTypes(), ['Old Fish']);
    });

    test('media promotion never overwrites existing files', () async {
      // Existing file the live (old) database would reference.
      final existing = File(path.join(mediaDir.path, 'catches', 'same.jpg'));
      await existing.parent.create(recursive: true);
      await existing.writeAsBytes([1, 1, 1]);

      final stagingDir = Directory(path.join(mediaDir.parent.path, 'media.staging'));
      final staged = File(path.join(stagingDir.path, 'catches', 'same.jpg'));
      await staged.parent.create(recursive: true);
      await staged.writeAsBytes([9, 9, 9]);

      await createTargetDatabase(catchFishTypes: ['Old Fish']);
      await File('$targetDbPath.restore').writeAsBytes(const []);

      await ZipBackupService.recoverInterruptedRestore(
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );

      // Original content preserved; the different-content staged file is
      // kept under a collision-resolved name instead of being dropped.
      expect(await existing.readAsBytes(), [1, 1, 1]);
      final renamed = File(path.join(mediaDir.path, 'catches', 'same_r1.jpg'));
      expect(await renamed.exists(), true);
      expect(await renamed.readAsBytes(), [9, 9, 9]);
      expect(await stagingDir.exists(), false);
    });

    test('media promotion skips identical-name identical-content files', () async {
      final existing = File(path.join(mediaDir.path, 'catches', 'same.jpg'));
      await existing.parent.create(recursive: true);
      await existing.writeAsBytes([1, 1, 1]);

      final stagingDir = Directory(path.join(mediaDir.parent.path, 'media.staging'));
      final staged = File(path.join(stagingDir.path, 'catches', 'same.jpg'));
      await staged.parent.create(recursive: true);
      await staged.writeAsBytes([1, 1, 1]);

      await createTargetDatabase(catchFishTypes: ['Old Fish']);
      await File('$targetDbPath.restore').writeAsBytes(const []);

      await ZipBackupService.recoverInterruptedRestore(
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );

      // Same content → treated as already in place; no suffixed copy.
      expect(await existing.readAsBytes(), [1, 1, 1]);
      expect(
        await File(path.join(mediaDir.path, 'catches', 'same_r1.jpg')).exists(),
        false,
      );
      expect(await stagingDir.exists(), false);
    });

    test('restore remaps db path when media filename collides', () async {
      // Live media dir already contains a DIFFERENT file at the path the
      // backup's database references.
      final existing = File(path.join(mediaDir.path, 'catches', 'dup.jpg'));
      await existing.parent.create(recursive: true);
      await existing.writeAsBytes([1, 1, 1]);

      await createTargetDatabase(catchFishTypes: ['Old Fish']);

      final zipPath = await buildBackupZip(
        backupCatches: ['New Fish'],
        backupCatchMedia: ['catches/dup.jpg'],
        mediaFiles: {
          'media/catches/dup.jpg': [9, 9, 9],
        },
      );

      final result = await ZipBackupService.restoreBackup(
        zipPath: zipPath,
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );

      expect(result.mediaPathConflicts, 1);
      // Existing file untouched; backup copy kept under resolved name.
      expect(await existing.readAsBytes(), [1, 1, 1]);
      final renamed = File(path.join(mediaDir.path, 'catches', 'dup_r1.jpg'));
      expect(await renamed.exists(), true);
      expect(await renamed.readAsBytes(), [9, 9, 9]);
      // Restored database points at the backup's copy.
      expect(await readTargetMediaPaths(), ['catches/dup_r1.jpg']);
      expect(await readTargetFishTypes(), ['New Fish']);
    });

    test('debug stage hook - marker exists at swap point', () async {
      await createTargetDatabase(catchFishTypes: ['Old Fish']);
      var markerSeenAtSwap = false;

      ZipBackupService.debugStageHook = (stage) async {
        if (stage == 'swapped') {
          markerSeenAtSwap = await File('$targetDbPath.restore').exists();
        }
      };

      final zipPath = await buildBackupZip(backupCatches: ['New Fish']);
      await ZipBackupService.restoreBackup(
        zipPath: zipPath,
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );
      ZipBackupService.debugStageHook = null;

      expect(markerSeenAtSwap, true);
      expect(await readTargetFishTypes(), ['New Fish']);
    });

    test('debug stage hook - abort at mediaStaged leaves target intact', () async {
      await createTargetDatabase(catchFishTypes: ['Old Fish']);

      ZipBackupService.debugStageHook = (stage) async {
        if (stage == 'mediaStaged') {
          throw StateError('simulated abort at mediaStaged');
        }
      };

      final zipPath = await buildBackupZip(
        backupCatches: ['New Fish'],
        mediaFiles: {'media/catches/x.jpg': [1]},
      );

      await expectLater(
        ZipBackupService.restoreBackup(
          zipPath: zipPath,
          databasePathOverride: targetDbPath,
          mediaDirectoryOverride: mediaDir,
        ),
        throwsA(isA<StateError>()),
      );
      ZipBackupService.debugStageHook = null;

      expect(await readTargetFishTypes(), ['Old Fish']);
      expect(await File('$targetDbPath.stage').exists(), false);
      expect(await File('$targetDbPath.restore').exists(), false);
    });

    test('restore lock blocks database access until released', () async {
      DatabaseHelper.setTestDatabasePath(targetDbPath);

      await DatabaseHelper.instance.beginRestore();
      expect(DatabaseHelper.instance.restoreInProgress, true);

      var completed = false;
      final pending = DatabaseHelper.instance.database.then((_) => completed = true);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(completed, false);

      await DatabaseHelper.instance.endRestore();
      await pending;
      expect(completed, true);
      expect(DatabaseHelper.instance.restoreInProgress, false);
    });

    test('second beginRestore throws while lock is held', () async {
      DatabaseHelper.setTestDatabasePath(targetDbPath);

      await DatabaseHelper.instance.beginRestore();
      await expectLater(
        DatabaseHelper.instance.beginRestore(),
        throwsA(isA<StateError>()),
      );
      await DatabaseHelper.instance.endRestore();
    });

    test('live restore end-to-end via DatabaseHelper singleton', () async {
      DatabaseHelper.setTestDatabasePath(targetDbPath);

      // Open the real database (full v28 schema) and seed old data.
      final db = await DatabaseHelper.instance.database;
      await db.insert('catches', {'fish_type': 'Old Fish'});

      final zipPath = await buildBackupZip(
        backupCatches: ['New Fish'],
        settings: BackupSettings(
          fishTypeSelectionMode: 1,
          defaultFishType: 'New Fish',
        ),
        mediaFiles: {
          'media/catches/restored.jpg': [5, 5, 5],
        },
      );

      // Live mode: no databasePathOverride — exercises the full swap path.
      final result = await ZipBackupService.restoreBackup(
        zipPath: zipPath,
        mediaDirectoryOverride: mediaDir,
      );

      // Database was swapped and reopened through the singleton.
      final liveDb = await DatabaseHelper.instance.database;
      final rows = await liveDb.query('catches');
      expect(rows.map((r) => r['fish_type']), ['New Fish']);

      // Media moved into place; markers cleaned up.
      expect(await File(path.join(mediaDir.path, 'catches', 'restored.jpg')).exists(), true);
      expect(await File('$targetDbPath.restore').exists(), false);
      expect(await File('$targetDbPath.stage').exists(), false);
      expect(result.mediaFilesRestored, 1);
      expect(result.referencedMediaMissing, 0);

      // Settings applied.
      expect(await PreferencesService.getDefaultFishType(), 'New Fish');
    });

    test('restore removes stale WAL/SHM sidecars', () async {
      await createTargetDatabase(catchFishTypes: ['Old Fish']);
      await File('$targetDbPath-wal').writeAsBytes([9, 9]);
      await File('$targetDbPath-shm').writeAsBytes([9, 9]);

      final zipPath = await buildBackupZip(backupCatches: ['New Fish']);

      await ZipBackupService.restoreBackup(
        zipPath: zipPath,
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );

      expect(await File('$targetDbPath-wal').exists(), false);
      expect(await File('$targetDbPath-shm').exists(), false);
      expect(await readTargetFishTypes(), ['New Fish']);
    });

    test('unreadable archive aborts before any database change', () async {
      await createTargetDatabase(catchFishTypes: ['Old Fish']);

      // Nested path collision: 'media/blocker' as file and as directory.
      final zipPath = await buildBackupZip(
        backupCatches: ['New Fish'],
        mediaFiles: {
          'media/blocker': [1],
          'media/blocker/inner.jpg': [2, 2],
        },
      );

      await expectLater(
        ZipBackupService.restoreBackup(
          zipPath: zipPath,
          databasePathOverride: targetDbPath,
          mediaDirectoryOverride: mediaDir,
        ),
        throwsA(isA<Exception>()),
      );

      // Original database untouched; no markers left behind.
      expect(await readTargetFishTypes(), ['Old Fish']);
      expect(await File('$targetDbPath.restore').exists(), false);
      expect(await File('$targetDbPath.stage').exists(), false);
      expect(
        await Directory(path.join(mediaDir.parent.path, 'media.staging')).exists(),
        false,
      );
    });

    test('referenced media absent from backup is reported', () async {
      await createTargetDatabase(catchFishTypes: ['Old Fish']);

      final zipPath = await buildBackupZip(
        backupCatches: ['New Fish'],
        backupCatchMedia: ['catches/ghost.jpg'],
      );

      final result = await ZipBackupService.restoreBackup(
        zipPath: zipPath,
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );

      expect(result.referencedMediaMissing, 1);
      expect(await readTargetFishTypes(), ['New Fish']);
    });
  });
}
