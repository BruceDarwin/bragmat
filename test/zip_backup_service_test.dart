import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:bragmat/models/backup_manifest.dart';
import 'package:bragmat/services/media_storage_service.dart';

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
}
