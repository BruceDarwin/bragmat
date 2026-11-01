import 'dart:io';

import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared OpenStreetMap layer configuration for every map surface in the
/// app. Centralising the tile URL, identifying User-Agent and the licence
/// attribution keeps all screens consistent and OSM Tile Usage Policy
/// compliant:
///
/// - `userAgentPackageName` produces `User-Agent: flutter_map
///   (com.bragmat.app)` on tile requests, identifying the application.
/// - [osmAttribution] renders permanent, visible '© OpenStreetMap
///   contributors' text in the corner of the map, linking to the OSM
///   copyright page.
class BragmatMapLayers {
  BragmatMapLayers._();

  /// Test seam: when non-null, every shared tile layer uses this provider
  /// instead of the default network provider, so widget tests can serve
  /// local tiles without touching the network.
  @visibleForTesting
  static TileProvider? debugTileProvider;

  /// Maximum age a cached tile is served without revalidation, matching
  /// the OSM Tile Usage Policy's minimum 7-day local-cache requirement.
  static const Duration tileMaxStale = Duration(days: 7);

  /// Upper bound for the on-disk tile cache. Exceeding it at startup
  /// clears the store entirely — a coarse but safe bound for a cache
  /// whose contents are always re-downloadable.
  static const int maxTileCacheBytes = 64 * 1024 * 1024; // 64 MB

  static CachedTileProvider? _cachedProvider;
  static CacheStore? _cacheStore;

  /// Whether the persistent tile cache is active.
  static bool get isTileCacheEnabled => _cachedProvider != null;

  /// The active store (visible for tests).
  @visibleForTesting
  static CacheStore? get cacheStore => _cacheStore;

  /// Initialise the persistent OSM tile cache. Call once at startup; any
  /// failure leaves [_cachedProvider] null and the default network
  /// provider is used — map display is never blocked by cache problems.
  static Future<void> initTileCache({Directory? cacheRoot}) async {
    try {
      final root =
          cacheRoot ?? await getApplicationCacheDirectory();
      final dir = Directory(p.join(root.path, 'bragmat_tiles'));
      await dir.create(recursive: true);
      await enforceCacheBound(dir);
      final store = FileCacheStore(dir.path);
      _cacheStore = store;
      _cachedProvider = CachedTileProvider(
        store: store,
        maxStale: tileMaxStale,
        // Serve the cached copy on any network failure, not just 404s —
        // previously viewed tiles stay available offline.
        hitCacheOnNetworkFailure: true,
      );
    } catch (e) {
      debugPrint('Tile cache init failed; using uncached tiles: $e');
      _cacheStore = null;
      _cachedProvider = null;
    }
  }

  /// Clears the on-disk tile cache (also the bound-eviction path).
  static Future<void> clearTileCache() async {
    try {
      await _cacheStore?.clean();
    } catch (_) {}
  }

  /// If the cache directory already exceeds [maxTileCacheBytes], wipe it.
  /// Tiles are public, re-downloadable data — a full reset is the safest
  /// eviction and cannot corrupt in-flight state (runs before store open).
  @visibleForTesting
  static Future<void> enforceCacheBound(Directory dir,
      {int maxBytes = maxTileCacheBytes}) async {
    if (!await dir.exists()) return;
    var total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
        if (total > maxBytes) {
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
          return;
        }
      }
    }
  }

  /// Standard OpenStreetMap raster tile layer.
  ///
  /// [onTileError] is forwarded to [TileLayer.errorTileCallback] so callers
  /// can surface tile-load failures without depending solely on
  /// connectivity detection.
  static TileLayer standardOsmTileLayer({ErrorTileCallBack? onTileError}) {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.bragmat.app',
      errorTileCallback: onTileError,
      tileProvider: debugTileProvider ?? _cachedProvider,
    );
  }

  /// Non-blocking banner shown over a map while the device is offline.
  /// The wording is deliberately cautious — only tiles already in the
  /// persistent cache render while offline; missing tiles appear as
  /// blank cells rather than implying a complete offline map.
  /// [bottom] positions the banner above the bottom edge (0 = pinned to
  /// the bottom of the map, as used by the embedded preview).
  static Positioned offlineBanner({double? bottom}) {
    return Positioned(
      bottom: bottom ?? 8,
      left: 8,
      right: 8,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.orange.shade50.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 16, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Offline — map shows cached imagery where available',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Permanent '© OpenStreetMap contributors' attribution (bottom-right).
  static Widget osmAttribution() {
    return SimpleAttributionWidget(
      source: const Text('OpenStreetMap contributors'),
      onTap: () => launchUrl(
        Uri.parse('https://www.openstreetmap.org/copyright'),
        mode: LaunchMode.externalApplication,
      ),
    );
  }
}
