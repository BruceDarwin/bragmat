// Cross-feature regression tests: photo-GPS metadata acceptance
// interacting with tide-reference selection and environmental
// recalculation in AddCatchScreen (edit mode).
//
// Scenario A — Automatic tide reference + accepted photo GPS:
//   catch coordinates change, recalculation is offered, the tide
//   request uses the NEW catch coordinates and 'automatic' mode is
//   retained.
// Scenario B — Fixed tide reference + accepted photo GPS:
//   catch coordinates change but the recorded reference and its
//   request coordinates are not silently replaced by the photo
//   location; includes a discontinued reference reconstructed from
//   recorded request coordinates.
// Scenario C — Declined / failed / cancelled recalculation:
//   recorded environmental values, catch state and the recorded
//   reference are preserved.
//
// Fake services + pickers are injected so no network or platform
// channel is touched.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/models/backup_manifest.dart';
import 'package:bragmat/models/catch.dart' as model;
import 'package:bragmat/models/environmental_condition.dart';
import 'package:bragmat/screens/add_catch_screen.dart';
import 'package:bragmat/services/environmental_conditions_service.dart';
import 'package:bragmat/services/gallery_photo_picker.dart';
import 'package:bragmat/services/media_storage_service.dart';
import 'package:bragmat/services/weather_service.dart';
import 'package:bragmat/services/worldtides_service.dart';
import 'package:bragmat/services/zip_backup_service.dart';

/// Controllable ImagePicker platform fake (fallback gallery path).
class FakeImagePicker extends ImagePickerPlatform
    with MockPlatformInterfaceMixin {
  XFile? nextPick;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      nextPick;

  @override
  Future<LostDataResponse> getLostData() async => LostDataResponse.empty();
}

/// Gallery-channel fake — 'unsupported' so picks fall back to
/// image_picker, as on non-Android platforms.
class FakeGalleryPicker extends GalleryPhotoPicker {
  @override
  Future<GalleryPickOutcome> pickFromGallery({required String context}) async =>
      const GalleryPickOutcome(GalleryPickStatus.unsupported);

  @override
  Future<RecoveredGalleryPick?> retrievePending() async => null;

  @override
  Future<String?> takeInterruptedPick() async => null;

  @override
  Future<void> acknowledgePending(String path) async {}
}

/// Deterministic WorldTides fake — no network, records requests.
class _FakeWorldTidesService implements WorldTidesService {
  bool available = true;
  Map<String, dynamic>? nextContext;
  int fetchCount = 0;
  double? lastLat;
  double? lastLon;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Map<String, dynamic>?> getTideContextForLocation(
    double latitude,
    double longitude,
    DateTime observationTime,
  ) async {
    fetchCount++;
    lastLat = latitude;
    lastLon = longitude;
    return nextContext;
  }
}

class _FakeWeatherService implements WeatherService {
  @override
  Future<WeatherData?> fetchWeather(
          double latitude, double longitude, DateTime dateTime) async =>
      null;

  @override
  String windDirectionToCompass(double? degrees) => 'N';
}

