import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../theme/brand_colors.dart';
import 'package:latlong2/latlong.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';
import '../models/catch_media.dart';
import '../models/fishing_buddy.dart';
import '../models/fishing_trip.dart';
import '../models/favourite_spot.dart';
import '../widgets/bragmat_map_layers.dart';
import '../widgets/catch_summary_sheet.dart';
import '../services/connectivity_service.dart';

class CatchMapScreen extends StatefulWidget {
  final Catch? centerOnCatch;

  /// When non-null, the trip filter is pre-applied on load — used by the
  /// Trip Details map's Expand action so the full-screen map opens
  /// already scoped to that trip.
  final int? initialTripId;

  const CatchMapScreen({super.key, this.centerOnCatch, this.initialTripId});

  @override
  State<CatchMapScreen> createState() => _CatchMapScreenState();
}

class _CatchMapScreenState extends State<CatchMapScreen> {
  List<Catch> _catches = [];
  List<Catch> _filteredCatches = [];
  Map<int, String> _fishingBuddyNames = {};
  Map<int, String> _fishingTripNames = {};
  Map<int, CatchMedia> _primaryMedia = {};
  List<FavouriteSpot> _favouriteSpots = [];
  bool _isLoading = true;
  bool _isOnline = true;
  
  // Filter state
  int? _selectedTripId;
  int? _selectedBuddyId;
  String? _selectedFishType;
  
  // Map controller for programmatic control
  final MapController _mapController = MapController();
  final ConnectivityService _connectivityService = ConnectivityService();

  @override
  void initState() {
    super.initState();
    _selectedTripId = widget.initialTripId;
    _loadData();
    _checkConnectivity();
    _connectivityService.connectivityStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
  }

  Future<void> _checkConnectivity() async {
    final isOnline = await _connectivityService.checkConnection();
    if (mounted) {
      setState(() {
        _isOnline = isOnline;
      });
    }
  }

