import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../database/database_helper.dart';
import '../database/migration_v29.dart';
import '../services/ownership_service.dart';
import '../models/backup_manifest.dart';
import '../services/media_storage_service.dart';
import '../services/preferences_service.dart';
import '../services/current_trip_service.dart';
import '../services/tide_reference_service.dart';

/// What a restore may do about ownership.
enum _RestoreOwnership {
  /// Restore and leave ownership exactly as stored in the backup.
  /// Restored data is NEVER silently assigned to the current install
  /// owner — an unowned backup restores unowned and requires the
  /// explicit claim afterwards, even on a claimed install.
  allow,

  /// Refuse — different owner.
  deny,

  /// Refuse — inconsistent ownership records; needs controlled
  /// recovery rather than a silent attach.
  ambiguous,
}

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
      
      onProgress?.call('Collecting media files...');

      // Step 2: Collect media files and rewrite every snapshot reference
      // to the exact archive-relative path the file is stored under.
      // Collection and normalisation are one pass so the snapshot can
      // never reference a name that is absent from the archive.
      final mediaResult = await _collectMediaFiles(snapshotPath, tempDir);
      
      onProgress?.call('Creating manifest...');
      
      // Step 4: Create manifest — report the snapshot's actual schema
      // version, not a constant.
      String bragmatVersion = 'unknown';
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        bragmatVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      } catch (_) {
        // Package info is unavailable in unit tests; keep creating backups.
      }
      final snapshotSchemaVersion = await schemaVersionOf(snapshotPath);
      final manifest = BackupManifest.create(
        bragmatVersion: bragmatVersion,
        databaseSchemaVersion: snapshotSchemaVersion,
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

  /// Media reference columns backed by the archive: (table, column,
  /// archive subdirectory).
  static const List<(String, String, String)> _mediaSources = [
    ('catch_media', 'file_path', 'catches'),
    ('trip_media', 'file_path', 'trips'),
    ('journal_media', 'file_path', 'journals'),
    ('catches', 'lure_photo_path', 'lures'),
    ('catches', 'image_path', 'catches'),
  ];

  /// Collect media files referenced by the snapshot database into
  /// `<tempDir>/media/` and rewrite each stored reference to the exact
  /// archive-relative path the file is copied under.
  ///
  /// Collection and path normalisation are deliberately a single pass so
  /// the snapshot can only reference names that exist in the archive:
  /// - relative paths resolve against the media directory, with legacy
  ///   singular subdirs (`catch/`) canonicalised
  /// - absolute paths resolve wherever readable, with a unique-basename
  ///   fallback inside the media directory
  /// - distinct source files sharing a basename are archived under a
  ///   `_cN` suffix instead of overwriting each other; byte-identical
  ///   duplicates share one archive entry
  static Future<_MediaCollectionResult> _collectMediaFiles(
    String databasePath,
    Directory tempDir,
  ) async {
    final db = await openDatabase(databasePath);
    final mediaDir = await MediaStorageService.getMediaDirectory();

    final backupMediaDir =
        Directory(path.join(tempDir.path, _mediaDirectoryName));
    if (!await backupMediaDir.exists()) {
      await backupMediaDir.create(recursive: true);
    }

    // Archive-relative name → staged file, for collision detection.
    final staged = <String, File>{};
    final collected = <String, int>{
      'catches': 0,
      'trips': 0,
      'journals': 0,
      'lures': 0,
    };
    final unresolvedRows = <String>{};
    int totalPhotos = 0;

    try {
      for (final (table, column, subdir) in _mediaSources) {
        List<Map<String, Object?>> rows;
        try {
          rows = await db.query(
            table,
            columns: ['id', column],
            where: '$column IS NOT NULL AND $column != \'\'',
          );
        } catch (_) {
          continue; // Table/column may not exist in older schemas.
        }
        for (final row in rows) {
          final ref = row[column] as String;
          final source = _resolveBackupSourceFile(ref, mediaDir);
          if (source == null) {
            unresolvedRows.add('$table:${row['id']}');
            continue;
          }
          var archiveRel = '$subdir/${path.basename(source.path)}';
          var write = true;
          final existing = staged[archiveRel];
          if (existing != null) {
            if (await _filesEqual(existing, source)) {
              // Identical content already archived — share the entry.
              write = false;
            } else {
              // Same basename, different content: archive under a
              // collision-safe name rather than overwriting.
              final ext = path.extension(archiveRel);
              final stem =
                  archiveRel.substring(0, archiveRel.length - ext.length);
              var n = 1;
              do {
                archiveRel = '${stem}_c$n$ext';
                n++;
              } while (staged.containsKey(archiveRel));
            }
          }
          if (write) {
            final dest = File(path.joinAll(
                [backupMediaDir.path, ...archiveRel.split('/')]));
            await dest.parent.create(recursive: true);
            await source.copy(dest.path);
            staged[archiveRel] = dest;
          }
          final portableRef = _toPortablePath(ref);
          if (archiveRel != portableRef) {
            await db.update(
              table,
              {column: archiveRel},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }
          collected[subdir] = collected[subdir]! + 1;
          totalPhotos++;
        }
      }

      // Verify: every stored reference must resolve to a staged archive
      // entry. Rows already counted as unresolved stay untouched.
      int missingPhotos = unresolvedRows.length;
      for (final (table, column, _) in _mediaSources) {
        List<Map<String, Object?>> rows;
        try {
          rows = await db.query(
            table,
            columns: ['id', column],
            where: '$column IS NOT NULL AND $column != \'\'',
          );
        } catch (_) {
          continue;
        }
        for (final row in rows) {
          if (unresolvedRows.contains('$table:${row['id']}')) continue;
          final ref = _toPortablePath(row[column] as String);
          if (!staged.containsKey(ref)) {
            missingPhotos++;
          }
        }
      }

      // Get catch and trip counts for statistics
      final catchResult =
          await db.rawQuery('SELECT COUNT(*) as count FROM catches');
      final catchCountStat = Sqflite.firstIntValue(catchResult) ?? 0;

      final tripResult =
          await db.rawQuery('SELECT COUNT(*) as count FROM fishing_trips');
      final tripCountStat = Sqflite.firstIntValue(tripResult) ?? 0;

      return _MediaCollectionResult(
        counts: BackupMediaCounts(
          catches: collected['catches']!,
          trips: collected['trips']!,
          journals: collected['journals']!,
          lures: collected['lures']!,
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

  /// Resolve a stored media reference to a readable file at backup time.
  ///
  /// Relative paths resolve against the media directory (with legacy
  /// singular-subdir canonicalisation). Absolute paths are tried as-is;
  /// when unreadable (e.g. a stale image-picker cache path from an older
  /// install) the basename is looked up inside the media directory and
  /// used only when it matches exactly one entity subdirectory.
  static File? _resolveBackupSourceFile(String ref, Directory mediaDir) {
    final portable = _toPortablePath(ref);
    if (path.isAbsolute(ref)) {
      final direct = File(ref);
      if (direct.existsSync()) return direct;
      final base = path.basename(portable);
      final matches = <File>[];
      for (final sub in const ['catches', 'trips', 'journals', 'lures']) {
        final candidate = File(path.join(mediaDir.path, sub, base));
        if (candidate.existsSync()) matches.add(candidate);
      }
      return matches.length == 1 ? matches.single : null;
    }
    var candidate = File(path.joinAll([mediaDir.path, ...portable.split('/')]));
    if (candidate.existsSync()) return candidate;
    final canonical = MediaStorageService.canonicalizeRelPath(portable);
    if (canonical != portable) {
      candidate =
          File(path.joinAll([mediaDir.path, ...canonical.split('/')]));
      if (candidate.existsSync()) return candidate;
    }
    return null;
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
  static const int _maxSupportedSchemaVersion = 29;

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

      // Ownership gate — a restore must never silently bypass the
      // installation's ownership controls. Ownership comes only from
      // the backup file itself: unowned (v28) backups restore unowned
      // and need the explicit claim afterwards; v29 backups restore
      // only when their owner matches; mismatched or ambiguous
      // ownership blocks the restore before any staging.
      final backupOwnership =
          await _readDbOwnership(sourceDbFile.path);
      // Live mode must read ownership via the live connection — a second
      // openDatabase on the same path would return the cached live
      // handle and closing it would break the restore.
      final targetOwnership = liveMode
          ? await _readDbOwnershipFrom(
              await DatabaseHelper.instance.systemDatabase)
          : await File(targetDbPath).exists()
              ? await _readDbOwnership(targetDbPath)
              : (ownerId: null as String?, ambiguous: false);
      final ownershipAction = _decideRestoreOwnership(
          targetOwnership.ownerId, backupOwnership);
      if (ownershipAction == _RestoreOwnership.deny) {
        throw Exception(
            'Restore refused: this backup belongs to a different account. '
            'Sign in with the owning account to restore it.');
      }
      if (ownershipAction == _RestoreOwnership.ambiguous) {
        throw Exception(
            'Restore refused: the backup\'s ownership data is '
            'inconsistent (partial or conflicting owner records). '
            'Controlled recovery required — the file was left untouched.');
      }
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

      // Upgrade the staged file to the current schema before the swap —
      // ownership is left exactly as the backup stores it; a failure
      // here aborts with the live database untouched.
      await _upgradeStagedDatabase(stagePath);
      await _reportStage('dbStaged', onProgress, 'Database staged');

      onProgress?.call('Staging media files...');

      // Stage all media and account for every path the backup database
      // references before the database is swapped. Files referenced but
      // absent from the archive are reported; copy failures abort the
      // restore while the live database is still untouched.
      final referencedPaths = await _collectReferencedMediaPaths(sourceDbFile.path);
      stagingMediaDir = _mediaStagingDirectory(mediaDir);
      await _stageMediaFiles(extractDir, stagingMediaDir);

      // Index staged files by basename so legacy absolute paths (e.g.
      // image-picker cache paths written by old builds) and legacy
      // subdirectory prefixes (`catch/` vs `catches/`) can be resolved
      // to the file the archive actually contains. Basenames that occur
      // under more than one staged path are ambiguous and are never
      // silently attached to a reference.
      final stagedByBasename = <String, String>{};
      final ambiguousBasenames = <String>{};
      if (await stagingMediaDir.exists()) {
        await for (final entity in stagingMediaDir.list(recursive: true)) {
          if (entity is! File) continue;
          final rel = _toPortablePath(
              path.relative(entity.path, from: stagingMediaDir.path));
          final base = path.posix.basename(rel);
          if (stagedByBasename.containsKey(base)) {
            ambiguousBasenames.add(base);
          } else {
            stagedByBasename[base] = rel;
          }
        }
      }

      final missingReferenced = <String>[];
      final ambiguousReferenced = <String>[];
      final repairs = <String, String>{};
      for (final relPath in referencedPaths) {
        var candidate = _toPortablePath(relPath);
        var staged = File(
            path.joinAll([stagingMediaDir.path, ...candidate.split('/')]));
        if (!await staged.exists() && !path.isAbsolute(relPath)) {
          // Legacy singular subdir prefix (catch/x → catches/x).
          final canonical =
              MediaStorageService.canonicalizeRelPath(candidate);
          if (canonical != candidate) {
            candidate = canonical;
            staged = File(path.joinAll(
                [stagingMediaDir.path, ...candidate.split('/')]));
          }
        }
        if (await staged.exists()) {
          if (candidate != relPath) {
            repairs[relPath] = candidate;
          }
          continue;
        }
        // No direct match — resolve by basename (absolute cache paths
        // and foreign prefixes). Unique match → repair; ambiguous or
        // absent → report missing without attaching the wrong file.
        final base = path.posix.basename(candidate);
        final stagedRel = stagedByBasename[base];
        if (stagedRel != null && !ambiguousBasenames.contains(base)) {
          repairs[relPath] = stagedRel;
        } else if (stagedRel != null) {
          ambiguousReferenced.add(relPath);
          missingReferenced.add(relPath);
        } else {
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
      // Persist corrected paths: legacy repairs (original ref → staged
      // path) are composed with collision remaps (staged path → final
      // path) so every stored reference ends at its promoted file.
      final pathUpdates = <String, String>{};
      repairs.forEach((ref, stagedRel) {
        pathUpdates[ref] = mediaResult.remapped[stagedRel] ?? stagedRel;
      });
      pathUpdates.addAll(mediaResult.remapped);
      await _remapMediaPathsInDatabase(
          targetDbPath, liveMode, pathUpdates);
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
        mediaPathConflicts: mediaResult.remapped.length,
        mediaPathsRepaired: repairs.length,
        ambiguousMediaRefs: ambiguousReferenced.length,
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

  // ---------------------------------------------------------------------
  // Restore ownership inspection
  // ---------------------------------------------------------------------

  /// Read ownership state from a database file — works on v28 files
  /// (no local_account) and v29 files.
  static Future<({String? ownerId, bool ambiguous})> _readDbOwnership(
      String dbPath) async {
    Database? db;
    try {
      db = await openDatabase(dbPath, readOnly: true);
      return await _readDbOwnershipFrom(db);
    } catch (_) {
      // Unreadable ownership metadata — treat as unowned rather than
      // blocking restores of pre-v29 backups outright.
      return (ownerId: null, ambiguous: false);
    } finally {
      await db?.close();
    }
  }

  /// Ownership read on an already-open handle (never closed here).
  static Future<({String? ownerId, bool ambiguous})> _readDbOwnershipFrom(
      Database db) async {
    final accountOwner = await OwnershipService.ownerIdFrom(db);
    final rowOwners = await MigrationV29.distinctRowOwners(db);
    if (rowOwners.length > 1) {
      return (ownerId: accountOwner, ambiguous: true);
    }
    if (accountOwner == null && rowOwners.isNotEmpty) {
      // Rows carry an owner but the account record is missing —
      // partial claim or tampered file.
      return (ownerId: null, ambiguous: true);
    }
    if (accountOwner != null &&
        rowOwners.isNotEmpty &&
        rowOwners.single != accountOwner) {
      return (ownerId: accountOwner, ambiguous: true);
    }
    return (ownerId: accountOwner, ambiguous: false);
  }

  static _RestoreOwnership _decideRestoreOwnership(String? currentOwner,
      ({String? ownerId, bool ambiguous}) backup) {
    if (backup.ambiguous) return _RestoreOwnership.ambiguous;
    if (backup.ownerId == null) {
      // Unowned backup: always allowed, ownership never assigned —
      // the explicit claim decides afterwards.
      return _RestoreOwnership.allow;
    }
    if (currentOwner == null || backup.ownerId == currentOwner) {
      return _RestoreOwnership.allow;
    }
    return _RestoreOwnership.deny;
  }

  /// Read the `PRAGMA user_version` of a database file — used to record
  /// the snapshot's real schema version in the backup manifest.
  static Future<int> schemaVersionOf(String dbPath) async {
    Database? db;
    try {
      db = await openDatabase(dbPath, readOnly: true);
      return (await db.rawQuery('PRAGMA user_version'))
          .first.values.first as int;
    } finally {
      await db?.close();
    }
  }

  /// Upgrade [stagedDbPath] to the current schema in place before the
  /// file is promoted to the live database path.
  static Future<void> _upgradeStagedDatabase(String stagedDbPath) async {
    Database? db;
    try {
      db = await openDatabase(stagedDbPath,
          version: _maxSupportedSchemaVersion,
          onUpgrade: DatabaseHelper.instance.upgradeDatabase);
    } finally {
      await db?.close();
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

    await completePendingMediaStaging(
      mediaDir,
      promote: swapCommitted,
      databasePath: dbPath,
      liveMode: databasePathOverride == null,
    );

    if (swapCommitted) {
      await recoveryMarker.delete();
    }
  }

  /// Move leftover staged media into place and remove the staging dir.
  ///
  /// When [promote] is false the staging directory is discarded instead —
  /// the restore it belonged to never committed its database swap, so the
  /// files must not overwrite media referenced by the live database.
  ///
  /// [databasePath] and [liveMode] identify the database whose media paths
  /// may need remapping after collision-resolved promotions.
  static Future<void> completePendingMediaStaging(
    Directory mediaDir, {
    required bool promote,
    String? databasePath,
    bool liveMode = true,
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
    if (databasePath != null) {
      await _remapMediaPathsInDatabase(databasePath, liveMode, result.remapped);
    }
    if (result.skipped == 0) {
      await stagingDir.delete(recursive: true);
    }
  }

  /// The staging directory for restored media, sibling of [mediaDir].
  static Directory _mediaStagingDirectory(Directory mediaDir) {
    return Directory(path.join(mediaDir.parent.path, _mediaStagingDirName));
  }

  /// Public accessor for debug diagnostics — the staging directory that
  /// would be used next to [mediaDir].
  static Directory mediaStagingDirectoryFor(Directory mediaDir) {
    return _mediaStagingDirectory(mediaDir);
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
              // Keep the reference exactly as stored — it is the key used
              // when persisting corrected paths back into the database.
              paths.add(filePath);
            }
          }
        } catch (_) {
          // Table may not exist in older-schema backups.
        }
      }
      for (final column in const ['lure_photo_path', 'image_path']) {
        try {
          final rows = await db.query('catches', columns: [column]);
          for (final row in rows) {
            final filePath = row[column] as String?;
            if (filePath != null && filePath.isNotEmpty) {
              paths.add(filePath);
            }
          }
        } catch (_) {}
      }
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
  /// filenames are collision-resistant and media is immutable once stored,
  /// so an identical name normally means identical content (verified by
  /// byte comparison). If contents ever differ, both files are kept: the
  /// staged file moves under a `_rN` suffixed name and the conflict is
  /// reported via the returned `remapped` map so the restored database
  /// can be pointed at the backup's copy.
  ///
  /// This keeps promotion safe even when a restore was interrupted and
  /// rolled back: the live database always references intact files.
  ///
  /// Renames are atomic on the same filesystem. The copy fallback goes
  /// through a `.partial` sibling file so an interrupted copy can never
  /// leave a truncated file at a referenced path.
  static Future<({int moved, int skipped, Map<String, String> remapped})>
      _moveMediaTree(
    Directory stagingDir,
    Directory mediaDir,
  ) async {
    int moved = 0;
    int skipped = 0;
    final remapped = <String, String>{};

    if (!await stagingDir.exists()) {
      return (moved: moved, skipped: skipped, remapped: remapped);
    }

    final entities = await stagingDir.list(recursive: true).toList();
    for (final entity in entities) {
      if (entity is! File) continue;
      final rel = _toPortablePath(path.relative(entity.path, from: stagingDir.path));
      var destRel = rel;
      var destFile = File(path.joinAll([mediaDir.path, ...destRel.split('/')]));
      try {
        await destFile.parent.create(recursive: true);
        if (await destFile.exists()) {
          if (await _filesEqual(entity, destFile)) {
            // Identical name, identical content — already in place.
            await entity.delete();
            moved++;
            continue;
          }
          // Genuine name collision: keep both files and remap the path.
          destRel = _collisionFreeRel(mediaDir, rel);
          remapped[rel] = destRel;
          destFile = File(path.joinAll([mediaDir.path, ...destRel.split('/')]));
          await destFile.parent.create(recursive: true);
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

    return (moved: moved, skipped: skipped, remapped: remapped);
  }

  /// Whether two files have identical content (size then byte compare).
  static Future<bool> _filesEqual(File a, File b) async {
    if (await a.length() != await b.length()) {
      return false;
    }
    final aBytes = await a.readAsBytes();
    final bBytes = await b.readAsBytes();
    for (var i = 0; i < aBytes.length; i++) {
      if (aBytes[i] != bBytes[i]) {
        return false;
      }
    }
    return true;
  }

  /// Produce a collision-free relative path by appending `_rN` to the stem.
  /// Assumes the destination directory already exists.
  static String _collisionFreeRel(Directory mediaDir, String rel) {
    final ext = path.extension(rel);
    final stem = rel.substring(0, rel.length - ext.length);
    var candidate = '${stem}_r1$ext';
    var n = 1;
    while (File(path.joinAll([mediaDir.path, ...candidate.split('/')])).existsSync()) {
      n++;
      candidate = '${stem}_r$n$ext';
    }
    return candidate;
  }

  /// Point restored-database media paths at their collision-resolved names.
  static Future<void> _remapMediaPathsInDatabase(
    String dbPath,
    bool liveMode,
    Map<String, String> remaps,
  ) async {
    if (remaps.isEmpty) {
      return;
    }
    Database? db;
    var ownDb = false;
    try {
      if (liveMode) {
        db = await DatabaseHelper.instance.database;
      } else {
        db = await openDatabase(dbPath);
        ownDb = true;
      }
      for (final table in const ['catch_media', 'trip_media', 'journal_media']) {
        for (final entry in remaps.entries) {
          try {
            await db.update(
              table,
              {'file_path': entry.value},
              where: 'file_path = ?',
              whereArgs: [entry.key],
            );
          } catch (_) {
            // Table may not exist in older-schema backups.
          }
        }
      }
      for (final column in const ['lure_photo_path', 'image_path']) {
        for (final entry in remaps.entries) {
          try {
            await db.update(
              'catches',
              {column: entry.value},
              where: '$column = ?',
              whereArgs: [entry.key],
            );
          } catch (_) {}
        }
      }
    } finally {
      if (ownDb) {
        await db?.close();
      }
    }
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

  /// Number of staged media files that collided with a same-named but
  /// different-content destination file. Both files were kept and the
  /// database paths were remapped to the backup's copy.
  final int mediaPathConflicts;

  /// Number of legacy references (absolute cache paths, `catch/` prefix,
  /// foreign prefixes) resolved to staged archive files and persisted
  /// into the restored database.
  final int mediaPathsRepaired;

  /// Number of references whose basename matched more than one staged
  /// file — reported rather than silently attached to the wrong photo.
  final int ambiguousMediaRefs;

  BackupRestoreResult({
    required this.manifest,
    required this.mediaFilesRestored,
    required this.mediaFilesSkipped,
    this.referencedMediaMissing = 0,
    this.mediaPathConflicts = 0,
    this.mediaPathsRepaired = 0,
    this.ambiguousMediaRefs = 0,
  });
}
