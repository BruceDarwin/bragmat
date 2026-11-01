// UX-1B — Trip Details catch-location map tests:
//  - chronological ordering (dated asc, undated last, id tiebreak)
//  - proximity grouping (identical/nearby coords)
//  - numbered + grouped marker rendering
//  - offline banner behaviour
//  - expand control and summary-sheet seam
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bragmat/models/catch.dart' as model;
import 'package:bragmat/widgets/bragmat_map_layers.dart';
import 'package:bragmat/widgets/trip_catch_map.dart';

class _MemoryTileProvider extends TileProvider {
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return MemoryImage(_png);
  }
}

model.Catch _c({
  int? id,
  double lat = -12.4634,
  double lng = 130.8456,
  String fish = 'Barramundi',
  DateTime? caught,
}) =>
    model.Catch(
      id: id,
      fishType: fish,
      lengthCm: 80,
      latitude: lat,
      longitude: lng,
      tripId: 7,
      createdAt: DateTime(2026, 1, 1),
      dateCaught: caught,
      coordinateSource: 'map_selected',
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    BragmatMapLayers.debugTileProvider = _MemoryTileProvider();
  });

  group('Ordering and grouping', () {
    test('chronologicalCatches sorts dated asc, undated last, id tiebreak',
        () {
      final sorted = TripCatchMap.chronologicalCatches([
        _c(id: 3, caught: DateTime(2026, 3, 1)),
        _c(id: 2, caught: DateTime(2026, 1, 1)),
        _c(id: 9), // undated
        _c(id: 1, caught: DateTime(2026, 1, 1)),
      ]);
      expect(sorted.map((c) => c.id).toList(), [1, 2, 3, 9]);
    });

    test('chronologicalCatches excludes invalid/missing coordinates', () {
      final sorted = TripCatchMap.chronologicalCatches([
        _c(id: 1, lat: double.nan),
        model.Catch(
          id: 2,
          fishType: 'X',
          lengthCm: 1,
          createdAt: DateTime(2026),
          tripId: 7,
        ),
        _c(id: 3, caught: DateTime(2026)),
      ]);
      expect(sorted.map((c) => c.id).toList(), [3]);
    });

    test('groupByProximity merges identical and near coords only', () {
      final g = TripCatchMap.groupByProximity([
        _c(id: 1, caught: DateTime(2026)),
        _c(id: 2, caught: DateTime(2026)), // identical to 1
        _c(id: 3, lat: -12.4640, caught: DateTime(2026)), // ~67 m away
        _c(id: 4, lat: -12.50, caught: DateTime(2026)), // ~4 km away
      ]);
      expect(g.length, 2);
      expect(g.first.map((c) => c.id).toList(), [1, 2, 3]);
      expect(g.last.map((c) => c.id).toList(), [4]);
    });
  });

  group('Widget rendering', () {
    testWidgets('renders numbered markers for a multi-catch trip',
        (tester) async {
      await tester.pumpWidget(_wrap(TripCatchMap(
        catches: [
          _c(id: 1, caught: DateTime(2026, 1, 1)),
          _c(id: 2, lat: -13.5, lng: 131.5, caught: DateTime(2026, 1, 2)),
        ],
        tripId: 7,
        tripName: 'Kakadu Run',
      )));
      await tester.pump();

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_full), findsOneWidget);
    });

    testWidgets('grouped catches show a single count marker',
        (tester) async {
      await tester.pumpWidget(_wrap(TripCatchMap(
        catches: [
          _c(id: 1, caught: DateTime(2026, 1, 1)),
          _c(id: 2, caught: DateTime(2026, 1, 2)), // identical coords
        ],
        tripId: 7,
        tripName: 'T',
      )));
      await tester.pump();

      expect(find.text('2+'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('offline shows the cached-imagery banner over the map',
        (tester) async {
      await tester.pumpWidget(_wrap(TripCatchMap(
        catches: [_c(id: 1, caught: DateTime(2026))],
        tripId: 7,
        tripName: 'T',
        isOnline: false,
      )));
      await tester.pump();

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(
          find.text('Offline — map shows cached imagery where available'),
          findsOneWidget);
    });

    testWidgets('no valid coordinates renders nothing', (tester) async {
      await tester.pumpWidget(_wrap(TripCatchMap(
        catches: [
          model.Catch(
              id: 1,
              fishType: 'X',
              lengthCm: 1,
              createdAt: DateTime(2026),
              tripId: 7),
        ],
        tripId: 7,
        tripName: 'T',
      )));
      await tester.pump();
      expect(find.byType(FlutterMap), findsNothing);
    });

    testWidgets('group marker tap lists each catch by sequence number',
        (tester) async {
      await tester.pumpWidget(_wrap(TripCatchMap(
        catches: [
          _c(id: 1, fish: 'Barramundi', caught: DateTime(2026, 1, 1)),
          _c(id: 2, fish: 'Queenfish', caught: DateTime(2026, 1, 2)),
        ],
        tripId: 7,
        tripName: 'T',
      )));
      await tester.pump();
      await tester.tap(find.text('2+'));
      await tester.pumpAndSettle();

      expect(find.text('2 catches at this location'), findsOneWidget);
      expect(find.text('Barramundi'), findsOneWidget);
      expect(find.text('Queenfish'), findsOneWidget);
    });
  });
}
