import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as path;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/models/catch.dart' as model;
import 'package:bragmat/screens/add_catch_screen.dart';
import 'package:bragmat/services/media_storage_service.dart';

/// Controllable ImagePicker platform fake.
class FakeImagePicker extends ImagePickerPlatform
    with MockPlatformInterfaceMixin {
  XFile? nextPick;
  LostDataResponse lostData = LostDataResponse.empty();
  int pickCalls = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    pickCalls++;
    return nextPick;
  }

  @override
  Future<LostDataResponse> getLostData() async => lostData;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;
  late FakeImagePicker fakePicker;

  // Real Moto G15 fixtures checked into the repo:
  //  - MFNR (repo root): full EXIF (DateTimeOriginal +09:30,
  //    GPS -12.3767, 130.8509)
  //  - SR (photo_metadata_tests/): GPS only, no EXIF datetime
  const mfnrFixture = 'IMG_20260617_213201147_MFNR.jpg';
  const srFixture = 'photo_metadata_tests/IMG_20260618_212522448_SR.jpg';

  Future<String> copyFixtureTo(String fixturePath, Directory dir) async {
    final dest = File(path.join(dir.path, path.basename(fixturePath)));
    await File(fixturePath).copy(dest.path);
    return dest.path;
  }

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('add_catch_meta_');
    DatabaseHelper.setTestDatabasePath(path.join(testDir.path, 'bragmat.db'));
    MediaStorageService.setTestDirectory(testDir);
    SharedPreferences.setMockInitialValues({});
    fakePicker = FakeImagePicker();
    ImagePickerPlatform.instance = fakePicker;
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    MediaStorageService.clearTestDirectory();
    try {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    } on PathAccessException {
      // Windows can hold transient file locks (sqlite/image decoders);
      // temp dirs are cleaned by the OS anyway.
    }
  });

  /// Widget tests run in a fake-async zone that does not service real
  /// dart:io futures (DB reads, EXIF reads, file copies). [runAsync]
  /// escapes the zone, but only completes one pending real-I/O "hop" per
  /// call — the pick pipeline chains several (extract → mkdir → copy →
  /// size verify → attach → prompt), so iterate generously.
  Future<void> flushRealAsync(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
  }

  Future<dynamic> pumpScreen(WidgetTester tester,
      {model.Catch? catchToEdit}) async {
    await tester.pumpWidget(MaterialApp(
      home: AddCatchScreen(catchToEdit: catchToEdit),
    ));
    await flushRealAsync(tester);
    await tester.pumpAndSettle();
    return tester.state(find.byType(AddCatchScreen)) as dynamic;
  }

  Future<void> tapAddPhoto(WidgetTester tester) async {
    final button = find.text('Add Photo');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await flushRealAsync(tester);
    await tester.pumpAndSettle();
  }

  /// Taps a dialog checkbox row, then pumps so the Apply button's
  /// enabled state rebuilds before it is tapped.
  Future<void> selectOption(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pump();
  }

  group('Add Catch photo metadata workflow', () {
    testWidgets('first photo with full EXIF auto-prompts; apply sets '
        'date, time, coords and photo_gps source', (tester) async {
      fakePicker.nextPick =
          XFile(mfnrFixture);

      final state = await pumpScreen(tester);
      await tapAddPhoto(tester);

      // Dialog appeared automatically for the first photo.
      expect(find.text('Photo Details Found'), findsOneWidget);
      expect(find.text('Use photo location'), findsOneWidget);

      // Accept everything.
      await selectOption(tester, 'Use photo date (17/6/2026)');
      await selectOption(tester, 'Use photo time (21:32)');
      await selectOption(tester, 'Use photo location');
      await tester.tap(find.text('Apply selected details'));
      await tester.pumpAndSettle();

      expect(state.debugDateCaught, DateTime(2026, 6, 17, 21, 32));
      expect(double.parse(state.debugLatitudeText),
          closeTo(-12.3767, 0.001));
      expect(double.parse(state.debugLongitudeText),
          closeTo(130.8509, 0.001));
      expect(state.debugCoordinateSource, 'photo_gps');

      // catch_media row carries the real capture time and GPS.
      expect(state.debugMediaItems, hasLength(1));
      final media = state.debugMediaItems.first;
      expect(media.dateTaken, DateTime(2026, 6, 17, 21, 32, 1));
      expect(media.latitude, closeTo(-12.3767, 0.001));
      expect(media.longitude, closeTo(130.8509, 0.001));
    });

    testWidgets('subsequent photos attach without another prompt',
        (tester) async {
      fakePicker.nextPick =
          XFile(mfnrFixture);

      final state = await pumpScreen(tester);

      await tapAddPhoto(tester);
      expect(find.text('Photo Details Found'), findsOneWidget);
      // Cancel the first prompt — no fields applied.
      await tester.tap(find.text('Keep current catch details'));
      await tester.pumpAndSettle();
      expect(state.debugLatitudeText, isEmpty);

      // Second photo: attaches silently, no prompt.
      await tapAddPhoto(tester);
      expect(find.text('Photo Details Found'), findsNothing);
      expect(state.debugMediaItems, hasLength(2));
      // And nothing was silently applied.
      expect(state.debugLatitudeText, isEmpty);
    });

    testWidgets('picker cancellation attaches nothing and prompts nothing',
        (tester) async {
      fakePicker.nextPick = null;

      final state = await pumpScreen(tester);
      await tapAddPhoto(tester);

      expect(fakePicker.pickCalls, 1);
      expect(state.debugMediaItems, isEmpty);
      expect(find.text('Photo Details Found'), findsNothing);
    });

    testWidgets('photo without EXIF attaches silently with null date_taken',
        (tester) async {
      // A valid image with no EXIF -> extraction yields "absent", attach
      // proceeds. (1x1 transparent PNG — decodes cleanly so the thumbnail
      // does not stall the frame pump.) File writes need the real event
      // loop, hence runAsync.
      final bogus = File(path.join(testDir.path, 'no_exif.png'));
      await tester.runAsync(() => bogus.writeAsBytes(const [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
        0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT
        0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05,
        0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND
        0xAE, 0x42, 0x60, 0x82,
      ]));
      fakePicker.nextPick = XFile(bogus.path);

      final state = await pumpScreen(tester);
      await tapAddPhoto(tester);

      expect(state.debugMediaItems, hasLength(1));
      expect(state.debugMediaItems.first.dateTaken, isNull);
      expect(state.debugMediaItems.first.latitude, isNull);
      expect(find.text('Photo Details Found'), findsNothing);
    });

    testWidgets('GPS-only photo prompts; date offered only as '
        'low-confidence file-mtime; date_taken stays null', (tester) async {
      fakePicker.nextPick =
          XFile(srFixture);

      final state = await pumpScreen(tester);
      await tapAddPhoto(tester);

      expect(find.text('Photo Details Found'), findsOneWidget);
      expect(find.text('Use photo location'), findsOneWidget);
      // No EXIF datetime -> the only date/time offer is the filesystem
      // mtime fallback, clearly labelled as low-confidence.
      expect(
        find.textContaining('this may not be when the photo was taken'),
        findsOneWidget,
      );

      await selectOption(tester, 'Use photo location');
      await tester.tap(find.text('Apply selected details'));
      await tester.pumpAndSettle();

      expect(double.parse(state.debugLatitudeText),
          closeTo(-12.3767, 0.001));
      expect(state.debugCoordinateSource, 'photo_gps');
      // Default date/time is untouched.
      expect(state.debugDateTimeEditedByUser, isFalse);
      // No EXIF capture time -> date_taken must NOT be attachment time.
      expect(state.debugMediaItems.first.dateTaken, isNull);
      expect(state.debugMediaItems.first.latitude, isNotNull);
    });

    testWidgets('edit mode: attaching a photo never auto-prompts and '
        'never silently modifies existing values', (tester) async {
      fakePicker.nextPick =
          XFile(mfnrFixture);

      final existing = model.Catch(
        id: 7,
        lengthCm: 45,
        createdAt: DateTime(2026, 10, 1),
        dateCaught: DateTime(2026, 10, 1, 9, 45),
        latitude: -33.8688,
        longitude: 151.2093,
        location: 'Sydney Harbour',
        coordinateSource: 'Device GPS',
      );

      final state = await pumpScreen(tester, catchToEdit: existing);
      await tapAddPhoto(tester);

      expect(state.debugMediaItems, hasLength(1));
      expect(find.text('Photo Details Found'), findsNothing);
      // Nothing silently changed.
      expect(state.debugDateCaught, DateTime(2026, 10, 1, 9, 45));
      expect(state.debugLatitudeText, '-33.8688');
      expect(state.debugLongitudeText, '151.2093');
      expect(state.debugCoordinateSource, 'Device GPS');
      // Media row still records the photo's true capture time.
      expect(state.debugMediaItems.first.dateTaken,
          DateTime(2026, 6, 17, 21, 32, 1));
    });

    testWidgets('edit mode: explicit Use Photo Details shows conflicts '
        'and applies only confirmed fields', (tester) async {
      fakePicker.nextPick =
          XFile(srFixture);

      final existing = model.Catch(
        id: 7,
        lengthCm: 45,
        createdAt: DateTime(2026, 10, 1),
        dateCaught: DateTime(2026, 10, 1, 9, 45),
        latitude: -33.8688,
        longitude: 151.2093,
        location: 'Sydney Harbour',
        coordinateSource: 'Device GPS',
      );

      final state = await pumpScreen(tester, catchToEdit: existing);
      await tapAddPhoto(tester);
      expect(state.debugMediaItems, hasLength(1));

      // Explicit per-photo action — the thumbnail's small white info
      // icon (a second, grey info icon exists elsewhere on the screen).
      await tester.tap(find.byWidgetPredicate((w) =>
          w is Icon && w.icon == Icons.info_outline && w.size == 16));
      await flushRealAsync(tester);
      await tester.pumpAndSettle();

      expect(find.text('Photo Details Found'), findsOneWidget);
      // Conflict line shows existing coordinates + name (the form field
      // and its hint text also contain the name, so match the specific
      // dialog conflict text).
      expect(
        find.textContaining('Current: -33.868800, 151.209300 (Sydney Harbour)'),
        findsOneWidget,
      );

      await selectOption(tester, 'Use photo location');
      await tester.tap(find.text('Apply selected details'));
      await tester.pumpAndSettle();

      expect(double.parse(state.debugLatitudeText),
          closeTo(-12.3767, 0.001));
      expect(state.debugCoordinateSource, 'photo_gps');
      // Catch date/time unchanged (photo time not selected).
      expect(state.debugDateCaught, DateTime(2026, 10, 1, 9, 45));
    });

    testWidgets('lost-camera-data recovery attaches the photo and prompts '
        'safely after build', (tester) async {
      // File copy needs the real event loop (fake-async zone otherwise).
      late final String recovered;
      await tester.runAsync(() async {
        recovered = await copyFixtureTo(mfnrFixture, testDir);
      });
      fakePicker.lostData =
          LostDataResponse(files: [XFile(recovered)]);

      final state = await pumpScreen(tester);

      // Photo was recovered and attached.
      expect(state.debugMediaItems, hasLength(1));
      expect(state.debugMediaItems.first.dateTaken,
          DateTime(2026, 6, 17, 21, 32, 1));
      // Deferred prompt appeared without lifecycle errors.
      expect(find.text('Photo Details Found'), findsOneWidget);
    });
  });
}
