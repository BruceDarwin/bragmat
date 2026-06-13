import 'dart:io';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/fishing_trip.dart';
import '../models/catch.dart';
import '../models/fishing_buddy.dart';
import '../models/catch_media.dart';
import 'catch_details_screen.dart';
import 'add_trip_screen.dart';

class TripDetailsScreen extends StatefulWidget {
  final FishingTrip trip;

  const TripDetailsScreen({super.key, required this.trip});

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  late FishingTrip _trip;
  List<Catch> _catches = [];
  Map<int, String> _fishingBuddyNames = {};
  Map<int, String> _primaryMediaPaths = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _loadData();
  }

  Future<void> _loadData() async {
    if (_trip.id == null) return;

    final catches = await DatabaseHelper.instance.getCatchesForTrip(_trip.id!);
    final buddies = await DatabaseHelper.instance.getFishingBuddies();
    final buddyMap = {for (var buddy in buddies) buddy.id!: buddy.name};

    // Load primary media paths for all catches
    final mediaMap = <int, String>{};
    for (final catchItem in catches) {
      if (catchItem.id != null) {
        final primaryMedia = await DatabaseHelper.instance.getPrimaryMediaForCatch(catchItem.id!);
        if (primaryMedia != null) {
          mediaMap[catchItem.id!] = primaryMedia.filePath;
        }
      }
    }

    if (mounted) {
      setState(() {
        _catches = catches;
        _fishingBuddyNames = buddyMap;
        _primaryMediaPaths = mediaMap;
        _isLoading = false;
      });
    }
  }

  String _formatDateRange(DateTime startDate, DateTime? endDate) {
    final start = '${startDate.day}/${startDate.month}/${startDate.year}';
    if (endDate != null) {
      final end = '${endDate.day}/${endDate.month}/${endDate.year}';
      return '$start - $end';
    }
    return start;
  }

  String _getTripStats() {
    if (_catches.isEmpty) return 'No catches';
    
    final totalFish = _catches.length;
    final species = _catches.map((c) => c.fishType).toSet().length;
    final buddies = _catches
        .where((c) => c.fishingBuddyId != null)
        .map((c) => c.fishingBuddyId)
        .toSet()
        .length;
    
    return '$totalFish fish, $species species, $buddies anglers';
  }

  Catch? _getLargestFish() {
    if (_catches.isEmpty) return null;
    return _catches.reduce((a, b) => a.lengthCm > b.lengthCm ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddTripScreen(tripToEdit: _trip),
                ),
              );
              if (result == true) {
                final updatedTrip = await DatabaseHelper.instance.getFishingTrip(_trip.id!);
                if (updatedTrip != null && mounted) {
                  setState(() {
                    _trip = updatedTrip;
                  });
                }
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Trip Info Card
                  Card(
                    margin: const EdgeInsets.all(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _trip.name,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 20,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatDateRange(_trip.startDate, _trip.endDate),
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: Colors.grey[700],
                                    ),
                              ),
                            ],
                          ),
                          if (_trip.location != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 20,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _trip.location!,
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                          color: Colors.grey[700],
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (_trip.notes != null && _trip.notes!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              _trip.notes!,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Stats Card
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trip Statistics',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _getTripStats(),
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          if (_getLargestFish() != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Largest: ${_getLargestFish()!.fishType} (${_getLargestFish()!.lengthCm} cm)',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Catches Section
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Catches (${_catches.length})',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),

                  if (_catches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.catching_pokemon,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No catches yet',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _catches.length,
                      itemBuilder: (context, index) {
                        final catchItem = _catches[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CatchDetailsScreen(catchItem: catchItem),
                                ),
                              );
                              if (result == true) {
                                await _loadData();
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  if (_primaryMediaPaths[catchItem.id] != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        File(_primaryMediaPaths[catchItem.id]!),
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            width: 60,
                                            height: 60,
                                            decoration: BoxDecoration(
                                              color: Colors.grey[300],
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(Icons.image_not_supported),
                                          );
                                        },
                                      ),
                                    )
                                  else
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[300],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.image_not_supported),
                                    ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          catchItem.fishType,
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${catchItem.lengthCm} cm',
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                color: Colors.grey[600],
                                              ),
                                        ),
                                        if (catchItem.fishingBuddyId != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Caught by ${_fishingBuddyNames[catchItem.fishingBuddyId] ?? 'Unknown'}',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Colors.grey[500],
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}
