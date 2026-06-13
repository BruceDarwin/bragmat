import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../database/database_helper.dart';
import '../models/fishing_trip.dart';
import '../models/catch.dart';
import '../models/trip_media.dart';
import 'catch_details_screen.dart';
import 'add_trip_screen.dart';
import 'photo_viewer_screen.dart';

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
  bool _isLoading = true;
  final ImagePicker _imagePicker = ImagePicker();

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
    final tripMedia = await DatabaseHelper.instance.getMediaForTrip(_trip.id!);

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
        _tripMedia = tripMedia;
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
