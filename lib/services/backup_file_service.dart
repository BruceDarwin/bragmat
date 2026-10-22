import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Platform-appropriate file access for backup export and restore.
///
/// Android uses the Storage Access Framework via the `bragmat/saf`
/// MethodChannel implemented in `MainActivity.kt`: the system picker lets
/// the user select a backup ZIP from shared Downloads, Google Drive or any
/// other document provider; the chosen `content://` URI is copied to a
/// local temp file which the existing restore pipeline consumes. Export
/// uses ACTION_CREATE_DOCUMENT so the user can save a freshly created
/// backup anywhere outside app-private storage.
///
/// iOS and desktop use `file_selector` (UIDocumentPicker on iOS) for import
/// and the system share sheet (`share_plus`, which surfaces "Save to
/// Files") for export — the idiomatic iOS equivalents. Locally created
/// backups live in [backupDirectory], which is the app-external Download
/// dir on Android and the app Documents dir elsewhere (user-visible in
/// the iOS Files app via UIFileSharingEnabled).
class BackupFileService {
  static const MethodChannel _channel = MethodChannel('bragmat/saf');

  /// Test seam — when set, [pickBackupZip] returns its result without
  /// touching the platform channel. Set to `() async => null` to
  /// simulate the user cancelling the picker.
  static Future<String?> Function()? debugPickerOverride;

  /// Test seam — when set, [exportBackup] returns its result without
  /// touching the platform channel.
  static Future<bool> Function(String localPath, String fileName)?
      debugExporterOverride;

  /// Test seam — when set, [backupDirectory] returns it without touching
  /// path_provider.
  static Directory? debugBackupDirectoryOverride;

  /// Show the system document picker and return a local path to the
  /// selected backup file.
  ///
  /// Returns the local file path, or null when the user cancels, the
  /// selection has no usable path, or the picker is unavailable.
  static Future<String?> pickBackupZip() async {
    if (debugPickerOverride != null) {
      return debugPickerOverride!();
    }
    if (!Platform.isAndroid) {
      // iOS (and desktop): UIDocumentPicker / native open dialog via
      // file_selector. The selection is copied into the app container,
      // so the returned path is a plain local file the restore pipeline
      // consumes directly.
      try {
        final result = await openFile(
          acceptedTypeGroups: const [
            XTypeGroup(extensions: ['zip', 'json'], label: 'Bragmat backups'),
          ],
        );
        return result?.path;
      } on MissingPluginException {
        return null;
      } on PlatformException {
        return null;
      }
    }
    try {
      return await _channel.invokeMethod<String>('pickBackup');
    } catch (_) {
      return null;
    }
  }

  /// Export [localPath] so the user can store it outside app-private
  /// storage, suggesting [fileName].
  ///
  /// Android: system "save as" document picker. iOS/desktop: the share
  /// sheet ("Save to Files" on iOS). [sharePositionOrigin] anchors the
  /// iPad share-sheet popover — pass the source widget's bounds when
  /// available; ignored elsewhere.
  ///
  /// Returns true when the file was exported, false when the user
  /// cancelled or the export failed.
  static Future<bool> exportBackup(
    String localPath,
    String fileName, {
    Rect? sharePositionOrigin,
  }) async {
    if (debugExporterOverride != null) {
      return debugExporterOverride!(localPath, fileName);
    }
    if (!Platform.isAndroid) {
      try {
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [XFile(localPath, name: fileName)],
            subject: 'Bragmat Backup',
            sharePositionOrigin: sharePositionOrigin,
          ),
        );
        return result.status == ShareResultStatus.success;
      } on MissingPluginException {
        return false;
      } on PlatformException {
        return false;
      }
    }
    try {
      return await _channel.invokeMethod<bool>(
            'exportBackup',
            {'path': localPath, 'name': fileName},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Directory where locally created backups are written and listed.
  ///
  /// Android: the app-private external Download dir (unchanged existing
  /// behaviour). iOS and desktop: the app Documents directory — on iOS it
  /// is user-visible in the Files app because the app declares
  /// UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace.
  static Future<Directory?> backupDirectory() async {
    if (debugBackupDirectoryOverride != null) {
      return debugBackupDirectoryOverride;
    }
    if (Platform.isAndroid) {
      return getDownloadsDirectory();
    }
    try {
      return await getApplicationDocumentsDirectory();
    } on MissingPluginException {
      return null;
    }
  }

  /// List portable (.zip) and legacy (.json) backup files in
  /// [backupDirectory], most recent first.
  static Future<List<File>> listLocalBackups() async {
    final directory = await backupDirectory();
    if (directory == null || !await directory.exists()) {
      return const [];
    }
    final files = directory
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.contains('bragmat_backup_') &&
            (f.path.endsWith('.zip') || f.path.endsWith('.json')))
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  /// Delete the temporary copy the document picker made of [path] after
  /// it has been consumed. Best-effort cleanup — iOS would purge the
  /// container temp dir eventually, but the file can be tens of MB.
  /// No-op on Android, where picks do not create a local temp copy.
  static Future<void> releasePickedFile(String path) async {
    if (Platform.isAndroid) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
