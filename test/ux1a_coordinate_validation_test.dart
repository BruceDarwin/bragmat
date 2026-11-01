// Unit tests for the UX-1A coordinate validation and coordinate-source
// label helpers.
//
// Covers:
//  - isValidMapLatitude / isValidMapLongitude / hasValidMapCoordinates
//    (null, NaN, infinite, out-of-range, boundary, and 0,0 values)
//  - coordinateSourceLabel for canonical stored values, legacy display
//    strings, unknown values, and photo-EXIF inference
import 'package:flutter_test/flutter_test.dart';

import 'package:bragmat/helpers/coordinate_source_label.dart';
import 'package:bragmat/helpers/coordinate_validation.dart';
import 'package:bragmat/models/catch_media.dart';

void main() {
  group('isValidMapLatitude', () {
    test('accepts valid values including boundaries and zero', () {
      expect(isValidMapLatitude(-12.4634), isTrue);
      expect(isValidMapLatitude(-90.0), isTrue);
      expect(isValidMapLatitude(90.0), isTrue);
      expect(isValidMapLatitude(0.0), isTrue);
    });

    test('rejects null, non-finite and out-of-range values', () {
      expect(isValidMapLatitude(null), isFalse);
      expect(isValidMapLatitude(double.nan), isFalse);
      expect(isValidMapLatitude(double.infinity), isFalse);
      expect(isValidMapLatitude(double.negativeInfinity), isFalse);
      expect(isValidMapLatitude(90.000001), isFalse);
      expect(isValidMapLatitude(-90.000001), isFalse);
    });
  });

  group('isValidMapLongitude', () {
    test('accepts valid values including boundaries and zero', () {
      expect(isValidMapLongitude(130.8456), isTrue);
      expect(isValidMapLongitude(-180.0), isTrue);
      expect(isValidMapLongitude(180.0), isTrue);
      expect(isValidMapLongitude(0.0), isTrue);
    });

    test('rejects null, non-finite and out-of-range values', () {
      expect(isValidMapLongitude(null), isFalse);
      expect(isValidMapLongitude(double.nan), isFalse);
      expect(isValidMapLongitude(double.infinity), isFalse);
      expect(isValidMapLongitude(180.000001), isFalse);
      expect(isValidMapLongitude(-180.000001), isFalse);
    });
  });

  group('hasValidMapCoordinates', () {
    test('requires both components valid', () {
      expect(hasValidMapCoordinates(-12.4634, 130.8456), isTrue);
      // (0, 0) is a legitimate coordinate, not a missing-value sentinel.
      expect(hasValidMapCoordinates(0.0, 0.0), isTrue);
      expect(hasValidMapCoordinates(-12.4634, null), isFalse);
      expect(hasValidMapCoordinates(null, 130.8456), isFalse);
      expect(hasValidMapCoordinates(91.0, 130.8456), isFalse);
      expect(hasValidMapCoordinates(-12.4634, 181.0), isFalse);
      expect(hasValidMapCoordinates(double.nan, 130.8456), isFalse);
    });
  });

  group('coordinateSourceLabel', () {
    test('maps canonical stored values', () {
      expect(coordinateSourceLabel(coordinateSource: 'manual'), 'Manual');
      expect(
          coordinateSourceLabel(coordinateSource: 'device_gps'), 'Device GPS');
      expect(
          coordinateSourceLabel(coordinateSource: 'photo_gps'), 'Photo GPS');
      expect(coordinateSourceLabel(coordinateSource: 'favourite_spot'),
          'Favourite Spot');
      expect(coordinateSourceLabel(coordinateSource: 'map_selected'),
          'Map Selected');
    });

    test('maps legacy display strings written by older versions', () {
      expect(coordinateSourceLabel(coordinateSource: 'Manual'), 'Manual');
      expect(
          coordinateSourceLabel(coordinateSource: 'Device GPS'), 'Device GPS');
      expect(coordinateSourceLabel(coordinateSource: 'Photo EXIF'),
          'Photo GPS');
      expect(coordinateSourceLabel(coordinateSource: 'Favourite Spot'),
          'Favourite Spot');
      expect(coordinateSourceLabel(coordinateSource: 'Map Selected'),
          'Map Selected');
    });

    test('passes unknown non-empty values through unchanged', () {
      expect(coordinateSourceLabel(coordinateSource: 'satellite_fix'),
          'satellite_fix');
    });

    test('infers Photo EXIF from matching media coordinates', () {
      final media = CatchMedia(
        catchId: 1,
        filePath: 'photos/a.jpg',
        latitude: -12.4634,
        longitude: 130.8456,
      );
      expect(
        coordinateSourceLabel(
          latitude: -12.4634,
          longitude: 130.8456,
          mediaItems: [media],
        ),
        'Photo EXIF',
      );
    });

    test('falls back to Manual without a recorded source or matching media',
        () {
      expect(coordinateSourceLabel(), 'Manual');
      final media = CatchMedia(
        catchId: 1,
        filePath: 'photos/a.jpg',
        latitude: -33.0,
        longitude: 151.0,
      );
      expect(
        coordinateSourceLabel(
          latitude: -12.4634,
          longitude: 130.8456,
          mediaItems: [media],
        ),
        'Manual',
      );
      // Media without coordinates never implies EXIF.
      final noGps =
          CatchMedia(catchId: 1, filePath: 'photos/b.jpg');
      expect(
        coordinateSourceLabel(
          latitude: -12.4634,
          longitude: 130.8456,
          mediaItems: [noGps],
        ),
        'Manual',
      );
    });
  });
}
