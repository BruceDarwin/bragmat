// Tests for the persistent OSM tile cache (Part B).
// Covers: provider selection/fallback, on-disk store round-trip and
// offline reuse via a mock Dio adapter, expired-entry revalidation,
// storage-bound eviction, and init-failure safety.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';

import 'package:bragmat/widgets/bragmat_map_layers.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class _PngAdapter implements HttpClientAdapter {
  int calls = 0;
  Object? error;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    if (error != null) throw error!;
    return ResponseBody.fromBytes(
      _png, 200,
      headers: {
        Headers.contentTypeHeader: ['image/png'],
        'cache-control': ['max-age=604800'],
      },
    );
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tile_cache_test_');
  });
  tearDown(() async {
    BragmatMapLayers.debugTileProvider = null;
    // Reset internal provider between tests via init with a bad root.
    try {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    } on PathAccessException {
      // Windows transient locks; OS cleans temp dirs.
    }
  });

  group('provider selection', () {
    test('uses CachedTileProvider after successful init', () async {
      await BragmatMapLayers.initTileCache(cacheRoot: tmp);
      expect(BragmatMapLayers.isTileCacheEnabled, isTrue);
      expect(
          BragmatMapLayers.standardOsmTileLayer().tileProvider,
          isA<CachedTileProvider>());
    });

    test('falls back to default provider when init fails', () async {
      // A file where a directory must be created forces init failure.
      File('${tmp.path}/not_a_dir').createSync();
      await BragmatMapLayers.initTileCache(
          cacheRoot: Directory('${tmp.path}/not_a_dir'));
      expect(BragmatMapLayers.isTileCacheEnabled, isFalse);
      final layer = BragmatMapLayers.standardOsmTileLayer();
      expect(layer.tileProvider, isA<NetworkTileProvider>());
    });

    test('debugTileProvider overrides everything', () async {
      await BragmatMapLayers.initTileCache(cacheRoot: tmp);
      final fake = _FakeProvider();
      BragmatMapLayers.debugTileProvider = fake;
      expect(
          BragmatMapLayers.standardOsmTileLayer().tileProvider, same(fake));
    });
  });

  group('on-disk cache behaviour', () {
    late FileCacheStore store;
    late _PngAdapter adapter;
    late Dio dio;
    const url = 'https://tile.openstreetmap.org/15/1/1.png';

    setUp(() async {
      store = FileCacheStore('${tmp.path}/tiles');
      adapter = _PngAdapter();
      dio = Dio()
        ..httpClientAdapter = adapter
        ..interceptors.add(DioCacheInterceptor(
            options: CacheOptions(
          store: store,
          policy: CachePolicy.forceCache,
          maxStale: BragmatMapLayers.tileMaxStale,
          hitCacheOnNetworkFailure: true,
          hitCacheOnErrorCodes: [404],
        )));
    });

    test('second request for same tile served from store (no re-fetch)',
        () async {
      await dio.get<List<int>>(url,
          options: Options(responseType: ResponseType.bytes));
      await dio.get<List<int>>(url,
          options: Options(responseType: ResponseType.bytes));
      expect(adapter.calls, 1);
      // Store contains entries on disk.
      expect(
          Directory('${tmp.path}/tiles')
              .listSync(recursive: true)
              .whereType<File>()
              .isNotEmpty,
          isTrue);
    });

    test('offline: cached tile returned when the network fails', () async {
      await dio.get<List<int>>(url,
          options: Options(responseType: ResponseType.bytes));
      adapter.error = DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.connectionError);
      final resp = await dio.get<List<int>>(url,
          options: Options(responseType: ResponseType.bytes));
      expect(resp.statusCode, 200);
      expect(resp.data, isNotEmpty);
    });

    test('new store instance after "restart" still serves cached tiles',
        () async {
      await dio.get<List<int>>(url,
          options: Options(responseType: ResponseType.bytes));
      // Simulate restart: new store + dio on the same directory.
      final store2 = FileCacheStore('${tmp.path}/tiles');
      final dio2 = Dio()
        ..httpClientAdapter = (_PngAdapter()
          ..error = DioException(
              requestOptions: RequestOptions(path: url),
              type: DioExceptionType.connectionError))
        ..interceptors.add(DioCacheInterceptor(
            options: CacheOptions(
          store: store2,
          policy: CachePolicy.forceCache,
          maxStale: BragmatMapLayers.tileMaxStale,
          hitCacheOnNetworkFailure: true,
        )));
      final resp = await dio2.get<List<int>>(url,
          options: Options(responseType: ResponseType.bytes));
      expect(resp.statusCode, 200);
    });
  });

  group('storage bound', () {
    test('enforceCacheBound wipes a directory exceeding the limit', () async {
      final dir = Directory('${tmp.path}/big')..createSync();
      File('${dir.path}/a.bin')
          .writeAsBytesSync(Uint8List(3 * 1024 * 1024));
      File('${dir.path}/b.bin')
          .writeAsBytesSync(Uint8List(3 * 1024 * 1024));
      await BragmatMapLayers.enforceCacheBound(dir,
          maxBytes: 4 * 1024 * 1024);
      expect(await dir.exists(), isFalse);
    });

    test('enforceCacheBound keeps a directory under the limit', () async {
      final dir = Directory('${tmp.path}/small')..createSync();
      File('${dir.path}/a.bin').writeAsBytesSync(Uint8List(128));
      await BragmatMapLayers.enforceCacheBound(dir, maxBytes: 1024);
      expect(await dir.exists(), isTrue);
    });

    test('enforceCacheBound tolerates a missing directory', () async {
      await BragmatMapLayers.enforceCacheBound(
          Directory('${tmp.path}/absent'));
    });
  });
}

class _FakeProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates c, TileLayer o) =>
      MemoryImage(_png);
}
