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
  
  /// Normalize media paths in the temporary database to relative paths.
  static Future<void> _normalizeMediaPaths(String databasePath) async {
    final db = await openDatabase(databasePath);
    
    try {
      // Normalize catch_media paths
      final catchMedia = await db.query('catch_media');
      for (final media in catchMedia) {
        final absolutePath = media['file_path'] as String;
        final relativePath = await MediaStorageService.toRelativePath(absolutePath);
        
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
        final relativePath = await MediaStorageService.toRelativePath(absolutePath);
        
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
        final relativePath = await MediaStorageService.toRelativePath(absolutePath);
        
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
          final relativePath = await MediaStorageService.toRelativePath(absolutePath);
          
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
        final relativePath = path.relative(entity.path, from: sourceDir.path);
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
