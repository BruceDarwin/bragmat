import 'dart:io';
import 'package:flutter/services.dart';

/// Access to the Android Storage Access Framework document picker.
///
/// Restore: the system picker lets the user select a backup ZIP from
/// shared Downloads, Google Drive or any other document provider; the
/// chosen `content://` URI is copied to a local temp file which the
/// existing restore pipeline consumes.
///
/// Export: ACTION_CREATE_DOCUMENT lets the user save a freshly created
/// backup anywhere outside app-private storage.
///
/// Implemented natively in `MainActivity.kt` (channel `bragmat/saf`).
/// Non-Android platforms return null/false — callers should keep any
/// platform-appropriate fallback.
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

  /// Show the system document picker and copy the selected document to
  /// a local file.
  ///
  /// Returns the local file path, or null when the user cancels or the
  /// platform does not support SAF.
  static Future<String?> pickBackupZip() async {
    if (debugPickerOverride != null) {
      return debugPickerOverride!();
    }
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      return await _channel.invokeMethod<String>('pickBackup');
    } catch (_) {
      return null;
    }
  }

  /// Show the system "save as" picker and copy [localPath] to the chosen
  /// destination, suggesting [fileName].
  ///
  /// Returns true when the file was exported, false when the user
  /// cancelled, the platform is unsupported, or the export failed.
  static Future<bool> exportBackup(String localPath, String fileName) async {
    if (debugExporterOverride != null) {
      return debugExporterOverride!(localPath, fileName);
    }
    if (!Platform.isAndroid) {
      return false;
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
}
