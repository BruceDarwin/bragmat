import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../database/database_helper.dart';
import '../models/backup_manifest.dart';
import '../services/media_storage_service.dart';
import '../services/preferences_service.dart';
import '../services/current_trip_service.dart';
import '../services/tide_reference_service.dart';

/// Service for creating and restoring portable ZIP backups.
/// 
/// This service handles:
/// - Creating consistent database snapshots using VACUUM INTO
/// - Normalizing media paths to portable relative paths
/// - Assembling ZIP archives with database and media files
/// - Validating backups before restore
/// - Safe restore with rollback capability
class ZipBackupService {
  static const String _databaseFileName = 'database.sqlite';
  static const String _manifestFileName = 'manifest.json';
  static const String _mediaDirectoryName = 'media';
  
  /// Maximum allowed archive size in bytes (500 MB)
  static const int _maxArchiveSize = 500 * 1024 * 1024;
  
  /// Create a portable ZIP backup.
  /// 
  /// Returns the path to the created ZIP file.
  /// 
  /// Throws Exception if backup creation fails.
  static Future<String> createBackup({
    required String outputDirectory,
    Function(String)? onProgress,
  }) async {
    final tempDir = Directory.systemTemp.createTempSync('bragmat_backup_');
    
    try {
      onProgress?.call('Creating database snapshot...');
      
      // Step 1: Create database snapshot
      final snapshotPath = path.join(tempDir.path, _databaseFileName);
      await DatabaseHelper.instance.createSnapshot(snapshotPath);
      
      onProgress?.call('Normalizing media paths...');
      
      // Step 2: Normalize paths in temporary database
      await _normalizeMediaPaths(snapshotPath);
      
      onProgress?.call('Collecting media files...');
      
      // Step 3: Collect media files and statistics
      final mediaResult = await _collectMediaFiles(snapshotPath, tempDir);
      
      onProgress?.call('Creating manifest...');
      
      // Step 4: Create manifest
      final packageInfo = await PackageInfo.fromPlatform();
      final manifest = BackupManifest.create(
        bragmatVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
        databaseSchemaVersion: 28,
        platform: _getPlatform(),
        contents: BackupContents(
          database: true,
          media: mediaResult.counts,
          settings: true,
        ),
        statistics: mediaResult.statistics,
        settings: await _exportSettings(),
      );
      
      // Step 5: Write manifest
      final manifestPath = path.join(tempDir.path, _manifestFileName);
      final manifestFile = File(manifestPath);
      await manifestFile.writeAsString(jsonEncode(manifest.toMap()));
      
      onProgress?.call('Assembling ZIP archive...');
      
      // Step 6: Create ZIP archive
      final zipPath = path.join(outputDirectory, _generateBackupFilename());
      await _createZipArchive(tempDir, zipPath);
      
      // Step 7: Verify archive size
      final zipFile = File(zipPath);
      final zipSize = await zipFile.length();
      if (zipSize > _maxArchiveSize) {
        await zipFile.delete();
        throw Exception('Backup archive exceeds maximum size of ${_maxArchiveSize ~/ (1024 * 1024)} MB');
      }
      
      // Cleanup
      await tempDir.delete(recursive: true);
      
      onProgress?.call('Backup complete');
      
      return zipPath;
    } catch (e) {
      // Cleanup on failure
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      rethrow;
    }
  }
  
  /// Convert a platform path to the portable backup format (forward slashes).
  static String _toPortablePath(String filePath) {
    return filePath.replaceAll('\\', '/');
  }

