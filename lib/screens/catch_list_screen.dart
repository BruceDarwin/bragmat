import 'dart:io';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';
import '../models/fishing_trip.dart';
import '../services/current_trip_service.dart';
import 'catch_details_screen.dart';

class CatchListScreen extends StatefulWidget {
  const CatchListScreen({super.key});

  @override
  State<CatchListScreen> createState() => _CatchListScreenState();
}

class _CatchListScreenState extends State<CatchListScreen> {
  List<Catch> _allCatches = [];
  List<Catch> _displayedCatches = [];
  List<Catch> _paginatedCatches = [];
  Map<int, String> _fishingBuddyNames = {};
  Map<int, String> _tripNames = {};
  Map<int, String> _primaryMediaPaths = {};
  int? _currentTripId;
  String? _currentTripName;
  
  // Search and filter state
  final TextEditingController _searchController = TextEditingController();
  String? _searchQuery;
  String? _selectedFishTypeFilter;
  int? _selectedTripFilter;
  int? _selectedBuddyFilter;
  DateTime? _startDateFilter;
  DateTime? _endDateFilter;
  bool? _hasPhotosFilter;
  bool? _hasLocationFilter;
  bool _currentTripOnlyFilter = false;
  
  // Sorting
  String _sortOption = 'Most Recent';
  
