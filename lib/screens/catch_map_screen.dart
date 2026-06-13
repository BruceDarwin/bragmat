import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';
import '../models/fishing_buddy.dart';

class CatchMapScreen extends StatefulWidget {
  const CatchMapScreen({super.key});

  @override
  State<CatchMapScreen> createState() => _CatchMapScreenState();
}

class _CatchMapScreenState extends State<CatchMapScreen> {
  List<Catch> _catches = [];
  Map<int, String> _fishingBuddyNames = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final catches = await DatabaseHelper.instance.getCatches();
    final buddies = await DatabaseHelper.instance.getFishingBuddies();
    final buddyMap = {for (var buddy in buddies) buddy.id!: buddy.name};

    // Filter catches that have valid coordinates
    final catchesWithCoords = catches.where((c) => 
      c.latitude != null && c.longitude != null
    ).toList();

    if (mounted) {
      setState(() {
        _catches = catchesWithCoords;
        _fishingBuddyNames = buddyMap;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catch Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _catches.isEmpty
              ? _buildEmptyState()
              : _buildMap(),
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
    if (_catches.isEmpty) {
      return const SizedBox.shrink();
    }

    final latitudes = _catches.map((c) => c.latitude!).toList();
    final longitudes = _catches.map((c) => c.longitude!).toList();
    
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
      options: MapOptions(
        initialCenter: LatLng(centerLat, centerLng),
        initialZoom: zoom,
        minZoom: 2,
        maxZoom: 18,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.bragmat',
        ),
        MarkerLayer(
          markers: _catches.map((catch_) {
            return Marker(
              point: LatLng(catch_.latitude!, catch_.longitude!),
              width: 40,
              height: 40,
              child: _buildMarker(catch_),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMarker(Catch catch_) {
    return GestureDetector(
      onTap: () => _showCatchDetails(catch_),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
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
    final buddyName = catch_.fishingBuddyId != null
        ? _fishingBuddyNames[catch_.fishingBuddyId]
        : null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(catch_.fishType),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(Icons.straighten, '${catch_.lengthCm} cm', 'Length'),
            const SizedBox(height: 8),
            _buildDetailRow(
              Icons.calendar_today,
              _formatDate(catch_.dateCaught ?? catch_.createdAt),
              'Date',
            ),
            if (buddyName != null) ...[
              const SizedBox(height: 8),
              _buildDetailRow(Icons.person, buddyName, 'Caught by'),
            ],
            if (catch_.location != null && catch_.location!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildDetailRow(Icons.place, catch_.location!, 'Location'),
            ],
            const SizedBox(height: 8),
            _buildDetailRow(
              Icons.my_location,
              '${catch_.latitude!.toStringAsFixed(6)}, ${catch_.longitude!.toStringAsFixed(6)}',
              'Coordinates',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String value, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
