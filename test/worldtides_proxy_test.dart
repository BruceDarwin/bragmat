// Unit tests for the WT2 proxy path in WorldTidesService.
//
// All network access is replaced by test seams (httpGetForTesting /
// proxyFetchForTesting / proxySessionForTesting) — no real WorldTides or
// Supabase traffic is made, and no API credits are consumed.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/services/worldtides_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;
  late WorldTidesService service;

  // Mocked flutter_secure_storage backing store.
  final secureChannel =
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String?> secureStore = {};

  // Observability
  Uri? lastHttpUrl;
  int httpCalls = 0;
  int proxyCalls = 0;
  Map<String, dynamic>? lastProxyArgs;
  Map<String, dynamic>? proxyResult;
  http.Response? httpResult;

  Map<String, dynamic> tidePayload(DateTime obs) => {
        'status': 200,
        'atlas': 'FES2022',
        'responseLat': -12.45,
        'responseLon': 130.84,
        'extremes': [
          {
            'type': 'High',
            'date': obs.subtract(const Duration(hours: 2)).toUtc().toIso8601String(),
            'height': 6.4,
          },
          {
            'type': 'Low',
            'date': obs.add(const Duration(hours: 4)).toUtc().toIso8601String(),
            'height': 1.1,
          },
        ],
      };

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testDir = Directory.systemTemp.createTempSync('bragmat_wt2_test_');
    DatabaseHelper.setTestDatabasePath(p.join(testDir.path, 'bragmat.db'));
    service = WorldTidesService();

    httpCalls = 0;
    proxyCalls = 0;
    lastHttpUrl = null;
    lastProxyArgs = null;
    proxyResult = null;
    httpResult = null;

    WorldTidesService.httpGetForTesting = (url) async {
      httpCalls++;
      lastHttpUrl = url;
      return httpResult ?? http.Response('', 500);
    };
    WorldTidesService.proxyFetchForTesting = ({
      required double latitude,
      required double longitude,
      required String date,
    }) async {
      proxyCalls++;
      lastProxyArgs = {'lat': latitude, 'lon': longitude, 'date': date};
      return proxyResult;
    };
    WorldTidesService.proxySessionForTesting = null;

    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
      final args = (call.arguments as Map?)?.cast<dynamic, dynamic>() ?? {};
      switch (call.method) {
        case 'read':
          return secureStore[args['key']];
        case 'write':
          secureStore[args['key'] as String] = args['value'] as String?;
          return null;
        case 'delete':
          secureStore.remove(args['key']);
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    WorldTidesService.httpGetForTesting = null;
    WorldTidesService.proxyFetchForTesting = null;
    WorldTidesService.proxySessionForTesting = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    if (await testDir.exists()) await testDir.delete(recursive: true);
  });

  final obs = DateTime(2026, 10, 20, 10, 0);
  const lat = -12.4634;
  const lon = 130.8446;

  group('proxy path — authenticated beta user without a local key', () {
    test('available via proxy session; proxies fetch and caches result',
        () async {
      WorldTidesService.proxySessionForTesting = true;
      proxyResult = tidePayload(obs);

      expect(await service.isAvailable(), isTrue);
      final ctx =
          await service.getTideContextForLocation(lat, lon, obs);
      expect(ctx, isNotNull);
      expect(proxyCalls, 1);
      expect(httpCalls, 0); // direct API never touched
      expect(lastProxyArgs, {'lat': lat, 'lon': lon, 'date': '2026-10-20'});
      expect(ctx!['tideContextDataSource'], 'WorldTides');

      // Second identical request must be served by the SQLite cache —
      // no repeat chargeable call.
      final again =
          await service.getTideContextForLocation(lat, lon, obs);
      expect(again, isNotNull);
      expect(proxyCalls, 1);
    });

    test('proxy rejection (403/429 surfaced as null) degrades gracefully',
        () async {
      WorldTidesService.proxySessionForTesting = true;
      proxyResult = null; // function returned an error status

      final ctx =
          await service.getTideContextForLocation(lat, lon, obs);
      expect(ctx, isNull);
      expect(proxyCalls, 1);
    });

    test('proxy fetcher throwing does not propagate', () async {
      WorldTidesService.proxySessionForTesting = true;
      WorldTidesService.proxyFetchForTesting = ({
        required double latitude,
        required double longitude,
        required String date,
      }) async =>
          throw StateError('simulated network failure');

      expect(await service.getTideContextForLocation(lat, lon, obs), isNull);
    });

    test('malformed proxy payload returns null without caching', () async {
      WorldTidesService.proxySessionForTesting = true;
      proxyResult = {'status': 200, 'extremes': <dynamic>[]};

      expect(await service.getTideContextForLocation(lat, lon, obs), isNull);
      expect(
        await DatabaseHelper.instance
            .getCachedTideData(lat, lon, '2026-10-20'),
        isNull,
      );
    });
  });

  group('local key path — direct integration preserved', () {
    test('a stored key uses the direct API and never touches the proxy',
        () async {
      secureStore['worldtides_api_key'] = 'TESTKEY0000';
      WorldTidesService.proxySessionForTesting = true;
      httpResult = http.Response(jsonEncode(tidePayload(obs)), 200);

      expect(await service.isAvailable(), isTrue);
      final ctx =
          await service.getTideContextForLocation(lat, lon, obs);
      expect(ctx, isNotNull);
      expect(httpCalls, 1);
      expect(proxyCalls, 0);
      expect(lastHttpUrl.toString(), contains('extremes'));
      expect(lastHttpUrl.toString(), contains('days=3'));
      expect(lastHttpUrl.toString(), contains('datum=CD'));
    });

    test('direct API 401 fails gracefully', () async {
      secureStore['worldtides_api_key'] = 'TESTKEY0000';
      httpResult = http.Response('unauthorized', 401);

      expect(await service.getTideContextForLocation(lat, lon, obs), isNull);
      expect(proxyCalls, 0);
    });
  });

  group('no key and no session', () {
    test('not available; no fetch attempted', () async {
      WorldTidesService.proxySessionForTesting = false;

      expect(await service.isAvailable(), isFalse);
      expect(await service.getTideContextForLocation(lat, lon, obs), isNull);
      expect(proxyCalls, 0);
      expect(httpCalls, 0);
    });
  });
}
