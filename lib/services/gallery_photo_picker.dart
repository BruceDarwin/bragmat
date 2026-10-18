import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Outcome of a gallery pick through the Android system Photo Picker.
enum GalleryPickStatus {
  /// A photo was selected; [GalleryPickOutcome.path] is set.
  picked,

  /// The user dismissed the picker.
  cancelled,

  /// The system Photo Picker (or its location-metadata request) is not
  /// supported on this platform — the caller should fall back to the
  /// existing image_picker flow.
  unsupported,

  /// A previously selected photo is still waiting to be recovered.
  /// The picker was NOT launched; [GalleryPickOutcome.path] and
  /// [GalleryPickOutcome.context] describe the pending result.
  pending,
}

class GalleryPickOutcome {
  const GalleryPickOutcome(this.status, {this.path, this.context});

  final GalleryPickStatus status;
  final String? path;
  final String? context;
}

/// A gallery selection whose delivery survived process death.
/// [context] is the caller-supplied token (e.g. 'new' or 'edit:42')
/// recorded when the pick was launched.
class RecoveredGalleryPick {
  const RecoveredGalleryPick({required this.path, required this.context});

  final String path;
  final String context;
}

/// Android-only gallery picker channel.
///
/// Uses `MediaStore.ACTION_PICK_IMAGES` with the location-metadata request
/// extra so the user can consent to sharing EXIF GPS with the app. On the
/// Moto G15 this produces a `picker.location-true` URI whose default stream
/// already contains full GPS — no `setRequireOriginal` and no
/// `ACCESS_MEDIA_LOCATION` needed.
///
/// Results are persisted natively (SharedPreferences) before delivery so a
/// pick that lands after activity/process death can be recovered later via
/// [retrievePending]. The record survives until [acknowledgePending] is
/// called after successful staging, and a new pick never erases it.
class GalleryPhotoPicker {
  GalleryPhotoPicker();

  /// Injectable instance — tests substitute a fake, mirroring the
  /// `ImagePickerPlatform.instance` pattern.
  static GalleryPhotoPicker instance = GalleryPhotoPicker();

  static const MethodChannel _channel =
      MethodChannel('bragmat/gallery_picker');

  /// Launch the system Photo Picker requesting location metadata.
  ///
  /// [context] identifies which catch the pick belongs to ('new' or
  /// `edit:<id>`); it is stored with the result so a recovered pick can
  /// only be attached to the catch it was started from.
  Future<GalleryPickOutcome> pickFromGallery({required String context}) async {
    if (!Platform.isAndroid) {
      return const GalleryPickOutcome(GalleryPickStatus.unsupported);
    }
    try {
      final res = await _channel
          .invokeMapMethod<String, dynamic>('pickImage', {'context': context});
      return _parseOutcome(res);
    } on PlatformException catch (e) {
      if (e.code == 'unsupported') {
        return const GalleryPickOutcome(GalleryPickStatus.unsupported);
      }
      rethrow;
    } on MissingPluginException {
      return const GalleryPickOutcome(GalleryPickStatus.unsupported);
    }
  }

  /// Returns a pick result that was persisted but never acknowledged —
  /// e.g. the process died while the picker was open. Null when nothing
  /// is pending or the recorded file no longer exists.
  Future<RecoveredGalleryPick?> retrievePending() async {
    if (!Platform.isAndroid) return null;
    try {
      final res =
          await _channel.invokeMapMethod<String, dynamic>('retrievePending');
      if (res == null) return null;
      final path = res['path'] as String?;
      final context = res['context'] as String?;
      if (path == null || context == null) return null;
      return RecoveredGalleryPick(path: path, context: context);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Clears a pending recovery record after the photo has been
  /// successfully staged (or confirmed unrecoverable — e.g. the temp
  /// file is gone).
  Future<void> acknowledgePending(String path) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('acknowledge', {'path': path});
    } on PlatformException {
      // Acknowledgement is best-effort cleanup; a stale record just
      // causes one extra (deduplicated) recovery attempt.
    } on MissingPluginException {
      // No-op outside Android.
    }
  }

  GalleryPickOutcome _parseOutcome(Map<String, dynamic>? res) {
    if (res == null) {
      return const GalleryPickOutcome(GalleryPickStatus.cancelled);
    }
    switch (res['status'] as String?) {
      case 'picked':
        final path = res['path'] as String?;
        if (path == null) {
          return const GalleryPickOutcome(GalleryPickStatus.cancelled);
        }
        return GalleryPickOutcome(GalleryPickStatus.picked,
            path: path, context: res['context'] as String?);
      case 'pending':
        final path = res['path'] as String?;
        final context = res['context'] as String?;
        if (path == null || context == null) {
          return const GalleryPickOutcome(GalleryPickStatus.cancelled);
        }
        return GalleryPickOutcome(GalleryPickStatus.pending,
            path: path, context: context);
      case 'unsupported':
        return const GalleryPickOutcome(GalleryPickStatus.unsupported);
      case 'cancelled':
      default:
        return const GalleryPickOutcome(GalleryPickStatus.cancelled);
    }
  }
}

/// Visible for tests only: reset the injectable instance.
@visibleForTesting
void resetGalleryPhotoPickerForTest(GalleryPhotoPicker picker) {
  GalleryPhotoPicker.instance = picker;
}
