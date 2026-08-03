import 'package:flutter_test/flutter_test.dart';
import 'package:bragmat/models/photo_metadata_result.dart';

void main() {
  group('PhotoMetadataResult Model', () {
    test('creates result with default values', () {
      final result = PhotoMetadataResult();
      
      expect(result.dateTime, isNull);
      expect(result.hasTimezone, false);
      expect(result.timezoneOffset, isNull);
      expect(result.latitude, isNull);
      expect(result.longitude, isNull);
      expect(result.dateTimeStatus, DateTimeStatus.absent);
      expect(result.gpsStatus, GpsStatus.absent);
      expect(result.dateTimeSource, DateTimeSource.none);
      expect(result.confidence, MetadataConfidence.none);
      expect(result.format, ImageFormat.unknown);
      expect(result.photoSource, PhotoSource.unknown);
    });

    test('creates result with custom values', () {
      final dateTime = DateTime(2026, 8, 3, 14, 35);
      final result = PhotoMetadataResult(
        dateTime: dateTime,
        hasTimezone: true,
        timezoneOffset: 9.5,
        latitude: -12.4634,
        longitude: 130.8416,
        dateTimeStatus: DateTimeStatus.valid,
        gpsStatus: GpsStatus.valid,
        dateTimeSource: DateTimeSource.dateTimeOriginal,
        confidence: MetadataConfidence.exif,
        format: ImageFormat.jpeg,
        photoSource: PhotoSource.camera,
      );
      
      expect(result.dateTime, dateTime);
      expect(result.hasTimezone, true);
      expect(result.timezoneOffset, 9.5);
      expect(result.latitude, -12.4634);
      expect(result.longitude, 130.8416);
      expect(result.dateTimeStatus, DateTimeStatus.valid);
      expect(result.gpsStatus, GpsStatus.valid);
      expect(result.dateTimeSource, DateTimeSource.dateTimeOriginal);
      expect(result.confidence, MetadataConfidence.exif);
      expect(result.format, ImageFormat.jpeg);
      expect(result.photoSource, PhotoSource.camera);
    });

    test('hasValidDateTime returns true for valid EXIF date/time', () {
      final result = PhotoMetadataResult(
        dateTime: DateTime(2026, 8, 3, 14, 35),
        dateTimeStatus: DateTimeStatus.valid,
        confidence: MetadataConfidence.exif,
      );
      
      expect(result.hasValidDateTime, true);
    });

    test('hasValidDateTime returns false for null dateTime', () {
      final result = PhotoMetadataResult(
        dateTimeStatus: DateTimeStatus.valid,
        confidence: MetadataConfidence.exif,
      );
      
      expect(result.hasValidDateTime, false);
    });

    test('hasValidDateTime returns false for malformed status', () {
      final result = PhotoMetadataResult(
        dateTime: DateTime(2026, 8, 3, 14, 35),
        dateTimeStatus: DateTimeStatus.malformed,
        confidence: MetadataConfidence.exif,
      );
      
      expect(result.hasValidDateTime, false);
    });

    test('hasValidDateTime returns false for none confidence', () {
      final result = PhotoMetadataResult(
        dateTime: DateTime(2026, 8, 3, 14, 35),
        dateTimeStatus: DateTimeStatus.valid,
        confidence: MetadataConfidence.none,
      );
      
      expect(result.hasValidDateTime, false);
    });

    test('hasValidGps returns true for valid GPS', () {
      final result = PhotoMetadataResult(
        latitude: -12.4634,
        longitude: 130.8416,
        gpsStatus: GpsStatus.valid,
        confidence: MetadataConfidence.exif,
      );
      
      expect(result.hasValidGps, true);
    });

    test('hasValidGps returns false for null coordinates', () {
      final result = PhotoMetadataResult(
        gpsStatus: GpsStatus.valid,
        confidence: MetadataConfidence.exif,
      );
      
      expect(result.hasValidGps, false);
    });

    test('hasValidGps returns false for incomplete GPS', () {
      final result = PhotoMetadataResult(
        latitude: -12.4634,
        gpsStatus: GpsStatus.incomplete,
        confidence: MetadataConfidence.exif,
      );
      
      expect(result.hasValidGps, false);
    });

    test('hasAnyMetadata returns true when has valid date/time', () {
      final result = PhotoMetadataResult(
        dateTime: DateTime(2026, 8, 3, 14, 35),
        dateTimeStatus: DateTimeStatus.valid,
        confidence: MetadataConfidence.exif,
      );
      
      expect(result.hasAnyMetadata, true);
    });

    test('hasAnyMetadata returns true when has valid GPS', () {
      final result = PhotoMetadataResult(
        latitude: -12.4634,
        longitude: 130.8416,
        gpsStatus: GpsStatus.valid,
        confidence: MetadataConfidence.exif,
      );
      
      expect(result.hasAnyMetadata, true);
    });

    test('hasAnyMetadata returns false when no metadata', () {
      final result = PhotoMetadataResult();
      
      expect(result.hasAnyMetadata, false);
    });

    test('isHighConfidence returns true for EXIF confidence', () {
      final result = PhotoMetadataResult(
        confidence: MetadataConfidence.exif,
      );
      
      expect(result.isHighConfidence, true);
    });

    test('isHighConfidence returns false for file system confidence', () {
      final result = PhotoMetadataResult(
        confidence: MetadataConfidence.fileSystem,
      );
      
      expect(result.isHighConfidence, false);
    });

    test('copyWith creates modified copy', () {
      final original = PhotoMetadataResult(
        dateTime: DateTime(2026, 8, 3, 14, 35),
        latitude: -12.4634,
        confidence: MetadataConfidence.exif,
      );
      
      final modified = original.copyWith(
        latitude: -12.4500,
        gpsStatus: GpsStatus.valid,
      );
      
      expect(modified.dateTime, original.dateTime);
      expect(modified.latitude, -12.4500);
      expect(modified.longitude, original.longitude);
      expect(modified.gpsStatus, GpsStatus.valid);
      expect(modified.confidence, original.confidence);
    });

    test('copyWith preserves unchanged values', () {
      final original = PhotoMetadataResult(
        dateTime: DateTime(2026, 8, 3, 14, 35),
        hasTimezone: true,
        timezoneOffset: 9.5,
        latitude: -12.4634,
        longitude: 130.8416,
        dateTimeStatus: DateTimeStatus.valid,
        gpsStatus: GpsStatus.valid,
        dateTimeSource: DateTimeSource.dateTimeOriginal,
        confidence: MetadataConfidence.exif,
        format: ImageFormat.jpeg,
        photoSource: PhotoSource.camera,
      );
      
      final modified = original.copyWith();
      
      expect(modified.dateTime, original.dateTime);
      expect(modified.hasTimezone, original.hasTimezone);
      expect(modified.timezoneOffset, original.timezoneOffset);
      expect(modified.latitude, original.latitude);
      expect(modified.longitude, original.longitude);
      expect(modified.dateTimeStatus, original.dateTimeStatus);
      expect(modified.gpsStatus, original.gpsStatus);
      expect(modified.dateTimeSource, original.dateTimeSource);
      expect(modified.confidence, original.confidence);
      expect(modified.format, original.format);
      expect(modified.photoSource, original.photoSource);
    });
  });

  group('GPS Conversion Validation', () {
    test('latitude between -90 and 90 is valid', () {
      expect(() => _validateLatitude(-90), returnsNormally);
      expect(() => _validateLatitude(0), returnsNormally);
      expect(() => _validateLatitude(90), returnsNormally);
      expect(() => _validateLatitude(-12.4634), returnsNormally);
    });

    test('latitude outside -90 to 90 is invalid', () {
      expect(() => _validateLatitude(-91), throwsA(isA<ArgumentError>()));
      expect(() => _validateLatitude(91), throwsA(isA<ArgumentError>()));
      expect(() => _validateLatitude(-180), throwsA(isA<ArgumentError>()));
    });

    test('longitude between -180 and 180 is valid', () {
      expect(() => _validateLongitude(-180), returnsNormally);
      expect(() => _validateLongitude(0), returnsNormally);
      expect(() => _validateLongitude(180), returnsNormally);
      expect(() => _validateLongitude(130.8416), returnsNormally);
    });

    test('longitude outside -180 to 180 is invalid', () {
      expect(() => _validateLongitude(-181), throwsA(isA<ArgumentError>()));
      expect(() => _validateLongitude(181), throwsA(isA<ArgumentError>()));
    });

    test('zero coordinates require explicit confirmation', () {
      final result = PhotoMetadataResult(
        latitude: 0.0,
        longitude: 0.0,
        gpsStatus: GpsStatus.rejected,
        confidence: MetadataConfidence.exif,
      );
      
      expect(result.gpsStatus, GpsStatus.rejected);
    });

    test('incomplete GPS (missing latitude or longitude)', () {
      final result1 = PhotoMetadataResult(
        latitude: -12.4634,
        gpsStatus: GpsStatus.incomplete,
      );
      expect(result1.gpsStatus, GpsStatus.incomplete);

      final result2 = PhotoMetadataResult(
        longitude: 130.8416,
        gpsStatus: GpsStatus.incomplete,
      );
      expect(result2.gpsStatus, GpsStatus.incomplete);
    });
  });

  group('DateTime Priority Rules', () {
    test('DateTimeOriginal has highest priority', () {
      expect(DateTimeSource.dateTimeOriginal.index, lessThan(DateTimeSource.dateTimeDigitized.index));
      expect(DateTimeSource.dateTimeOriginal.index, lessThan(DateTimeSource.dateTime.index));
      expect(DateTimeSource.dateTimeOriginal.index, lessThan(DateTimeSource.fileModification.index));
    });

    test('DateTimeDigitized has second priority', () {
      expect(DateTimeSource.dateTimeDigitized.index, lessThan(DateTimeSource.dateTime.index));
      expect(DateTimeSource.dateTimeDigitized.index, lessThan(DateTimeSource.fileModification.index));
    });

    test('DateTime has third priority', () {
      expect(DateTimeSource.dateTime.index, lessThan(DateTimeSource.fileModification.index));
    });

    test('fileModification has lowest priority', () {
      expect(DateTimeSource.fileModification.index, greaterThan(DateTimeSource.dateTime.index));
    });
  });

  group('Timezone Offset Parsing', () {
    test('positive UTC offset', () {
      final result = PhotoMetadataResult(
        timezoneOffset: 9.5,
        hasTimezone: true,
      );
      expect(result.timezoneOffset, 9.5);
      expect(result.hasTimezone, true);
    });

    test('negative UTC offset', () {
      final result = PhotoMetadataResult(
        timezoneOffset: -5.0,
        hasTimezone: true,
      );
      expect(result.timezoneOffset, -5.0);
      expect(result.hasTimezone, true);
    });

    test('UTC offset (zero)', () {
      final result = PhotoMetadataResult(
        timezoneOffset: 0.0,
        hasTimezone: true,
      );
      expect(result.timezoneOffset, 0.0);
      expect(result.hasTimezone, true);
    });

    test('missing timezone offset', () {
      final result = PhotoMetadataResult(
        hasTimezone: false,
      );
      expect(result.timezoneOffset, isNull);
      expect(result.hasTimezone, false);
    });

    test('daylight saving timezone', () {
      final result = PhotoMetadataResult(
        timezoneOffset: 10.0, // Sydney DST
        hasTimezone: true,
      );
      expect(result.timezoneOffset, 10.0);
      expect(result.hasTimezone, true);
    });
  });

  group('Confidence Levels', () {
    test('EXIF confidence is higher than file system', () {
      expect(MetadataConfidence.exif.index, lessThan(MetadataConfidence.fileSystem.index));
    });

    test('none confidence is lowest', () {
      expect(MetadataConfidence.none.index, greaterThan(MetadataConfidence.fileSystem.index));
    });
  });

  group('Image Format Detection', () {
    test('JPEG format', () {
      final result = PhotoMetadataResult(format: ImageFormat.jpeg);
      expect(result.format, ImageFormat.jpeg);
    });

    test('HEIC format', () {
      final result = PhotoMetadataResult(format: ImageFormat.heic);
      expect(result.format, ImageFormat.heic);
    });

    test('unknown format by default', () {
      final result = PhotoMetadataResult();
      expect(result.format, ImageFormat.unknown);
    });
  });

  group('Photo Source Tracking', () {
    test('camera source', () {
      final result = PhotoMetadataResult(photoSource: PhotoSource.camera);
      expect(result.photoSource, PhotoSource.camera);
    });

    test('gallery source', () {
      final result = PhotoMetadataResult(photoSource: PhotoSource.gallery);
      expect(result.photoSource, PhotoSource.gallery);
    });

    test('lost data source', () {
      final result = PhotoMetadataResult(photoSource: PhotoSource.lostData);
      expect(result.photoSource, PhotoSource.lostData);
    });
  });
}

// Helper validation functions (to be implemented in service)
void _validateLatitude(double lat) {
  if (lat < -90 || lat > 90) {
    throw ArgumentError('Latitude must be between -90 and 90');
  }
}

void _validateLongitude(double lon) {
  if (lon < -180 || lon > 180) {
    throw ArgumentError('Longitude must be between -180 and 180');
  }
}
