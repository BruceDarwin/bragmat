import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../helpers/coordinate_validation.dart';
import '../models/catch.dart';
import '../screens/catch_map_screen.dart';
import 'bragmat_map_layers.dart';

/// Embedded map preview of a catch's recorded location, shown inside the
/// Catch Details Location card.
///
/// Behaviour:
/// - Renders nothing when the catch has no valid coordinates.
/// - Pan and zoom are enabled; the map itself never navigates — the
///   explicit expand button opens the existing full-screen map.
/// - When [isOnline] is false an offline notice replaces the map so the
///   location data in the surrounding card remains accessible.
/// - Individual tile-load failures are surfaced via a subtle banner while
///   the map (and any loaded tiles) stays visible.
class CatchLocationMapPreview extends StatefulWidget {
  final Catch catchItem;
  final bool isOnline;
  final double height;

  const CatchLocationMapPreview({
    super.key,
    required this.catchItem,
    this.isOnline = true,
    this.height = 200,
    @visibleForTesting this.debugTileLoadFailed = false,
  });

  /// Test seam: start in the tile-failure state without requiring a real
  /// network error.
  final bool debugTileLoadFailed;

  /// Whether the catch's coordinates are safe to display on a map.
  static bool hasValidCoordinates(Catch catchItem) {
    return hasValidMapCoordinates(catchItem.latitude, catchItem.longitude);
  }

  @override
  State<CatchLocationMapPreview> createState() =>
      _CatchLocationMapPreviewState();
}

class _CatchLocationMapPreviewState extends State<CatchLocationMapPreview> {
  late bool _tileLoadFailed = widget.debugTileLoadFailed;

  void _openFullScreenMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CatchMapScreen(centerOnCatch: widget.catchItem),
      ),
    );
  }

  void _onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    if (mounted && !_tileLoadFailed) {
      setState(() => _tileLoadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!CatchLocationMapPreview.hasValidCoordinates(widget.catchItem)) {
      return const SizedBox.shrink();
    }

    if (!widget.isOnline) {
      return _buildOfflineNotice(context);
    }

    final center = LatLng(
      widget.catchItem.latitude!,
      widget.catchItem.longitude!,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 15.0,
                minZoom: 2,
                maxZoom: 18,
              ),
              children: [
                BragmatMapLayers.standardOsmTileLayer(
                  onTileError: _onTileError,
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: center,
                      width: 40,
                      height: 40,
                      child: _buildMarker(context),
                    ),
                  ],
                ),
                BragmatMapLayers.osmAttribution(),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                elevation: 2,
                child: IconButton(
                  icon: const Icon(Icons.open_in_full),
                  tooltip: 'Expand Map',
                  onPressed: _openFullScreenMap,
                ),
              ),
            ),
            if (_tileLoadFailed)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.orange.shade100.withValues(alpha: 0.95),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off,
                          size: 16, color: Colors.orange.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Some map tiles could not be loaded',
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
          ],
        ),
      ),
    );
  }

  Widget _buildMarker(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(
        Icons.location_on,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  Widget _buildOfflineNotice(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off,
            size: 20,
            color: Colors.orange.shade700,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Map imagery unavailable while offline',
              style: TextStyle(
                fontSize: 14,
                color: Colors.orange.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
