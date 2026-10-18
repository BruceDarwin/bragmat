import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bragmat/models/photo_metadata_result.dart';
import 'package:bragmat/models/photo_details_decision.dart';
import 'package:bragmat/widgets/photo_details_dialog.dart';

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

  Future<PhotoDetailsDecision?>? pendingResult;

  /// Pumps a host button and taps it to open the dialog. The dialog's
  /// return value is captured in [pendingResult] once it pops.
  Future<void> openDialog(
    WidgetTester tester,
    PhotoMetadataResult metadata, {
    DateTime? currentDateCaught,
    bool authoritative = false,
    double? currentLatitude,
    double? currentLongitude,
    String? currentLocationName,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () {
              pendingResult = showDialog<PhotoDetailsDecision>(
                context: context,
                builder: (_) => PhotoDetailsFoundDialog(
                  metadata: metadata,
                  currentDateCaught: currentDateCaught,
                  currentDateTimeAuthoritative: authoritative,
                  currentLatitude: currentLatitude,
                  currentLongitude: currentLongitude,
                  currentLocationName: currentLocationName,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<PhotoDetailsDecision?> readResult() => pendingResult!;

  testWidgets('shows photo date, time, timezone and location', (tester) async {
    await openDialog(tester, fullMetadata());

    expect(find.text('Photo Details Found'), findsOneWidget);
    expect(find.textContaining('17/6/2026'), findsWidgets);
    expect(find.textContaining('21:32'), findsWidgets);
    expect(find.textContaining('UTC+09:30'), findsOneWidget);
    expect(find.textContaining('-12.376700, 130.850900'), findsWidgets);
    expect(find.text('Use photo date (17/6/2026)'), findsOneWidget);
    expect(find.text('Use photo time (21:32)'), findsOneWidget);
    expect(find.text('Use photo location'), findsOneWidget);
  });

  testWidgets('warns when photo has no timezone information', (tester) async {
    await openDialog(
        tester,
        fullMetadata().copyWith(hasTimezone: false, timezoneOffset: null));

    expect(
      find.textContaining('does not include timezone information'),
      findsOneWidget,
    );
  });

  testWidgets('file-modification date carries the low-confidence label',
      (tester) async {
    await openDialog(
      tester,
      PhotoMetadataResult(
        dateTime: DateTime(2024, 5, 6, 7, 8, 9),
        dateTimeStatus: DateTimeStatus.valid,
        dateTimeSource: DateTimeSource.fileModification,
        confidence: MetadataConfidence.fileSystem,
      ),
    );

    expect(
      find.textContaining('this may not be when the photo was taken'),
      findsOneWidget,
    );
  });

  testWidgets('invalid GPS is explained but never offered', (tester) async {
    await openDialog(
      tester,
      fullMetadata().copyWith(gpsStatus: GpsStatus.rejected),
    );

    expect(find.textContaining('location could not be used'), findsOneWidget);
    expect(find.textContaining('invalid coordinates'), findsOneWidget);
    // Only date/time checkboxes are offered.
    expect(find.text('Use photo location'), findsNothing);
    expect(find.text('Use photo date (17/6/2026)'), findsOneWidget);
  });

  testWidgets('incomplete GPS is explained but never offered', (tester) async {
    await openDialog(
      tester,
      fullMetadata().copyWith(gpsStatus: GpsStatus.incomplete),
    );

    expect(find.textContaining('incomplete data'), findsOneWidget);
    expect(find.text('Use photo location'), findsNothing);
  });

  testWidgets('malformed date is explained, no date/time offered',
      (tester) async {
    await openDialog(
      tester,
      fullMetadata().copyWith(dateTimeStatus: DateTimeStatus.malformed),
    );

    expect(
        find.textContaining('date and time could not be read'), findsOneWidget);
    expect(find.textContaining('Use photo date'), findsNothing);
    // Location still offerable independently.
    expect(find.text('Use photo location'), findsOneWidget);
  });

  testWidgets('conflict line shown for authoritative existing values',
      (tester) async {
    await openDialog(
      tester,
      fullMetadata(),
      currentDateCaught: DateTime(2026, 10, 1, 9, 45),
      authoritative: true,
      currentLatitude: -12.45,
      currentLongitude: 130.8,
      currentLocationName: 'Darwin Harbour',
    );

    expect(find.textContaining('Current: 1/10/2026 09:45'), findsOneWidget);
    expect(find.textContaining('Darwin Harbour'), findsOneWidget);
  });

  testWidgets('no conflict line for untouched default date/time',
      (tester) async {
    await openDialog(
      tester,
      fullMetadata(),
      currentDateCaught: DateTime(2026, 10, 1, 9, 45),
      authoritative: false,
    );

    expect(find.textContaining('Current: 1/10/2026'), findsNothing);
    // The photo value itself is still shown.
    expect(find.textContaining('17/6/2026'), findsWidgets);
  });

  testWidgets('apply returns independent field selections', (tester) async {
    await openDialog(tester, fullMetadata());

    // Select date + location only.
    await tester.tap(find.text('Use photo date (17/6/2026)'));
    await tester.pump();
    await tester.tap(find.text('Use photo location'));
    await tester.pump();
    await tester.tap(find.text('Apply selected details'));
    await tester.pumpAndSettle();

    final result = await readResult();
    expect(result, isNotNull);
    expect(result!.useDate, true);
    expect(result.useTime, false);
    expect(result.useLocation, true);
  });

  testWidgets('keep current details returns null (cancel)', (tester) async {
    await openDialog(tester, fullMetadata());

    await tester.tap(find.text('Keep current catch details'));
    await tester.pumpAndSettle();

    expect(await readResult(), isNull);
  });

  testWidgets('apply disabled until at least one field is selected',
      (tester) async {
    await openDialog(tester, fullMetadata());

    ElevatedButton applyBtn() => tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Apply selected details'));

    expect(applyBtn().onPressed, isNull);

    await tester.tap(find.text('Use photo time (21:32)'));
    await tester.pump();
    expect(applyBtn().onPressed, isNotNull);
  });

  testWidgets('no metadata -> explanation and OK only, returns null',
      (tester) async {
    await openDialog(tester, const PhotoMetadataResult());

    expect(
      find.textContaining(
          'No date, time or location details were found in this photo'),
      findsOneWidget,
    );
    expect(find.text('Apply selected details'), findsNothing);
    expect(find.text('OK'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(await readResult(), isNull);
  });

  testWidgets('unchecking a selected field removes it from the decision',
      (tester) async {
    await openDialog(tester, fullMetadata());

    await tester.tap(find.text('Use photo location'));
    await tester.pump();
    await tester.tap(find.text('Use photo location')); // uncheck
    await tester.pump();

    await tester.tap(find.text('Use photo date (17/6/2026)'));
    await tester.pump();
    await tester.tap(find.text('Apply selected details'));
    await tester.pumpAndSettle();

    final result = await readResult();
    expect(result!.useLocation, false);
    expect(result.useDate, true);
  });
}