Map<String, dynamic> _tideContext({
  required String station,
  required String phrase,
  double responseLat = -12.4667,
  double responseLon = 130.85,
}) =>
    {
      'tideStationName': station,
      'worldtidesAtlas': 'Australia',
      'worldtidesResponseLat': responseLat,
      'worldtidesResponseLon': responseLon,
      'referenceTideEventType': 'High',
      'referenceTideEventTime': DateTime(2026, 8, 2, 13, 0),
      'referenceTideEventHeight': 6.5,
      'tideContextPhrase': phrase,
      'tideContextDataSource': 'WorldTides',
      'tideContextConfidence': 'High',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Real Moto G15 fixture: full EXIF, GPS -12.3767, 130.8509.
  const mfnrFixture = 'IMG_20260617_213201147_MFNR.jpg';
  const photoLat = -12.3767;
  const photoLon = 130.8509;

  const oldLat = -33.8688;
  const oldLon = 151.2093;

  late Directory testDir;
  late FakeImagePicker fakePicker;
  late _FakeWorldTidesService tides;
  final service = EnvironmentalConditionsService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testDir = Directory.systemTemp.createTempSync('tide_photo_x_');
    DatabaseHelper.setTestDatabasePath(p.join(testDir.path, 'bragmat.db'));
    MediaStorageService.setTestDirectory(testDir);
    fakePicker = FakeImagePicker();
    ImagePickerPlatform.instance = fakePicker;
    GalleryPhotoPicker.instance = FakeGalleryPicker();
    tides = _FakeWorldTidesService();
    service.worldTidesService = tides;
    service.weatherService = _FakeWeatherService();
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
      // Windows can hold transient file locks; temp dirs are cleaned
      // by the OS anyway.
    }
  });

  // NOTE: test-body DB calls must run inside tester.runAsync — sqflite's
  // I/O never completes in the widget test's fake-async zone.

  Future<void> flushRealAsync(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
  }

  Future<dynamic> pumpEditScreen(
      WidgetTester tester, model.Catch catchToEdit) async {
    await tester.pumpWidget(MaterialApp(
      home: AddCatchScreen(catchToEdit: catchToEdit),
    ));
    await flushRealAsync(tester);
    await tester.pumpAndSettle();
    return tester.state(find.byType(AddCatchScreen)) as dynamic;
  }

  /// Seed a catch at the "old" coordinates plus an environmental
  /// condition row in the requested tide-reference mode.
  Future<model.Catch> seedCatch(
    WidgetTester tester, {
    required String tideMode,
    String? tideName,
    double? requestLat,
    double? requestLon,
    String? phrase,
    String? station,
  }) async {
    late final int id;
    await tester.runAsync(() async {
      final db = await DatabaseHelper.instance.database;
      id = await db.insert(
          'catches',
          model.Catch(
            lengthCm: 45,
            createdAt: DateTime(2026, 10, 1),
            dateCaught: DateTime(2026, 10, 1, 9, 45),
            latitude: oldLat,
            longitude: oldLon,
            location: 'Sydney Harbour',
            coordinateSource: 'Device GPS',
          ).toMap());
      await db.insert('environmental_conditions', {
        'catch_id': id,
        'observation_date_time': '2026-10-01T09:45:00.000',
        'latitude': oldLat,
        'longitude': oldLon,
        'tide_reference_mode': tideMode,
        'tide_reference_name': tideName,
        'tide_request_lat': requestLat,
        'tide_request_lon': requestLon,
        'worldtides_station': station,
        'tide_context_phrase': phrase,
        'tide_context_data_source': 'WorldTides',
        'created_at': '2026-10-01T09:45:00.000',
        'updated_at': '2026-10-01T09:45:00.000',
      });
    });
    return model.Catch(
      id: id,
      lengthCm: 45,
      createdAt: DateTime(2026, 10, 1),
      dateCaught: DateTime(2026, 10, 1, 9, 45),
      latitude: oldLat,
      longitude: oldLon,
      location: 'Sydney Harbour',
      coordinateSource: 'Device GPS',
    );
  }

  Future<EnvironmentalCondition?> conditionRow(
          WidgetTester tester, int catchId) async =>
      tester.runAsync<EnvironmentalCondition?>(() =>
          EnvironmentalConditionsService()
              .getEnvironmentalConditionForCatch(catchId));

  Future<Map<String, Object?>> catchRow(
          WidgetTester tester, int catchId) async =>
      (await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        final rows =
            await db.query('catches', where: 'id = ?', whereArgs: [catchId]);
        return rows.single;
      }))!;

  /// Attach the GPS-bearing fixture and explicitly accept its location.
  Future<void> attachPhotoAndAcceptLocation(WidgetTester tester) async {
    fakePicker.nextPick = XFile(mfnrFixture);
    final button = find.text('Add Photo');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await flushRealAsync(tester);
    await tester.pumpAndSettle();

    // The first photo may auto-prompt; otherwise use the per-photo
    // metadata action.
    if (find.text('Photo Details Found').evaluate().isEmpty) {
      await tester.tap(find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.info_outline && w.size == 16));
      await flushRealAsync(tester);
      await tester.pumpAndSettle();
    }
    expect(find.text('Photo Details Found'), findsOneWidget);
    await tester.tap(find.text('Use photo location'));
    await tester.pump();
    await tester.tap(find.text('Apply selected details'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSaveAndFlush(WidgetTester tester) async {
    final save = find.text('Save Changes');
    await tester.ensureVisible(save);
    await tester.pump();
    await tester.tap(save);
    await flushRealAsync(tester);
    await tester.pumpAndSettle();
  }

  group('photo GPS x tide reference integration', () {
    testWidgets(
        'A — automatic reference + accepted photo GPS: recalculation '
        'offered, request uses new catch coordinates, mode stays automatic',
        (tester) async {
      final catchToEdit = await seedCatch(tester,
          tideMode: 'automatic',
          requestLat: oldLat,
          requestLon: oldLon,
          phrase: 'old automatic tide context',
          station: 'Old Station');
      tides.nextContext =
          _tideContext(station: 'Nightcliff', phrase: 'new automatic context');

      final state = await pumpEditScreen(tester, catchToEdit);
      await attachPhotoAndAcceptLocation(tester);

      // Photo coordinates accepted onto the catch fields.
      expect(double.parse(state.debugLatitudeText), closeTo(photoLat, 0.001));
      expect(double.parse(state.debugLongitudeText), closeTo(photoLon, 0.001));
      expect(state.debugCoordinateSource, 'photo_gps');

      await tapSaveAndFlush(tester);

      // Recalculation is offered for the automatic-mode location change.
      expect(find.text('Recalculate Environmental Information'),
          findsOneWidget);
      await tester.tap(find.text('Recalculate'));
      await flushRealAsync(tester);
      await tester.pumpAndSettle();

      // Tide request went to the NEW catch coordinates, not the old row.
      expect(tides.fetchCount, 1);
      expect(tides.lastLat, closeTo(photoLat, 0.001));
      expect(tides.lastLon, closeTo(photoLon, 0.001));

      final row = await conditionRow(tester, catchToEdit.id!);
      expect(row!.tideReferenceMode, 'automatic');
      expect(row.tideReferenceName, isNull);
      expect(row.tideRequestLat, closeTo(photoLat, 0.001));
      expect(row.tideRequestLon, closeTo(photoLon, 0.001));
      expect(row.latitude, closeTo(photoLat, 0.001));
      expect(row.worldtidesStation, 'Nightcliff');
      expect(row.tideContextPhrase, 'new automatic context');

      final saved = await catchRow(tester, catchToEdit.id!);
      expect(saved['latitude'], closeTo(photoLat, 0.001));
      expect(saved['longitude'], closeTo(photoLon, 0.001));
      expect(saved['coordinate_source'], 'photo_gps');
    });

    testWidgets(
        'B — fixed reference + accepted photo GPS: catch coordinates '
        'change but recorded reference and request coordinates are kept',
        (tester) async {
      // No prior WorldTides context — a fetch is forced, which lets the
      // test prove the request goes to the recorded reference
      // coordinates rather than the newly applied photo location.
      final catchToEdit = await seedCatch(tester,
          tideMode: 'fixed',
          tideName: 'Darwin',
          requestLat: -12.4667,
          requestLon: 130.85);
      tides.nextContext =
          _tideContext(station: 'Darwin', phrase: 'Darwin high tide 6.5 m');

      final state = await pumpEditScreen(tester, catchToEdit);
      await attachPhotoAndAcceptLocation(tester);
      expect(state.debugCoordinateSource, 'photo_gps');

      await tapSaveAndFlush(tester);

      // No recalculation prompt for a fixed reference — the save
      // completed and the screen popped.
      expect(find.text('Recalculate Environmental Information'),
          findsNothing);
      expect(find.byType(AddCatchScreen), findsNothing);

      // The tide request still used the recorded reference coordinates,
      // never the photo location.
      expect(tides.fetchCount, 1);
      expect(tides.lastLat, closeTo(-12.4667, 0.001));
      expect(tides.lastLon, closeTo(130.85, 0.001));

      final row = await conditionRow(tester, catchToEdit.id!);
      expect(row!.tideReferenceMode, 'fixed');
      expect(row.tideReferenceName, 'Darwin');
      expect(row.tideRequestLat, closeTo(-12.4667, 0.001));
      expect(row.tideRequestLon, closeTo(130.85, 0.001));
      expect(row.worldtidesStation, 'Darwin');
      expect(row.tideContextPhrase, 'Darwin high tide 6.5 m');

      // The catch itself carries the photo coordinates.
      final saved = await catchRow(tester, catchToEdit.id!);
      expect(saved['latitude'], closeTo(photoLat, 0.001));
      expect(saved['coordinate_source'], 'photo_gps');
    });

    testWidgets(
        'B — discontinued fixed reference is reconstructed from recorded '
        'request coordinates and survives a photo-GPS save',
        (tester) async {
      final catchToEdit = await seedCatch(tester,
          tideMode: 'fixed',
          tideName: 'Cape Fourcroy (discontinued)',
          requestLat: -12.1,
          requestLon: 130.2);
      tides.nextContext = _tideContext(
          station: 'Cape Fourcroy', phrase: 'historic refreshed');

      final state = await pumpEditScreen(tester, catchToEdit);
      await attachPhotoAndAcceptLocation(tester);
      expect(state.debugCoordinateSource, 'photo_gps');

      await tapSaveAndFlush(tester);
      expect(find.byType(AddCatchScreen), findsNothing);

      // Request used the recorded coordinates, not photo or automatic.
      expect(tides.lastLat, closeTo(-12.1, 0.001));
      expect(tides.lastLon, closeTo(130.2, 0.001));

      final row = await conditionRow(tester, catchToEdit.id!);
      expect(row!.tideReferenceMode, 'fixed');
      expect(row.tideReferenceName, 'Cape Fourcroy (discontinued)');
      expect(row.tideRequestLat, closeTo(-12.1, 0.001));
      expect(row.tideRequestLon, closeTo(130.2, 0.001));

      final saved = await catchRow(tester, catchToEdit.id!);
      expect(saved['latitude'], closeTo(photoLat, 0.001));
      expect(saved['coordinate_source'], 'photo_gps');
    });

    testWidgets(
        'C — declining recalculation preserves the recorded '
        'environmental values while the catch keeps the photo location',
        (tester) async {
      final catchToEdit = await seedCatch(tester,
          tideMode: 'automatic',
          requestLat: oldLat,
          requestLon: oldLon,
          phrase: 'old automatic tide context',
          station: 'Old Station');

      await pumpEditScreen(tester, catchToEdit);
      await attachPhotoAndAcceptLocation(tester);
      await tapSaveAndFlush(tester);

      expect(find.text('Recalculate Environmental Information'),
          findsOneWidget);
      await tester.tap(find.text('Keep existing information'));
      await flushRealAsync(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AddCatchScreen), findsNothing);

      // No fetch; the recorded row is untouched.
      expect(tides.fetchCount, 0);
      final row = await conditionRow(tester, catchToEdit.id!);
      expect(row!.tideReferenceMode, 'automatic');
      expect(row.tideRequestLat, closeTo(oldLat, 0.001));
      expect(row.latitude, closeTo(oldLat, 0.001));
      expect(row.tideContextPhrase, 'old automatic tide context');
      expect(row.worldtidesStation, 'Old Station');

      final saved = await catchRow(tester, catchToEdit.id!);
      expect(saved['latitude'], closeTo(photoLat, 0.001));
    });

    testWidgets(
        'C — failed recalculation leaves the catch and recorded '
        'reference intact', (tester) async {
      final catchToEdit = await seedCatch(tester,
          tideMode: 'automatic',
          requestLat: oldLat,
          requestLon: oldLon,
          phrase: 'old automatic tide context',
          station: 'Old Station');
      tides.nextContext = null; // fetch yields nothing

      await pumpEditScreen(tester, catchToEdit);
      await attachPhotoAndAcceptLocation(tester);
      await tapSaveAndFlush(tester);

      expect(find.text('Recalculate Environmental Information'),
          findsOneWidget);
      await tester.tap(find.text('Recalculate'));
      await flushRealAsync(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AddCatchScreen), findsNothing);

      // Fetch attempted once; recorded condition preserved verbatim.
      expect(tides.fetchCount, 1);
      final row = await conditionRow(tester, catchToEdit.id!);
      expect(row!.tideReferenceMode, 'automatic');
      expect(row.tideRequestLat, closeTo(oldLat, 0.001));
      expect(row.latitude, closeTo(oldLat, 0.001));
      expect(row.tideContextPhrase, 'old automatic tide context');
      expect(row.worldtidesStation, 'Old Station');

      final saved = await catchRow(tester, catchToEdit.id!);
      expect(saved['latitude'], closeTo(photoLat, 0.001));
      expect(saved['coordinate_source'], 'photo_gps');
    });

    testWidgets(
        'C — cancelling the reference-change prompt after a photo-GPS '
        'apply persists neither the reference nor the catch change',
        (tester) async {
      final catchToEdit = await seedCatch(tester,
          tideMode: 'fixed',
          tideName: 'Darwin',
          requestLat: -12.4667,
          requestLon: 130.85,
          phrase: 'Darwin high tide 6.5 m',
          station: 'Darwin');

      final state = await pumpEditScreen(tester, catchToEdit);
      await attachPhotoAndAcceptLocation(tester);
      expect(state.debugCoordinateSource, 'photo_gps');

      // Change the reference, then cancel the mandatory prompt.
      await tester.ensureVisible(
          find.byKey(const Key('catch_tide_reference_field')));
      await tester.pump();
      await tester
          .tap(find.byKey(const Key('catch_tide_reference_field')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('tide_ref_search')), 'gove');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('tide_ref_melville_bay')));
      await tester.pumpAndSettle();

      await tapSaveAndFlush(tester);
      expect(find.text('Tide Reference Changed'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Still editing; nothing was persisted.
      expect(find.byType(AddCatchScreen), findsOneWidget);
      expect(tides.fetchCount, 0);
      final row = await conditionRow(tester, catchToEdit.id!);
      expect(row!.tideReferenceName, 'Darwin');
      expect(row.tideRequestLat, closeTo(-12.4667, 0.001));
      final saved = await catchRow(tester, catchToEdit.id!);
      expect(saved['latitude'], closeTo(oldLat, 0.001));
      expect(saved['coordinate_source'], 'Device GPS');
    });
  });

  group('ZIP backup/restore preserves tide + photo metadata', () {
    test(
        'round-trip preserves catch location, photo_gps provenance, '
        'catch_media EXIF fields, recorded tide reference and WorldTides '
        'metadata — with no recalculation during restore', () async {
      final mediaDir = await MediaStorageService.getMediaDirectory();
      final targetDbPath = p.join(testDir.path, 'target_bragmat.db');

      // A source database carrying a photo-GPS catch, its media row and
      // a fixed-reference environmental condition.
      final srcPath = p.join(testDir.path, 'src_bragmat.db');
      final src = await openDatabase(srcPath, version: 29,
          onCreate: (db, v) async {
        await db.execute('CREATE TABLE catches ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, fish_type TEXT, '
            'date_caught TEXT, latitude REAL, longitude REAL, '
            'coordinate_source TEXT)');
        await db.execute('CREATE TABLE catch_media ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, catch_id INTEGER, '
            'file_path TEXT, media_type TEXT, date_taken TEXT, '
            'latitude REAL, longitude REAL)');
        await db.execute('CREATE TABLE environmental_conditions ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, catch_id INTEGER, '
            'observation_date_time TEXT, latitude REAL, longitude REAL, '
            'tide_reference_mode TEXT, tide_reference_name TEXT, '
            'tide_request_lat REAL, tide_request_lon REAL, '
            'worldtides_station TEXT, worldtides_atlas TEXT, '
            'worldtides_response_lat REAL, worldtides_response_lon REAL, '
            'tide_context_phrase TEXT, tide_context_data_source TEXT)');
      });
      await src.insert('catches', {
        'fish_type': 'Barramundi',
        'date_caught': '2026-06-17T21:32:01.000',
        'latitude': photoLat,
        'longitude': photoLon,
        'coordinate_source': 'photo_gps',
      });
      await src.insert('catch_media', {
        'catch_id': 1,
        'file_path': 'catches/gps_photo.jpg',
        'media_type': 'photo',
        'date_taken': '2026-06-17T21:32:01.000',
        'latitude': photoLat,
        'longitude': photoLon,
      });
      await src.insert('environmental_conditions', {
        'catch_id': 1,
        'observation_date_time': '2026-06-17T21:32:01.000',
        'latitude': photoLat,
        'longitude': photoLon,
        'tide_reference_mode': 'fixed',
        'tide_reference_name': 'Darwin',
        'tide_request_lat': -12.4667,
        'tide_request_lon': 130.85,
        'worldtides_station': 'Darwin',
        'worldtides_atlas': 'Australia',
        'worldtides_response_lat': -12.4667,
        'worldtides_response_lon': 130.85,
        'tide_context_phrase': 'Darwin high tide 6.5 m',
        'tide_context_data_source': 'WorldTides',
      });
      await src.close();

      // Build the ZIP: manifest + whole database + the real EXIF photo.
      final archive = Archive();
      final manifest = BackupManifest.create(
        bragmatVersion: '1.0.0+8',
        databaseSchemaVersion: 29,
        platform: 'android',
        contents: BackupContents(
          database: true,
          media:
              BackupMediaCounts(catches: 1, trips: 0, journals: 0, lures: 0),
          settings: false,
        ),
        statistics: BackupStatistics(
            catches: 1, trips: 0, photos: 1, missingPhotos: 0),
      );
      final manifestBytes = utf8.encode(jsonEncode(manifest.toMap()));
      archive.addFile(
          ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
      final dbBytes = await File(srcPath).readAsBytes();
      archive.addFile(
          ArchiveFile('database.sqlite', dbBytes.length, dbBytes));
      final photoBytes = await File(mfnrFixture).readAsBytes();
      archive.addFile(ArchiveFile(
          'media/catches/gps_photo.jpg', photoBytes.length, photoBytes));
      final zipPath = p.join(testDir.path, 'roundtrip_backup.zip');
      await File(zipPath).writeAsBytes(ZipEncoder().encode(archive)!);

      final result = await ZipBackupService.restoreBackup(
        zipPath: zipPath,
        databasePathOverride: targetDbPath,
        mediaDirectoryOverride: mediaDir,
      );
      expect(result.mediaFilesRestored, 1);

      // Restored database carries every field verbatim.
      final restored =
          await openDatabase(targetDbPath, readOnly: true);
      try {
        final catchRows = await restored.query('catches');
        expect(catchRows.single['latitude'], closeTo(photoLat, 0.001));
        expect(catchRows.single['longitude'], closeTo(photoLon, 0.001));
        expect(catchRows.single['coordinate_source'], 'photo_gps');
        expect(
            catchRows.single['date_caught'], '2026-06-17T21:32:01.000');

        final mediaRows = await restored.query('catch_media');
        expect(mediaRows.single['file_path'], 'catches/gps_photo.jpg');
        expect(
            mediaRows.single['date_taken'], '2026-06-17T21:32:01.000');
        expect(mediaRows.single['latitude'], closeTo(photoLat, 0.001));

        final envRows = await restored.query('environmental_conditions');
        expect(envRows.single['tide_reference_mode'], 'fixed');
        expect(envRows.single['tide_reference_name'], 'Darwin');
        expect(envRows.single['tide_request_lat'], -12.4667);
        expect(envRows.single['tide_request_lon'], 130.85);
        expect(envRows.single['worldtides_station'], 'Darwin');
        expect(envRows.single['worldtides_atlas'], 'Australia');
        expect(envRows.single['worldtides_response_lat'], -12.4667);
        expect(envRows.single['tide_context_phrase'],
            'Darwin high tide 6.5 m');
      } finally {
        await restored.close();
      }

      // Photograph file restored byte-identical — its EXIF remains
      // re-extractable.
      final restoredPhoto =
          File(p.join(mediaDir.path, 'catches', 'gps_photo.jpg'));
      expect(await restoredPhoto.exists(), isTrue);
      expect(await restoredPhoto.readAsBytes(), photoBytes);

      // Restore is a file swap: no WorldTides request ran.
      expect(tides.fetchCount, 0);
    });
  });
}