  // Pagination
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 50;
  int _currentPage = 0;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadCatches();
    _loadFishingBuddyNames();
    _loadTripNames();
    _loadCurrentTrip();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreCatches();
    }
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

  Future<void> _loadTripNames() async {
    final trips = await DatabaseHelper.instance.getFishingTrips();
    final tripMap = {for (var trip in trips) trip.id!: trip.name};
    setState(() {
      _tripNames = tripMap;
    });
  }

  Future<void> _loadCatches() async {
    final data = await DatabaseHelper.instance.getCatches();
    
    setState(() {
      _allCatches = data;
    });
    
    _applyFiltersAndSort();
    _loadMoreCatches();
  }

  Future<void> _loadMoreCatches() async {
    if (_isLoadingMore || !_hasMore) return;
    
    setState(() {
      _isLoadingMore = true;
    });
    
    final startIndex = _currentPage * _pageSize;
    final endIndex = (startIndex + _pageSize).clamp(0, _displayedCatches.length);
    
    if (startIndex >= _displayedCatches.length) {
      setState(() {
        _isLoadingMore = false;
        _hasMore = false;
      });
      return;
    }
    
    final batch = _displayedCatches.sublist(startIndex, endIndex);
    
    // Load primary media paths for this batch only
    final mediaMap = <int, String>{};
    for (final catchItem in batch) {
      if (catchItem.id != null && !_primaryMediaPaths.containsKey(catchItem.id)) {
        final primaryMedia = await DatabaseHelper.instance.getPrimaryMediaForCatch(catchItem.id!);
        if (primaryMedia != null) {
          mediaMap[catchItem.id!] = primaryMedia.filePath;
        }
      }
    }
    
    setState(() {
      _primaryMediaPaths.addAll(mediaMap);
      _paginatedCatches.addAll(batch);
      _currentPage++;
      _isLoadingMore = false;
      _hasMore = endIndex < _displayedCatches.length;
    });
  }

  void _applyFiltersAndSort() {
    List<Catch> filtered = List.from(_allCatches);
    
    // Apply search - split into multiple terms, all must match
    if (_searchQuery != null && _searchQuery!.isNotEmpty) {
      final terms = _searchQuery!.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      filtered = filtered.where((c) {
        // All search terms must be found in at least one searchable field
        return terms.every((term) {
          return c.fishType.toLowerCase().contains(term) ||
                 (c.notes?.toLowerCase().contains(term) ?? false) ||
                 (c.location?.toLowerCase().contains(term) ?? false) ||
                 (_tripNames[c.tripId]?.toLowerCase().contains(term) ?? false) ||
                 (_fishingBuddyNames[c.fishingBuddyId]?.toLowerCase().contains(term) ?? false);
        });
      }).toList();
    }
    
    // Apply fish type filter
    if (_selectedFishTypeFilter != null && _selectedFishTypeFilter != 'All') {
      filtered = filtered.where((c) => c.fishType == _selectedFishTypeFilter).toList();
    }
    
    // Apply trip filter
    if (_selectedTripFilter != null) {
      filtered = filtered.where((c) => c.tripId == _selectedTripFilter).toList();
    }
    
    // Apply current trip only filter
    if (_currentTripOnlyFilter && _currentTripId != null) {
      filtered = filtered.where((c) => c.tripId == _currentTripId).toList();
    }
    
    // Apply buddy filter
    if (_selectedBuddyFilter != null) {
      filtered = filtered.where((c) => c.fishingBuddyId == _selectedBuddyFilter).toList();
    }
    
    // Apply date range filter
    if (_startDateFilter != null) {
      filtered = filtered.where((c) {
        final date = c.dateCaught ?? c.createdAt;
        return date.isAfter(_startDateFilter!) || date.isAtSameMomentAs(_startDateFilter!);
      }).toList();
    }
    
    if (_endDateFilter != null) {
      filtered = filtered.where((c) {
        final date = c.dateCaught ?? c.createdAt;
        return date.isBefore(_endDateFilter!) || date.isAtSameMomentAs(_endDateFilter!);
      }).toList();
    }
    
    // Apply has photos filter
    if (_hasPhotosFilter == true) {
      filtered = filtered.where((c) => _primaryMediaPaths.containsKey(c.id)).toList();
    } else if (_hasPhotosFilter == false) {
      filtered = filtered.where((c) => !_primaryMediaPaths.containsKey(c.id)).toList();
    }
    
    // Apply has location filter
    if (_hasLocationFilter == true) {
      filtered = filtered.where((c) => c.latitude != null && c.longitude != null).toList();
    } else if (_hasLocationFilter == false) {
      filtered = filtered.where((c) => c.latitude == null || c.longitude == null).toList();
    }
    
    // Apply sorting
    switch (_sortOption) {
      case 'Most Recent':
        filtered.sort((a, b) {
          final aDate = a.dateCaught ?? a.createdAt;
          final bDate = b.dateCaught ?? b.createdAt;
          return bDate.compareTo(aDate);
        });
        break;
      case 'Oldest':
        filtered.sort((a, b) {
          final aDate = a.dateCaught ?? a.createdAt;
          final bDate = b.dateCaught ?? b.createdAt;
          return aDate.compareTo(bDate);
        });
        break;
      case 'Largest Fish':
        filtered.sort((a, b) => b.lengthCm.compareTo(a.lengthCm));
        break;
      case 'Smallest Fish':
        filtered.sort((a, b) => a.lengthCm.compareTo(b.lengthCm));
        break;
      case 'Fish Type':
        filtered.sort((a, b) => a.fishType.compareTo(b.fishType));
        break;
    }
    
    setState(() {
      _displayedCatches = filtered;
      _paginatedCatches = [];
      _currentPage = 0;
      _hasMore = true;
    });
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = null;
      _searchController.clear();
      _selectedFishTypeFilter = null;
      _selectedTripFilter = null;
      _selectedBuddyFilter = null;
      _startDateFilter = null;
      _endDateFilter = null;
      _hasPhotosFilter = null;
      _hasLocationFilter = null;
      _currentTripOnlyFilter = false;
      _sortOption = 'Most Recent';
    });
    _applyFiltersAndSort();
    _loadMoreCatches();
  }

  bool _hasActiveFilters() {
    return _searchQuery != null && _searchQuery!.isNotEmpty ||
           _selectedFishTypeFilter != null ||
           _selectedTripFilter != null ||
           _selectedBuddyFilter != null ||
           _startDateFilter != null ||
           _endDateFilter != null ||
           _hasPhotosFilter != null ||
           _hasLocationFilter != null ||
           _currentTripOnlyFilter ||
           _sortOption != 'Most Recent';
  }

  List<String> _getFishTypes() {
    final types = _allCatches.map((c) => c.fishType).toSet().toList();
    types.sort();
    return types;
  }

  void _showFilterSortDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Filter & Sort'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sort
                const Text('Sort By', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _sortOption,
                  decoration: const InputDecoration(labelText: 'Sort'),
                  items: const [
                    DropdownMenuItem(value: 'Most Recent', child: Text('Most Recent')),
                    DropdownMenuItem(value: 'Oldest', child: Text('Oldest')),
                    DropdownMenuItem(value: 'Largest Fish', child: Text('Largest Fish')),
                    DropdownMenuItem(value: 'Smallest Fish', child: Text('Smallest Fish')),
                    DropdownMenuItem(value: 'Fish Type', child: Text('Fish Type')),
                  ],
                  onChanged: (value) {
                    setDialogState(() => _sortOption = value!);
                  },
                ),
                const SizedBox(height: 16),
                
                // Fish Type
                const Text('Fish Type', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedFishTypeFilter,
                  decoration: const InputDecoration(labelText: 'Fish Type'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    ..._getFishTypes().map((type) {
                      return DropdownMenuItem(value: type, child: Text(type));
                    }),
                  ],
                  onChanged: (value) {
                    setDialogState(() => _selectedFishTypeFilter = value);
                  },
                ),
                const SizedBox(height: 16),
                
                // Trip
                const Text('Trip', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: _selectedTripFilter,
                  decoration: const InputDecoration(labelText: 'Trip'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All Trips')),
                    ..._tripNames.entries.map((entry) {
                      return DropdownMenuItem(value: entry.key, child: Text(entry.value));
                    }),
                  ],
                  onChanged: (value) {
                    setDialogState(() => _selectedTripFilter = value);
                  },
                ),
                const SizedBox(height: 16),
                
                // Buddy
                const Text('Fishing Buddy', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: _selectedBuddyFilter,
                  decoration: const InputDecoration(labelText: 'Buddy'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All Buddies')),
                    ..._fishingBuddyNames.entries.map((entry) {
                      return DropdownMenuItem(value: entry.key, child: Text(entry.value));
                    }),
                  ],
                  onChanged: (value) {
                    setDialogState(() => _selectedBuddyFilter = value);
                  },
                ),
                const SizedBox(height: 16),
                
                // Date Range
                const Text('Date Range', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _startDateFilter ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setDialogState(() => _startDateFilter = date);
                          }
                        },
                        icon: const Icon(Icons.calendar_today),
                        label: Text(_startDateFilter != null 
                            ? '${_startDateFilter!.day}/${_startDateFilter!.month}/${_startDateFilter!.year}'
                            : 'Start Date'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _endDateFilter ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setDialogState(() => _endDateFilter = date);
                          }
                        },
                        icon: const Icon(Icons.calendar_today),
                        label: Text(_endDateFilter != null 
                            ? '${_endDateFilter!.day}/${_endDateFilter!.month}/${_endDateFilter!.year}'
                            : 'End Date'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Has Photos
                const Text('Photos', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<bool?>(
                  value: _hasPhotosFilter,
                  decoration: const InputDecoration(labelText: 'Has Photos'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All')),
                    DropdownMenuItem(value: true, child: Text('With Photos')),
                    DropdownMenuItem(value: false, child: Text('Without Photos')),
                  ],
                  onChanged: (value) {
                    setDialogState(() => _hasPhotosFilter = value);
                  },
                ),
                const SizedBox(height: 16),
                
                // Has Location
                const Text('Location', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<bool?>(
                  value: _hasLocationFilter,
                  decoration: const InputDecoration(labelText: 'Has Location'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All')),
                    DropdownMenuItem(value: true, child: Text('With Location')),
                    DropdownMenuItem(value: false, child: Text('Without Location')),
                  ],
                  onChanged: (value) {
                    setDialogState(() => _hasLocationFilter = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() {
                  _selectedFishTypeFilter = null;
                  _selectedTripFilter = null;
                  _selectedBuddyFilter = null;
                  _startDateFilter = null;
                  _endDateFilter = null;
                  _hasPhotosFilter = null;
                  _hasLocationFilter = null;
                  _sortOption = 'Most Recent';
                });
              },
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {});
                _applyFiltersAndSort();
                _loadMoreCatches();
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Catches'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSortDialog,
            tooltip: 'Filter & Sort',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search catches, e.g. Barra Daly',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery != null && _searchQuery!.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchQuery = null;
                            _searchController.clear();
                          });
                          _applyFiltersAndSort();
                          _loadMoreCatches();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
                _applyFiltersAndSort();
                _loadMoreCatches();
              },
            ),
          ),
          
          // Current trip banner (only shown when current trip is set)
          if (_currentTripName != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Current Trip: $_currentTripName',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await CurrentTripService.clearCurrentTrip();
                      setState(() {
                        _currentTripId = null;
                        _currentTripName = null;
                        _currentTripOnlyFilter = false;
                      });
                      _applyFiltersAndSort();
                      _loadMoreCatches();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          
          // Current Trip Only filter (only shown when current trip is set)
          if (_currentTripId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilterChip(
                label: const Text('Show Current Trip Only'),
                selected: _currentTripOnlyFilter,
                onSelected: (selected) {
                  setState(() {
                    _currentTripOnlyFilter = selected;
                  });
                  _applyFiltersAndSort();
                  _loadMoreCatches();
                },
                avatar: _currentTripOnlyFilter 
                    ? const Icon(Icons.check, size: 18)
                    : const Icon(Icons.directions_boat, size: 18),
              ),
            ),
          
          // Active filters and count
          if (_hasActiveFilters())
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (_searchQuery != null && _searchQuery!.isNotEmpty)
                          Chip(
                            label: Text('Search: $_searchQuery'),
                            onDeleted: () {
                              setState(() {
                                _searchQuery = null;
                                _searchController.clear();
                              });
                              _applyFiltersAndSort();
                              _loadMoreCatches();
                            },
                          ),
                        if (_selectedFishTypeFilter != null)
                          Chip(
                            label: Text('Fish: $_selectedFishTypeFilter'),
                            onDeleted: () {
                              setState(() => _selectedFishTypeFilter = null);
                              _applyFiltersAndSort();
                              _loadMoreCatches();
                            },
                          ),
                        if (_selectedTripFilter != null)
                          Chip(
                            label: Text('Trip: ${_tripNames[_selectedTripFilter]}'),
                            onDeleted: () {
                              setState(() => _selectedTripFilter = null);
                              _applyFiltersAndSort();
                              _loadMoreCatches();
                            },
                          ),
                        if (_selectedBuddyFilter != null)
                          Chip(
                            label: Text('Buddy: ${_fishingBuddyNames[_selectedBuddyFilter]}'),
                            onDeleted: () {
                              setState(() => _selectedBuddyFilter = null);
                              _applyFiltersAndSort();
                              _loadMoreCatches();
                            },
                          ),
                        if (_startDateFilter != null || _endDateFilter != null)
                          Chip(
                            label: Text('Date Range'),
                            onDeleted: () {
                              setState(() {
                                _startDateFilter = null;
                                _endDateFilter = null;
                              });
                              _applyFiltersAndSort();
                              _loadMoreCatches();
                            },
                          ),
                        if (_hasPhotosFilter != null)
                          Chip(
                            label: Text(_hasPhotosFilter! ? 'Has Photos' : 'No Photos'),
                            onDeleted: () {
                              setState(() => _hasPhotosFilter = null);
                              _applyFiltersAndSort();
                              _loadMoreCatches();
                            },
                          ),
                        if (_hasLocationFilter != null)
                          Chip(
                            label: Text(_hasLocationFilter! ? 'Has Location' : 'No Location'),
                            onDeleted: () {
                              setState(() => _hasLocationFilter = null);
                              _applyFiltersAndSort();
                              _loadMoreCatches();
                            },
                          ),
                        if (_sortOption != 'Most Recent')
                          Chip(
                            label: Text('Sort: $_sortOption'),
                            onDeleted: () {
                              setState(() => _sortOption = 'Most Recent');
                              _applyFiltersAndSort();
                              _loadMoreCatches();
                            },
                          ),
                        if (_currentTripOnlyFilter)
                          Chip(
                            label: const Text('Show Current Trip Only'),
                            onDeleted: () {
                              setState(() => _currentTripOnlyFilter = false);
                              _applyFiltersAndSort();
                              _loadMoreCatches();
                            },
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text('Clear All'),
                  ),
                ],
              ),
            ),
          
          // Catch count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _currentTripOnlyFilter
                  ? 'Showing ${_paginatedCatches.length} catches from $_currentTripName'
                  : 'Showing ${_paginatedCatches.length} of ${_displayedCatches.length} catches',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ),
          
          // Catch list with pagination
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _paginatedCatches.length + (_isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _paginatedCatches.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                
                final catchItem = _paginatedCatches[index];
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