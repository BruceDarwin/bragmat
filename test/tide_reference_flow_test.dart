// Integration tests for the tide-reference flow in
// EnvironmentalConditionsService — exercised against a real (ffi)
// database with fake WorldTides/Weather services.
//
// Covers:
//  - D2: changing the reference actually refetches and rewrites context
//  - D2: a failed fetch on a changed request preserves the recorded row
//  - D3: explicit recalculation failure returns null and preserves data
//  - D1: recorded references resolve via the central resolver; an
//        unresolved fixed reference is never substituted with automatic
//  - saveEnvironmentalConditionForCatch preserves recorded reference and
//    WorldTides source metadata (regression: they were wiped on save)
//  - offline behaviour: no fetch, condition still recorded

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/models/catch.dart' as model;
import 'package:bragmat/models/tide_reference.dart';
import 'package:bragmat/services/environmental_conditions_service.dart';
import 'package:bragmat/services/tide_reference_service.dart';
import 'package:bragmat/services/weather_service.dart';
import 'package:bragmat/services/worldtides_service.dart';

/// Deterministic WorldTides fake — no network, records requests.
class _FakeWorldTidesService implements WorldTidesService {
  bool available = true;
  Map<String, dynamic>? nextContext;
  bool throwOnFetch = false;
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
    if (throwOnFetch) throw Exception('simulated fetch failure');
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

model.Catch _catch({double lat = -12.4634, double lon = 130.8456}) =>
    model.Catch(
      id: 7,
      lengthCm: 0,
      createdAt: DateTime(2026, 8, 2, 10, 0),
      dateCaught: DateTime(2026, 8, 2, 10, 0),
      latitude: lat,
      longitude: lon,
    );

Future<void> _insertDarwinCondition(
  int catchId, {
  String mode = 'fixed',
  String? name = 'Darwin',
  double? requestLat = -12.4667,
  double? requestLon = 130.85,
  bool withContext = true,
}) async {
  final db = await DatabaseHelper.instance.database;
  await db.insert('environmental_conditions', {
    'catch_id': catchId,
    'observation_date_time': '2026-08-02T10:00:00.000',
    'latitude': -12.4634,
    'longitude': 130.8456,
    'tide_reference_mode': mode,
    'tide_reference_name': name,
    'tide_request_lat': requestLat,
    'tide_request_lon': requestLon,
    'worldtides_station': withContext ? 'Darwin' : null,
    'worldtides_atlas': withContext ? 'Australia' : null,
    'worldtides_response_lat': withContext ? -12.4667 : null,
    'worldtides_response_lon': withContext ? 130.85 : null,
    'tide_context_phrase': withContext ? 'Darwin high tide 6.5 m' : null,
    'tide_context_data_source': withContext ? 'WorldTides' : null,
    'created_at': '2026-08-02T10:00:00.000',
    'updated_at': '2026-08-02T10:00:00.000',
  });
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;
  late _FakeWorldTidesService tides;

  final service = EnvironmentalConditionsService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testDir = Directory.systemTemp.createTempSync('bragmat_tide_test_');
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

  group('D2 — request-change detection in upsert', () {
    test('changing to a different fixed reference refetches and rewrites '
        'the tide context', () async {
      await _insertDarwinCondition(7);
      tides.nextContext = _tideContext(
        station: 'Melville Bay',
        phrase: 'Melville Bay high tide 3.1 m',
        responseLat: -12.25,
        responseLon: 136.70,
      );

      const gove = TideReference(
        id: 'melville_bay',
        displayName: 'Melville Bay',
        latitude: -12.25,
        longitude: 136.70,
      );

      final result = await service.upsertCalculatedConditionsForCatch(
        _catch(),
        tideReference: gove,
      );

      expect(result, TideRecalculationResult.success);
      expect(tides.fetchCount, 1,
          reason: 'a changed reference must trigger a new request');
      expect(tides.lastLat, -12.25);
      expect(tides.lastLon, 136.70);

      final row = await service.getEnvironmentalConditionForCatch(7);
      expect(row!.tideReferenceMode, 'fixed');
      expect(row.tideReferenceName, 'Melville Bay');
      expect(row.tideRequestLat, -12.25);
      expect(row.worldtidesStation, 'Melville Bay');
      expect(row.tideContextPhrase, 'Melville Bay high tide 3.1 m');
    });

    test('same request coordinates and date reuse the recorded context — '
        'no fetch', () async {
      await _insertDarwinCondition(7);
      tides.nextContext = _tideContext(
        station: 'Darwin',
        phrase: 'fresh Darwin phrase',
      );

      final result = await service.upsertCalculatedConditionsForCatch(
        _catch(),
        tideReference: TideReferenceService.getReferenceById('darwin'),
      );

      expect(result, TideRecalculationResult.success);
      expect(tides.fetchCount, 0);

      final row = await service.getEnvironmentalConditionForCatch(7);
      expect(row!.tideContextPhrase, 'Darwin high tide 6.5 m');
    });

    test('automatic mode: changed catch location refetches', () async {
      await _insertDarwinCondition(
        7,
        mode: 'automatic',
        name: null,
        requestLat: -12.4634,
        requestLon: 130.8456,
      );
      tides.nextContext = _tideContext(
        station: 'Darwin',
        phrase: 'relocated catch tide phrase',
      );

      final moved = _catch(lat: -12.70, lon: 130.36);
      final result = await service.upsertCalculatedConditionsForCatch(
        moved,
        tideReference: TideReferenceService.getAllReferences()
            .firstWhere((r) => r.id == 'automatic'),
      );

      expect(result, TideRecalculationResult.success);
      expect(tides.fetchCount, 1);
      expect(tides.lastLat, -12.70);
      expect(tides.lastLon, 130.36);
    });

    test('changed request + failed fetch preserves the recorded row and '
        'reports unavailable', () async {
      await _insertDarwinCondition(7);
      tides.nextContext = null; // fetch returns nothing

      const gove = TideReference(
        id: 'melville_bay',
        displayName: 'Melville Bay',
        latitude: -12.25,
        longitude: 136.70,
      );

      final result = await service.upsertCalculatedConditionsForCatch(
        _catch(),
        tideReference: gove,
      );

      expect(result, TideRecalculationResult.unavailable);

      // The row must still carry the ORIGINAL reference + its valid tide
      // data — the attempted change is not misrepresented as applied.
      final row = await service.getEnvironmentalConditionForCatch(7);
      expect(row!.tideReferenceName, 'Darwin');
      expect(row.tideRequestLat, -12.4667);
      expect(row.tideContextPhrase, 'Darwin high tide 6.5 m');
      expect(row.worldtidesStation, 'Darwin');
    });
  });

  group('D3 — explicit recalculation failure', () {
    test('failed explicit recalculation returns null and preserves the '
        'recorded reference and tide data', () async {
      await _insertDarwinCondition(7);
      tides.nextContext = null;

      final updated = await service.recalculateEnvironmentalConditionForCatch(
        _catch(),
        useRecordedReference: true,
      );

      expect(updated, isNull);

      final row = await service.getEnvironmentalConditionForCatch(7);
      expect(row!.tideReferenceMode, 'fixed');
      expect(row.tideReferenceName, 'Darwin');
      expect(row.tideContextPhrase, 'Darwin high tide 6.5 m');
      expect(row.worldtidesStation, 'Darwin');
    });

    test('successful explicit recalculation returns the updated row',
        () async {
      await _insertDarwinCondition(7);
      tides.nextContext = _tideContext(
        station: 'Darwin',
        phrase: 'recalculated Darwin tide',
      );

      final updated = await service.recalculateEnvironmentalConditionForCatch(
        _catch(),
        useRecordedReference: true,
      );

      expect(updated, isNotNull);
      final row = await service.getEnvironmentalConditionForCatch(7);
      expect(row!.tideContextPhrase, 'recalculated Darwin tide');
      expect(row.tideReferenceName, 'Darwin');
    });
  });

  group('D1 — recorded reference resolution', () {
    test('legacy fixed row (name "Dundee Beach", no catalogue entry) '
        'reconstructs from recorded request coordinates', () async {
      await _insertDarwinCondition(
        7,
        name: 'Dundee Beach',
        requestLat: -12.705,
        requestLon: 130.355,
      );

      // No explicit reference — the recorded one must be resolved.
      final result = await service.upsertCalculatedConditionsForCatch(
        _catch(),
      );

      expect(result, TideRecalculationResult.success);
      final row = await service.getEnvironmentalConditionForCatch(7);
      // The recorded reference name and its request coordinates survive —
      // they must not be flattened to a different station or automatic.
      expect(row!.tideReferenceMode, 'fixed');
      expect(row.tideReferenceName, 'Dundee Beach');
      expect(row.tideRequestLat, -12.705);
      expect(row.tideRequestLon, 130.355);
    });

    test('unresolvable fixed row (no name, no request coords) keeps its '
        'recorded mode verbatim', () async {
      await _insertDarwinCondition(
        7,
        name: null,
        requestLat: null,
        requestLon: null,
      );

      final result = await service.upsertCalculatedConditionsForCatch(
        _catch(),
      );

      expect(result, TideRecalculationResult.success);
      final row = await service.getEnvironmentalConditionForCatch(7);
      expect(row!.tideReferenceMode, 'fixed',
          reason: 'an unresolved fixed reference is never silently '
              'rewritten as automatic');
    });
  });

  group('manual save preserves automated fields', () {
    test('saveEnvironmentalConditionForCatch keeps the recorded reference '
        'and WorldTides source metadata', () async {
      await _insertDarwinCondition(7);

      await service.saveEnvironmentalConditionForCatch(
        7,
        DateTime(2026, 8, 2, 10, 0),
        -12.4634,
        130.8456,
        tideStage: 'High Tide',
      );

      final row = await service.getEnvironmentalConditionForCatch(7);
      expect(row!.tideStage, 'High Tide');
      // Automated fields survive a manual save.
      expect(row.tideReferenceMode, 'fixed');
      expect(row.tideReferenceName, 'Darwin');
      expect(row.tideRequestLat, -12.4667);
      expect(row.tideRequestLon, 130.85);
      expect(row.worldtidesStation, 'Darwin');
      expect(row.worldtidesAtlas, 'Australia');
      expect(row.tideContextPhrase, 'Darwin high tide 6.5 m');
      expect(row.tideContextDataSource, 'WorldTides');
    });
  });

  group('offline behaviour', () {
    test('new catch with WorldTides unavailable records the selected '
        'reference and reports unavailable', () async {
      tides.available = false;

      final result = await service.upsertCalculatedConditionsForCatch(
        _catch(),
        tideReference: TideReferenceService.getReferenceById('darwin'),
      );

      expect(result, TideRecalculationResult.unavailable);

      final row = await service.getEnvironmentalConditionForCatch(7);
      expect(row, isNotNull);
      expect(row!.tideReferenceMode, 'fixed');
      expect(row.tideReferenceName, 'Darwin');
      expect(row.tideContextPhrase, isNull);
      expect(tides.fetchCount, 0);
    });
  });
}
