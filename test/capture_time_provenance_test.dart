import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/models/catch_media.dart';
import 'package:bragmat/models/photo_metadata_result.dart';
import 'package:bragmat/services/capture_time_provenance.dart';
import 'package:bragmat/services/media_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;

  const mfnrFixture = 'IMG_20260617_213201147_MFNR.jpg';
  const srFixture = 'photo_metadata_tests/IMG_20260618_212522448_SR.jpg';

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('provenance_');
    MediaStorageService.setTestDirectory(testDir);
    DatabaseHelper.setTestDatabasePath(path.join(testDir.path, 'b.db'));
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    MediaStorageService.clearTestDirectory();
    try {
      if (await testDir.exists()) await testDir.delete(recursive: true);
    } on PathAccessException {
      // Windows transient file locks; OS cleans temp dirs.
    }
  });

  PhotoMetadataResult exifResult(DateTime dt) => PhotoMetadataResult(
        dateTime: dt,
        hasTimezone: true,
        timezoneOffset: 9.5,
        dateTimeStatus: DateTimeStatus.valid,
        dateTimeSource: DateTimeSource.dateTimeOriginal,
        confidence: MetadataConfidence.exif,
        format: ImageFormat.jpeg,
      );

  group('CaptureTimeProvenanceService.classify', () {
    test('absent when no stored value', () {
      expect(
        CaptureTimeProvenanceService.classify(
          stored: null,
          metadata: exifResult(DateTime(2026, 6, 17, 21, 32, 1)),
        ),
        CaptureTimeProvenance.absent,
      );
    });

    test('exifVerified when stored matches EXIF capture time', () {
      expect(
        CaptureTimeProvenanceService.classify(
          stored: DateTime(2026, 6, 17, 21, 32, 1),
          metadata: exifResult(DateTime(2026, 6, 17, 21, 32, 1)),
        ),
        CaptureTimeProvenance.exifVerified,
      );
    });

    test('exifVerified tolerates sub-second stored components', () {
      expect(
        CaptureTimeProvenanceService.classify(
          stored: DateTime(2026, 6, 17, 21, 32, 1, 400),
          metadata: exifResult(DateTime(2026, 6, 17, 21, 32, 1)),
        ),
        CaptureTimeProvenance.exifVerified,
      );
    });

    test('conflict when stored differs from EXIF capture time', () {
      // Legacy attachment-time row: stored value is the attach moment,
      // not the capture time.
      expect(
        CaptureTimeProvenanceService.classify(
          stored: DateTime(2026, 6, 20, 9, 0),
          metadata: exifResult(DateTime(2026, 6, 17, 21, 32, 1)),
        ),
        CaptureTimeProvenance.conflict,
      );
    });

    test('unverifiable when photo has no EXIF capture time', () {
      const mtime = PhotoMetadataResult(
        dateTimeStatus: DateTimeStatus.valid,
        dateTimeSource: DateTimeSource.fileModification,
        confidence: MetadataConfidence.fileSystem,
      );
      expect(
        CaptureTimeProvenanceService.classify(
          stored: DateTime(2026, 6, 20, 9, 0),
          metadata: mtime,
        ),
        CaptureTimeProvenance.unverifiable,
      );
      expect(
        CaptureTimeProvenanceService.classify(
          stored: DateTime(2026, 6, 20, 9, 0),
          metadata: const PhotoMetadataResult(),
        ),
        CaptureTimeProvenance.unverifiable,
      );
    });
  });

  group('CaptureTimeProvenanceService.assess (stored photo re-extraction)',
      () {
    Future<CatchMedia> storeMedia(
      String fixture,
      DateTime? dateTaken,
    ) async {
      final storedPath = await MediaStorageService.copyPhotoToStorage(
        fixture,
        'catch',
        1,
        'primary',
      );
      expect(storedPath, isNotNull);
      return CatchMedia(
        catchId: 1,
        filePath: storedPath!,
        role: 'primary',
        dateTaken: dateTaken,
      );
    }

    test('verified for a media row carrying the true capture time', () async {
      final media = await storeMedia(
        mfnrFixture,
        DateTime(2026, 6, 17, 21, 32, 1),
      );
      expect(
        await CaptureTimeProvenanceService.assess(media),
        CaptureTimeProvenance.exifVerified,
      );
    });

    test('conflict for a legacy attachment-time value', () async {
      final media = await storeMedia(
        mfnrFixture,
        DateTime(2026, 10, 5, 14, 0), // attachment time, not capture time
      );
      expect(
        await CaptureTimeProvenanceService.assess(media),
        CaptureTimeProvenance.conflict,
      );
    });

    test('unverifiable for a GPS-only photo (no EXIF capture time)',
        () async {
      final media = await storeMedia(
        srFixture,
        DateTime(2026, 10, 5, 14, 0),
      );
      expect(
        await CaptureTimeProvenanceService.assess(media),
        CaptureTimeProvenance.unverifiable,
      );
    });

    test('absent when date_taken is null', () async {
      final media = await storeMedia(srFixture, null);
      expect(
        await CaptureTimeProvenanceService.assess(media),
        CaptureTimeProvenance.absent,
      );
    });

    test('unverifiable when the stored file is missing', () async {
      final media = CatchMedia(
        catchId: 1,
        filePath: 'catches/does_not_exist.jpg',
        dateTaken: DateTime(2026, 6, 17, 21, 32, 1),
      );
      expect(
        await CaptureTimeProvenanceService.assess(media),
        CaptureTimeProvenance.unverifiable,
      );
    });
  });
}
