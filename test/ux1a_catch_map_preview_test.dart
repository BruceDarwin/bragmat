// Widget tests for the UX-1A embedded catch-location map preview and its
// integration into CatchDetailsScreen.
//
// Covers:
//  - preview renders FlutterMap + marker + attribution + expand control
//    for a catch with valid coordinates
//  - preview renders nothing for missing/invalid coordinates
//  - offline state keeps the map (cached tiles) with a non-blocking banner
//  - tile-load failure surfaces a non-blocking banner
//  - expand control navigates to the full-screen CatchMapScreen
//  - Catch Details Location card shows the preview, coordinates and the
//    resolved coordinate-source label (canonical + legacy values)

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/models/catch.dart' as model;
import 'package:bragmat/screens/catch_details_screen.dart';
import 'package:bragmat/screens/catch_map_screen.dart';
import 'package:bragmat/screens/location_picker_screen.dart';
import 'package:bragmat/widgets/bragmat_map_layers.dart';
import 'package:bragmat/widgets/catch_location_map_preview.dart';

const _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

/// Serves a 1x1 transparent PNG for every tile request so map widgets can
/// be exercised in tests without network access.
class _MemoryTileProvider extends TileProvider {
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return MemoryImage(_png);
  }
}

model.Catch _catchWith({
  double? latitude = -12.4634,
  double? longitude = 130.8456,
  String? coordinateSource = 'device_gps',
  String? location,
}) {
  return model.Catch(
    fishType: 'Barramundi',
    lengthCm: 55,
    createdAt: DateTime(2026, 10, 1, 9, 45),
    dateCaught: DateTime(2026, 9, 30, 16, 20),
    latitude: latitude,
    longitude: longitude,
    location: location,
    coordinateSource: coordinateSource,
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: Center(child: child)));
}

