import 'dart:io';

import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';

import '../models/photo_metadata_result.dart';

/// Offline photo metadata extraction and validation service.
///
/// Reads EXIF date/time, timezone offset and GPS coordinates from an image
/// and reports them as a [PhotoMetadataResult]. The service never applies
/// extracted values to catch data — it only describes what the photo claims.
/// Presentation and application of the result are the caller's decision.
///
/// Notes on the `exif` package (v3.x): map keys are IFD-prefixed
/// (e.g. 'GPS GPSLatitude', 'EXIF DateTimeOriginal', 'Image DateTime') and
/// values are [IfdTag] objects — not raw lists. Tag names are resolved
/// tolerantly so prefixed and unprefixed forms both work.
class PhotoMetadataService {
  /// Extract metadata from an image file.
  ///
  /// Non-blocking: any read/parse failure returns a result describing what
  /// could be recovered (typically [PhotoMetadataResult] with no metadata),
  /// never throws for corrupt or unsupported content.
  static Future<PhotoMetadataResult> extractFromFile(
    String imagePath, {
    PhotoSource photoSource = PhotoSource.unknown,
  }) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return PhotoMetadataResult(photoSource: photoSource);
      }
      final bytes = await file.readAsBytes();
      final format = detectFormat(bytes);
      DateTime? fileModified;
      try {
        fileModified = await file.lastModified();
      } catch (_) {
        fileModified = null;
      }
      return extractFromBytes(
        bytes,
        format: format,
        photoSource: photoSource,
        fileModified: fileModified,
      );
    } catch (_) {
      return PhotoMetadataResult(photoSource: photoSource);
    }
  }

  /// Extract metadata from raw image bytes.
  ///
  /// [format] may be supplied by the caller; when [ImageFormat.unknown] the
  /// format is detected from magic bytes. [fileModified] supplies the file
  /// modification fallback timestamp (only used when no EXIF timestamp is
  /// found and always labelled [DateTimeSource.fileModification]).
  static Future<PhotoMetadataResult> extractFromBytes(
    Uint8List bytes, {
    ImageFormat format = ImageFormat.unknown,
    PhotoSource photoSource = PhotoSource.unknown,
    DateTime? fileModified,
  }) async {
    final detected = format == ImageFormat.unknown ? detectFormat(bytes) : format;

    Map<String, IfdTag> tags;
    try {
      tags = await readExifFromBytes(bytes);
    } catch (_) {
      tags = const {};
    }

    return parseExifTags(
      tags,
      format: detected,
      photoSource: photoSource,
      fileModified: fileModified,
    );
  }

  /// Parse an already-decoded EXIF tag map into a [PhotoMetadataResult].
  ///
  /// Exposed for unit tests so synthetic tag maps (including edge cases
  /// that are hard to encode into fixture JPEGs) can be exercised without
  /// file I/O or byte-level EXIF construction.
  @visibleForTesting
  static PhotoMetadataResult parseExifTags(
    Map<String, IfdTag> tags, {
    ImageFormat format = ImageFormat.unknown,
    PhotoSource photoSource = PhotoSource.unknown,
    DateTime? fileModified,
  }) {
    return _parseTags(
      tags,
      format: format,
      photoSource: photoSource,
      fileModified: fileModified,
    );
  }

  /// Detect image format from magic bytes.
  static ImageFormat detectFormat(Uint8List bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return ImageFormat.jpeg;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return ImageFormat.png;
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && // 'R'
        bytes[1] == 0x49 && // 'I'
        bytes[2] == 0x46 && // 'F'
        bytes[3] == 0x46 && // 'F'
        bytes[8] == 0x57 && // 'W'
        bytes[9] == 0x45 && // 'E'
        bytes[10] == 0x42 && // 'B'
        bytes[11] == 0x50) {
      return ImageFormat.webp;
    }
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 && // 'f'
        bytes[5] == 0x74 && // 't'
        bytes[6] == 0x79 && // 'y'
        bytes[7] == 0x70) {
      // 'ftyp' box — HEIC/HEIF brands
      const heicBrands = ['heic', 'heix', 'hevc', 'hevx', 'heim', 'heis', 'mif1', 'msf1'];
      final brand = String.fromCharCodes(bytes.sublist(8, 12));
      if (heicBrands.contains(brand)) {
        return ImageFormat.heic;
      }
    }
    return ImageFormat.unknown;
  }

  // -------------------------------------------------------------------
  // EXIF parsing
  // -------------------------------------------------------------------

  static PhotoMetadataResult _parseTags(
    Map<String, IfdTag> tags, {
    required ImageFormat format,
    required PhotoSource photoSource,
    DateTime? fileModified,
  }) {
    final dateTimeResult = _extractDateTime(tags, fileModified: fileModified);
    final gpsResult = _extractGps(tags);

    final hasExif =
        dateTimeResult.source != DateTimeSource.none &&
                dateTimeResult.source != DateTimeSource.fileModification ||
            gpsResult.status != GpsStatus.absent;

    final confidence = hasExif
        ? MetadataConfidence.exif
        : (dateTimeResult.source == DateTimeSource.fileModification
            ? MetadataConfidence.fileSystem
            : MetadataConfidence.none);

    return PhotoMetadataResult(
      dateTime: dateTimeResult.value,
      hasTimezone: dateTimeResult.hasTimezone,
      timezoneOffset: dateTimeResult.timezoneOffset,
      latitude: gpsResult.latitude,
      longitude: gpsResult.longitude,
      dateTimeStatus: dateTimeResult.status,
      gpsStatus: gpsResult.status,
      dateTimeSource: dateTimeResult.source,
      confidence: confidence,
      format: format,
      photoSource: photoSource,
    );
  }

  /// Resolve an EXIF tag by IFD + name, tolerating both the prefixed form
  /// produced by exif v3 ('GPS GPSLatitude') and unprefixed keys.
  static IfdTag? _tag(Map<String, IfdTag> tags, String ifd, String name) {
    return tags['$ifd $name'] ?? tags[name];
  }

  // -------------------------------------------------------------------
  // Date / time
  // -------------------------------------------------------------------

  static _DateTimeExtraction _extractDateTime(
    Map<String, IfdTag> tags, {
    DateTime? fileModified,
  }) {
    // Priority: DateTimeOriginal > DateTimeDigitized > DateTime (IFD0) >
    // file modification (low-confidence fallback).
    const candidates = [
      ('EXIF', 'DateTimeOriginal', 'EXIF', 'OffsetTimeOriginal', DateTimeSource.dateTimeOriginal),
      ('EXIF', 'DateTimeDigitized', 'EXIF', 'OffsetTimeDigitized', DateTimeSource.dateTimeDigitized),
      ('Image', 'DateTime', 'EXIF', 'OffsetTime', DateTimeSource.dateTime),
    ];

    var sawMalformedTag = false;

    for (final (dtIfd, dtName, offIfd, offName, source) in candidates) {
      final dtTag = _tag(tags, dtIfd, dtName);
      if (dtTag == null) continue;

      final parsed = _parseExifDateTime(dtTag.printable);
      if (parsed == null) {
        sawMalformedTag = true;
        continue;
      }

      // Reject implausible timestamps: far future or pre-digital-camera era.
      if (_isImplausible(parsed)) {
        return _DateTimeExtraction(
          value: parsed,
          status: DateTimeStatus.rejected,
          source: source,
        );
      }

      final offsetTag = _tag(tags, offIfd, offName);
      final offset = offsetTag == null ? null : _parseUtcOffset(offsetTag.printable);

      return _DateTimeExtraction(
        value: parsed,
        status: DateTimeStatus.valid,
        source: source,
        hasTimezone: offset != null,
        timezoneOffset: offset,
      );
    }

    if (sawMalformedTag) {
      return const _DateTimeExtraction(status: DateTimeStatus.malformed);
    }

    // Fallback: file modification timestamp — low confidence, explicitly
    // labelled so the UI can warn that it may not be the capture time.
    if (fileModified != null) {
      return _DateTimeExtraction(
        value: fileModified,
        status: DateTimeStatus.valid,
        source: DateTimeSource.fileModification,
      );
    }

    return const _DateTimeExtraction(status: DateTimeStatus.absent);
  }

  /// Parse EXIF date/time 'YYYY:MM:DD HH:MM:SS' (also tolerating '-' date
  /// separators and a 'T' between date and time). Returns null on malformed
  /// input. The result is a plain local wall-clock value — no timezone is
  /// invented or applied.
  static DateTime? _parseExifDateTime(String printable) {
    final match = RegExp(
      r'^\s*(\d{4})[:/-](\d{1,2})[:/-](\d{1,2})[ T](\d{1,2}):(\d{1,2}):(\d{1,2})\s*$',
    ).firstMatch(printable.trim());
    if (match == null) return null;

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);

    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    if (hour > 23 || minute > 59 || second > 59) return null;

    return DateTime(year, month, day, hour, minute, second);
  }

  /// Whether a parsed timestamp is implausible for a real capture time:
  /// before 1990 or more than 48 hours in the future (the grace absorbs
  /// timezone skew and camera clock drift).
  static bool _isImplausible(DateTime dt) {
    if (dt.year < 1990) return true;
    return dt.isAfter(DateTime.now().add(const Duration(hours: 48)));
  }

  /// Parse a UTC offset string like '+09:30' or '-05:00' into decimal hours
  /// (e.g. 9.5). Returns null when absent or malformed.
  static double? _parseUtcOffset(String printable) {
    final match = RegExp(r'^\s*([+-])(\d{1,2}):(\d{2})\s*$').firstMatch(printable.trim());
    if (match == null) return null;

    final sign = match.group(1) == '-' ? -1 : 1;
    final hours = int.parse(match.group(2)!);
    final minutes = int.parse(match.group(3)!);
    if (hours > 14 || minutes > 59) return null;

    return sign * (hours + minutes / 60.0);
  }

  // -------------------------------------------------------------------
  // GPS
  // -------------------------------------------------------------------

  static _GpsExtraction _extractGps(Map<String, IfdTag> tags) {
    final latTag = _tag(tags, 'GPS', 'GPSLatitude');
    final latRefTag = _tag(tags, 'GPS', 'GPSLatitudeRef');
    final lonTag = _tag(tags, 'GPS', 'GPSLongitude');
    final lonRefTag = _tag(tags, 'GPS', 'GPSLongitudeRef');

    if (latTag == null && latRefTag == null && lonTag == null && lonRefTag == null) {
      return const _GpsExtraction(status: GpsStatus.absent);
    }
    if (latTag == null || latRefTag == null || lonTag == null || lonRefTag == null) {
      return const _GpsExtraction(status: GpsStatus.incomplete);
    }

    final latParts = _dmsFromTag(latTag);
    final lonParts = _dmsFromTag(lonTag);
    final latRef = _gpsRef(latRefTag, 'NS');
    final lonRef = _gpsRef(lonRefTag, 'EW');

    if (latParts == null || lonParts == null || latRef == null || lonRef == null) {
      return const _GpsExtraction(status: GpsStatus.malformed);
    }

    var latitude = _dmsToDecimal(latParts);
    var longitude = _dmsToDecimal(lonParts);
    if (latRef == 'S') latitude = -latitude;
    if (lonRef == 'W') longitude = -longitude;

    // Range validation — reject rather than clamp or substitute.
    if (latitude.abs() > 90 || longitude.abs() > 180) {
      return _GpsExtraction(
        status: GpsStatus.rejected,
        latitude: latitude,
        longitude: longitude,
      );
    }

    // (0,0) is almost certainly bogus data, not a real position — rejected
    // per approved validation rules; the UI may surface it only with
    // explicit user confirmation, never as a suggestion.
    if (latitude == 0.0 && longitude == 0.0) {
      return _GpsExtraction(
        status: GpsStatus.rejected,
        latitude: latitude,
        longitude: longitude,
      );
    }

    return _GpsExtraction(
      status: GpsStatus.valid,
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// Convert an EXIF GPS coordinate tag to [degrees, minutes, seconds].
  ///
  /// EXIF stores these as three RATIONAL values, surfaced by the `exif`
  /// package as an [IfdTag] whose `values.toList()` contains [Ratio] and/or
  /// plain `num` items. Returns null on malformed content.
  static List<double>? _dmsFromTag(IfdTag tag) {
    try {
      final raw = tag.values.toList();
      if (raw.length < 3) return null;

      double? numAt(int i) {
        final v = raw[i];
        if (v is Ratio) return v.toDouble();
        if (v is num) return v.toDouble();
        return null;
      }

      final degrees = numAt(0);
      final minutes = numAt(1);
      final seconds = numAt(2);
      if (degrees == null || minutes == null || seconds == null) return null;

      // Component sanity: reject non-finite values (e.g. zero denominators)
      // and out-of-range components — minutes/seconds must be within [0, 60).
      if (!degrees.isFinite || !minutes.isFinite || !seconds.isFinite) {
        return null;
      }
      if (degrees < 0 || minutes < 0 || minutes >= 60 || seconds < 0 || seconds >= 60) {
        return null;
      }

      return [degrees, minutes, seconds];
    } catch (_) {
      return null;
    }
  }

  /// Normalise a GPS hemisphere reference to a single uppercase letter and
  /// validate it against the allowed set ('NS' for latitude, 'EW' for
  /// longitude). Returns null when absent or unrecognised.
  static String? _gpsRef(IfdTag tag, String allowed) {
    var ref = tag.printable.trim().toUpperCase();

    // Some sources yield the raw bytes (e.g. 'S\0') — printable normally
    // strips the null, but fall back to first printable character.
    if (ref.length > 1) {
      ref = ref.substring(0, 1);
    }
    if (ref.isNotEmpty && allowed.contains(ref)) {
      return ref;
    }
    return null;
  }

  static double _dmsToDecimal(List<double> dms) {
    return dms[0] + dms[1] / 60 + dms[2] / 3600;
  }
}

/// Internal result of date/time extraction.
class _DateTimeExtraction {
  final DateTime? value;
  final DateTimeStatus status;
  final DateTimeSource source;
  final bool hasTimezone;
  final double? timezoneOffset;

  const _DateTimeExtraction({
    this.value,
    required this.status,
    this.source = DateTimeSource.none,
    this.hasTimezone = false,
    this.timezoneOffset,
  });
}

/// Internal result of GPS extraction.
class _GpsExtraction {
  final GpsStatus status;
  final double? latitude;
  final double? longitude;

  const _GpsExtraction({
    required this.status,
    this.latitude,
    this.longitude,
  });
}
