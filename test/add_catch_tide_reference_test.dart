// Widget regression for the tide-reference workflow in AddCatchScreen
// (edit mode) — exercised against a real (ffi) database with fake
// WorldTides/Weather services and the shared picker sheet.
//
// Covers the full user-visible flow:
//  - picking a different reference via TideReferencePickerSheet
//  - the mandatory "Tide Reference Changed" recalculation confirmation
//  - failed recalculation: "Save without tide information" stamps the
//    applied reference and clears stale tide data
//  - failed recalculation: "Revert to recorded reference" preserves the
//    recorded reference and its tide data
//  - cancelling the prompt leaves the catch untouched
//  - historical catches (no recorded reference): "Not recorded",
//    confirmation prompt, and cancel preserving the unmodified catch

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/models/catch.dart' as model;
import 'package:bragmat/models/environmental_condition.dart';
import 'package:bragmat/screens/add_catch_screen.dart';
import 'package:bragmat/services/environmental_conditions_service.dart';
import 'package:bragmat/services/weather_service.dart';
import 'package:bragmat/services/worldtides_service.dart';

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

/// Weather fake that never reaches the network.
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

// NOTE: test-body DB calls must run inside tester.runAsync — sqflite's
// I/O never completes in the widget test's fake-async zone. The screen's
// own async work (loaders, save handlers) progresses under pump() as
// usual.