  /// Normalize media paths in the temporary database to relative paths.
  static Future<void> _normalizeMediaPaths(String databasePath) async {
    final db = await openDatabase(databasePath);
    
    try {
      // Normalize catch_media paths
      final catchMedia = await db.query('catch_media');
      for (final media in catchMedia) {
        final absolutePath = media['file_path'] as String;
        final relativePath = _toPortablePath(await MediaStorageService.toRelativePath(absolutePath));
        
        // Only update if path was successfully converted to relative
        if (relativePath != absolutePath && path.isRelative(relativePath)) {
          await db.update(
            'catch_media',
            {'file_path': relativePath},
            where: 'id = ?',
            whereArgs: [media['id']],
          );
        }
      }
      
      // Normalize trip_media paths
      final tripMedia = await db.query('trip_media');
      for (final media in tripMedia) {
        final absolutePath = media['file_path'] as String;
        final relativePath = _toPortablePath(await MediaStorageService.toRelativePath(absolutePath));
        
        if (relativePath != absolutePath && path.isRelative(relativePath)) {
          await db.update(
            'trip_media',
            {'file_path': relativePath},
            where: 'id = ?',
            whereArgs: [media['id']],
          );
        }
      }
      
      // Normalize journal_media paths
      final journalMedia = await db.query('journal_media');
      for (final media in journalMedia) {
        final absolutePath = media['file_path'] as String;
        final relativePath = _toPortablePath(await MediaStorageService.toRelativePath(absolutePath));
        
        if (relativePath != absolutePath && path.isRelative(relativePath)) {
          await db.update(
            'journal_media',
            {'file_path': relativePath},
            where: 'id = ?',
            whereArgs: [media['id']],
          );
        }
      }
      
      // Normalize lure_photo_path in catches
      final catches = await db.query('catches', columns: ['id', 'lure_photo_path']);
      for (final catch_ in catches) {
        final absolutePath = catch_['lure_photo_path'] as String?;
        if (absolutePath != null && absolutePath.isNotEmpty) {
          final relativePath = _toPortablePath(await MediaStorageService.toRelativePath(absolutePath));
          
          if (relativePath != absolutePath && path.isRelative(relativePath)) {
            await db.update(
              'catches',
              {'lure_photo_path': relativePath},
              where: 'id = ?',
              whereArgs: [catch_['id']],
            );
          }
        }
      }
    } finally {
      await db.close();
    }
  }
  
  /// Collect media files referenced by the database.
  /// 
  /// Returns media counts and statistics, and copies files to the temp directory.
  static Future<_MediaCollectionResult> _collectMediaFiles(
    String databasePath,
    Directory tempDir,
  ) async {
    final db = await openDatabase(databasePath);
    
    final mediaDir = Directory(path.join(tempDir.path, _mediaDirectoryName));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    
    int catchCount = 0;
    int tripCount = 0;
    int journalCount = 0;
    int lureCount = 0;
    int missingPhotos = 0;
    int totalPhotos = 0;
    
    try {
      // Collect catch media
      final catchMedia = await db.query('catch_media');
      for (final media in catchMedia) {
        final relativePath = media['file_path'] as String;
        if (await _copyMediaFile(relativePath, mediaDir, 'catches')) {
          catchCount++;
          totalPhotos++;
        } else {
          missingPhotos++;
        }
      }
      
      // Collect trip media
      final tripMedia = await db.query('trip_media');
      for (final media in tripMedia) {
        final relativePath = media['file_path'] as String;
        if (await _copyMediaFile(relativePath, mediaDir, 'trips')) {
          tripCount++;
          totalPhotos++;
        } else {
          missingPhotos++;
        }
      }
      
      // Collect journal media
      final journalMedia = await db.query('journal_media');
      for (final media in journalMedia) {
        final relativePath = media['file_path'] as String;
        if (await _copyMediaFile(relativePath, mediaDir, 'journals')) {
          journalCount++;
          totalPhotos++;
        } else {
          missingPhotos++;
        }
      }
      
      // Collect lure photos
      final catches = await db.query('catches', columns: ['lure_photo_path']);
      for (final catch_ in catches) {
        final relativePath = catch_['lure_photo_path'] as String?;
        if (relativePath != null && relativePath.isNotEmpty) {
          if (await _copyMediaFile(relativePath, mediaDir, 'lures')) {
            lureCount++;
            totalPhotos++;
          } else {
            missingPhotos++;
          }
        }
      }
      
      // Get catch and trip counts for statistics
      final catchResult = await db.rawQuery('SELECT COUNT(*) as count FROM catches');
      final catchCountStat = Sqflite.firstIntValue(catchResult) ?? 0;
      
      final tripResult = await db.rawQuery('SELECT COUNT(*) as count FROM fishing_trips');
      final tripCountStat = Sqflite.firstIntValue(tripResult) ?? 0;
      
      return _MediaCollectionResult(
        counts: BackupMediaCounts(
          catches: catchCount,
          trips: tripCount,
          journals: journalCount,
          lures: lureCount,
        ),
        statistics: BackupStatistics(
          catches: catchCountStat,
          trips: tripCountStat,
          photos: totalPhotos,
          missingPhotos: missingPhotos,
        ),
      );
    } finally {
      await db.close();
    }
  }
  
