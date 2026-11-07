// iOS device-defect regressions (IOS-D1, IOS-D2):
//
//  IOS-D1 — editing an existing catch could leave Save permanently
//    dead: prompt-cancel paths inside _saveCatch returned early while
//    _isSaving was still true, so the guard swallowed every later press.
//    These tests cancel the "Tide Reference Changed" prompt and prove a
//    subsequent Save still runs.
//
//  IOS-D2 — on a GPS failure the location picker silently adopted the
//    centre-of-Australia camera fallback as the SELECTED location.
//    These tests prove a failed fix now leaves the selection empty,
//    disables Confirm and shows an explicit unavailable message.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/models/catch.dart' as model;
import 'package:bragmat/screens/add_catch_screen.dart';
import 'package:bragmat/screens/location_picker_screen.dart';
import 'package:bragmat/services/environmental_conditions_service.dart';
import 'package:bragmat/services/weather_service.dart';
import 'package:bragmat/services/worldtides_service.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Deterministic WorldTides fake — no network, records requests.
class _FakeWorldTidesService implements WorldTidesService {
  Map<String, dynamic>? nextContext;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Map<String, dynamic>?> getTideContextForLocation(
    double latitude,
    double longitude,
    DateTime observationTime,
  ) async =>
      nextContext;
}

/// Weather fake that never reaches the network.
class _FakeWeatherService implements WeatherService {
  @override
  Future<WeatherData?> fetchWeather(
          double latitude, double longitude, DateTime dateTime) async =>
      null;

  @override
  String windDirectionToCompass(double? degrees) => 'N';
}

/// Geolocator fake — controls the outcome of the permission and fix calls.
class _FakeGeolocator extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  Position? nextPosition;
  Object? nextError;
  LocationPermission permission = LocationPermission.always;
  int positionCalls = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    positionCalls++;
    if (nextError != null) throw nextError!;
    return nextPosition!;
  }
}

Position _pos(double lat, double lon) => Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime(2026, 11, 7),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Map<String, dynamic> _tideContext({
  required String station,
  required String phrase,
}) =>
    {
      'tideStationName': station,
      'worldtidesAtlas': 'Australia',
      'worldtidesResponseLat': -12.4667,
      'worldtidesResponseLon': 130.85,
      'referenceTideEventType': 'High',
      'referenceTideEventTime': DateTime(2026, 8, 2, 13, 0),
      'referenceTideEventHeight': 6.5,
      'referenceTideEventRelation': 'Before',
      'minutesFromReferenceTideEvent': 180,
      'previousTideEventType': 'Low',
      'previousTideEventTime': DateTime(2026, 8, 2, 7, 0),
      'previousTideEventHeight': 1.2,
      'nextTideEventType': 'Low',
      'nextTideEventTime': DateTime(2026, 8, 2, 19, 30),
      'nextTideEventHeight': 1.4,
      'tideContextPhrase': phrase,
      'tideContextDataSource': 'WorldTides',
      'tideContextConfidence': 'High',
    };

// NOTE: DB calls must run inside tester.runAsync — sqflite's I/O never
// completes in the widget test's fake-async zone.

Future<model.Catch> _insertCatch(WidgetTester tester) async {
  final id = await tester.runAsync(() async {
    final db = await DatabaseHelper.instance.database;
    return db.insert(
        'catches',
        model.Catch(
          lengthCm: 0,
          createdAt: DateTime(2026, 8, 2, 10, 0),
          dateCaught: DateTime(2026, 8, 2, 10, 0),
          latitude: -12.4634,
          longitude: 130.8456,
        ).toMap());
  });
  return model.Catch(
    id: id,
    lengthCm: 0,
    createdAt: DateTime(2026, 8, 2, 10, 0),
    dateCaught: DateTime(2026, 8, 2, 10, 0),
    latitude: -12.4634,
    longitude: 130.8456,
  );
}

Future<void> _insertDarwinCondition(WidgetTester tester, int catchId) async {
  await tester.runAsync(() async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('environmental_conditions', {
      'catch_id': catchId,
      'observation_date_time': '2026-08-02T10:00:00.000',
      'latitude': -12.4634,
      'longitude': 130.8456,
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
      'created_at': '2026-08-02T10:00:00.000',
      'updated_at': '2026-08-02T10:00:00.000',
    });
  });
}

