import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bragmat/models/photo_metadata_result.dart';
import 'package:bragmat/services/photo_metadata_service.dart';

void main() {
  group('Real Moto G15 fixtures', () {
    const mfnr = 'IMG_20260617_213201147_MFNR.jpg';
    const sr = 'photo_metadata_tests/IMG_20260618_212522448_SR.jpg';

    test('MFNR camera photo: full EXIF datetime, offset and GPS', () async {
      final result = await PhotoMetadataService.extractFromFile(
        mfnr,
        photoSource: PhotoSource.camera,
      );

      expect(result.format, ImageFormat.jpeg);
      expect(result.photoSource, PhotoSource.camera);
      expect(result.confidence, MetadataConfidence.exif);

      // Capture time preserved as wall-clock value.
      expect(result.dateTimeStatus, DateTimeStatus.valid);
      expect(result.dateTime, DateTime(2026, 6, 17, 21, 32, 1));
      expect(result.dateTimeSource, DateTimeSource.dateTimeOriginal);

      // EXIF OffsetTimeOriginal '+09:30' retained.
      expect(result.hasTimezone, true);
      expect(result.timezoneOffset, 9.5);

      // GPS 12°22'36.28"S 130°51'3.17"E.
      expect(result.gpsStatus, GpsStatus.valid);
      expect(result.latitude, closeTo(-12.3767444, 0.0001));
      expect(result.longitude, closeTo(130.8508806, 0.0001));

      expect(result.hasValidDateTime, true);
      expect(result.hasValidGps, true);
      expect(result.hasAnyMetadata, true);
    });

    test('SR photo: GPS present, no EXIF datetime tags', () async {
      // Byte-level extraction without a file-mtime fallback.
      final bytes = await File(sr).readAsBytes();
      final result = await PhotoMetadataService.extractFromBytes(bytes);

      expect(result.gpsStatus, GpsStatus.valid);
      expect(result.latitude, closeTo(-12.3766583, 0.0001));
      expect(result.longitude, closeTo(130.8507556, 0.0001));

      // No EXIF timestamp of any kind -> absent, not invented.
      expect(result.dateTimeStatus, DateTimeStatus.absent);
      expect(result.dateTime, isNull);
      expect(result.dateTimeSource, DateTimeSource.none);
      expect(result.hasTimezone, false);
    });

    test('SR photo from file: falls back to file modification timestamp',
        () async {
      final result = await PhotoMetadataService.extractFromFile(sr);

      // File mtime is offered only as a labelled low-confidence fallback.
      expect(result.dateTimeStatus, DateTimeStatus.valid);
      expect(result.dateTimeSource, DateTimeSource.fileModification);
      expect(result.hasTimezone, false);
      expect(result.gpsStatus, GpsStatus.valid);
      // Confidence stays 'exif' because GPS metadata came from EXIF.
      expect(result.confidence, MetadataConfidence.exif);
    });
  });

  group('Format detection', () {
    test('JPEG magic bytes', () {
      expect(
        PhotoMetadataService.detectFormat(
            Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0])),
        ImageFormat.jpeg,
      );
    });

    test('PNG magic bytes', () {
      expect(
        PhotoMetadataService.detectFormat(Uint8List.fromList(
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        ImageFormat.png,
      );
    });

    test('WebP magic bytes', () {
      expect(
        PhotoMetadataService.detectFormat(Uint8List.fromList([
          0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50
        ])),
        ImageFormat.webp,
      );
    });

    test('HEIC ftyp box', () {
      final bytes = Uint8List.fromList([
        0, 0, 0, 0,
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x68, 0x65, 0x69, 0x63, // 'heic'
      ]);
      expect(PhotoMetadataService.detectFormat(bytes), ImageFormat.heic);
    });

    test('unknown format', () {
      expect(
        PhotoMetadataService.detectFormat(
            Uint8List.fromList([0x01, 0x02, 0x03, 0x04])),
        ImageFormat.unknown,
      );
    });
  });

  group('Date/time extraction (byte-level EXIF)', () {
    test('DateTimeOriginal + OffsetTimeOriginal', () async {
      final jpeg = _jpegWithExif(
        dateTimeOriginal: '2026:06:17 21:32:01',
        offsetTimeOriginal: '+09:30',
      );
      final r = await PhotoMetadataService.extractFromBytes(jpeg);

      expect(r.dateTimeStatus, DateTimeStatus.valid);
      expect(r.dateTime, DateTime(2026, 6, 17, 21, 32, 1));
      expect(r.dateTimeSource, DateTimeSource.dateTimeOriginal);
      expect(r.hasTimezone, true);
      expect(r.timezoneOffset, 9.5);
      expect(r.confidence, MetadataConfidence.exif);
    });

    test('DateTimeOriginal without offset -> clock preserved, no timezone',
        () async {
      final jpeg = _jpegWithExif(dateTimeOriginal: '2015:01:02 03:04:05');
      final r = await PhotoMetadataService.extractFromBytes(jpeg);

      expect(r.dateTime, DateTime(2015, 1, 2, 3, 4, 5));
      expect(r.hasTimezone, false);
      expect(r.timezoneOffset, isNull);
    });

    test('DateTimeDigitized used when DateTimeOriginal absent', () async {
      final jpeg = _jpegWithExif(
        dateTimeDigitized: '2020:07:04 10:20:30',
        offsetTimeDigitized: '-05:00',
      );
      final r = await PhotoMetadataService.extractFromBytes(jpeg);

      expect(r.dateTime, DateTime(2020, 7, 4, 10, 20, 30));
      expect(r.dateTimeSource, DateTimeSource.dateTimeDigitized);
      expect(r.timezoneOffset, -5.0);
    });

    test('IFD0 DateTime is the third-priority source', () async {
      final jpeg = _jpegWithExif(
        imageDateTime: '2019:03:04 05:06:07',
        offsetTime: '+00:00',
      );
      final r = await PhotoMetadataService.extractFromBytes(jpeg);

      expect(r.dateTime, DateTime(2019, 3, 4, 5, 6, 7));
      expect(r.dateTimeSource, DateTimeSource.dateTime);
      expect(r.hasTimezone, true);
      expect(r.timezoneOffset, 0.0);
    });

    test('malformed DateTimeOriginal falls through to DateTimeDigitized',
        () async {
      final jpeg = _jpegWithExif(
        dateTimeOriginal: 'not a date',
        dateTimeDigitized: '2021:11:22 13:14:15',
      );
      final r = await PhotoMetadataService.extractFromBytes(jpeg);

      expect(r.dateTimeStatus, DateTimeStatus.valid);
      expect(r.dateTimeSource, DateTimeSource.dateTimeDigitized);
      expect(r.dateTime, DateTime(2021, 11, 22, 13, 14, 15));
    });

    test('all datetime tags malformed -> malformed status', () async {
      final jpeg = _jpegWithExif(
        dateTimeOriginal: 'garbage',
        dateTimeDigitized: 'also garbage',
      );
      final r = await PhotoMetadataService.extractFromBytes(jpeg);
      expect(r.dateTimeStatus, DateTimeStatus.malformed);
    });

    test('future date is rejected', () async {
      final jpeg = _jpegWithExif(dateTimeOriginal: '2999:01:01 00:00:00');
      final r = await PhotoMetadataService.extractFromBytes(jpeg);
      expect(r.dateTimeStatus, DateTimeStatus.rejected);
      expect(r.hasValidDateTime, false);
    });

    test('implausibly old date (1980) is rejected', () async {
      final jpeg = _jpegWithExif(dateTimeOriginal: '1980:01:06 00:00:00');
      final r = await PhotoMetadataService.extractFromBytes(jpeg);
      expect(r.dateTimeStatus, DateTimeStatus.rejected);
    });

    test('malformed offset does not invalidate the timestamp', () async {
      final jpeg = _jpegWithExif(
        dateTimeOriginal: '2026:06:17 21:32:01',
        offsetTimeOriginal: 'GMT+9',
      );
      final r = await PhotoMetadataService.extractFromBytes(jpeg);

      expect(r.dateTimeStatus, DateTimeStatus.valid);
      expect(r.hasTimezone, false);
      expect(r.timezoneOffset, isNull);
    });

    test('offset is paired to its own datetime source only', () async {
      // OffsetTimeDigitized must not be paired to DateTimeOriginal.
      final jpeg = _jpegWithExif(
        dateTimeOriginal: '2026:06:17 21:32:01',
        offsetTimeDigitized: '+09:30',
      );
      final r = await PhotoMetadataService.extractFromBytes(jpeg);
      expect(r.hasTimezone, false);
    });

    test('file modification fallback is labelled low confidence', () async {
      final jpeg = _jpegWithExif(); // no EXIF at all
      final mtime = DateTime(2024, 5, 6, 7, 8, 9);
      final r = await PhotoMetadataService.extractFromBytes(
        jpeg,
        fileModified: mtime,
      );

      expect(r.dateTime, mtime);
      expect(r.dateTimeSource, DateTimeSource.fileModification);
      expect(r.dateTimeStatus, DateTimeStatus.valid);
      expect(r.confidence, MetadataConfidence.fileSystem);
      expect(r.isHighConfidence, false);
    });

    test('EXIF datetime takes precedence over file modification', () async {
      final jpeg = _jpegWithExif(dateTimeOriginal: '2026:06:17 21:32:01');
      final r = await PhotoMetadataService.extractFromBytes(
        jpeg,
        fileModified: DateTime(2024, 1, 1),
      );
      expect(r.dateTimeSource, DateTimeSource.dateTimeOriginal);
    });
  });

  group('GPS extraction (byte-level EXIF)', () {
    test('valid coordinates south/east', () async {
      final jpeg = _jpegWithExif(
        lat: [
          [12, 1],
          [22, 1],
          [36, 1]
        ],
        latRef: 'S',
        lon: [
          [130, 1],
          [51, 1],
          [3, 1]
        ],
        lonRef: 'E',
      );
      final r = await PhotoMetadataService.extractFromBytes(jpeg);

      expect(r.gpsStatus, GpsStatus.valid);
      expect(r.latitude, closeTo(-12.3766667, 0.0001));
      expect(r.longitude, closeTo(130.8508333, 0.0001));
      expect(r.confidence, MetadataConfidence.exif);
    });

    test('west longitude is negative', () async {
      final jpeg = _jpegWithExif(
        lat: [
          [33, 1],
          [52, 1],
          [0, 1]
        ],
        latRef: 'N',
        lon: [
          [117, 1],
          [10, 1],
          [0, 1]
        ],
        lonRef: 'W',
      );
      final r = await PhotoMetadataService.extractFromBytes(jpeg);
      expect(r.latitude, closeTo(33.8666667, 0.0001));
      expect(r.longitude, closeTo(-117.1666667, 0.0001));
    });

    test('latitude only -> incomplete', () async {
      final jpeg = _jpegWithExif(
        lat: [
          [12, 1],
          [22, 1],
          [36, 1]
        ],
        latRef: 'S',
      );
      final r = await PhotoMetadataService.extractFromBytes(jpeg);
      expect(r.gpsStatus, GpsStatus.incomplete);
      expect(r.hasValidGps, false);
    });

    test('missing hemisphere ref -> incomplete', () async {
      final jpeg = _jpegWithExif(
        lat: [
          [12, 1],
          [22, 1],
          [36, 1]
        ],
        lon: [
          [130, 1],
          [51, 1],
          [3, 1]
        ],
      );
      final r = await PhotoMetadataService.extractFromBytes(jpeg);
      expect(r.gpsStatus, GpsStatus.incomplete);
    });

    test('out-of-range latitude (95 deg) rejected, values retained', () async {
      final jpeg = _jpegWithExif(
        lat: [
          [95, 1],
          [0, 1],
          [0, 1]
        ],
        latRef: 'N',
        lon: [
          [130, 1],
          [51, 1],
          [3, 1]
        ],
        lonRef: 'E',
      );
      final r = await PhotoMetadataService.extractFromBytes(jpeg);
      expect(r.gpsStatus, GpsStatus.rejected);
      expect(r.hasValidGps, false);
    });

    test('zero coordinates are rejected, not treated as valid', () async {
      final jpeg = _jpegWithExif(
        lat: [
          [0, 1],
          [0, 1],
          [0, 1]
        ],
        latRef: 'N',
        lon: [
          [0, 1],
          [0, 1],
          [0, 1]
        ],
        lonRef: 'E',
      );
      final r = await PhotoMetadataService.extractFromBytes(jpeg);
      expect(r.gpsStatus, GpsStatus.rejected);
      expect(r.hasValidGps, false);
    });

    test('invalid hemisphere ref -> malformed', () async {
      final jpeg = _jpegWithExif(
        lat: [
          [12, 1],
          [22, 1],
          [36, 1]
        ],
        latRef: 'X',
        lon: [
          [130, 1],
          [51, 1],
          [3, 1]
        ],
        lonRef: 'E',
      );
      final r = await PhotoMetadataService.extractFromBytes(jpeg);
      expect(r.gpsStatus, GpsStatus.malformed);
    });
  });

  group('parseExifTags (synthetic tag maps)', () {
    IfdTag asciiTag(int tag, String s) => IfdTag(
          tag: tag,
          tagType: 'ASCII',
          printable: s,
          values: IfdBytes.fromList(utf8.encode('$s\u0000')),
        );

    IfdTag ratiosTag(int tag, List<List<int>> rats) => IfdTag(
          tag: tag,
          tagType: 'RATIONAL',
          printable: rats.map((r) => '${r[0]}/${r[1]}').join(', '),
          values: IfdRatios(rats.map((r) => Ratio(r[0], r[1])).toList()),
        );

    IfdTag intsTag(int tag, List<int> ints) => IfdTag(
          tag: tag,
          tagType: 'SHORT',
          printable: ints.toString(),
          values: IfdInts(ints),
        );

    test('unprefixed bare keys are tolerated', () {
      final r = PhotoMetadataService.parseExifTags({
        'DateTimeOriginal': asciiTag(0x9003, '2026:06:17 21:32:01'),
        'GPSLatitude': ratiosTag(0x0002, [
          [12, 1],
          [22, 1],
          [36, 1]
        ]),
        'GPSLatitudeRef': asciiTag(0x0001, 'S'),
        'GPSLongitude': ratiosTag(0x0004, [
          [130, 1],
          [51, 1],
          [3, 1]
        ]),
        'GPSLongitudeRef': asciiTag(0x0003, 'E'),
      });

      expect(r.dateTime, DateTime(2026, 6, 17, 21, 32, 1));
      expect(r.gpsStatus, GpsStatus.valid);
      expect(r.latitude, closeTo(-12.3766667, 0.0001));
    });

    test('integer DMS components (IfdInts) parse', () {
      final r = PhotoMetadataService.parseExifTags({
        'GPS GPSLatitude': intsTag(0x0002, [12, 22, 36]),
        'GPS GPSLatitudeRef': asciiTag(0x0001, 'S'),
        'GPS GPSLongitude': intsTag(0x0004, [130, 51, 3]),
        'GPS GPSLongitudeRef': asciiTag(0x0003, 'E'),
      });
      expect(r.gpsStatus, GpsStatus.valid);
      expect(r.latitude, closeTo(-12.3766667, 0.0001));
    });

    test('zero-denominator ratio -> malformed, never zero-substituted', () {
      final r = PhotoMetadataService.parseExifTags({
        'GPS GPSLatitude': ratiosTag(0x0002, [
          [1, 0],
          [22, 1],
          [36, 1]
        ]),
        'GPS GPSLatitudeRef': asciiTag(0x0001, 'S'),
        'GPS GPSLongitude': ratiosTag(0x0004, [
          [130, 1],
          [51, 1],
          [3, 1]
        ]),
        'GPS GPSLongitudeRef': asciiTag(0x0003, 'E'),
      });
      expect(r.gpsStatus, GpsStatus.malformed);
      expect(r.latitude, isNull);
      expect(r.hasValidGps, false);
    });

    test('out-of-range DMS component (minutes 90) -> malformed', () {
      final r = PhotoMetadataService.parseExifTags({
        'GPS GPSLatitude': ratiosTag(0x0002, [
          [12, 1],
          [90, 1],
          [36, 1]
        ]),
        'GPS GPSLatitudeRef': asciiTag(0x0001, 'S'),
        'GPS GPSLongitude': ratiosTag(0x0004, [
          [130, 1],
          [51, 1],
          [3, 1]
        ]),
        'GPS GPSLongitudeRef': asciiTag(0x0003, 'E'),
      });
      expect(r.gpsStatus, GpsStatus.malformed);
    });

    test('empty tag map -> absent everything, no confidence', () {
      final r = PhotoMetadataService.parseExifTags(const {});
      expect(r.dateTimeStatus, DateTimeStatus.absent);
      expect(r.gpsStatus, GpsStatus.absent);
      expect(r.confidence, MetadataConfidence.none);
      expect(r.hasAnyMetadata, false);
    });
  });

  group('Graceful failure', () {
    test('nonexistent file returns empty result, no throw', () async {
      final r = await PhotoMetadataService.extractFromFile(
          'does/not/exist.jpg');
      expect(r.hasAnyMetadata, false);
      expect(r.dateTimeStatus, DateTimeStatus.absent);
      expect(r.gpsStatus, GpsStatus.absent);
    });

    test('garbage bytes -> no crash, absent', () async {
      final r = await PhotoMetadataService.extractFromBytes(
          Uint8List.fromList(utf8.encode('this is not an image at all')));
      expect(r.hasAnyMetadata, false);
      expect(r.format, ImageFormat.unknown);
    });

    test('truncated JPEG header -> absent, no crash', () async {
      final r = await PhotoMetadataService.extractFromBytes(
          Uint8List.fromList([0xFF, 0xD8, 0xFF]));
      expect(r.hasAnyMetadata, false);
      expect(r.format, ImageFormat.jpeg);
    });

    test('JPEG with no APP1/EXIF -> absent', () async {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
      final r = await PhotoMetadataService.extractFromBytes(jpeg);
      expect(r.gpsStatus, GpsStatus.absent);
      expect(r.dateTimeStatus, DateTimeStatus.absent);
    });
  });
}

