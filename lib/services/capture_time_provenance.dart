import '../models/catch_media.dart';
import '../models/photo_metadata_result.dart';
import 'media_storage_service.dart';
import 'photo_metadata_service.dart';

/// What can be said about a stored `catch_media.date_taken` value without
/// modifying the record.
///
/// Historical rows may carry attachment-time values (written by the old
/// picker path), verified EXIF capture times (written by the metadata
/// workflow), or user-supplied values. Because the schema has no
/// provenance column, the only trustworthy discriminator is the stored
/// photo's own EXIF data.
enum CaptureTimeProvenance {
  /// The media row has no `date_taken` value.
  absent,

  /// The stored value matches the photo's EXIF capture time — verified
  /// capture time.
  exifVerified,

  /// The photo carries a different EXIF capture time — the stored value
  /// is NOT the capture time (legacy attachment-time or a value set by
  /// another path).
  conflict,

  /// The photo has no verifiable EXIF capture time, so the stored value
  /// cannot be confirmed — typical for legacy attachment-time rows and
  /// photos whose EXIF was stripped.
  unverifiable,
}

/// Read-only provenance assessment for `catch_media.date_taken`.
///
/// Re-extracts metadata from the stored photo (which preserves the
/// picker output byte-for-byte) and compares it with the stored value.
/// Never writes to the database — historical records are classified, not
/// corrected.
class CaptureTimeProvenanceService {
  /// Classify [stored] against the photo's extracted [metadata].
  ///
  /// EXIF datetimes have second precision; stored values may carry
  /// sub-second components from older attachment-time writes, so the
  /// comparison tolerates a 1-second delta.
  static CaptureTimeProvenance classify({
    required DateTime? stored,
    required PhotoMetadataResult metadata,
  }) {
    if (stored == null) return CaptureTimeProvenance.absent;

    final exifCapture = metadata.dateTimeStatus == DateTimeStatus.valid &&
            metadata.dateTimeSource != DateTimeSource.fileModification
        ? metadata.dateTime
        : null;

    if (exifCapture == null) return CaptureTimeProvenance.unverifiable;

    return stored.difference(exifCapture).abs() <= const Duration(seconds: 1)
        ? CaptureTimeProvenance.exifVerified
        : CaptureTimeProvenance.conflict;
  }

  /// Resolve [media]'s stored file, re-extract its metadata and classify
  /// its `date_taken`. Returns [CaptureTimeProvenance.unverifiable] when
  /// the file is missing or unreadable.
  static Future<CaptureTimeProvenance> assess(CatchMedia media) async {
    if (media.dateTaken == null) return CaptureTimeProvenance.absent;
    try {
      final resolved = await MediaStorageService.resolvePath(media.filePath);
      final metadata = await PhotoMetadataService.extractFromFile(resolved);
      return classify(stored: media.dateTaken, metadata: metadata);
    } catch (_) {
      return CaptureTimeProvenance.unverifiable;
    }
  }
}
