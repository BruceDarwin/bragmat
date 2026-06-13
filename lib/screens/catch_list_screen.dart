import 'dart:io';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';
import '../services/current_trip_service.dart';
import 'catch_details_screen.dart';

class CatchListScreen extends StatefulWidget {
  const CatchListScreen({super.key});

  @override
  State<CatchListScreen> createState() => _CatchListScreenState();
}

class _CatchListScreenState extends State<CatchListScreen> {
  List<Catch> _catches = [];
  List<Catch> _filteredCatches = [];
  String? _selectedFishTypeFilter;
  Map<int, String> _fishingBuddyNames = {};
  Map<int, String> _primaryMediaPaths = {};
  int? _currentTripId;
  String? _currentTripName;

  @override
  void initState() {
    super.initState();
    _loadCatches();
    _loadFishingBuddyNames();
    _loadCurrentTrip();
  }

  Future<void> _loadCurrentTrip() async {
    final currentTripId = await CurrentTripService.getCurrentTripId();
    if (currentTripId != null) {
      final trip = await DatabaseHelper.instance.getFishingTrip(currentTripId);
      if (mounted) {
        setState(() {
          _currentTripId = currentTripId;
          _currentTripName = trip?.name;
        });
      }
    }
  }

  Future<void> _loadFishingBuddyNames() async {
    final buddies = await DatabaseHelper.instance.getFishingBuddies();
    final buddyMap = {for (var buddy in buddies) buddy.id!: buddy.name};
    setState(() {
      _fishingBuddyNames = buddyMap;
    });
  }

  Future<void> _loadCatches() async {
    final data = await DatabaseHelper.instance.getCatches();
    // Sort by Date Caught, newest first. If dateCaught is null, use createdAt
    data.sort((a, b) {
      final aDate = a.dateCaught ?? a.createdAt;
      final bDate = b.dateCaught ?? b.createdAt;
      return bDate.compareTo(aDate);
    });
    
    // Load primary media paths for all catches
    final mediaMap = <int, String>{};
    for (final catchItem in data) {
      if (catchItem.id != null) {
        final primaryMedia = await DatabaseHelper.instance.getPrimaryMediaForCatch(catchItem.id!);
        if (primaryMedia != null) {
          mediaMap[catchItem.id!] = primaryMedia.filePath;
        }
      }
    }
    
    setState(() {
      _catches = data;
      _primaryMediaPaths = mediaMap;
      _applyFilter();
    });
  }

  void _applyFilter() {
    if (_selectedFishTypeFilter == null || _selectedFishTypeFilter == 'All') {
      _filteredCatches = _catches;
    } else {
      _filteredCatches = _catches.where((c) => c.fishType == _selectedFishTypeFilter).toList();
    }
  }

  List<String> _getFishTypes() {
    final types = _catches.map((c) => c.fishType).toSet().toList();
    types.sort();
    return types;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Catches'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _selectedFishTypeFilter = value;
                _applyFilter();
              });
            },
            itemBuilder: (context) {
              return [
                const PopupMenuItem(
                  value: 'All',
                  child: Text('All Fish Types'),
                ),
                ..._getFishTypes().map((type) {
                  return PopupMenuItem(
                    value: type,
                    child: Text(type),
                  );
                }),
              ];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_currentTripName != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.directions_boat,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Trip',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                        ),
                        Text(
                          _currentTripName!,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await CurrentTripService.clearCurrentTrip();
                      setState(() {
                        _currentTripId = null;
                        _currentTripName = null;
                      });
                    },
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredCatches.length,
        itemBuilder: (context, index) {
          final catchItem = _filteredCatches[index];
          return Card(
            child: InkWell(
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CatchDetailsScreen(catchItem: catchItem),
                  ),
                );
                if (result == true) {
                  _loadCatches();
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
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.image_not_supported,
                          size: 40,
                          color: Colors.grey[400],
                        ),
                      ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            catchItem.fishType,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${catchItem.lengthCm} cm',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (catchItem.dateCaught != null)
                            Text(
                              '${catchItem.dateCaught!.day}/${catchItem.dateCaught!.month}/${catchItem.dateCaught!.year}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          if (catchItem.fishingBuddyId != null && _fishingBuddyNames[catchItem.fishingBuddyId] != 'Me')
                            Text(
                              _fishingBuddyNames[catchItem.fishingBuddyId] ?? 'Unknown',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                          if (catchItem.location != null && catchItem.location!.isNotEmpty)
                            Text(
                              catchItem.location!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
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
          ),
        ],
      ),
    );
  }
}