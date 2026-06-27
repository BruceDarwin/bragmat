import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../models/fishing_trip.dart';
import '../models/catch.dart';
import '../models/trip_media.dart';
import '../models/trip_journal.dart';
import '../models/journal_media.dart';
import '../models/trip_summary.dart';
import '../services/current_trip_service.dart';
import '../services/trip_summary_service.dart';
import 'catch_details_screen.dart';
import 'add_trip_screen.dart';
import 'photo_viewer_screen.dart';
import 'journal_entry_screen.dart';

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
  List<TripMedia> _tripMedia = [];
  List<TripJournal> _journalEntries = [];
  Map<int, String> _journalPrimaryMediaPaths = {};
  bool _isLoading = true;
  int? _currentTripId;
  TripSummary? _tripSummary;
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  final TripSummaryService _tripSummaryService = TripSummaryService();

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _loadData();
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

  Future<void> _loadData() async {
    if (_trip.id == null) return;

    final catches = await DatabaseHelper.instance.getCatchesForTrip(_trip.id!);
    final buddies = await DatabaseHelper.instance.getFishingBuddies();
    final buddyMap = {for (var buddy in buddies) buddy.id!: buddy.name};
    final tripMedia = await DatabaseHelper.instance.getMediaForTrip(_trip.id!);
    final journalEntries = await DatabaseHelper.instance.getJournalForTrip(_trip.id!);

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

    // Load primary media paths for all journal entries
    final journalMediaMap = <int, String>{};
    for (final journal in journalEntries) {
      if (journal.id != null) {
        final primaryMedia = await DatabaseHelper.instance.getPrimaryMediaForJournalEntry(journal.id!);
        if (primaryMedia != null) {
          journalMediaMap[journal.id!] = primaryMedia.filePath;
        }
      }
    }

    // Load trip summary
    TripSummary? tripSummary;
    try {
      tripSummary = await _tripSummaryService.generateTripSummary(_trip.id!);
    } catch (e) {
      // If trip summary fails, continue without it
    }

    if (mounted) {
      setState(() {
        _catches = catches;
        _fishingBuddyNames = buddyMap;
        _primaryMediaPaths = mediaMap;
        _tripMedia = tripMedia;
        _journalEntries = journalEntries;
        _journalPrimaryMediaPaths = journalMediaMap;
        _tripSummary = tripSummary;
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
    if (_catches.isEmpty && _journalEntries.isEmpty) return 'No catches or journal entries';
    
    final totalFish = _catches.length;
    final species = _catches.map((c) => c.fishType).toSet().length;
    final buddies = _catches
        .where((c) => c.fishingBuddyId != null)
        .map((c) => c.fishingBuddyId)
        .toSet()
        .length;
    final journalCount = _journalEntries.length;
    
    String stats = '';
    if (totalFish > 0) {
      stats += '$totalFish fish, $species species, $buddies anglers';
    }
    if (journalCount > 0) {
      if (stats.isNotEmpty) stats += ', ';
      stats += '$journalCount journal entr${journalCount == 1 ? 'y' : 'ies'}';
      
      // Add most recent journal entry date
      if (_journalEntries.isNotEmpty) {
        final mostRecent = _journalEntries.first;
        stats += ' (latest: ${_formatJournalDateTime(mostRecent.journalDateTime)})';
      }
    }
    
    return stats.isEmpty ? 'No catches or journal entries' : stats;
  }

  Catch? _getLargestFish() {
    if (_catches.isEmpty) return null;
    return _catches.reduce((a, b) => a.lengthCm > b.lengthCm ? a : b);
  }

  Future<void> _addTripPhoto() async {
    if (_trip.id == null) return;

    final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final tripMedia = TripMedia(
      tripId: _trip.id!,
      filePath: image.path,
      mediaType: 'photo',
      role: _tripMedia.isEmpty ? 'primary' : 'other',
    );

    await DatabaseHelper.instance.insertTripMedia(tripMedia);
    await _loadData();
  }

  Future<void> _deleteTripPhoto(int mediaId) async {
    await DatabaseHelper.instance.deleteTripMedia(mediaId);
    await _loadData();
  }

  Future<void> _setPrimaryTripPhoto(int mediaId) async {
    await DatabaseHelper.instance.setPrimaryTripMedia(mediaId);
    await _loadData();
  }

  Future<void> _addJournalEntry() async {
    if (_trip.id == null) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JournalEntryScreen(tripId: _trip.id!),
      ),
    );
    if (result == true) {
      await _loadData();
    }
  }

  Future<void> _editJournalEntry(TripJournal journal) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JournalEntryScreen(
          tripId: _trip.id!,
          journalToEdit: journal,
        ),
      ),
    );
    if (result == true) {
      await _loadData();
    }
  }

  Future<void> _searchJournalEntries(String query) async {
    if (_trip.id == null) return;

    if (query.isEmpty) {
      final entries = await DatabaseHelper.instance.getJournalForTrip(_trip.id!);
      if (mounted) {
        setState(() {
          _journalEntries = entries;
        });
      }
    } else {
      final entries = await DatabaseHelper.instance.searchJournalForTrip(_trip.id!, query);
      if (mounted) {
        setState(() {
          _journalEntries = entries;
        });
      }
    }
  }

  String _formatJournalDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _getJournalPreview(String text) {
    if (text.length <= 100) return text;
    return '${text.substring(0, 100)}...';
  }

  IconData _getJournalIcon(String type) {
    switch (type) {
      case 'general':
        return Icons.note;
      case 'fishing_report':
        return Icons.report;
      case 'weather':
        return Icons.cloud;
      case 'tide':
        return Icons.water;
      case 'wildlife':
        return Icons.pets;
      case 'campsite':
        return Icons.cabin;
      case 'boat_equipment':
        return Icons.directions_boat;
      case 'other':
        return Icons.label;
      default:
        return Icons.note;
    }
  }

  Future<void> _setCurrentTrip() async {
    if (_trip.id != null) {
      await CurrentTripService.setCurrentTrip(_trip.id);
      setState(() {
        _currentTripId = _trip.id;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_trip.name} set as current trip')),
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
        title: const Text('Trip Details'),
        actions: [
          if (_currentTripId != _trip.id)
            TextButton(
              onPressed: _setCurrentTrip,
              child: const Text('Set as Current Trip'),
            )
          else
            TextButton(
              onPressed: _clearCurrentTrip,
              child: const Text('Clear Current Trip'),
            ),
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
                  await _loadData();
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

                  // Trip Summary Section
                  if (_tripSummary != null) _buildTripSummarySection(),

                  // Stats Card (legacy, kept for compatibility)
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

                  // Trip Photos Section
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Trip Photos (${_tripMedia.length})',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_a_photo),
                              onPressed: _addTripPhoto,
                              tooltip: 'Add Photo',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_tripMedia.isEmpty)
                          Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.photo_library,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'No trip photos yet',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Colors.grey[600],
                                      ),
                                ),
                              ],
                            ),
                          )
                        else
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemCount: _tripMedia.length,
                            itemBuilder: (context, index) {
                              final media = _tripMedia[index];
                              return Stack(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PhotoViewerScreen(imagePath: media.filePath),
                                        ),
                                      );
                                    },
                                    child: Hero(
                                      tag: 'trip_photo_${media.id}',
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.file(
                                          File(media.filePath),
                                          width: double.infinity,
                                          height: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              color: Colors.grey[300],
                                              child: const Icon(Icons.image_not_supported),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (media.role == 'primary')
                                    Positioned(
                                      top: 4,
                                      left: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Cover',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: PopupMenuButton<String>(
                                      icon: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Icon(
                                          Icons.more_vert,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                      onSelected: (value) async {
                                        if (value == 'delete') {
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text('Delete Photo'),
                                              content: const Text('Are you sure you want to delete this photo?'),
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
                                          if (confirmed == true) {
                                            await _deleteTripPhoto(media.id!);
                                          }
                                        } else if (value == 'primary') {
                                          await _setPrimaryTripPhoto(media.id!);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        if (media.role != 'primary')
                                          const PopupMenuItem(
                                            value: 'primary',
                                            child: Text('Set as Cover'),
                                          ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                      ],
                    ),
                  ),

                  // Journal Section
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Journal (${_journalEntries.length})',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: _addJournalEntry,
                              tooltip: 'Add Entry',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Search bar
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search journal entries...',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          onChanged: _searchJournalEntries,
                        ),
                        const SizedBox(height: 12),
                        if (_journalEntries.isEmpty)
                          Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.book,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'No journal entries yet',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Colors.grey[600],
                                      ),
                                ),
                              ],
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _journalEntries.length,
                            itemBuilder: (context, index) {
                              final entry = _journalEntries[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  onTap: () => _editJournalEntry(entry),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (_journalPrimaryMediaPaths[entry.id] != null)
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.file(
                                              File(_journalPrimaryMediaPaths[entry.id]!),
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
                                          ),
                                        if (_journalPrimaryMediaPaths[entry.id] != null)
                                          const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    _getJournalIcon(entry.journalType),
                                                    size: 20,
                                                    color: Colors.grey[600],
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    _formatJournalDateTime(entry.journalDateTime),
                                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                          color: Colors.grey[600],
                                                        ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    TripJournal.getJournalTypeDisplayName(entry.journalType),
                                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                          color: Colors.grey[500],
                                                        ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                entry.title,
                                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _getJournalPreview(entry.entryText),
                                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                      ],
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

  Widget _buildTripSummarySection() {
    if (_tripSummary == null) return const SizedBox.shrink();
    
    final summary = _tripSummary!;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Trip Summary Header with Share button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Trip Summary',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: _shareTripReport,
                tooltip: 'Share Trip Report',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        
        // Trip Summary Card
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Trip header with photo
                Row(
                  children: [
                    if (summary.primaryPhotoPath != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(summary.primaryPhotoPath!),
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildDefaultTripIcon();
                          },
                        ),
                      )
                    else
                      _buildDefaultTripIcon(),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            summary.tripName,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDateRange(summary.startDate, summary.endDate),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                summary.durationText,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[500],
                                    ),
                              ),
                              const SizedBox(width: 8),
                              const Text('•'),
                              const SizedBox(width: 8),
                              Text(
                                '${summary.totalCatches} Fish',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[500],
                                    ),
                              ),
                              const SizedBox(width: 8),
                              const Text('•'),
                              const SizedBox(width: 8),
                              Text(
                                '${summary.speciesCount} Species',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[500],
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Trip Statistics Grid
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildTripStatisticsGrid(summary),
        ),
        
        const SizedBox(height: 16),
        
        // Catch Highlights
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Catch Highlights',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildCatchHighlights(summary),
        ),
        
        const SizedBox(height: 16),
        
        // Location Highlights - temporarily disabled
        // if (summary.bestLocation != null) ...[
        //   Padding(
        //     padding: const EdgeInsets.symmetric(horizontal: 16),
        //     child: Text(
        //       'Location Highlights',
        //       style: Theme.of(context).textTheme.titleMedium?.copyWith(
        //             fontWeight: FontWeight.bold,
        //           ),
        //     ),
        //   ),
        //   const SizedBox(height: 8),
        //   Padding(
        //     padding: const EdgeInsets.symmetric(horizontal: 16),
        //     child: _buildLocationHighlights(summary),
        //   ),
        //   const SizedBox(height: 16),
        // ],
        
        // Journal Summary
        if (summary.journalSummary != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Journal Summary',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildJournalSummary(summary.journalSummary!),
          ),
          const SizedBox(height: 16),
        ],
        
        // Achievement Highlights - only show if achievements were unlocked
        if (summary.unlockedAchievements.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Achievement Highlights',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildAchievementHighlights(summary),
          ),
          const SizedBox(height: 16),
        ],
        
        // Trip Recap
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Trip Recap',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildTripRecap(summary),
        ),
        
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildDefaultTripIcon() {
    return Container(
      width: 80,
      height: 80,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.directions_boat,
        color: Theme.of(context).colorScheme.primary,
        size: 40,
      ),
    );
  }

  Widget _buildTripStatisticsGrid(TripSummary summary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.catching_pokemon,
                    label: 'Total Catches',
                    value: summary.totalCatches.toString(),
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.category,
                    label: 'Species',
                    value: summary.speciesCount.toString(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.straighten,
                    label: 'Largest Fish',
                    value: summary.largestFishLength != null 
                        ? '${summary.largestFishLength}cm'
                        : 'N/A',
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.show_chart,
                    label: 'Avg Length',
                    value: '${summary.averageLength.toStringAsFixed(1)}cm',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.photo_library,
                    label: 'Photos',
                    value: summary.totalPhotos.toString(),
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.book,
                    label: 'Journal',
                    value: summary.journalEntryCount.toString(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
          size: 24,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
        ),
      ],
    );
  }

  Widget _buildCatchHighlights(TripSummary summary) {
    return Column(
      children: [
        if (summary.largestFish != null)
          _buildCatchHighlightCard(
            icon: Icons.emoji_events,
            title: 'Biggest Fish',
            highlight: summary.largestFish!,
          ),
        if (summary.mostCommonSpecies != null) ...[
          const SizedBox(height: 8),
          _buildCatchHighlightCard(
            icon: Icons.favorite,
            title: _getSpeciesHighlightTitle(summary.mostCommonSpecies!),
            highlight: summary.mostCommonSpecies!,
          ),
        ],
        if (summary.firstCatch != null) ...[
          const SizedBox(height: 8),
          _buildCatchHighlightCard(
            icon: Icons.play_arrow,
            title: 'First Catch',
            highlight: summary.firstCatch!,
          ),
        ],
        if (summary.lastCatch != null) ...[
          const SizedBox(height: 8),
          _buildCatchHighlightCard(
            icon: Icons.stop,
            title: 'Last Catch',
            highlight: summary.lastCatch!,
          ),
        ],
      ],
    );
  }
  
  String _getSpeciesHighlightTitle(CatchHighlight highlight) {
    switch (highlight.highlightType) {
      case 'only_species':
        return 'Only Species';
      case 'species_mix':
        return 'Species Mix';
      case 'most_common':
      default:
        return 'Most Common Species';
    }
  }
  
  String _getSpeciesDisplayText(CatchHighlight highlight) {
    switch (highlight.highlightType) {
      case 'species_mix':
        return '${highlight.length} caught, ${highlight.species}';
      case 'only_species':
      case 'most_common':
      default:
        return highlight.species;
    }
  }
  
  String _getSpeciesSubtitle(CatchHighlight highlight) {
    switch (highlight.highlightType) {
      case 'species_mix':
        return _formatDate(highlight.date);
      case 'only_species':
        return '${highlight.length} caught • ${_formatDate(highlight.date)}';
      case 'most_common':
      default:
        return '${highlight.length} caught • ${_formatDate(highlight.date)}';
    }
  }

  Widget _buildCatchHighlightCard({
    required IconData icon,
    required String title,
    required CatchHighlight highlight,
  }) {
    return GestureDetector(
      onTap: highlight.catchId != null ? () async {
        final catchItem = await DatabaseHelper.instance.getCatch(highlight.catchId!);
        if (catchItem != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CatchDetailsScreen(catchItem: catchItem),
            ),
          );
        }
      } : null,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (highlight.photoPath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(highlight.photoPath!),
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildDefaultCatchIcon(icon);
                    },
                  ),
                )
              else
                _buildDefaultCatchIcon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getSpeciesDisplayText(highlight),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getSpeciesSubtitle(highlight),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[500],
                          ),
                    ),
                  ],
                ),
              ),
              if (highlight.catchId != null)
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultCatchIcon(IconData icon) {
    return Container(
      width: 50,
      height: 50,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        color: Theme.of(context).colorScheme.primary,
        size: 24,
      ),
    );
  }

  Widget _buildLocationHighlights(TripSummary summary) {
    // Temporarily disabled due to parameter promotion issue
    return const SizedBox.shrink();
  }

  Widget _buildJournalSummary(TripJournalSummary journalSummary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.book,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '${journalSummary.entryCount} Journal Entr${journalSummary.entryCount == 1 ? 'y' : 'ies'}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            if (journalSummary.latestEntryTitle != null) ...[
              const SizedBox(height: 8),
              Text(
                journalSummary.latestEntryTitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                journalSummary.latestEntryPreview ?? '',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                _formatJournalDateTime(journalSummary.latestEntryDate!),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[500],
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAchievementHighlights(TripSummary summary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.emoji_events,
                  color: Colors.amber,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '${summary.unlockedAchievements.length} Achievement${summary.unlockedAchievements.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: summary.unlockedAchievements.map((achievement) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🏆', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                        Text(
                          achievement,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripRecap(TripSummary summary) {
    final story = _tripSummaryService.generateTripStory(summary);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          story,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
                height: 1.5,
              ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _shareTripReport() async {
    if (_tripSummary == null) return;
    
    final shareText = _tripSummaryService.generateShareableText(_tripSummary!);
    
    try {
      await Share.share(shareText, subject: '${_tripSummary!.tripName} - Trip Report');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to share trip report')),
        );
      }
    }
  }
}
