import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/connectivity_service.dart';
import '../widgets/bragmat_map_layers.dart';

class LocationPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  const LocationPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _mapController = MapController();
  LatLng? _selectedLocation;
  bool _isLoading = true;
  bool _isOnline = true;
  final ConnectivityService _connectivityService = ConnectivityService();

  @override
  void initState() {
    super.initState();
    _initializeLocation();
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

  Future<void> _initializeLocation() async {
    LatLng initialCenter;

    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      // Use existing catch coordinates
      initialCenter = LatLng(widget.initialLatitude!, widget.initialLongitude!);
      _selectedLocation = initialCenter;
    } else {
      // Try to get current device location
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        initialCenter = LatLng(position.latitude, position.longitude);
        _selectedLocation = initialCenter;
      } catch (e) {
        // Default to a sensible location (e.g., center of Australia)
        initialCenter = const LatLng(-25.2744, 133.7751);
        _selectedLocation = initialCenter;
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      
      // Move map to initial center after a short delay to ensure controller is ready
      Future.delayed(const Duration(milliseconds: 100), () {
        _mapController.move(initialCenter, 15.0);
      });
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _selectedLocation = point;
    });
  }

  void _confirmLocation() {
    if (_selectedLocation != null) {
      Navigator.pop(context, {
        'latitude': _selectedLocation!.latitude,
        'longitude': _selectedLocation!.longitude,
      });
    }
  }

  void _cancel() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Location'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _selectedLocation != null ? _confirmLocation : null,
            tooltip: 'Confirm',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          // The map renders even offline: the persistent tile cache can
          // serve previously viewed tiles; a banner flags the degraded
          // state instead of removing the map, and tap-to-select plus
          // manual coordinate entry stay usable.
          : Stack(
              children: [
                _buildOnlineMap(),
                if (!_isOnline) BragmatMapLayers.offlineBanner(),
              ],
            ),
    );
  }

  Widget _buildOnlineMap() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _selectedLocation ?? const LatLng(-25.2744, 133.7751),
            initialZoom: 15.0,
            minZoom: 2,
            maxZoom: 18,
            onTap: _onMapTap,
          ),
          children: [
            BragmatMapLayers.standardOsmTileLayer(),
            if (_selectedLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selectedLocation!,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
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
                  ),
                ],
              ),
            BragmatMapLayers.osmAttribution(),
          ],
        ),
        Positioned(
          bottom: 20,
          left: 16,
          right: 16,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedLocation != null) ...[
                    Text(
                      'Selected Location:',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lat: ${_selectedLocation!.latitude.toStringAsFixed(6)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      'Lng: ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ] else
                    const Text('Tap on the map to select a location'),
                  if (!_isOnline) ...[
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Or enter coordinates:',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        hintText: '-12.4604',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      onChanged: (value) {
                        final lat = double.tryParse(value);
                        if (lat == null) return;
                        setState(() {
                          _selectedLocation = LatLng(
                            lat,
                            _selectedLocation?.longitude ?? 133.7751,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        hintText: '130.8412',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      onChanged: (value) {
                        final lng = double.tryParse(value);
                        if (lng == null) return;
                        setState(() {
                          _selectedLocation = LatLng(
                            _selectedLocation?.latitude ?? -25.2744,
                            lng,
                          );
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _cancel,
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _selectedLocation != null ? _confirmLocation : null,
                          child: const Text('Confirm'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

}