  /// Copy a media file to the backup directory.
  /// 
  /// Returns true if successful, false if file is missing or inaccessible.
  static Future<bool> _copyMediaFile(
    String relativePath,
    Directory backupMediaDir,
    String subDir,
  ) async {
    try {
      // Resolve relative path to absolute
      final absolutePath = await MediaStorageService.resolvePath(relativePath);
      final sourceFile = File(absolutePath);
      
      if (!await sourceFile.exists()) {
        return false;
      }
      
      // Determine destination path in backup
      final filename = path.basename(relativePath);
      final destDir = Directory(path.join(backupMediaDir.path, subDir));
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      final destPath = path.join(destDir.path, filename);
      
      // Copy file
      await sourceFile.copy(destPath);
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Export application settings for backup.
  static Future<BackupSettings> _exportSettings() async {
    final fishTypeMode = await PreferencesService.getFishTypeSelectionMode();
    final defaultFishType = await PreferencesService.getDefaultFishType();
    final lastUsedFishType = await PreferencesService.getLastUsedFishType();
    final currentTripId = await CurrentTripService.getCurrentTripId();
    final tideMode = await TideReferenceService.getMode();
    final tideReferenceId = await TideReferenceService.getCurrentReference();
    
    return BackupSettings(
      fishTypeSelectionMode: fishTypeMode.index,
      defaultFishType: defaultFishType,
      lastUsedFishType: lastUsedFishType,
      currentTripId: currentTripId,
      tideReferenceMode: tideMode,
      tideReferenceId: tideReferenceId.id,
    );
  }
  
  /// Create ZIP archive from the temporary directory.
  static Future<void> _createZipArchive(Directory sourceDir, String zipPath) async {
    final zipFile = File(zipPath);
    
    // Create archive
    final archive = Archive();
    
    await for (final entity in sourceDir.list(recursive: true)) {
      if (entity is File) {
        // ZIP entry names must use forward slashes for cross-platform portability
        final relativePath = _toPortablePath(path.relative(entity.path, from: sourceDir.path));
        final fileBytes = await entity.readAsBytes();
        final archiveFile = ArchiveFile(relativePath, fileBytes.length, fileBytes);
        archive.addFile(archiveFile);
      }
    }
    
    // Encode and write to file
    final zipBytes = ZipEncoder().encode(archive);
    await zipFile.writeAsBytes(zipBytes!);
  }
  
  /// Generate a backup filename with timestamp.
  static String _generateBackupFilename() {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    return 'bragmat_backup_$timestamp.zip';
  }
  
  /// Get the current platform identifier.
  static String _getPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  /// Maximum database schema version this build can restore.
  static const int _maxSupportedSchemaVersion = 28;

  /// Validate a backup ZIP without modifying any data.
  ///
  /// Extracts the archive to a temporary location, parses and validates the
  /// manifest, and verifies the embedded database integrity.
  ///
  /// Returns a [BackupValidationResult] containing the manifest (if readable)
  /// and a list of validation errors. The backup is usable when
  /// [BackupValidationResult.isValid] is true.
  static Future<BackupValidationResult> validateBackup(String zipPath) async {
    final tempDir = Directory.systemTemp.createTempSync('bragmat_restore_validate_');

    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return BackupValidationResult(errors: ['Backup file not found']);
      }

      final zipSize = await zipFile.length();
      if (zipSize > _maxArchiveSize) {
        return BackupValidationResult(errors: [
          'Backup archive exceeds maximum size of ${_maxArchiveSize ~/ (1024 * 1024)} MB',
        ]);
      }

      final Directory extractDir;
      try {
        extractDir = await _extractZip(zipPath, tempDir);
      } catch (e) {
        return BackupValidationResult(errors: [_errorMessage(e)]);
      }

      return await _validateExtracted(extractDir);
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  /// Restore a portable ZIP backup, replacing the current database and media.
  ///
  /// The backup is fully validated before any changes are made. A safety
  /// snapshot of the current database is taken before the swap so the original
  /// data can be restored if the backup's database fails verification.
  ///
  /// Parameters:
  /// - [zipPath]: path to the backup ZIP file
  /// - [onProgress]: optional callback for progress messages
  /// - [databasePathOverride]: target database path (defaults to the live
  ///   database; used for testing — when set, the live database connection is
  ///   not touched)
  /// - [mediaDirectoryOverride]: target media directory (defaults to
  ///   [MediaStorageService.getMediaDirectory]; used for testing)
  ///
  /// Returns a [BackupRestoreResult] describing what was restored.
  ///
  /// Throws Exception if the backup is invalid or the restore fails.
  static Future<BackupRestoreResult> restoreBackup({
    required String zipPath,
    Function(String)? onProgress,
    String? databasePathOverride,
    Directory? mediaDirectoryOverride,
  }) async {
    final tempDir = Directory.systemTemp.createTempSync('bragmat_restore_');

    try {
      onProgress?.call('Extracting backup...');

      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        throw Exception('Backup file not found');
      }
      if (await zipFile.length() > _maxArchiveSize) {
        throw Exception('Backup archive exceeds maximum size of ${_maxArchiveSize ~/ (1024 * 1024)} MB');
      }

      final extractDir = await _extractZip(zipPath, tempDir);

      onProgress?.call('Validating backup...');

      final validation = await _validateExtracted(extractDir);
      if (!validation.isValid) {
        throw Exception('Invalid backup: ${validation.errors.join('; ')}');
      }

      final sourceDbFile = File(path.join(extractDir.path, _databaseFileName));
      final liveMode = databasePathOverride == null;
      final targetDbPath =
          databasePathOverride ?? await DatabaseHelper.instance.databaseFilePath;
      final targetDbFile = File(targetDbPath);

      onProgress?.call('Creating safety snapshot...');

      // Preserve the current database so a failed restore can be rolled back.
      String? rollbackPath;
      if (await targetDbFile.exists()) {
        rollbackPath = path.join(tempDir.path, 'rollback.db');
        if (liveMode) {
          await DatabaseHelper.instance.createSnapshot(rollbackPath);
        } else {
          await targetDbFile.copy(rollbackPath);
        }
      }

      onProgress?.call('Restoring database...');

      if (liveMode) {
        await DatabaseHelper.instance.closeDatabase();
      }

      try {
        await sourceDbFile.copy(targetDbPath);
      } catch (e) {
        await _rollbackDatabase(targetDbPath, rollbackPath, liveMode);
        throw Exception('Failed to restore database: $e');
      }

      // Verify the swapped-in database before touching anything else.
      if (!await _verifyDatabaseFile(targetDbPath)) {
        await _rollbackDatabase(targetDbPath, rollbackPath, liveMode);
        throw Exception('Restored database failed integrity check; original data was preserved');
      }

      onProgress?.call('Restoring media files...');

      final mediaResult = await _restoreMediaFiles(
        extractDir,
        mediaDirectoryOverride ?? await MediaStorageService.getMediaDirectory(),
      );

      onProgress?.call('Restoring settings...');

      final settings = validation.manifest?.settings;
      if (settings != null) {
        await _restoreSettings(settings, targetDbPath, liveMode);
      }

      if (liveMode) {
        // Re-open the live database so the app can keep using it.
        await DatabaseHelper.instance.database;
      }

      await tempDir.delete(recursive: true);

      onProgress?.call('Restore complete');

      return BackupRestoreResult(
        manifest: validation.manifest!,
        mediaFilesRestored: mediaResult.restored,
        mediaFilesSkipped: mediaResult.skipped,
      );
    } catch (e) {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      rethrow;
    }
  }

  /// Extract a backup ZIP into [tempDir]/extracted with traversal protection.
  static Future<Directory> _extractZip(String zipPath, Directory tempDir) async {
    final bytes = await File(zipPath).readAsBytes();

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw Exception('Invalid backup file: not a valid ZIP archive');
    }

    final extractDir = Directory(path.join(tempDir.path, 'extracted'));
    await extractDir.create(recursive: true);

    for (final entry in archive.files) {
      if (!entry.isFile) continue;

      // Normalize separators and guard against path traversal entries.
      final normalized = path.posix.normalize(_toPortablePath(entry.name));
      if (normalized == '..' ||
          normalized.startsWith('../') ||
          normalized.startsWith('/') ||
          path.posix.isAbsolute(normalized)) {
        throw Exception('Invalid backup file: unsafe entry "${entry.name}"');
      }

      final outFile = File(path.joinAll([extractDir.path, ...normalized.split('/')]));
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(entry.content as List<int>);
    }

    return extractDir;
  }

