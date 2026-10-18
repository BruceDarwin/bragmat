import 'package:flutter_test/flutter_test.dart';

import 'package:bragmat/models/photo_metadata_result.dart';
import 'package:bragmat/services/photo_details_applier.dart';
import 'package:bragmat/models/photo_details_decision.dart';

void main() {
  PhotoMetadataResult fullMetadata() => PhotoMetadataResult(
        dateTime: DateTime(2026, 6, 17, 21, 32, 1),
        hasTimezone: true,
        timezoneOffset: 9.5,
        latitude: -12.3767,
        longitude: 130.8509,
        dateTimeStatus: DateTimeStatus.valid,
        gpsStatus: GpsStatus.valid,
        dateTimeSource: DateTimeSource.dateTimeOriginal,
        confidence: MetadataConfidence.exif,
        format: ImageFormat.jpeg,
      );

  group('PhotoDetailsApplier.buildUpdates', () {
    test('applies date, time and location together', () {
      final u = PhotoDetailsApplier.buildUpdates(
        metadata: fullMetadata(),
        decision: const PhotoDetailsDecision(
            useDate: true, useTime: true, useLocation: true),
        currentDateCaught: DateTime(2026, 10, 1, 9, 0),
      );

      expect(u.dateCaught, DateTime(2026, 6, 17, 21, 32));
      expect(u.latitude, -12.3767);
      expect(u.longitude, 130.8509);
      expect(u.coordinateSource, 'photo_gps');
      expect(u.clearFavouriteSpot, true);
      expect(u.isEmpty, false);
    });

    test('date only: photo date merged with existing time', () {
      final u = PhotoDetailsApplier.buildUpdates(
        metadata: fullMetadata(),
        decision: const PhotoDetailsDecision(useDate: true),
        currentDateCaught: DateTime(2026, 10, 1, 9, 45),
      );

      expect(u.dateCaught, DateTime(2026, 6, 17, 9, 45));
      expect(u.latitude, isNull);
      expect(u.coordinateSource, isNull);
      expect(u.clearFavouriteSpot, false);
    });

    test('time only: photo time merged with existing date', () {
      final u = PhotoDetailsApplier.buildUpdates(
        metadata: fullMetadata(),
        decision: const PhotoDetailsDecision(useTime: true),
        currentDateCaught: DateTime(2026, 10, 1, 9, 45),
      );

      expect(u.dateCaught, DateTime(2026, 10, 1, 21, 32));
      expect(u.latitude, isNull);
    });

    test('location only: coordinates + photo_gps source, no datetime', () {
      final u = PhotoDetailsApplier.buildUpdates(
        metadata: fullMetadata(),
        decision: const PhotoDetailsDecision(useLocation: true),
        currentDateCaught: DateTime(2026, 10, 1, 9, 45),
      );

      expect(u.dateCaught, isNull);
      expect(u.latitude, -12.3767);
      expect(u.longitude, 130.8509);
      expect(u.coordinateSource, 'photo_gps');
    });

    test('no selections -> empty updates, nothing changes', () {
      final u = PhotoDetailsApplier.buildUpdates(
        metadata: fullMetadata(),
        decision: const PhotoDetailsDecision(),
        currentDateCaught: DateTime(2026, 10, 1, 9, 45),
      );
      expect(u.isEmpty, true);
    });

    test('invalid GPS can never be applied even if requested', () {
      for (final status in [
        GpsStatus.rejected,
        GpsStatus.malformed,
        GpsStatus.incomplete
      ]) {
        final u = PhotoDetailsApplier.buildUpdates(
          metadata: fullMetadata().copyWith(gpsStatus: status),
          decision: const PhotoDetailsDecision(useLocation: true),
          currentDateCaught: DateTime(2026, 10, 1, 9, 45),
        );
        expect(u.latitude, isNull, reason: 'status: $status');
        expect(u.coordinateSource, isNull, reason: 'status: $status');
      }
    });

    test('absent GPS -> no location applied', () {
      final u = PhotoDetailsApplier.buildUpdates(
        metadata: PhotoMetadataResult(
          dateTime: DateTime(2026, 6, 17, 21, 32),
          dateTimeStatus: DateTimeStatus.valid,
          dateTimeSource: DateTimeSource.dateTimeOriginal,
          gpsStatus: GpsStatus.absent,
          confidence: MetadataConfidence.exif,
        ),
        decision: const PhotoDetailsDecision(useLocation: true),
        currentDateCaught: DateTime(2026, 10, 1, 9, 45),
      );
      expect(u.latitude, isNull);
      expect(u.coordinateSource, isNull);
    });

    test('invalid datetime can never be applied even if requested', () {
      for (final status in [
        DateTimeStatus.malformed,
        DateTimeStatus.rejected
      ]) {
        final u = PhotoDetailsApplier.buildUpdates(
          metadata: fullMetadata().copyWith(dateTimeStatus: status),
          decision: const PhotoDetailsDecision(useDate: true, useTime: true),
          currentDateCaught: DateTime(2026, 10, 1, 9, 45),
        );
        expect(u.dateCaught, isNull, reason: 'status: $status');
      }
    });

    test('file-modification datetime is applied when user selects it', () {
      final mtime = DateTime(2024, 5, 6, 7, 8, 9);
      final u = PhotoDetailsApplier.buildUpdates(
        metadata: fullMetadata().copyWith(
          dateTime: mtime,
          hasTimezone: false,
          timezoneOffset: null,
          dateTimeSource: DateTimeSource.fileModification,
          confidence: MetadataConfidence.fileSystem,
        ),
        decision: const PhotoDetailsDecision(useDate: true, useTime: true),
        currentDateCaught: DateTime(2026, 10, 1, 9, 45),
      );
      // Applied at catch granularity (minute precision).
      expect(u.dateCaught, DateTime(2024, 5, 6, 7, 8));
    });

    test('no current catch value -> merges onto "now" for partial selects',
        () {
      final u = PhotoDetailsApplier.buildUpdates(
        metadata: fullMetadata(),
        decision: const PhotoDetailsDecision(useDate: true),
        currentDateCaught: null,
      );
      // Photo date with current time-of-day.
      expect(u.dateCaught!.year, 2026);
      expect(u.dateCaught!.month, 6);
      expect(u.dateCaught!.day, 17);
    });
  });

  group('PhotoDetailsApplier.shouldAutoPrompt', () {
    test('first photo in add mode with metadata -> prompt', () {
      expect(
        PhotoDetailsApplier.shouldAutoPrompt(
          metadata: fullMetadata(),
          isFirstPhoto: true,
          isEditMode: false,
        ),
        true,
      );
    });

    test('subsequent photos never auto-prompt', () {
      expect(
        PhotoDetailsApplier.shouldAutoPrompt(
          metadata: fullMetadata(),
          isFirstPhoto: false,
          isEditMode: false,
        ),
        false,
      );
    });

    test('edit mode never auto-prompts even for first new photo', () {
      expect(
        PhotoDetailsApplier.shouldAutoPrompt(
          metadata: fullMetadata(),
          isFirstPhoto: true,
          isEditMode: true,
        ),
        false,
      );
      expect(
        PhotoDetailsApplier.shouldAutoPrompt(
          metadata: fullMetadata(),
          isFirstPhoto: false,
          isEditMode: true,
        ),
        false,
      );
    });

    test('photo without metadata does not prompt', () {
      expect(
        PhotoDetailsApplier.shouldAutoPrompt(
          metadata: const PhotoMetadataResult(),
          isFirstPhoto: true,
          isEditMode: false,
        ),
        false,
      );
    });

    test('file-mtime-only metadata does not auto-prompt', () {
      // A photo whose only signal is the filesystem modification time is
      // not "useful metadata" — the low-confidence suggestion stays
      // available through the explicit action, but attaching such a photo
      // must not interrupt the user.
      expect(
        PhotoDetailsApplier.shouldAutoPrompt(
          metadata: PhotoMetadataResult(
            dateTime: DateTime(2024, 5, 6, 7, 8),
            dateTimeStatus: DateTimeStatus.valid,
            dateTimeSource: DateTimeSource.fileModification,
            confidence: MetadataConfidence.fileSystem,
          ),
          isFirstPhoto: true,
          isEditMode: false,
        ),
        false,
      );
    });

    test('EXIF datetime without GPS still auto-prompts', () {
      expect(
        PhotoDetailsApplier.shouldAutoPrompt(
          metadata: PhotoMetadataResult(
            dateTime: DateTime(2026, 6, 17, 21, 32),
            dateTimeStatus: DateTimeStatus.valid,
            dateTimeSource: DateTimeSource.dateTimeOriginal,
          ),
          isFirstPhoto: true,
          isEditMode: false,
        ),
        true,
      );
    });
  });
}
