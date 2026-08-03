/// Immutable result model for photo metadata extraction.
/// 
/// Distinguishes between value present, absent, malformed, rejected,
/// timezone known/unknown, metadata source, and confidence level.
class PhotoMetadataResult {
  /// The date/time extracted from the photo (local time at capture location)
  final DateTime? dateTime;
  
  /// Whether the date/time has a confirmed timezone offset
  final bool hasTimezone;
  
  /// The timezone offset in hours (e.g., +9.5 for ACST, -5 for EST)
  final double? timezoneOffset;
  
  /// The latitude extracted from GPS
  final double? latitude;
  
  /// The longitude extracted from GPS
  final double? longitude;
  
  /// Status of date/time extraction
  final DateTimeStatus dateTimeStatus;
  
  /// Status of GPS extraction
  final GpsStatus gpsStatus;
  
  /// Which EXIF tag provided the date/time
  final DateTimeSource dateTimeSource;
  
  /// Confidence level of the extracted data
  final MetadataConfidence confidence;
  
  /// Image format detected
  final ImageFormat format;
  
  /// Whether the photo was from camera or gallery
  final PhotoSource photoSource;

  const PhotoMetadataResult({
    this.dateTime,
    this.hasTimezone = false,
    this.timezoneOffset,
    this.latitude,
    this.longitude,
    this.dateTimeStatus = DateTimeStatus.absent,
    this.gpsStatus = GpsStatus.absent,
    this.dateTimeSource = DateTimeSource.none,
    this.confidence = MetadataConfidence.none,
    this.format = ImageFormat.unknown,
    this.photoSource = PhotoSource.unknown,
  });

  /// Whether the date/time is valid and can be used
  bool get hasValidDateTime => 
      dateTime != null && 
      dateTimeStatus == DateTimeStatus.valid &&
      confidence != MetadataConfidence.none;

  /// Whether the GPS is valid and can be used
  bool get hasValidGps => 
      latitude != null && 
      longitude != null &&
      gpsStatus == GpsStatus.valid &&
      confidence != MetadataConfidence.none;

  /// Whether any metadata is available
  bool get hasAnyMetadata => hasValidDateTime || hasValidGps;

  /// Whether this is a high-confidence result from EXIF
  bool get isHighConfidence => confidence == MetadataConfidence.exif;

  /// Copy with method for creating modified copies
  PhotoMetadataResult copyWith({
    DateTime? dateTime,
    bool? hasTimezone,
    double? timezoneOffset,
    double? latitude,
    double? longitude,
    DateTimeStatus? dateTimeStatus,
    GpsStatus? gpsStatus,
    DateTimeSource? dateTimeSource,
    MetadataConfidence? confidence,
    ImageFormat? format,
    PhotoSource? photoSource,
  }) {
    return PhotoMetadataResult(
      dateTime: dateTime ?? this.dateTime,
      hasTimezone: hasTimezone ?? this.hasTimezone,
      timezoneOffset: timezoneOffset ?? this.timezoneOffset,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      dateTimeStatus: dateTimeStatus ?? this.dateTimeStatus,
      gpsStatus: gpsStatus ?? this.gpsStatus,
      dateTimeSource: dateTimeSource ?? this.dateTimeSource,
      confidence: confidence ?? this.confidence,
      format: format ?? this.format,
      photoSource: photoSource ?? this.photoSource,
    );
  }

  @override
  String toString() {
    return 'PhotoMetadataResult('
        'dateTime: $dateTime, '
        'hasTimezone: $hasTimezone, '
        'timezoneOffset: $timezoneOffset, '
        'latitude: $latitude, '
        'longitude: $longitude, '
        'dateTimeStatus: $dateTimeStatus, '
        'gpsStatus: $gpsStatus, '
        'dateTimeSource: $dateTimeSource, '
        'confidence: $confidence, '
        'format: $format, '
        'photoSource: $photoSource)';
  }
}

/// Status of date/time extraction
enum DateTimeStatus {
  /// No date/time data found
  absent,
  /// Date/time found and valid
  valid,
  /// Date/time found but malformed
  malformed,
  /// Date/time found but rejected by validation (e.g., future date)
  rejected,
}

/// Status of GPS extraction
enum GpsStatus {
  /// No GPS data found
  absent,
  /// GPS found and valid
  valid,
  /// GPS found but malformed
  malformed,
  /// GPS found but rejected by validation (e.g., 0,0)
  rejected,
  /// GPS incomplete (missing latitude or longitude)
  incomplete,
}

/// Which EXIF tag provided the date/time
enum DateTimeSource {
  /// No source
  none,
  /// DateTimeOriginal tag
  dateTimeOriginal,
  /// DateTimeDigitized tag
  dateTimeDigitized,
  /// DateTime tag
  dateTime,
  /// File modification timestamp (low confidence)
  fileModification,
}

/// Confidence level of extracted data
enum MetadataConfidence {
  /// No metadata
  none,
  /// From EXIF tags (high confidence)
  exif,
  /// From file system (low confidence)
  fileSystem,
}

/// Image format detected
enum ImageFormat {
  /// Unknown format
  unknown,
  /// JPEG format
  jpeg,
  /// HEIC/HEIF format
  heic,
  /// PNG format
  png,
  /// WebP format
  webp,
}

/// Photo source
enum PhotoSource {
  /// Unknown source
  unknown,
  /// Camera capture
  camera,
  /// Gallery selection
  gallery,
  /// Lost data recovery
  lostData,
}
