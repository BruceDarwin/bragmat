import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
      tileProvider: debugTileProvider,
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