void _mockConnectivity(TestWidgetsFlutterBinding binding) {
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _connectivityChannel,
    (call) async => ['wifi'],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testDir =
        await Directory.systemTemp.createTemp('ux1a_map_preview_test_');
    DatabaseHelper.setTestDatabasePath(p.join(testDir.path, 'bragmat.db'));
    BragmatMapLayers.debugTileProvider = _MemoryTileProvider();
    _mockConnectivity(TestWidgetsFlutterBinding.instance);
  });

  tearDown(() async {
    BragmatMapLayers.debugTileProvider = null;
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivityChannel, null);
    try {
      if (await testDir.exists()) await testDir.delete(recursive: true);
    } on PathAccessException {
      // Windows transient file locks; OS cleans temp dirs.
    }
  });

  group('CatchLocationMapPreview', () {
    testWidgets('renders map, marker, attribution and expand control',
        (tester) async {
      await tester.pumpWidget(_wrap(
        CatchLocationMapPreview(catchItem: _catchWith()),
      ));
      await tester.pump();

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(MarkerLayer), findsOneWidget);
      expect(find.byType(SimpleAttributionWidget), findsOneWidget);
      expect(find.text('OpenStreetMap contributors'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_full), findsOneWidget);
    });

    testWidgets('renders nothing when coordinates are missing', (tester) async {
      await tester.pumpWidget(_wrap(
        CatchLocationMapPreview(
          catchItem: _catchWith(latitude: null, longitude: null),
        ),
      ));
      await tester.pump();
      expect(find.byType(FlutterMap), findsNothing);
    });

    testWidgets('renders nothing when coordinates are out of range',
        (tester) async {
      await tester.pumpWidget(_wrap(
        CatchLocationMapPreview(
          catchItem: _catchWith(latitude: 91.0, longitude: 130.8456),
        ),
      ));
      await tester.pump();
      expect(find.byType(FlutterMap), findsNothing);
    });

    testWidgets('renders map for the 0,0 coordinate', (tester) async {
      await tester.pumpWidget(_wrap(
        CatchLocationMapPreview(
          catchItem: _catchWith(latitude: 0.0, longitude: 0.0),
        ),
      ));
      await tester.pump();
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets('offline keeps the map and shows a banner', (tester) async {
      await tester.pumpWidget(_wrap(
        CatchLocationMapPreview(
          catchItem: _catchWith(),
          isOnline: false,
        ),
      ));
      await tester.pump();

      // The map (marker, attribution, expand) stays rendered; only cached
      // tiles will display, flagged by a non-blocking banner.
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(MarkerLayer), findsOneWidget);
      expect(find.byIcon(Icons.open_in_full), findsOneWidget);
      expect(
          find.text('Offline — map shows cached imagery where available'),
          findsOneWidget);
    });

    testWidgets('reconnection removes the offline banner', (tester) async {
      await tester.pumpWidget(_wrap(
        CatchLocationMapPreview(
          catchItem: _catchWith(),
          isOnline: false,
        ),
      ));
      await tester.pump();
      expect(
          find.text('Offline — map shows cached imagery where available'),
          findsOneWidget);

      await tester.pumpWidget(_wrap(
        CatchLocationMapPreview(
          catchItem: _catchWith(),
          isOnline: true,
        ),
      ));
      await tester.pump();
      expect(
          find.text('Offline — map shows cached imagery where available'),
          findsNothing);
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets('tile failure shows a non-blocking banner over the map',
        (tester) async {
      await tester.pumpWidget(_wrap(
        CatchLocationMapPreview(
          catchItem: _catchWith(),
          debugTileLoadFailed: true,
        ),
      ));
      await tester.pump();

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('Some map tiles could not be loaded'), findsOneWidget);
    });

    testWidgets('expand control pushes the full-screen CatchMapScreen',
        (tester) async {
      await tester.pumpWidget(_wrap(
        CatchLocationMapPreview(catchItem: _catchWith()),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.open_in_full));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CatchMapScreen), findsOneWidget);
    });
  });

  group('CatchDetailsScreen location card', () {
    Future<void> openDetails(
        WidgetTester tester, model.Catch catchItem) async {
      await tester.runAsync(() async {
        await DatabaseHelper.instance.database;
      });
      await tester.pumpWidget(
          MaterialApp(home: CatchDetailsScreen(catchItem: catchItem)));
      await tester.pump();
      // Let the async DB loaders (buddy, media, env, connectivity) settle.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    testWidgets('shows map preview, coordinates and canonical source label',
        (tester) async {
      await openDetails(tester, _catchWith(location: 'Dundee Beach'));

      expect(find.text('Location'), findsWidgets);
      expect(find.byType(CatchLocationMapPreview), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('-12.463400, 130.845600'), findsOneWidget);
      expect(find.text('Coordinate Source'), findsOneWidget);
      expect(find.text('Device GPS'), findsOneWidget);
      expect(find.text('Dundee Beach'), findsWidgets);
    });

    testWidgets('shows no map when the catch has no coordinates',
        (tester) async {
      await openDetails(
        tester,
        _catchWith(
            latitude: null, longitude: null, location: 'Dundee Beach'),
      );

      expect(find.byType(FlutterMap), findsNothing);
      expect(find.text('GPS Coordinates'), findsNothing);
      expect(find.text('Dundee Beach'), findsWidgets);
    });

    testWidgets('legacy stored source strings display as labels',
        (tester) async {
      await openDetails(
        tester,
        _catchWith(coordinateSource: 'Map Selected'),
      );

      expect(find.text('Coordinate Source'), findsOneWidget);
      expect(find.text('Map Selected'), findsOneWidget);
    });
  });

  group('Offline map surfaces (D1)', () {
    void mockOffline() {
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        _connectivityChannel,
        (call) async => ['none'],
      );
    }

    void mockOnline() {
      _mockConnectivity(TestWidgetsFlutterBinding.instance);
    }

    testWidgets('CatchMapScreen keeps map, markers and banner offline',
        (tester) async {
      mockOffline();
      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        await db.insert('catches', _catchWith().toMap());
      });
      await tester.pumpWidget(const MaterialApp(home: CatchMapScreen()));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester
            .runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(MarkerLayer), findsWidgets);
      expect(
          find.text('Offline — map shows cached imagery where available'),
          findsOneWidget);
      expect(find.byType(SimpleAttributionWidget), findsOneWidget);
      // No full-screen offline fallback: markers/FABs remain.
      expect(find.text('Map tiles unavailable'), findsNothing);
      // Flush the 10s offline-debounce timer before the test ends.
      await tester.pump(const Duration(seconds: 11));
      mockOnline();
    });

    testWidgets('LocationPicker offline: map, manual entry and select',
        (tester) async {
      mockOffline();
      // Initial coordinates skip the geolocator fetch (which schedules a
      // platform-timeout timer unavailable in tests).
      await tester.pumpWidget(const MaterialApp(
          home: LocationPickerScreen(
              initialLatitude: -12.4634, initialLongitude: 130.8456)));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester
            .runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(
          find.text('Offline — map shows cached imagery where available'),
          findsOneWidget);
      // Manual coordinate entry is offered offline.
      expect(find.text('Or enter coordinates:'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Latitude'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Longitude'), findsOneWidget);

      // Tap-to-select still works offline and enables Confirm.
      final mapCenter = tester.getCenter(find.byType(FlutterMap));
      await tester.tapAt(mapCenter);
      await tester.pump();
      expect(find.text('Selected Location:'), findsOneWidget);
      expect(
          tester
              .widget<ElevatedButton>(find.widgetWithText(
                  ElevatedButton, 'Confirm'))
              .onPressed,
          isNotNull);
      // Flush the 10s offline-debounce timer before the test ends.
      await tester.pump(const Duration(seconds: 11));
      mockOnline();
    });
  });
}