  /// Validate an extracted backup directory (manifest + database integrity).
  static Future<BackupValidationResult> _validateExtracted(Directory extractDir) async {
    final errors = <String>[];
    BackupManifest? manifest;

    // Parse and validate the manifest.
    final manifestFile = File(path.join(extractDir.path, _manifestFileName));
    if (!await manifestFile.exists()) {
      errors.add('manifest.json is missing from backup');
    } else {
      try {
        final map = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
        manifest = BackupManifest.fromMap(map);
        errors.addAll(manifest.validate(
          maxSupportedSchemaVersion: _maxSupportedSchemaVersion,
        ));
      } catch (e) {
        errors.add('manifest.json is invalid: ${_errorMessage(e)}');
      }
    }

    // Verify the embedded database exists and passes integrity checks.
    final dbFile = File(path.join(extractDir.path, _databaseFileName));
    if (!await dbFile.exists()) {
      errors.add('database.sqlite is missing from backup');
    } else {
      Database? db;
      try {
        db = await openDatabase(dbFile.path, readOnly: true);

        final integrity = await db.rawQuery('PRAGMA integrity_check');
        if (integrity.isEmpty || integrity.first['integrity_check'] != 'ok') {
          errors.add('Backup database failed integrity check');
        }

        final versionRows = await db.rawQuery('PRAGMA user_version');
        final userVersion = Sqflite.firstIntValue(versionRows) ?? 0;
        if (userVersion > _maxSupportedSchemaVersion) {
          errors.add(
            'Backup database schema version $userVersion is not supported '
            '(max: $_maxSupportedSchemaVersion)',
          );
        }
      } catch (e) {
        errors.add('Backup database is not readable: ${_errorMessage(e)}');
      } finally {
        await db?.close();
      }
    }

    // Count media files included in the backup.
    int mediaFileCount = 0;
    final mediaDir = Directory(path.join(extractDir.path, _mediaDirectoryName));
    if (await mediaDir.exists()) {
      await for (final entity in mediaDir.list(recursive: true)) {
        if (entity is File) mediaFileCount++;
      }
    }

    return BackupValidationResult(
      manifest: manifest,
      errors: errors,
      mediaFileCount: mediaFileCount,
    );
  }

