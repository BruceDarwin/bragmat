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

  /// Directory name used to stage restored media files before the database
  /// is swapped. Created as a sibling of the media directory so final moves
  /// stay on the same filesystem.
  static const String _mediaStagingDirName = 'media.staging';

  /// Debug/test hook invoked at each restore stage boundary.
  ///
  /// Stages, in order: `validated`, `dbStaged`, `mediaStaged`,
  /// `recoveryCreated`, `swapped`, `mediaMoved`, `settingsRestored`,
  /// `restored`. Throwing or calling `exit()` inside the hook simulates an
  /// interruption at that point — for tests and debug builds only.
  static Future<void> Function(String stage)? debugStageHook;

  /// Report progress and fire the debug stage hook.
  static Future<void> _reportStage(
    String stage,
    Function(String)? onProgress,
    String message,
  ) async {
    onProgress?.call(message);
    final hook = debugStageHook;
    if (hook != null) {
      await hook(stage);
    }
  }

  /// Restore a portable ZIP backup, replacing the current database and media.
  ///
  /// Restore is staged for safety:
  /// 1. The ZIP is extracted and fully validated (manifest + integrity).
  /// 2. The replacement database is staged as `<db>.stage` next to the live
  ///    file and verified — a bad file never touches the live path.
  /// 3. All media is copied into a staging directory and every path the
  ///    backup database references is accounted for. A staging failure aborts
  ///    the restore before the database is swapped.
  /// 4. A persistent recovery copy `<db>.restore` is retained for the whole
  ///    swap — if the process dies mid-restore, the next launch recovers via
  ///    [recoverInterruptedRestore].
  /// 5. The live database is closed (blocking other access via the restore
  ///    lock), sidecars are removed, and the staged file is renamed into
  ///    place — atomic on POSIX, and safe on Windows because the target was
  ///    deleted first.
  /// 6. Staged media is moved into place (same-filesystem rename) and
  ///    settings are restored. Only then is the recovery copy deleted.
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

    String? targetDbPath;
    String? stagePath;
    String? recoveryPath;
    Directory? stagingMediaDir;

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
      await _reportStage('validated', onProgress, 'Backup validated');

      final sourceDbFile = File(path.join(extractDir.path, _databaseFileName));
      final liveMode = databasePathOverride == null;
      targetDbPath =
          databasePathOverride ?? await DatabaseHelper.instance.databaseFilePath;
      final targetDbFile = File(targetDbPath);
      final mediaDir =
          mediaDirectoryOverride ?? await MediaStorageService.getMediaDirectory();

      onProgress?.call('Staging database...');

      // Stage the replacement on the same filesystem as the target so the
      // final rename is atomic (POSIX) and cannot produce a torn file.
      stagePath = '$targetDbPath.stage';
      await sourceDbFile.copy(stagePath);
      if (!await _verifyDatabaseFile(stagePath)) {
        throw Exception('Backup database failed integrity check after staging');
      }
      await _reportStage('dbStaged', onProgress, 'Database staged');

      onProgress?.call('Staging media files...');

      // Stage all media and account for every path the backup database
      // references before the database is swapped. Files referenced but
      // absent from the archive are reported; copy failures abort the
      // restore while the live database is still untouched.
      final referencedPaths = await _collectReferencedMediaPaths(sourceDbFile.path);
      stagingMediaDir = _mediaStagingDirectory(mediaDir);
      await _stageMediaFiles(extractDir, stagingMediaDir);
      final missingReferenced = <String>[];
      for (final relPath in referencedPaths) {
        if (path.isAbsolute(relPath)) {
          missingReferenced.add(relPath);
          continue;
        }
        final staged = File(path.joinAll([stagingMediaDir.path, ...relPath.split('/')]));
        if (!await staged.exists()) {
          missingReferenced.add(relPath);
        }
      }
      await _reportStage('mediaStaged', onProgress, 'Media staged');

      onProgress?.call('Creating recovery copy...');

      // Retained next to the live database until the restore is confirmed —
      // doubles as the "restore in flight" marker for next-launch recovery.
      recoveryPath = '$targetDbPath.restore';
      if (await targetDbFile.exists()) {
        if (liveMode) {
          await DatabaseHelper.instance.createSnapshot(recoveryPath);
        } else {
          await targetDbFile.copy(recoveryPath);
        }
      } else {
        await File(recoveryPath).writeAsBytes(const []);
      }
      await _reportStage('recoveryCreated', onProgress, 'Recovery copy created');

      onProgress?.call('Restoring database...');

      if (liveMode) {
        await DatabaseHelper.instance.beginRestore();
      }
      try {
        if (liveMode) {
          await DatabaseHelper.instance.closeDatabase();
        }

        // Sidecars from the old database can never apply to the new file.
        await _deleteSidecars(targetDbPath);

        // Same-directory rename. On POSIX (Android/iOS) rename atomically
        // replaces the destination — there is no gap where no database
        // exists. Windows' MoveFileEx cannot overwrite, so the target is
        // deleted first; the recovery marker covers that brief window.
        if (Platform.isWindows && await targetDbFile.exists()) {
          await targetDbFile.delete();
        }
        await File(stagePath).rename(targetDbPath);
        stagePath = null;

        if (!await _verifyDatabaseFile(targetDbPath)) {
          throw Exception('Restored database failed integrity check');
        }

        if (liveMode) {
          await DatabaseHelper.instance.reopenDatabaseForRestore();
        }
      } catch (e) {
        await _rollbackDatabase(targetDbPath, recoveryPath, liveMode);
        throw Exception('Failed to restore database: ${_errorMessage(e)}');
      } finally {
        if (liveMode) {
          await DatabaseHelper.instance.endRestore();
        }
      }
      await _reportStage('swapped', onProgress, 'Database replaced');

      final mediaResult = await _moveMediaTree(stagingMediaDir, mediaDir);
      if (mediaResult.skipped == 0 && await stagingMediaDir.exists()) {
        await stagingMediaDir.delete(recursive: true);
      }
      if (mediaResult.skipped == 0) {
        stagingMediaDir = null;
      }
      // If files were skipped the staging directory is kept so
      // recoverInterruptedRestore() can retry the move on next launch.
      await _reportStage('mediaMoved', onProgress, 'Media moved');

      final settings = validation.manifest?.settings;
      if (settings != null) {
        try {
          await _restoreSettings(settings, targetDbPath, liveMode);
        } catch (_) {
          // Settings are non-critical — a preferences failure must not
          // fail the restore once the database has been swapped.
        }
      }

      await _reportStage('settingsRestored', onProgress, 'Settings restored');

      // Restore confirmed — drop the recovery marker.
      await File(recoveryPath).delete();
      recoveryPath = null;

      await tempDir.delete(recursive: true);

      await _reportStage('restored', onProgress, 'Restore complete');

      return BackupRestoreResult(
        manifest: validation.manifest!,
        mediaFilesRestored: mediaResult.moved,
        mediaFilesSkipped: mediaResult.skipped,
        referencedMediaMissing: missingReferenced.length,
      );
    } catch (e) {
      // Discard leftovers. The recovery copy is only dropped when the live
      // database is intact (never swapped or successfully rolled back);
      // otherwise it stays for next-launch recovery.
      if (stagePath != null) {
        final stageFile = File(stagePath);
        if (await stageFile.exists()) {
          await stageFile.delete();
        }
      }
      if (stagingMediaDir != null && await stagingMediaDir.exists()) {
        await stagingMediaDir.delete(recursive: true);
      }
      if (targetDbPath != null &&
          recoveryPath != null &&
          await File(recoveryPath).exists() &&
          await _verifyDatabaseFile(targetDbPath)) {
        await File(recoveryPath).delete();
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      rethrow;
    }
  }

  /// Recover after an interrupted restore.
  ///
  /// Called at application startup. Delegates database-file recovery to
  /// [DatabaseHelper.recoverInterruptedRestore] (which also runs on first
  /// database access) and completes any pending media staging move.
  ///
  /// Staged media is only promoted when the database swap committed — the
  /// helper retains the `.restore` marker in exactly that case. Staging left
  /// by a restore that never swapped (or was rolled back) is discarded so
  /// the live database never references media from an aborted restore.
  static Future<void> recoverInterruptedRestore({
    String? databasePathOverride,
    Directory? mediaDirectoryOverride,
  }) async {
    await DatabaseHelper.instance
        .recoverInterruptedRestore(databasePathOverride);

    final dbPath = databasePathOverride ??
        await DatabaseHelper.instance.databaseFilePath;
    final mediaDir =
        mediaDirectoryOverride ?? await MediaStorageService.getMediaDirectory();

    // Marker still present after helper recovery → the swap committed and
    // staged media belongs to the now-live database.
    final recoveryMarker = File('$dbPath.restore');
    final swapCommitted = await recoveryMarker.exists();

    await completePendingMediaStaging(mediaDir, promote: swapCommitted);

    if (swapCommitted) {
      await recoveryMarker.delete();
    }
  }

  /// Move leftover staged media into place and remove the staging dir.
  ///
  /// When [promote] is false the staging directory is discarded instead —
  /// the restore it belonged to never committed its database swap, so the
  /// files must not overwrite media referenced by the live database.
  static Future<void> completePendingMediaStaging(
    Directory mediaDir, {
    required bool promote,
  }) async {
    final stagingDir = _mediaStagingDirectory(mediaDir);
    if (!await stagingDir.exists()) {
      return;
    }
    if (!promote) {
      await stagingDir.delete(recursive: true);
      return;
    }
    final result = await _moveMediaTree(stagingDir, mediaDir);
    if (result.skipped == 0) {
      await stagingDir.delete(recursive: true);
    }
  }

  /// The staging directory for restored media, sibling of [mediaDir].
  static Directory _mediaStagingDirectory(Directory mediaDir) {
    return Directory(path.join(mediaDir.parent.path, _mediaStagingDirName));
  }

  /// Collect every media path referenced by a backup database.
  static Future<Set<String>> _collectReferencedMediaPaths(String dbPath) async {
    final paths = <String>{};
    Database? db;
    try {
      db = await openDatabase(dbPath, readOnly: true);
      for (final table in const ['catch_media', 'trip_media', 'journal_media']) {
        try {
          final rows = await db.query(table, columns: ['file_path']);
          for (final row in rows) {
            final filePath = row['file_path'] as String?;
            if (filePath != null && filePath.isNotEmpty) {
              paths.add(_toPortablePath(filePath));
            }
          }
        } catch (_) {
          // Table may not exist in older-schema backups.
        }
      }
      try {
        final rows = await db.query('catches', columns: ['lure_photo_path']);
        for (final row in rows) {
          final filePath = row['lure_photo_path'] as String?;
          if (filePath != null && filePath.isNotEmpty) {
            paths.add(_toPortablePath(filePath));
          }
        }
      } catch (_) {}
    } finally {
      await db?.close();
    }
    return paths;
  }

  /// Copy all media from the extracted backup into [stagingDir].
  ///
  /// The staging directory sits next to the media directory so the final
  /// move stays on the same filesystem. A copy failure aborts the restore.
  static Future<void> _stageMediaFiles(
    Directory extractDir,
    Directory stagingDir,
  ) async {
    if (await stagingDir.exists()) {
      await stagingDir.delete(recursive: true);
    }

    final sourceMediaDir = Directory(path.join(extractDir.path, _mediaDirectoryName));
    if (!await sourceMediaDir.exists()) {
      return; // Nothing to stage.
    }

    await for (final entity in sourceMediaDir.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = _toPortablePath(path.relative(entity.path, from: sourceMediaDir.path));
      final destFile = File(path.joinAll([stagingDir.path, ...rel.split('/')]));
      await destFile.parent.create(recursive: true);
      await entity.copy(destFile.path);
    }
  }

  /// Move staged media files into [mediaDir], preserving relative paths.
  ///
  /// Existing destination files are never overwritten — generated media
  /// filenames are collision-resistant, so an identical name means the file
  /// is already the correct content. This keeps promotion safe even when a
  /// restore was interrupted and rolled back: the live database continues
  /// to reference its original, intact files.
  ///
  /// Renames are atomic on the same filesystem. The copy fallback goes
  /// through a `.partial` sibling file so an interrupted copy can never
  /// leave a truncated file at a referenced path.
  static Future<({int moved, int skipped})> _moveMediaTree(
    Directory stagingDir,
    Directory mediaDir,
  ) async {
    int moved = 0;
    int skipped = 0;

    if (!await stagingDir.exists()) {
      return (moved: moved, skipped: skipped);
    }

    final entities = await stagingDir.list(recursive: true).toList();
    for (final entity in entities) {
      if (entity is! File) continue;
      final rel = _toPortablePath(path.relative(entity.path, from: stagingDir.path));
      final destFile = File(path.joinAll([mediaDir.path, ...rel.split('/')]));
      try {
        await destFile.parent.create(recursive: true);
        if (await destFile.exists()) {
          await entity.delete();
          moved++;
          continue;
        }
        try {
          await entity.rename(destFile.path);
        } catch (_) {
          final partialPath = '${destFile.path}.partial';
          await entity.copy(partialPath);
          await File(partialPath).rename(destFile.path);
          await entity.delete();
        }
        moved++;
      } catch (e) {
        skipped++;
      }
    }

    return (moved: moved, skipped: skipped);
  }

  /// Delete the WAL, SHM and rollback-journal sidecars for a database path.
  static Future<void> _deleteSidecars(String dbPath) async {
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final file = File('$dbPath$suffix');
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
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

  /// Restore the original database after a failed swap.
  ///
  /// Puts the recovery copy back over the target and removes stale
  /// WAL/SHM sidecars. An empty recovery file means no database existed
  /// before the restore — the broken target is simply deleted.
  static Future<void> _rollbackDatabase(
    String targetDbPath,
    String? recoveryPath,
    bool liveMode,
  ) async {
    try {
      await _deleteSidecars(targetDbPath);
      final target = File(targetDbPath);
      if (await target.exists()) {
        await target.delete();
      }
      final recoveryFile = recoveryPath != null ? File(recoveryPath) : null;
      if (recoveryFile != null &&
          await recoveryFile.exists() &&
          await recoveryFile.length() > 0) {
        await recoveryFile.copy(targetDbPath);
      }
    } finally {
      if (liveMode) {
        // Re-open the live database regardless of rollback outcome.
        // Bypasses the restore lock — safe while the lock is held.
        try {
          await DatabaseHelper.instance.reopenDatabaseForRestore();
        } catch (_) {}
      }
    }
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

  /// Number of media paths the restored database references that were not
  /// present in the backup archive (missing when the backup was created).
  final int referencedMediaMissing;

  BackupRestoreResult({
    required this.manifest,
    required this.mediaFilesRestored,
    required this.mediaFilesSkipped,
    this.referencedMediaMissing = 0,
  });
}
