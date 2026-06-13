import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/fishing_trip.dart';
import '../services/current_trip_service.dart';
import 'trip_details_screen.dart';
import 'add_trip_screen.dart';

class FishingTripsScreen extends StatefulWidget {
  const FishingTripsScreen({super.key});

  @override
  State<FishingTripsScreen> createState() => _FishingTripsScreenState();
}

class _FishingTripsScreenState extends State<FishingTripsScreen> {
  List<FishingTrip> _trips = [];
  Map<int, int> _catchCounts = {};
  bool _isLoading = true;
  int? _currentTripId;

  @override
  void initState() {
    super.initState();
    _loadTrips();
    _loadCurrentTrip();
  }

  Future<void> _loadCurrentTrip() async {
    final currentTripId = await CurrentTripService.getCurrentTripId();
    if (mounted) {
      setState(() {
        _currentTripId = currentTripId;
      });
    }
  }

  Future<void> _loadTrips() async {
    final trips = await DatabaseHelper.instance.getFishingTrips();
    
    // Load catch counts for each trip
    final counts = <int, int>{};
    for (final trip in trips) {
      if (trip.id != null) {
        final count = await DatabaseHelper.instance.getCatchCountForTrip(trip.id!);
        counts[trip.id!] = count;
      }
    }
    
    if (mounted) {
      setState(() {
        _trips = trips;
        _catchCounts = counts;
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

  Future<void> _deleteTrip(FishingTrip trip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Trip'),
        content: Text('Are you sure you want to delete ${trip.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && trip.id != null) {
      await DatabaseHelper.instance.deleteFishingTrip(trip.id!);
      // If this was the current trip, clear it
      if (_currentTripId == trip.id) {
        await CurrentTripService.clearCurrentTrip();
        setState(() {
          _currentTripId = null;
        });
      }
      await _loadTrips();
    }
  }

  Future<void> _setCurrentTrip(FishingTrip trip) async {
    if (trip.id != null) {
      await CurrentTripService.setCurrentTrip(trip.id);
      setState(() {
        _currentTripId = trip.id;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${trip.name} set as current trip')),
        );
      }
    }
  }

  Future<void> _clearCurrentTrip() async {
    await CurrentTripService.clearCurrentTrip();
    setState(() {
      _currentTripId = null;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current trip cleared')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fishing Trips'),
        actions: [
          if (_currentTripId != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearCurrentTrip,
              tooltip: 'Clear Current Trip',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTrips,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _trips.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.directions_boat,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No trips yet',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create a fishing trip to organize your catches!',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[500],
                            ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _trips.length,
                  itemBuilder: (context, index) {
                    final trip = _trips[index];
                    final catchCount = trip.id != null ? _catchCounts[trip.id!] ?? 0 : 0;
                    final isCurrentTrip = _currentTripId == trip.id;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: isCurrentTrip ? 4 : 1,
                      color: isCurrentTrip 
                          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                          : null,
                      child: InkWell(
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TripDetailsScreen(trip: trip),
                            ),
                          );
                          if (result == true) {
                            await _loadTrips();
                            await _loadCurrentTrip();
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (isCurrentTrip)
                                    Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'CURRENT',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      trip.name,
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                  if (!isCurrentTrip)
                                    IconButton(
                                      icon: const Icon(Icons.star_border),
                                      onPressed: () => _setCurrentTrip(trip),
                                      tooltip: 'Set as Current Trip',
                                    )
                                  else
                                    IconButton(
                                      icon: const Icon(Icons.star),
                                      onPressed: () => _clearCurrentTrip(),
                                      tooltip: 'Clear Current Trip',
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => _deleteTrip(trip),
                                    tooltip: 'Delete',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 18,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatDateRange(trip.startDate, trip.endDate),
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Colors.grey[600],
                                        ),
                                  ),
                                ],
                              ),
                              if (trip.location != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      size: 18,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        trip.location!,
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: Colors.grey[600],
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.catching_pokemon,
                                    size: 18,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$catchCount catch${catchCount == 1 ? '' : 'es'}',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Colors.grey[600],
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AddTripScreen(),
            ),
          );
          if (result == true) {
            await _loadTrips();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