  Future<void> _loadData() async {
    final catches = await DatabaseHelper.instance.getCatches();
    final buddies = await DatabaseHelper.instance.getFishingBuddies();
    final trips = await DatabaseHelper.instance.getFishingTrips();
    final spots = await DatabaseHelper.instance.getFavouriteSpots();
    
    final buddyMap = {for (var buddy in buddies) buddy.id!: buddy.name};
    final tripMap = {for (var trip in trips) trip.id!: trip.name};
    
    // Load primary media for catches
    final mediaMap = <int, CatchMedia>{};
    for (final catch_ in catches) {
      if (catch_.id != null) {
        final media = await DatabaseHelper.instance.getMediaForCatch(catch_.id!);
        final primary = media.where((m) => m.role == 'primary').firstOrNull;
        if (primary != null) {
          mediaMap[catch_.id!] = primary;
        }
      }
    }

    // Filter catches that have valid coordinates
    final catchesWithCoords = catches.where((c) => 
      c.latitude != null && c.longitude != null
    ).toList();

    if (mounted) {
      setState(() {
        _catches = catchesWithCoords;
        _filteredCatches = catchesWithCoords;
        _fishingBuddyNames = buddyMap;
        _fishingTripNames = tripMap;
        _primaryMedia = mediaMap;
        _favouriteSpots = spots;
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredCatches = _catches.where((c) {
        if (_selectedTripId != null && c.tripId != _selectedTripId) return false;
        if (_selectedBuddyId != null && c.fishingBuddyId != _selectedBuddyId) return false;
        if (_selectedFishType != null) {
          if (_selectedFishType == 'Unidentified') {
            if (c.fishType != null && c.fishType!.isNotEmpty) return false;
          } else {
            if (c.fishType != _selectedFishType) return false;
          }
        }
        return true;
      }).toList();
    });
  }

  void _zoomToAllCatches() {
    if (_filteredCatches.isEmpty) return;
    
    final latitudes = _filteredCatches.map((c) => c.latitude!).toList();
    final longitudes = _filteredCatches.map((c) => c.longitude!).toList();
    
    final minLat = latitudes.reduce((a, b) => a < b ? a : b);
    final maxLat = latitudes.reduce((a, b) => a > b ? a : b);
    final minLng = longitudes.reduce((a, b) => a < b ? a : b);
    final maxLng = longitudes.reduce((a, b) => a > b ? a : b);

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    final zoom = maxDiff > 0 ? (14.0 - (maxDiff * 10)).clamp(2.0, 18.0) : 10.0;

    _mapController.move(LatLng(centerLat, centerLng), zoom);
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Catches'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Fishing Trip'),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _selectedTripId,
                decoration: const InputDecoration(labelText: 'Trip'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Trips')),
                  ..._fishingTripNames.entries.map((entry) {
                    return DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() => _selectedTripId = value);
                },
              ),
              const SizedBox(height: 16),
              const Text('Fishing Buddy'),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _selectedBuddyId,
                decoration: const InputDecoration(labelText: 'Buddy'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Buddies')),
                  ..._fishingBuddyNames.entries.map((entry) {
                    return DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() => _selectedBuddyId = value);
                },
              ),
              const SizedBox(height: 16),
              const Text('Fish Type'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedFishType,
                decoration: const InputDecoration(labelText: 'Fish Type'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Types')),
                  const DropdownMenuItem(value: 'Unidentified', child: Text('Unidentified')),
                  ..._catches.map((c) => c.fishType).where((t) => t != null && t!.isNotEmpty).map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type!),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() => _selectedFishType = value);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedTripId = null;
                _selectedBuddyId = null;
                _selectedFishType = null;
              });
              _applyFilters();
              Navigator.pop(context);
            },
            child: const Text('Clear All'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _applyFilters();
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catch Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Filter',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredCatches.isEmpty
              ? _buildEmptyState()
              // The map renders even offline: the persistent tile cache
              // can serve previously viewed tiles; a banner flags the
              // degraded state instead of removing the map.
              : Stack(
                  children: [
                    _buildMap(),
                    if (!_isOnline) BragmatMapLayers.offlineBanner(),
                  ],
                ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'zoom_all',
            mini: true,
            onPressed: _zoomToAllCatches,
            child: const Icon(Icons.zoom_out_map),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'my_location',
            mini: true,
            onPressed: _showLocationNotAvailable,
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  void _showLocationNotAvailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Device GPS capture will be available in a future update'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _handleMapTap(LatLng point) {
    // Find the nearest catch to the tapped point
    const double tapThreshold = 0.0005; // Approx 50 meters
    
    Catch? nearestCatch;
    double minDistance = tapThreshold;
    
    for (final catch_ in _filteredCatches) {
      final distance = _calculateDistance(
        point.latitude,
        point.longitude,
        catch_.latitude!,
        catch_.longitude!,
      );
      
      if (distance < minDistance) {
        minDistance = distance;
        nearestCatch = catch_;
      }
    }
    
    if (nearestCatch != null) {
      _showCatchDetails(nearestCatch);
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    // Simple Euclidean distance for small distances
    final latDiff = lat2 - lat1;
    final lonDiff = lon2 - lon1;
    return (latDiff * latDiff + lonDiff * lonDiff).abs();
  }

  // Future: Add method to capture current device location
  // Future<void> _captureCurrentLocation() async {
  //   // Use geolocator package to get current position
  //   // final position = await Geolocator.getCurrentPosition();
  //   // _mapController.move(LatLng(position.latitude, position.longitude), 15.0);
  // }

  // Future: Add method to handle map tap for location selection
  // void _onMapTap(TapPosition tapPosition, LatLng point) {
  //   // Could be used to:
  //   // 1. Add a new catch at this location
  //   // 2. Set coordinates for an existing catch
  //   // 3. Mark as favourite fishing location
  // }

  // Future: Add method to render heat map layer
  // Widget _buildHeatMapLayer() {
  //   // Use flutter_map_heatmap or custom circle markers
  //   // to show density of catches in an area
  // }

  // Favourite spots marker
  Widget _buildFavouriteSpotMarker(FavouriteSpot spot) {
    return Container(
      decoration: BoxDecoration(
        color: BrandColors.warmOrange,
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
        Icons.star,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No mapped catches yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add GPS coordinates to catches to see them on the map.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[500],
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    // Calculate center and zoom to fit all markers
    if (_filteredCatches.isEmpty) {
      return const SizedBox.shrink();
    }

    // If centerOnCatch is provided, use those coordinates
    if (widget.centerOnCatch != null && 
        widget.centerOnCatch!.latitude != null && 
        widget.centerOnCatch!.longitude != null) {
      final lat = widget.centerOnCatch!.latitude!;
      final lng = widget.centerOnCatch!.longitude!;
      
      // Validate coordinates
      if (lat.isFinite && lng.isFinite && !lat.isNaN && !lng.isNaN) {
        return FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(lat, lng),
            initialZoom: 15.0,
            minZoom: 2,
            maxZoom: 18,
          ),
          children: [
            BragmatMapLayers.standardOsmTileLayer(),
            MarkerLayer(
              markers: _filteredCatches.map((catch_) {
                return Marker(
                  point: LatLng(catch_.latitude!, catch_.longitude!),
                  width: 40,
                  height: 40,
                  child: _buildMarker(catch_),
                );
              }).toList(),
            ),
            if (_favouriteSpots.isNotEmpty)
              MarkerLayer(
                markers: _favouriteSpots.map((spot) {
                  return Marker(
                    point: LatLng(spot.latitude, spot.longitude),
                    width: 40,
                    height: 40,
                    child: _buildFavouriteSpotMarker(spot),
                  );
                }).toList(),
              ),
            BragmatMapLayers.osmAttribution(),
          ],
        );
      }
    }

    // Otherwise, calculate center and zoom to fit all markers
    final latitudes = _filteredCatches.map((c) => c.latitude!).toList();
    final longitudes = _filteredCatches.map((c) => c.longitude!).toList();
    
    final minLat = latitudes.reduce((a, b) => a < b ? a : b);
    final maxLat = latitudes.reduce((a, b) => a > b ? a : b);
    final minLng = longitudes.reduce((a, b) => a < b ? a : b);
    final maxLng = longitudes.reduce((a, b) => a > b ? a : b);

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    // Calculate appropriate zoom level
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    
    // Simple zoom calculation (not perfect but functional)
    final zoom = maxDiff > 0 ? (14.0 - (maxDiff * 10)).clamp(2.0, 18.0) : 10.0;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(centerLat, centerLng),
        initialZoom: zoom,
        minZoom: 2,
        maxZoom: 18,
      ),
      children: [
        BragmatMapLayers.standardOsmTileLayer(),
        MarkerLayer(
          markers: _filteredCatches.map((catch_) {
            return Marker(
              point: LatLng(catch_.latitude!, catch_.longitude!),
              width: 50,
              height: 50,
              child: _buildMarker(catch_),
            );
          }).toList(),
        ),
        if (_favouriteSpots.isNotEmpty)
          MarkerLayer(
            markers: _favouriteSpots.map((spot) {
              return Marker(
                point: LatLng(spot.latitude, spot.longitude),
                width: 40,
                height: 40,
                child: _buildFavouriteSpotMarker(spot),
              );
            }).toList(),
          ),
        BragmatMapLayers.osmAttribution(),
      ],
    );
  }

  Widget _buildMarker(Catch catch_) {
    return InkWell(
      onTap: () => _showCatchDetails(catch_),
      child: Container(
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
        child: Icon(
          Icons.location_on,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  void _showCatchDetails(Catch catch_) {
    showCatchSummarySheet(
      context, catch_,
      buddyName: catch_.fishingBuddyId != null
          ? _fishingBuddyNames[catch_.fishingBuddyId]
          : null,
      tripName: catch_.tripId != null
          ? _fishingTripNames[catch_.tripId]
          : null,
      primaryMediaPath: catch_.id != null ? _primaryMedia[catch_.id!]?.filePath : null,
    );
  }
}