  /// Verify a database file opens and passes PRAGMA integrity_check.
  static Future<bool> _verifyDatabaseFile(String dbPath) async {
    Database? db;
    try {
      db = await openDatabase(dbPath, readOnly: true);
      final result = await db.rawQuery('PRAGMA integrity_check');
      return result.isNotEmpty && result.first['integrity_check'] == 'ok';
    } catch (e) {
      return false;
    } finally {
      await db?.close();
    }
  }

  /// Restore the original database after a failed restore attempt.
  static Future<void> _rollbackDatabase(
    String targetDbPath,
    String? rollbackPath,
    bool liveMode,
  ) async {
    try {
      final rollbackFile = rollbackPath != null ? File(rollbackPath) : null;
      if (rollbackFile != null && await rollbackFile.exists()) {
        await rollbackFile.copy(targetDbPath);
      } else {
        final target = File(targetDbPath);
        if (await target.exists()) {
          await target.delete();
        }
      }
    } finally {
      if (liveMode) {
        // Re-open the live database regardless of rollback outcome.
        try {
          await DatabaseHelper.instance.database;
        } catch (_) {}
      }
    }
  }

  /// Copy media files from the extracted backup into the media directory.
  ///
  /// Preserves the relative directory structure under media/ so database
  /// paths (e.g. catches/photo.jpg) resolve correctly after restore.
  static Future<({int restored, int skipped})> _restoreMediaFiles(
    Directory extractDir,
    Directory mediaDir,
  ) async {
    int restored = 0;
    int skipped = 0;

    final sourceMediaDir = Directory(path.join(extractDir.path, _mediaDirectoryName));
    if (!await sourceMediaDir.exists()) {
      return (restored: restored, skipped: skipped);
    }

    await for (final entity in sourceMediaDir.list(recursive: true)) {
      if (entity is! File) continue;
      try {
        final rel = _toPortablePath(path.relative(entity.path, from: sourceMediaDir.path));
        final destFile = File(path.joinAll([mediaDir.path, ...rel.split('/')]));
        await destFile.parent.create(recursive: true);
        await entity.copy(destFile.path);
        restored++;
      } catch (e) {
        skipped++;
      }
    }

    return (restored: restored, skipped: skipped);
  }