extension on WidgetTester {
  /// Pump frames until [finder] resolves, alternating pump() with
  /// runAsync() so both fake-clock waits (sqflite lock retries) and
  /// real I/O progress. pumpAndSettle is unusable here: the screen's
  /// loading spinner keeps frames scheduled while fake-time lock waits
  /// drain, exceeding the settle timeout.
  Future<void> pumpUntil(Finder finder,
      {int maxPumps = 300, String? because, bool invert = false}) async {
    for (var i = 0; i < maxPumps; i++) {
      await pump(const Duration(milliseconds: 100));
      await runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      if (finder.evaluate().isNotEmpty != invert) return;
    }
    throw StateError(
        'timed out waiting for ${because ?? finder.toString()}');
  }

  /// Push AddCatchScreen in edit mode and wait for initial data.
  Future<void> openEditCatch(model.Catch catchToEdit) async {
    await pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AddCatchScreen(catchToEdit: catchToEdit),
              ),
            ),
            child: const Text('edit'),
          ),
        ),
      ),
    ));
    await tap(find.text('edit'));
    await pump();
    await pumpUntil(find.byKey(const Key('catch_tide_reference_field')),
        because: 'AddCatchScreen to finish loading');
    await pumpAndSettle();
    expect(find.byType(AddCatchScreen), findsOneWidget);
  }

  /// Open the shared picker, filter by [query] and tap [key].
  Future<void> pickTideReference(String query, String id) async {
    await ensureVisible(find.byKey(const Key('catch_tide_reference_field')));
    await pump();
    await tap(find.byKey(const Key('catch_tide_reference_field')));
    await pumpAndSettle();
    expect(find.byKey(const Key('tide_ref_search')), findsOneWidget);
    await enterText(find.byKey(const Key('tide_ref_search')), query);
    await pump(const Duration(milliseconds: 50));
    final tile = find.byKey(Key('tide_ref_$id'));
    await ensureVisible(tile);
    await pump(const Duration(milliseconds: 50));
    await tap(tile);
    await pumpUntil(find.byKey(const Key('tide_ref_search')),
        because: 'picker to close', invert: true);
  }

  /// Scroll to and tap the save button.
  Future<void> tapSave() async {
    await ensureVisible(find.text('Save Changes'));
    await pump();
    await tap(find.text('Save Changes'));
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;
  late _FakeWorldTidesService tides;
  final service = EnvironmentalConditionsService();
  final geo = _FakeGeolocator();
  final realGeo = GeolocatorPlatform.instance;

  setUpAll(() {
    GeolocatorPlatform.instance = geo;
  });

  tearDownAll(() {
    GeolocatorPlatform.instance = realGeo;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    testDir =
        Directory.systemTemp.createTempSync('bragmat_ios_d_test_');
    DatabaseHelper.setTestDatabasePath(p.join(testDir.path, 'bragmat.db'));
    tides = _FakeWorldTidesService();
    service.worldTidesService = tides;
    service.weatherService = _FakeWeatherService();
    geo
      ..nextPosition = null
      ..nextError = null
      ..positionCalls = 0
      ..permission = LocationPermission.always;
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    if (await testDir.exists()) await testDir.delete(recursive: true);
  });

  group('IOS-D1 — edit save stays usable after a cancelled prompt', () {
    testWidgets(
        'cancel "Tide Reference Changed" then Save again — prompt reappears',
        (tester) async {
      final catchToEdit = await _insertCatch(tester);
      await _insertDarwinCondition(tester, catchToEdit.id!);
      tides.nextContext = _tideContext(
        station: 'Melville Bay',
        phrase: 'Melville Bay high tide 3.1 m',
      );

      await tester.openEditCatch(catchToEdit);
      await tester.pickTideReference('gove', 'melville_bay');

      // First save: cancel the mandatory recalculation prompt.
      await tester.tapSave();
      await tester.pumpUntil(find.text('Tide Reference Changed'),
          because: 'first reference-change prompt');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // _isSaving must have been released — a second Save press runs
      // the flow again instead of being swallowed by the guard.
      await tester.tapSave();
      await tester.pumpUntil(find.text('Tide Reference Changed'),
          because: 'reference-change prompt to reappear');

      // This time confirm the revert path completes the save.
      await tester.tap(find.text('Revert to recorded reference'));
      await tester.pumpUntil(find.byType(AddCatchScreen),
          because: 'screen to pop after save', invert: true);
    });

    testWidgets('edit form finishes loading — Save visible on iPhone 11 '
        'viewport', (tester) async {
      // iPhone 11 logical viewport: 414 x 896.
      tester.binding.setSurfaceSize(const Size(414, 896));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final catchToEdit = await _insertCatch(tester);
      await tester.openEditCatch(catchToEdit);

      await tester.ensureVisible(find.text('Save Changes'));
      expect(find.text('Save Changes'), findsOneWidget);
      expect(
          tester.widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Save Changes')),
          isNotNull);
    });

    testWidgets('failed initial-data load shows error state, Save blocked',
        (tester) async {
      final catchToEdit = await _insertCatch(tester);
      // Corrupt the observation timestamp — DateTime.parse throws inside
      // getEnvironmentalConditionForCatch, failing the initial load.
      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        await db.insert('environmental_conditions', {
          'catch_id': catchToEdit.id,
          'observation_date_time': 'not-a-date',
          'created_at': '2026-08-02T10:00:00.000',
          'updated_at': '2026-08-02T10:00:00.000',
        });
      });

      await tester.pumpWidget(MaterialApp(
        home: AddCatchScreen(catchToEdit: catchToEdit),
      ));
      await tester.pumpUntil(
          find.textContaining("Couldn't load this catch"),
          because: 'load-failure error state');

      // No partially loaded form and no Save path — nothing can
      // silently overwrite the stored catch.
      expect(find.text('Save Changes'), findsNothing);
      final row = await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        return db.query('catches',
            where: 'id = ?', whereArgs: [catchToEdit.id]);
      });
      expect(row, isNotEmpty);
    });

    testWidgets('successful edit persists after saving', (tester) async {
      final catchToEdit = await _insertCatch(tester);
      await _insertDarwinCondition(tester, catchToEdit.id!);

      await tester.openEditCatch(catchToEdit);

      // Edit a simple field (notes) — no reference/location/date change,
      // so save takes the plain upsert path without prompts.
      final notesField = find.ancestor(
          of: find.text('Catch Notes'), matching: find.byType(TextField));
      await tester.ensureVisible(notesField);
      await tester.enterText(notesField, 'edited notes');
      await tester.tapSave();
      await tester.pumpUntil(find.byType(AddCatchScreen),
          because: 'screen to pop after save', invert: true);

      final rows = await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        return db.query('catches',
            where: 'id = ?', whereArgs: [catchToEdit.id]);
      });
      expect(rows, isNotNull);
      expect(rows!.single['notes'], 'edited notes');
    });
  });

  group('IOS-D2 — GPS failure never writes fallback coordinates', () {
    testWidgets(
        'failed fix: selection stays empty, Confirm disabled, error shown',
        (tester) async {
      geo.nextError = Exception('position unavailable');

      await tester.pumpWidget(
          const MaterialApp(home: LocationPickerScreen()));
      await tester.pumpUntil(
        find.textContaining("Couldn't get your current location"),
        because: 'location-unavailable message',
      );

      // Confirm is disabled while nothing is selected — the central-
      // Australia camera fallback must not become a selection.
      final confirm = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.check));
      expect(confirm.onPressed, isNull);

      // Drain the pending delayed map move + connectivity events.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('successful fix: selection set and Confirm enabled',
        (tester) async {
      geo.nextPosition = _pos(-12.4634, 130.8456);

      Map<String, double>? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<Map<String, double>>(
                  MaterialPageRoute(
                      builder: (_) => const LocationPickerScreen()),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final confirm = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.check));
      expect(confirm.onPressed, isNotNull);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!['latitude'], closeTo(-12.4634, 1e-6));
      expect(result!['longitude'], closeTo(130.8456, 1e-6));
    });

    for (final (name, setup) in [
      ('permission denied', () => geo.permission = LocationPermission.denied),
      ('permission denied forever',
          () => geo.permission = LocationPermission.deniedForever),
      ('fix timeout/failure',
          () => geo.nextError = Exception('getCurrentPosition timed out')),
    ]) {
      testWidgets('$name: no selection, Confirm disabled, error shown',
          (tester) async {
        setup();
        await tester.pumpWidget(
            const MaterialApp(home: LocationPickerScreen()));
        await tester.pumpUntil(
          find.textContaining("Couldn't get your current location"),
          because: 'location-unavailable message for $name',
        );
        final confirm = tester.widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.check));
        expect(confirm.onPressed, isNull);
        await tester.pump(const Duration(seconds: 1));
      });
    }
  });
}