// ---------------------------------------------------------------------------
// Minimal JPEG + EXIF builder for byte-level tests.
// Produces SOI + APP1('Exif\0\0' + TIFF) + EOI, which the `exif` package
// parses fully without needing actual image data.
// ---------------------------------------------------------------------------

class _Entry {
  _Entry(this.tag, this.type, this.count, this.inline, [this.overflow]);

  final int tag;
  final int type;
  final int count;
  List<int> inline; // up to 4 bytes, or the 4-byte value/offset slot
  List<int>? overflow; // >4-byte payload placed in the data area
  int dataOffset = 0;

  factory _Entry.ascii(int tag, String s) {
    final bytes = utf8.encode('$s\u0000');
    return _Entry(tag, 2, bytes.length, bytes.length <= 4 ? bytes : const [],
        bytes.length > 4 ? bytes : null);
  }

  factory _Entry.longPtr(int tag, int value) =>
      _Entry(tag, 4, 1, _u32(value));

  factory _Entry.rationals(int tag, List<List<int>> rats) {
    final b = <int>[];
    for (final r in rats) {
      b.addAll(_u32(r[0]));
      b.addAll(_u32(r[1]));
    }
    return _Entry(tag, 5, rats.length, const [], b);
  }
}

List<int> _u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _u32(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

Uint8List _jpegWithExif({
  String? imageDateTime,
  String? dateTimeOriginal,
  String? dateTimeDigitized,
  String? offsetTime,
  String? offsetTimeOriginal,
  String? offsetTimeDigitized,
  List<List<int>>? lat,
  String? latRef,
  List<List<int>>? lon,
  String? lonRef,
}) {
  final exifNeeded = dateTimeOriginal != null ||
      dateTimeDigitized != null ||
      offsetTime != null ||
      offsetTimeOriginal != null ||
      offsetTimeDigitized != null;
  final gpsNeeded =
      lat != null || latRef != null || lon != null || lonRef != null;

  final ifd0 = <_Entry>[];
  final exif = <_Entry>[];
  final gps = <_Entry>[];

  if (imageDateTime != null) ifd0.add(_Entry.ascii(0x0132, imageDateTime));
  final exifPtr = _Entry.longPtr(0x8769, 0);
  final gpsPtr = _Entry.longPtr(0x8825, 0);
  if (exifNeeded) ifd0.add(exifPtr);
  if (gpsNeeded) ifd0.add(gpsPtr);

  if (dateTimeOriginal != null) {
    exif.add(_Entry.ascii(0x9003, dateTimeOriginal));
  }
  if (dateTimeDigitized != null) {
    exif.add(_Entry.ascii(0x9004, dateTimeDigitized));
  }
  if (offsetTime != null) exif.add(_Entry.ascii(0x9010, offsetTime));
  if (offsetTimeOriginal != null) {
    exif.add(_Entry.ascii(0x9011, offsetTimeOriginal));
  }
  if (offsetTimeDigitized != null) {
    exif.add(_Entry.ascii(0x9012, offsetTimeDigitized));
  }

  if (latRef != null) gps.add(_Entry.ascii(0x0001, latRef));
  if (lat != null) gps.add(_Entry.rationals(0x0002, lat));
  if (lonRef != null) gps.add(_Entry.ascii(0x0003, lonRef));
  if (lon != null) gps.add(_Entry.rationals(0x0004, lon));

  ifd0.sort((a, b) => a.tag.compareTo(b.tag));
  exif.sort((a, b) => a.tag.compareTo(b.tag));
  gps.sort((a, b) => a.tag.compareTo(b.tag));

  // Lay out: TIFF header(8) -> IFD0 -> EXIF IFD -> GPS IFD -> data area.
  var pos = 8;
  pos += 2 + 12 * ifd0.length + 4;
  exifPtr.inline = _u32(pos);
  if (exifNeeded) pos += 2 + 12 * exif.length + 4;
  gpsPtr.inline = _u32(pos);
  if (gpsNeeded) pos += 2 + 12 * gps.length + 4;

  var dataPos = pos;
  for (final e in [...ifd0, ...exif, ...gps]) {
    if (e.overflow != null) {
      e.dataOffset = dataPos;
      dataPos += e.overflow!.length;
      e.inline = _u32(e.dataOffset);
    }
  }

  void emitIfd(BytesBuilder out, List<_Entry> entries) {
    out.add(_u16(entries.length));
    for (final e in entries) {
      out.add(_u16(e.tag));
      out.add(_u16(e.type));
      out.add(_u32(e.count));
      final inline = List<int>.from(e.inline);
      while (inline.length < 4) {
        inline.add(0);
      }
      out.add(inline.sublist(0, 4));
    }
    out.add(_u32(0)); // next IFD
  }

  final tiff = BytesBuilder();
  tiff.add([0x49, 0x49, 0x2A, 0x00]); // 'II' + 42
  tiff.add(_u32(8));
  emitIfd(tiff, ifd0);
  if (exifNeeded) emitIfd(tiff, exif);
  if (gpsNeeded) emitIfd(tiff, gps);
  for (final e in [...ifd0, ...exif, ...gps]) {
    if (e.overflow != null) tiff.add(e.overflow!);
  }
  final tiffBytes = tiff.toBytes();

  final app1Payload = BytesBuilder()
    ..add([0x45, 0x78, 0x69, 0x66, 0x00, 0x00]) // 'Exif\0\0'
    ..add(tiffBytes);
  final app1 = app1Payload.toBytes();

  final jpeg = BytesBuilder()
    ..add([0xFF, 0xD8]) // SOI
    ..add([0xFF, 0xE1]) // APP1
    ..add([(app1.length + 2) >> 8, (app1.length + 2) & 0xFF])
    ..add(app1)
    ..add([0xFF, 0xD9]); // EOI
  return jpeg.toBytes();
}