  /// Restore application settings captured in the backup manifest.
  static Future<void> _restoreSettings(
    BackupSettings settings,
    String databasePath,
    bool liveMode,
  ) async {
    final modeIndex = settings.fishTypeSelectionMode;
    if (modeIndex != null &&
        modeIndex >= 0 &&
        modeIndex < FishTypeSelectionMode.values.length) {
      await PreferencesService.setFishTypeSelectionMode(
        FishTypeSelectionMode.values[modeIndex],
      );
    }

    if (settings.defaultFishType != null) {
      await PreferencesService.setDefaultFishType(settings.defaultFishType);
    }

    if (settings.lastUsedFishType != null) {
      await PreferencesService.setLastUsedFishType(settings.lastUsedFishType!);
    }

    // Only restore the current trip if it exists in the restored database.
    final currentTripId = settings.currentTripId;
    if (currentTripId != null) {
      Database? db;
      var tripExists = false;
      try {
        db = liveMode
            ? await DatabaseHelper.instance.database
            : await openDatabase(databasePath, readOnly: true);
        final rows = await db.query(
          'fishing_trips',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [currentTripId],
        );
        tripExists = rows.isNotEmpty;
      } catch (e) {
        tripExists = false;
      } finally {
        if (!liveMode) {
          await db?.close();
        }
      }

      if (tripExists) {
        await CurrentTripService.setCurrentTrip(currentTripId);
      } else {
        await CurrentTripService.clearCurrentTrip();
      }
    } else {
      await CurrentTripService.clearCurrentTrip();
    }

    final tideMode = settings.tideReferenceMode;
    final tideRefId = settings.tideReferenceId;
    if (tideMode == 'fixed' &&
        tideRefId != null &&
        TideReferenceService.getReferenceById(tideRefId) != null) {
      await TideReferenceService.setFixedReference(tideRefId);
    } else if (tideMode != null) {
      await TideReferenceService.setAutomaticMode();
    }
  }

  /// Extract a readable message from an error object.
  static String _errorMessage(Object e) {
    return e.toString().replaceFirst('Exception: ', '');
  }
}

/// Internal result class for media collection.
class _MediaCollectionResult {
  final BackupMediaCounts counts;
  final BackupStatistics statistics;
  
  _MediaCollectionResult({
    required this.counts,
    required this.statistics,
  });
}

/// Result of validating a backup file without restoring it.
class BackupValidationResult {
  /// The parsed manifest, or null if it could not be read.
  final BackupManifest? manifest;

  /// Validation errors. Empty means the backup is usable.
  final List<String> errors;

  /// Number of media files contained in the backup.
  final int mediaFileCount;

  BackupValidationResult({
    this.manifest,
    List<String>? errors,
    this.mediaFileCount = 0,
  }) : errors = errors ?? const [];

  /// Whether the backup passed validation and can be restored.
  bool get isValid => manifest != null && errors.isEmpty;
}

/// Result of a completed backup restore.
class BackupRestoreResult {
  /// The manifest from the restored backup.
  final BackupManifest manifest;

  /// Number of media files copied into media storage.
  final int mediaFilesRestored;

  /// Number of media files that could not be copied.
  final int mediaFilesSkipped;

  BackupRestoreResult({
    required this.manifest,
    required this.mediaFilesRestored,
    required this.mediaFilesSkipped,
  });
}
