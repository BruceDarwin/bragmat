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
import 'package:bragmat/models/catch_media.dart';
import 'package:bragmat/models/photo_metadata_result.dart';
import 'package:bragmat/screens/add_catch_screen.dart';
import 'package:bragmat/services/environmental_conditions_service.dart';
import 'package:bragmat/services/gallery_photo_picker.dart';
import 'package:bragmat/services/media_storage_service.dart';
import 'package:bragmat/services/photo_metadata_service.dart';

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

/// Controllable fake for the Android gallery-picker channel. Defaults to
/// `unsupported` so tests that don't configure it exercise the existing
/// image_picker fallback unchanged.
class FakeGalleryPicker extends GalleryPhotoPicker {
  GalleryPickOutcome nextOutcome =
      const GalleryPickOutcome(GalleryPickStatus.unsupported);
  RecoveredGalleryPick? pendingPick;
  int pickCalls = 0;
  String? lastContext;
  final List<String> acknowledged = [];

  @override
  Future<GalleryPickOutcome> pickFromGallery(
      {required String context}) async {
    pickCalls++;
    lastContext = context;
    return nextOutcome;
  }

  @override
  Future<RecoveredGalleryPick?> retrievePending() async => pendingPick;

  @override
  Future<void> acknowledgePending(String path) async {
    acknowledged.add(path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;
  late FakeImagePicker fakePicker;
  late FakeGalleryPicker fakeGallery;

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
    fakeGallery = FakeGalleryPicker();
    GalleryPhotoPicker.instance = fakeGallery;
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

  /// Seeds an existing catch with one stored photo on disk.
  Future<int> seedCatchWithPhoto(Directory dir) async {
    final stored = File(
        path.join(dir.path, 'bragmat', 'media', 'catches', 'existing.jpg'));
    await stored.parent.create(recursive: true);
    await File(mfnrFixture).copy(stored.path);
    final catchId = await DatabaseHelper.instance.insertCatch(model.Catch(
      lengthCm: 45,
      createdAt: DateTime(2026, 10, 1),
      dateCaught: DateTime(2026, 10, 1, 9, 45),
    ));
    await DatabaseHelper.instance.insertCatchMedia(CatchMedia(
      catchId: catchId,
      filePath: 'catches/existing.jpg',
      mediaType: 'photo',
      role: 'primary',
    ));
    return catchId;
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

    testWidgets('repeated lost-data delivery does not duplicate media',
        (tester) async {
      // Android can surface the same lost file again on a later
      // lifecycle resume (initState + resumed both call
      // retrieveLostData). The recovery path must dedupe.
      late final String recovered;
      await tester.runAsync(() async {
        recovered = await copyFixtureTo(mfnrFixture, testDir);
      });
      // The fake returns the same lost data on every call — matching a
      // platform that has not yet cleared its lost-data response.
      fakePicker.lostData =
          LostDataResponse(files: [XFile(recovered)]);

      final state = await pumpScreen(tester);
      expect(state.debugMediaItems, hasLength(1));
      expect(find.text('Photo Details Found'), findsOneWidget);
      // Dismiss the prompt so a second one would be distinguishable.
      await tester.tap(find.text('Keep current catch details'));
      await tester.pumpAndSettle();

      // Simulate a later resume redelivering the same file.
      await state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await flushRealAsync(tester);
      await tester.pumpAndSettle();

      expect(state.debugMediaItems, hasLength(1));
      expect(find.text('Photo Details Found'), findsNothing);
    });

    testWidgets('stored photo retains EXIF for later re-extraction',
        (tester) async {
      fakePicker.nextPick =
          XFile(mfnrFixture);

      final state = await pumpScreen(tester);
      await tapAddPhoto(tester);
      // Dismiss the auto-prompt.
      await tester.tap(find.text('Keep current catch details'));
      await tester.pumpAndSettle();

      final media = state.debugMediaItems.first as CatchMedia;
      late final PhotoMetadataResult reextracted;
      await tester.runAsync(() async {
        final resolved =
            await MediaStorageService.resolvePath(media.filePath);
        reextracted =
            await PhotoMetadataService.extractFromFile(resolved);
      });

      // The stored copy is byte-for-byte — capture time, offset and GPS
      // survive for re-extraction (explicit "Use photo details" relies
      // on this for historical photos).
      expect(reextracted.hasValidDateTime, isTrue);
      expect(reextracted.dateTime, DateTime(2026, 6, 17, 21, 32, 1));
      expect(reextracted.hasTimezone, isTrue);
      expect(reextracted.timezoneOffset, closeTo(9.5, 0.01));
      expect(reextracted.hasValidGps, isTrue);
      expect(reextracted.latitude, closeTo(-12.3767, 0.001));
    });

    testWidgets('date_taken and GPS survive the database round-trip',
        (tester) async {
      fakePicker.nextPick =
          XFile(mfnrFixture);

      final state = await pumpScreen(tester);
      await tapAddPhoto(tester);
      await tester.tap(find.text('Keep current catch details'));
      await tester.pumpAndSettle();

      final media = state.debugMediaItems.first as CatchMedia;
      late final List<CatchMedia> rows;
      await tester.runAsync(() async {
        final catchId =
            await DatabaseHelper.instance.insertCatch(model.Catch(
          lengthCm: 40,
          createdAt: DateTime(2026, 6, 17),
        ));
        await DatabaseHelper.instance
            .insertCatchMedia(media.copyWith(catchId: catchId));
        rows =
            await DatabaseHelper.instance.getMediaForCatch(catchId);
      });

      expect(rows, hasLength(1));
      // Wall-clock local time round-trips byte-exactly (ISO-8601 naive).
      expect(rows.first.dateTaken, DateTime(2026, 6, 17, 21, 32, 1));
      expect(rows.first.latitude, closeTo(-12.3767, 0.001));
      expect(rows.first.longitude, closeTo(130.8509, 0.001));
    });

    testWidgets('applying photo GPS to an existing catch still triggers '
        'the environmental recalculation prompt on save',
        (tester) async {
      fakePicker.nextPick =
          XFile(srFixture);

      // Seed a real catch row + environmental condition so the save
      // path has something to compare against.
      late final int catchId;
      await tester.runAsync(() async {
        catchId = await DatabaseHelper.instance.insertCatch(model.Catch(
          lengthCm: 45,
          createdAt: DateTime(2026, 10, 1),
          dateCaught: DateTime(2026, 10, 1, 9, 45),
          latitude: -33.8688,
          longitude: 151.2093,
          location: 'Sydney Harbour',
          coordinateSource: 'Device GPS',
        ));
        await EnvironmentalConditionsService()
            .saveEnvironmentalConditionForCatch(
          catchId,
          DateTime(2026, 10, 1, 9, 45),
          -33.8688,
          151.2093,
        );
      });

      final existing = model.Catch(
        id: catchId,
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

      // Explicit per-photo action → apply location only.
      await tester.tap(find.byWidgetPredicate((w) =>
          w is Icon && w.icon == Icons.info_outline && w.size == 16));
      await flushRealAsync(tester);
      await tester.pumpAndSettle();
      await selectOption(tester, 'Use photo location');
      await tester.tap(find.text('Apply selected details'));
      await tester.pumpAndSettle();

      // Save — the photo-applied location change must surface the
      // existing environmental recalculation safeguard.
      final save = find.text('Save Changes');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await flushRealAsync(tester);
      await tester.pumpAndSettle();

      expect(find.text('Recalculate Environmental Information'),
          findsOneWidget);

      // Keep existing env data — save proceeds and persists the
      // photo-supplied coordinates.
      await tester.tap(find.text('Keep existing information'));
      await flushRealAsync(tester);
      await tester.pumpAndSettle();

      late final model.Catch? saved;
      await tester.runAsync(() async {
        saved = await DatabaseHelper.instance.getCatch(catchId);
      });
      expect(saved, isNotNull);
      expect(saved!.latitude, closeTo(-12.3767, 0.001));
      expect(saved!.coordinateSource, 'photo_gps');
    });

    testWidgets('edit-mode lost-camera-data recovery attaches to the '
        'existing catch without auto-prompting', (tester) async {
      late final int catchId;
      late final String recovered;
      await tester.runAsync(() async {
        catchId = await seedCatchWithPhoto(testDir);
        recovered = await copyFixtureTo(srFixture, testDir);
      });
      fakePicker.lostData =
          LostDataResponse(files: [XFile(recovered)]);

      final state = await pumpScreen(tester,
          catchToEdit: model.Catch(
            id: catchId,
            lengthCm: 45,
            createdAt: DateTime(2026, 10, 1),
            dateCaught: DateTime(2026, 10, 1, 9, 45),
          ));

      // Existing photo + recovered photo; recovery ran during init.
      expect(state.debugMediaItems, hasLength(2));
      // Existing photo keeps the primary role; recovered is 'other'.
      expect(state.debugMediaItems.first.role, 'primary');
      expect(state.debugMediaItems.last.role, 'other');
      // Edit-mode attachments never auto-prompt — explicit action only.
      expect(find.text('Photo Details Found'), findsNothing);

      // Save persists the recovered media against the edited catch.
      final save = find.text('Save Changes');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await flushRealAsync(tester);
      await tester.pumpAndSettle();

      late final List<CatchMedia> rows;
      await tester.runAsync(() async {
        rows = await DatabaseHelper.instance.getMediaForCatch(catchId);
      });
      expect(rows, hasLength(2));
      expect(rows.map((m) => m.catchId), everyElement(catchId));
    });

    testWidgets('repeated lost-data delivery in edit mode does not '
        'duplicate media', (tester) async {
      late final int catchId;
      late final String recovered;
      await tester.runAsync(() async {
        catchId = await seedCatchWithPhoto(testDir);
        recovered = await copyFixtureTo(srFixture, testDir);
      });
      fakePicker.lostData =
          LostDataResponse(files: [XFile(recovered)]);

      final state = await pumpScreen(tester,
          catchToEdit: model.Catch(
            id: catchId,
            lengthCm: 45,
            createdAt: DateTime(2026, 10, 1),
            dateCaught: DateTime(2026, 10, 1, 9, 45),
          ));
      expect(state.debugMediaItems, hasLength(2));

      // Later resume redelivers the same file — dedupe holds.
      await state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await flushRealAsync(tester);
      await tester.pumpAndSettle();
      expect(state.debugMediaItems, hasLength(2));
    });

    testWidgets('recovered edit-mode photo coexists with a subsequent '
        'gallery pick', (tester) async {
      late final int catchId;
      late final String recovered;
      await tester.runAsync(() async {
        catchId = await seedCatchWithPhoto(testDir);
        recovered = await copyFixtureTo(srFixture, testDir);
      });
      fakePicker.lostData =
          LostDataResponse(files: [XFile(recovered)]);

      final state = await pumpScreen(tester,
          catchToEdit: model.Catch(
            id: catchId,
            lengthCm: 45,
            createdAt: DateTime(2026, 10, 1),
            dateCaught: DateTime(2026, 10, 1, 9, 45),
          ));
      expect(state.debugMediaItems, hasLength(2));

      // A later picker operation (which on Android clears the plugin's
      // lost-data cache) must leave recovered attachments intact.
      late final String picked;
      await tester.runAsync(() async {
        picked = await copyFixtureTo(mfnrFixture, testDir);
      });
      fakePicker.nextPick = XFile(picked);
      await tapAddPhoto(tester);

      expect(state.debugMediaItems, hasLength(3));
      expect(fakePicker.pickCalls, 1);
    });

    testWidgets('lost-data pointing at a missing file attaches nothing '
        'and does not crash', (tester) async {
      fakePicker.lostData = LostDataResponse(
          files: [XFile(path.join(testDir.path, 'does_not_exist.jpg'))]);

      final state = await pumpScreen(tester);
      await flushRealAsync(tester);
      await tester.pumpAndSettle();

      expect(state.debugMediaItems, isEmpty);
      expect(find.text('Photo Details Found'), findsNothing);
    });

    testWidgets('empty lost-data response is a no-op', (tester) async {
      fakePicker.lostData = LostDataResponse.empty();
      final state = await pumpScreen(tester);
      expect(state.debugMediaItems, isEmpty);
      expect(find.text('Photo Details Found'), findsNothing);
    });
  });

  group('Platform gallery picker channel', () {
    /// Writes a minimal valid PNG (no EXIF) — models a photo delivered
    /// after the user denied location-metadata consent.
    Future<File> writeNoExifPng(Directory dir) async {
      final f = File(path.join(dir.path, 'no_exif_gallery.png'));
      await f.writeAsBytes(const [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
        0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
        0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05,
        0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
        0xAE, 0x42, 0x60, 0x82,
      ]);
      return f;
    }

    testWidgets('consent-granted pick: GPS offered as independent '
        'suggestion, provenance photo_gps, record acknowledged',
        (tester) async {
      late final String picked;
      await tester.runAsync(() async {
        picked = await copyFixtureTo(srFixture, testDir);
      });
      fakeGallery.nextOutcome = GalleryPickOutcome(
          GalleryPickStatus.picked, path: picked, context: 'new');

      final state = await pumpScreen(tester);
      await tapAddPhoto(tester);

      // Channel used with the correct new-catch context.
      expect(fakeGallery.pickCalls, 1);
      expect(fakeGallery.lastContext, 'new');
      expect(state.debugMediaItems, hasLength(1));
      // Staged successfully -> recovery record acknowledged.
      expect(fakeGallery.acknowledged, [picked]);

      // GPS-only photo: location offered, explicit acceptance required.
      expect(find.text('Photo Details Found'), findsOneWidget);
      expect(find.text('Use photo location'), findsOneWidget);
      await selectOption(tester, 'Use photo location');
      await tester.tap(find.text('Apply selected details'));
      await tester.pumpAndSettle();

      expect(double.parse(state.debugLatitudeText),
          closeTo(-12.3767, 0.001));
      expect(state.debugCoordinateSource, 'photo_gps');
      // Camera-intent-style file has no capture datetime -> stays null.
      expect(state.debugMediaItems.first.dateTaken, isNull);
    });

    testWidgets('consent-denied pick (EXIF stripped): photo still '
        'attaches, no coordinates invented', (tester) async {
      late final File denied;
      await tester.runAsync(() async {
        denied = await writeNoExifPng(testDir);
      });
      fakeGallery.nextOutcome = GalleryPickOutcome(
          GalleryPickStatus.picked, path: denied.path, context: 'new');

      final state = await pumpScreen(tester);
      await tapAddPhoto(tester);

      expect(state.debugMediaItems, hasLength(1));
      expect(state.debugMediaItems.first.latitude, isNull);
      expect(state.debugMediaItems.first.dateTaken, isNull);
      expect(find.text('Photo Details Found'), findsNothing);
      expect(fakeGallery.acknowledged, [denied.path]);
    });

    testWidgets('picker cancellation attaches nothing', (tester) async {
      fakeGallery.nextOutcome =
          const GalleryPickOutcome(GalleryPickStatus.cancelled);

      final state = await pumpScreen(tester);
      await tapAddPhoto(tester);

      expect(fakeGallery.pickCalls, 1);
      expect(state.debugMediaItems, isEmpty);
      expect(find.text('Photo Details Found'), findsNothing);
    });

    testWidgets('unsupported platform falls back to image_picker flow',
        (tester) async {
      // fakeGallery defaults to 'unsupported'.
      late final String picked;
      await tester.runAsync(() async {
        picked = await copyFixtureTo(mfnrFixture, testDir);
      });
      fakePicker.nextPick = XFile(picked);

      final state = await pumpScreen(tester);
      await tapAddPhoto(tester);

      // Channel consulted first, image_picker used after unsupported.
      expect(fakeGallery.pickCalls, 1);
      expect(fakePicker.pickCalls, 1);
      expect(state.debugMediaItems, hasLength(1));
      expect(find.text('Photo Details Found'), findsOneWidget);
    });

    testWidgets('pending gallery pick recovers into matching new-catch '
        'context and is acknowledged once', (tester) async {
      late final String recovered;
      await tester.runAsync(() async {
        recovered = await copyFixtureTo(mfnrFixture, testDir);
      });
      fakeGallery.pendingPick =
          RecoveredGalleryPick(path: recovered, context: 'new');

      final state = await pumpScreen(tester);

      expect(state.debugMediaItems, hasLength(1));
      expect(fakeGallery.acknowledged, [recovered]);
      // First photo on a new catch still auto-prompts.
      expect(find.text('Photo Details Found'), findsOneWidget);

      // A later resume must not deliver it twice.
      await tester.tap(find.text('Keep current catch details'));
      await tester.pumpAndSettle();
      await state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await flushRealAsync(tester);
      await tester.pumpAndSettle();
      expect(state.debugMediaItems, hasLength(1));
    });

    testWidgets('pending edit-context pick attaches to that catch and '
        'not to a different one', (tester) async {
      late final int catchId;
      late final String recovered;
      await tester.runAsync(() async {
        catchId = await seedCatchWithPhoto(testDir);
        recovered = await copyFixtureTo(srFixture, testDir);
      });
      fakeGallery.pendingPick =
          RecoveredGalleryPick(path: recovered, context: 'edit:$catchId');

      final state = await pumpScreen(
          tester,
          catchToEdit: model.Catch(
            id: catchId,
            lengthCm: 45,
            createdAt: DateTime(2026, 10, 1),
            dateCaught: DateTime(2026, 10, 1, 9, 45),
          ));

      expect(state.debugMediaItems, hasLength(2));
      expect(state.debugMediaItems.last.role, 'other');
      expect(fakeGallery.acknowledged, [recovered]);
      expect(find.text('Photo Details Found'), findsNothing);
    });

    testWidgets('pending pick for a different catch is never attached '
        'and stays pending', (tester) async {
      late final String recovered;
      await tester.runAsync(() async {
        recovered = await copyFixtureTo(mfnrFixture, testDir);
      });
      // Recorded against catch 99 — this screen is a new catch.
      fakeGallery.pendingPick =
          RecoveredGalleryPick(path: recovered, context: 'edit:99');

      final state = await pumpScreen(tester);

      expect(state.debugMediaItems, isEmpty);
      expect(fakeGallery.acknowledged, isEmpty);
      expect(find.text('Photo Details Found'), findsNothing);

      // Surfaced through a pick attempt instead: still not attachable.
      fakeGallery.nextOutcome = GalleryPickOutcome(
          GalleryPickStatus.pending, path: recovered, context: 'edit:99');
      await tapAddPhoto(tester);
      expect(state.debugMediaItems, isEmpty);
      expect(fakeGallery.acknowledged, isEmpty);
    });

    testWidgets('pending delivery through the pick path attaches and '
        'acks when context matches', (tester) async {
      late final String recovered;
      await tester.runAsync(() async {
        recovered = await copyFixtureTo(srFixture, testDir);
      });
      fakeGallery.nextOutcome = GalleryPickOutcome(
          GalleryPickStatus.pending, path: recovered, context: 'new');

      final state = await pumpScreen(tester);
      await tapAddPhoto(tester);

      expect(state.debugMediaItems, hasLength(1));
      expect(fakeGallery.acknowledged, [recovered]);
    });

    testWidgets('pending record for a missing file is discarded '
        'without attaching', (tester) async {
      fakeGallery.pendingPick = RecoveredGalleryPick(
          path: path.join(testDir.path, 'gone.jpg'), context: 'new');

      final state = await pumpScreen(tester);

      expect(state.debugMediaItems, isEmpty);
      // Dead record is acknowledged/cleared — no infinite pending loop.
      expect(fakeGallery.acknowledged, hasLength(1));
    });

    testWidgets('recovered pick coexists with a subsequent gallery '
        'selection', (tester) async {
      late final String recovered;
      late final String picked;
      await tester.runAsync(() async {
        recovered = await copyFixtureTo(srFixture, testDir);
        picked = await copyFixtureTo(mfnrFixture, testDir);
      });
      fakeGallery.pendingPick =
          RecoveredGalleryPick(path: recovered, context: 'new');

      final state = await pumpScreen(tester);
      expect(state.debugMediaItems, hasLength(1));

      fakeGallery.nextOutcome = GalleryPickOutcome(
          GalleryPickStatus.picked, path: picked, context: 'new');
      // Dismiss the recovery auto-prompt first.
      await tester.tap(find.text('Keep current catch details'));
      await tester.pumpAndSettle();
      await tapAddPhoto(tester);

      expect(state.debugMediaItems, hasLength(2));
      expect(fakeGallery.acknowledged, [recovered, picked]);
    });
  });
}
