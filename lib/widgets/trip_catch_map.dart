/// Embedded catch-locations map for Trip Details (UX-1B).
///
/// - Shows every catch of the trip that has valid recorded coordinates,
///   as numbered markers in chronological order (dateCaught ascending;
///   missing timestamps sort last; ties broken by catch id so numbering
///   is deterministic).
/// - Catches within [_groupToleranceDegrees] (~111 m) are collapsed into
///   one grouped marker showing the member count; tapping it lists each
///   catch individually. Grouping is by geographic proximity, not screen
///   pixels, so zooming in does NOT split a group — identical spots stay
///   grouped but each member remains selectable.
/// - The viewport uses CameraFit.bounds over every catch location; no
///   catch is ever excluded to increase zoom.
/// - Pan/zoom gestures never navigate; the expand button opens the
///   shared CatchMapScreen with the trip filter pre-applied.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../helpers/coordinate_validation.dart';
import '../models/catch.dart';
import '../screens/catch_map_screen.dart';
import 'bragmat_map_layers.dart';
import 'catch_summary_sheet.dart';

class TripCatchMap extends StatelessWidget {
  /// The trip's catches (all of them — this widget filters to those with
  /// valid coordinates).
  final List<Catch> catches;
  final int tripId;
  final String tripName;
  final Map<int, String> primaryMediaByCatch;
  final Map<int, String> buddyNames;
  final bool isOnline;

  /// Geographic grouping tolerance in degrees (~111 m at the equator).
  static const double groupToleranceDegrees = 0.001;

  const TripCatchMap({
    super.key,
    required this.catches,
    required this.tripId,
    required this.tripName,
    this.primaryMediaByCatch = const {},
    this.buddyNames = const {},
    this.isOnline = true,
    this.height = 220,
  });

  final double height;

  /// Catches of the trip with displayable coordinates, sorted
  /// chronologically (dateCaught asc, nulls last, catch id tiebreak) —
  /// the ordering the numbered markers display.
  static List<Catch> chronologicalCatches(Iterable<Catch> catches) {
    final list = catches
        .where((c) => hasValidMapCoordinates(c.latitude, c.longitude))
        .toList();
    list.sort((a, b) {
      final at = a.dateCaught ?? a.createdAt;
      final bt = b.dateCaught ?? b.createdAt;
      final am = a.dateCaught == null ? 1 : 0;
      final bm = b.dateCaught == null ? 1 : 0;
      if (am != bm) return am - bm; // dated before undated
      final t = at.compareTo(bt);
      if (t != 0) return t;
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });
    return list;
  }

  /// Groups sorted catches by coordinate proximity. Each catch joins the
  /// first existing group within [groupToleranceDegrees] in BOTH axes —
  /// greedy and deterministic given the stable sorted input.
  static List<List<Catch>> groupByProximity(List<Catch> sorted) {
    final groups = <List<Catch>>[];
    for (final c in sorted) {
      var placed = false;
      for (final g in groups) {
        final ref = g.first;
        if ((c.latitude! - ref.latitude!).abs() < groupToleranceDegrees &&
            (c.longitude! - ref.longitude!).abs() < groupToleranceDegrees) {
          g.add(c);
          placed = true;
          break;
        }
      }
      if (!placed) groups.add([c]);
    }
    return groups;
  }

  int _sequenceOf(List<Catch> sorted, Catch c) => sorted.indexOf(c) + 1;

  void _openFullScreenMap(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CatchMapScreen(initialTripId: tripId),
      ),
    );
  }

  void _showCatch(BuildContext context, List<Catch> sorted, Catch c) {
    showCatchSummarySheet(
      context, c,
      tripName: tripName,
      buddyName:
          c.fishingBuddyId != null ? buddyNames[c.fishingBuddyId] : null,
      primaryMediaPath: c.id != null ? primaryMediaByCatch[c.id!] : null,
      sequenceLabel: 'Catch ${_sequenceOf(sorted, c)} of ${sorted.length}',
    );
  }

  void _showGroup(BuildContext context, List<Catch> sorted, List<Catch> g) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${g.length} catches at this location',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final c in g)
              ListTile(
                leading: CircleAvatar(
                  radius: 12,
                  child: Text('${_sequenceOf(sorted, c)}',
                      style: const TextStyle(fontSize: 12)),
                ),
                title: Text(c.fishType?.isEmpty ?? true
                    ? 'Unidentified'
                    : c.fishType!),
                subtitle: Text(
                    '${c.dateCaught ?? c.createdAt}'.substring(0, 10)),
                onTap: () {
                  Navigator.pop(context);
                  _showCatch(context, sorted, c);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = chronologicalCatches(catches);
    if (sorted.isEmpty) return const SizedBox.shrink();

    final groups = groupByProximity(sorted);
    final bounds = LatLngBounds.fromPoints(
      sorted.map((c) => LatLng(c.latitude!, c.longitude!)).toList(),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCameraFit: sorted.length == 1
                    ? CameraFit.insideBounds(
                        bounds: bounds,
                        padding: const EdgeInsets.all(60),
                        minZoom: 15,
                        maxZoom: 15,
                      )
                    : CameraFit.bounds(
                        bounds: bounds,
                        padding: const EdgeInsets.all(60),
                      ),
                minZoom: 2,
                maxZoom: 18,
              ),
              children: [
                BragmatMapLayers.standardOsmTileLayer(),
                MarkerLayer(
                  markers: [
                    for (final g in groups)
                      Marker(
                        point: LatLng(
                          g.first.latitude!,
                          g.first.longitude!,
                        ),
                        width: 44,
                        height: 44,
                        child: g.length == 1
                            ? _NumberedMarker(
                                number: _sequenceOf(sorted, g.first),
                                onTap: () =>
                                    _showCatch(context, sorted, g.first),
                              )
                            : _GroupMarker(
                                count: g.length,
                                onTap: () => _showGroup(context, sorted, g),
                              ),
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
                  onPressed: () => _openFullScreenMap(context),
                ),
              ),
            ),
            if (!isOnline) BragmatMapLayers.offlineBanner(bottom: 0),
          ],
        ),
      ),
    );
  }
}

class _NumberedMarker extends StatelessWidget {
  final int number;
  final VoidCallback onTap;
  const _NumberedMarker({required this.number, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 4)
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          '$number',
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14),
        ),
      ),
    );
  }
}

class _GroupMarker extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _GroupMarker({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 4)
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          '$count+',
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12),
        ),
      ),
    );
  }
}