Future<model.Catch> _insertCatch(WidgetTester tester, {
  double lat = -12.4634,
  double lon = 130.8456,
}) async {
  final id = await tester.runAsync(() async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('catches', model.Catch(
      lengthCm: 0,
      createdAt: DateTime(2026, 8, 2, 10, 0),
      dateCaught: DateTime(2026, 8, 2, 10, 0),
      latitude: lat,
      longitude: lon,
    ).toMap());
  });
  return model.Catch(
    id: id,
    lengthCm: 0,
    createdAt: DateTime(2026, 8, 2, 10, 0),
    dateCaught: DateTime(2026, 8, 2, 10, 0),
    latitude: lat,
    longitude: lon,
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

/// Read the recorded environmental row — via runAsync (see note above).
Future<EnvironmentalCondition?> _conditionRow(
        WidgetTester tester, int catchId) async =>
    tester.runAsync<EnvironmentalCondition?>(() =>
        EnvironmentalConditionsService()
            .getEnvironmentalConditionForCatch(catchId));

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
      await runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 10)));
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
    // The field is findable mid-push-transition; settle it so
    // subsequent taps land on final positions.
    await pumpAndSettle();
    expect(find.byType(AddCatchScreen), findsOneWidget);
  }

  /// Open the shared picker, filter by [query] and tap [key].
  Future<void> pickTideReference(String query, String id) async {
    await ensureVisible(find.byKey(const Key('catch_tide_reference_field')));
    await pump();
    await tap(find.byKey(const Key('catch_tide_reference_field')));
    // The sheet's search field is in the tree immediately but still
    // offscreen — settle the entrance animation before interacting.
    await pumpAndSettle();
    expect(find.byKey(const Key('tide_ref_search')), findsOneWidget);
    await enterText(find.byKey(const Key('tide_ref_search')), query);
    await pump(const Duration(milliseconds: 50));
    final tile = find.byKey(Key('tide_ref_$id'));
    await ensureVisible(tile);
    await pump(const Duration(milliseconds: 50));
    await tap(tile);
    // Wait for the sheet itself to leave the tree — the launcher field
    // is still present underneath it.
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

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;
  late _FakeWorldTidesService tides;
  final service = EnvironmentalConditionsService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testDir = Directory.systemTemp.createTempSync('bragmat_catch_tide_test_');
    DatabaseHelper.setTestDatabasePath(p.join(testDir.path, 'bragmat.db'));
    tides = _FakeWorldTidesService();
    service.worldTidesService = tides;
    service.weatherService = _FakeWeatherService();
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    if (await testDir.exists()) await testDir.delete(recursive: true);
  });

  testWidgets('pick a different reference, confirm recalculation — '
      'context is rewritten for the new reference', (tester) async {
    final catchToEdit = await _insertCatch(tester);
    await _insertDarwinCondition(tester, catchToEdit.id!);
    tides.nextContext = _tideContext(
      station: 'Melville Bay',
      phrase: 'Melville Bay high tide 3.1 m',
      responseLat: -12.2,
      responseLon: 136.6667,
    );

    await tester.openEditCatch(catchToEdit);
    await tester.pickTideReference('gove', 'melville_bay');
    expect(find.text('Melville Bay'), findsWidgets);

    await tester.tapSave();
    await tester.pumpUntil(find.text('Tide Reference Changed'),
        because: 'reference-change prompt');
    await tester.tap(find.text('Recalculate and save'));
    await tester.pumpUntil(find.byType(AddCatchScreen),
        because: 'screen to pop after save', invert: true);

    final row = await _conditionRow(tester, catchToEdit.id!);
    expect(row!.tideReferenceMode, 'fixed');
    expect(row.tideReferenceName, 'Melville Bay');
    expect(row.tideRequestLat, -12.2);
    expect(row.tideRequestLon, 136.6667);
    expect(row.worldtidesStation, 'Melville Bay');
    expect(row.tideContextPhrase, 'Melville Bay high tide 3.1 m');
  });

  testWidgets('failed recalculation — "Save without tide information" '
      'clears stale tide data and stamps the applied reference',
      (tester) async {
    final catchToEdit = await _insertCatch(tester);
    await _insertDarwinCondition(tester, catchToEdit.id!);
    tides.nextContext = null; // fetch yields nothing

    await tester.openEditCatch(catchToEdit);
    await tester.pickTideReference('wadeye', 'port_keats');

    await tester.tapSave();
    await tester.pumpUntil(find.text('Tide Reference Changed'),
        because: 'reference-change prompt');
    await tester.tap(find.text('Recalculate and save'));
    await tester.pumpUntil(find.text('Tide Information Unavailable'),
        because: 'failed-recalculation prompt');
    await tester.tap(find.text('Save without tide information'));
    await tester.pumpUntil(find.byType(AddCatchScreen),
        because: 'screen to pop after save', invert: true);

    final row = await _conditionRow(tester, catchToEdit.id!);
    // The honestly-applied reference is stamped with its request
    // coordinates; the stale WorldTides context is gone.
    expect(row!.tideReferenceMode, 'fixed');
    expect(row.tideReferenceName, 'Port Keats');
    expect(row.tideRequestLat, -14.15);
    expect(row.tideRequestLon, 129.5667);
    expect(row.tideContextPhrase, isNull);
    expect(row.worldtidesStation, isNull);
  });

  testWidgets('failed recalculation — "Revert to recorded reference" '
      'preserves the recorded reference and its tide data',
      (tester) async {
    final catchToEdit = await _insertCatch(tester);
    await _insertDarwinCondition(tester, catchToEdit.id!);
    tides.nextContext = null;

    await tester.openEditCatch(catchToEdit);
    await tester.pickTideReference('gove', 'melville_bay');

    await tester.tapSave();
    await tester.pumpUntil(find.text('Tide Reference Changed'),
        because: 'reference-change prompt');
    await tester.tap(find.text('Recalculate and save'));
    await tester.pumpUntil(find.text('Tide Information Unavailable'),
        because: 'failed-recalculation prompt');
    await tester.tap(find.text('Revert to recorded reference'));
    await tester.pumpUntil(find.byType(AddCatchScreen),
        because: 'screen to pop after revert', invert: true);

    final row = await _conditionRow(tester, catchToEdit.id!);
    // Revert re-applies the recorded reference — request unchanged, so
    // the recorded tide data is preserved untouched.
    expect(row!.tideReferenceMode, 'fixed');
    expect(row.tideReferenceName, 'Darwin');
    expect(row.tideRequestLat, -12.4667);
    expect(row.tideRequestLon, 130.85);
    expect(row.tideContextPhrase, 'Darwin high tide 6.5 m');
    expect(row.worldtidesStation, 'Darwin');
  });

  testWidgets('cancelling the reference-change prompt aborts the save '
      'and leaves the recorded row untouched', (tester) async {
    final catchToEdit = await _insertCatch(tester);
    await _insertDarwinCondition(tester, catchToEdit.id!);

    await tester.openEditCatch(catchToEdit);
    await tester.pickTideReference('gove', 'melville_bay');

    await tester.tapSave();
    await tester.pumpUntil(find.text('Tide Reference Changed'),
        because: 'reference-change prompt');
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Still editing — nothing was persisted.
    expect(find.byType(AddCatchScreen), findsOneWidget);
    expect(tides.fetchCount, 0);
    final row = await _conditionRow(tester, catchToEdit.id!);
    expect(row!.tideReferenceName, 'Darwin');
    expect(row.tideContextPhrase, 'Darwin high tide 6.5 m');
  });

  testWidgets('historical catch — picker offers "Not recorded"; '
      'confirmed selection records the reference', (tester) async {
    final catchToEdit = await _insertCatch(tester); // no condition row
    tides.nextContext = _tideContext(
      station: 'Darwin',
      phrase: 'Darwin high tide 6.5 m',
    );

    await tester.openEditCatch(catchToEdit);
    await tester.ensureVisible(
        find.byKey(const Key('catch_tide_reference_field')));
    await tester.pump();
    expect(find.text('Not recorded'), findsOneWidget);

    await tester.pickTideReference('darwin', 'darwin');

    await tester.tapSave();
    await tester.pumpUntil(find.text('Set Tide Reference'),
        because: 'historical-reference prompt');
    await tester.tap(find.text('Set reference and recalculate'));
    await tester.pumpUntil(find.byType(AddCatchScreen),
        because: 'screen to pop after save', invert: true);

    final row = await _conditionRow(tester, catchToEdit.id!);
    expect(row, isNotNull);
    expect(row!.tideReferenceMode, 'fixed');
    expect(row.tideReferenceName, 'Darwin');
    expect(row.tideRequestLat, -12.4667);
    expect(row.tideContextPhrase, 'Darwin high tide 6.5 m');
  });

  testWidgets('historical catch — cancelling the prompt preserves the '
      'unmodified catch (no condition row written)', (tester) async {
    final catchToEdit = await _insertCatch(tester);

    await tester.openEditCatch(catchToEdit);
    await tester.pickTideReference('darwin', 'darwin');

    await tester.tapSave();
    await tester.pumpUntil(find.text('Set Tide Reference'),
        because: 'historical-reference prompt');
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Save aborted — still editing, no environmental row created.
    expect(find.byType(AddCatchScreen), findsOneWidget);
    expect(tides.fetchCount, 0);
    final row = await _conditionRow(tester, catchToEdit.id!);
    expect(row, isNull);
  });
}
