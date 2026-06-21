import 'package:flutter/material.dart';
import 'dart:io';
import '../database/database_helper.dart';
import 'catch_details_screen.dart';
import 'trip_details_screen.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  Map<String, dynamic>? _statistics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    final stats = await DatabaseHelper.instance.getStatistics();
    if (mounted) {
      setState(() {
        _statistics = stats;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStatistics,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _statistics == null
              ? const Center(child: Text('Error loading statistics'))
              : _buildStatisticsContent(),
    );
  }

  Widget _buildStatisticsContent() {
    final totalCatches = _statistics!['totalCatches'] as int;
    
    if (totalCatches == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.catching_pokemon,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No catches yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start catching fish to see your statistics!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[500],
                  ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Catch Activity Summary
          _buildSectionTitle('Activity Summary'),
          const SizedBox(height: 8),
          _buildActivitySummary(),
          const SizedBox(height: 24),

          // Featured Cards
          _buildSectionTitle('Highlights'),
          const SizedBox(height: 8),
          _buildLargestFishCard(),
          const SizedBox(height: 16),
          _buildMostRecentCatchCard(),
          const SizedBox(height: 16),
          _buildMostProductiveTripCard(),
          const SizedBox(height: 24),

          // Species Statistics
          _buildSectionTitle('Species Statistics'),
          const SizedBox(height: 8),
          _buildAverageLengthBySpecies(),
          const SizedBox(height: 16),
          _buildSpeciesRecords(),
          const SizedBox(height: 24),

          // Location Summary
          _buildSectionTitle('Location Summary'),
          const SizedBox(height: 8),
          _buildLocationSummary(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }

  Widget _buildActivitySummary() {
    final totalCatches = _statistics!['totalCatches'] as int;
    final totalTrips = _statistics!['totalTrips'] as int;
    final totalBuddies = _statistics!['totalBuddies'] as int;
    final totalSpecies = _statistics!['totalSpecies'] as int;
    final totalPhotos = _statistics!['totalPhotos'] as int;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    icon: Icons.catching_pokemon,
                    value: totalCatches.toString(),
                    label: 'Catches',
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    icon: Icons.directions_boat,
                    value: totalTrips.toString(),
                    label: 'Trips',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    icon: Icons.person,
                    value: totalBuddies.toString(),
                    label: 'Buddies',
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    icon: Icons.category,
                    value: totalSpecies.toString(),
                    label: 'Species',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    icon: Icons.photo_library,
                    value: totalPhotos.toString(),
                    label: 'Photos',
                  ),
                ),
                const Expanded(child: SizedBox()), // Spacer
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
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

  Widget _buildLargestFishCard() {
    final largestFish = _statistics!['largestFish'] as Map<String, dynamic>?;
    if (largestFish == null) return const SizedBox.shrink();

    final fishId = largestFish['id'] as int?;
    final fishType = largestFish['fishType'] as String;
    final length = largestFish['length'] as int;
    final dateCaught = largestFish['dateCaught'] as DateTime?;
    final photoPath = largestFish['photoPath'] as String?;

    return GestureDetector(
      onTap: fishId != null
          ? () async {
              final catchItem = await DatabaseHelper.instance.getCatch(fishId!);
              if (catchItem != null && mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CatchDetailsScreen(catchItem: catchItem),
                  ),
                );
              }
            }
          : null,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Photo or icon
              if (photoPath != null && File(photoPath).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(photoPath),
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildDefaultFishIcon();
                    },
                  ),
                )
              else
                _buildDefaultFishIcon(),
              const SizedBox(width: 16),
              Expanded(
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
                        const SizedBox(width: 4),
                        Text(
                          'Largest Fish',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fishType,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildDetailChip(Icons.straighten, '$length cm'),
                        if (dateCaught != null) ...[
                          const SizedBox(width: 8),
                          _buildDetailChip(
                            Icons.calendar_today,
                            '${dateCaught.day}/${dateCaught.month}/${dateCaught.year}',
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (fishId != null)
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

  Widget _buildDefaultFishIcon() {
    return Container(
      width: 80,
      height: 80,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.emoji_events,
        color: Theme.of(context).colorScheme.primary,
        size: 40,
      ),
    );
  }

  Widget _buildMostRecentCatchCard() {
    final mostRecentCatch = _statistics!['mostRecentCatch'] as Map<String, dynamic>?;
    if (mostRecentCatch == null) return const SizedBox.shrink();

    final catchId = mostRecentCatch['id'] as int?;
    final fishType = mostRecentCatch['fishType'] as String;
    final length = mostRecentCatch['length'] as int;
    final date = mostRecentCatch['date'] as DateTime;
    final location = mostRecentCatch['location'] as String?;
    final photoPath = mostRecentCatch['photoPath'] as String?;

    return GestureDetector(
      onTap: catchId != null
          ? () async {
              final catchItem = await DatabaseHelper.instance.getCatch(catchId!);
              if (catchItem != null && mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CatchDetailsScreen(catchItem: catchItem),
                  ),
                );
              }
            }
          : null,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Photo or icon
              if (photoPath != null && File(photoPath).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(photoPath),
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildDefaultRecentIcon();
                    },
                  ),
                )
              else
                _buildDefaultRecentIcon(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Most Recent',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fishType,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildDetailChip(Icons.straighten, '$length cm'),
                        const SizedBox(width: 8),
                        _buildDetailChip(
                          Icons.calendar_today,
                          '${date.day}/${date.month}/${date.year}',
                        ),
                      ],
                    ),
                    if (location != null && location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              location,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (catchId != null)
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

  Widget _buildDefaultRecentIcon() {
    return Container(
      width: 80,
      height: 80,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.access_time,
        color: Theme.of(context).colorScheme.primary,
        size: 40,
      ),
    );
  }

  Widget _buildMostProductiveTripCard() {
    final mostProductiveTrip = _statistics!['mostProductiveTrip'] as Map<String, dynamic>?;
    if (mostProductiveTrip == null) return const SizedBox.shrink();

    final tripId = mostProductiveTrip['id'] as int?;
    final tripName = mostProductiveTrip['name'] as String?;
    final location = mostProductiveTrip['location'] as String?;
    final catchCount = mostProductiveTrip['catchCount'] as int?;
    final photoPath = mostProductiveTrip['photoPath'] as String?;

    return GestureDetector(
      onTap: tripId != null
          ? () async {
              final trip = await DatabaseHelper.instance.getFishingTrip(tripId!);
              if (trip != null && mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TripDetailsScreen(trip: trip),
                  ),
                );
              }
            }
          : null,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Photo or icon
              if (photoPath != null && File(photoPath).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(photoPath),
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
                    Row(
                      children: [
                        Icon(
                          Icons.directions_boat,
                          color: Colors.blue,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Most Productive Trip',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tripName ?? 'N/A',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildDetailChip(Icons.catching_pokemon, '$catchCount catches'),
                        if (location != null && location.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _buildDetailChip(Icons.location_on, location),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (tripId != null)
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

  Widget _buildDetailChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: Colors.grey[700],
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[700],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildAverageLengthBySpecies() {
    final topFishTypes = _statistics!['topFishTypes'] as List?;
    if (topFishTypes == null || topFishTypes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.straighten,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Top 5 Species by Catch Count',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...topFishTypes.take(5).map((fishType) {
              final fishName = fishType['fishType'] as String;
              final count = fishType['count'] as int;
              final avgLength = fishType['averageLength'] as double;
              
              // Find largest for this species
              final speciesRecords = _statistics!['speciesRecords'] as List?;
              int? largestLength;
              if (speciesRecords != null) {
                final matchingRecords = speciesRecords.where((r) => r['fishType'] == fishName);
                if (matchingRecords.isNotEmpty) {
                  final record = matchingRecords.first;
                  largestLength = record['length'] as int?;
                }
              }
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            fishName,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        Text(
                          '$count caught',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildDetailChip(Icons.straighten, 'Avg: ${avgLength.toStringAsFixed(1)} cm'),
                        if (largestLength != null) ...[
                          const SizedBox(width: 8),
                          _buildDetailChip(Icons.emoji_events, 'Largest: $largestLength cm'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeciesRecords() {
    final speciesRecords = _statistics!['speciesRecords'] as List?;
    if (speciesRecords == null || speciesRecords.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                  'Species Records',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...speciesRecords.take(5).map((record) {
              final fishType = record['fishType'] as String;
              final length = record['length'] as int;
              final catchId = record['id'] as int?;
              final photoPath = record['photoPath'] as String?;

              return GestureDetector(
                onTap: catchId != null
                    ? () async {
                        final catchItem = await DatabaseHelper.instance.getCatch(catchId!);
                        if (catchItem != null && mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CatchDetailsScreen(catchItem: catchItem),
                            ),
                          );
                        }
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      // Photo thumbnail or icon
                      if (photoPath != null && File(photoPath).existsSync())
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(photoPath),
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildSmallRecordIcon();
                            },
                          ),
                        )
                      else
                        _buildSmallRecordIcon(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fishType,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            Text(
                              '$length cm',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (catchId != null)
                        Icon(
                          Icons.chevron_right,
                          color: Colors.grey[400],
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallRecordIcon() {
    return Container(
      width: 50,
      height: 50,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.emoji_events,
        color: Colors.amber,
        size: 24,
      ),
    );
  }

  Widget _buildLocationSummary() {
    final totalLocations = _statistics!['totalLocations'] as int;
    final mostProductiveLocation = _statistics!['mostProductiveLocation'] as String?;
    final mostProductiveLocationCount = _statistics!['mostProductiveLocationCount'] as int?;
    final largestFishLocation = _statistics!['largestFishLocation'] as String?;
    final catchesWithCoordinates = _statistics!['catchesWithCoordinates'] as int;
    final locationPercentage = _statistics!['locationPercentage'] as String;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Location Summary',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildLocationStat(
                    icon: Icons.place,
                    label: 'Unique Locations',
                    value: totalLocations.toString(),
                  ),
                ),
                if (mostProductiveLocation != null) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildLocationStat(
                      icon: Icons.star,
                      label: 'Most Productive',
                      value: mostProductiveLocation,
                      subtitle: '$mostProductiveLocationCount catches',
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildLocationStat(
                    icon: Icons.my_location,
                    label: 'Catches with Coordinates',
                    value: catchesWithCoordinates.toString(),
                    subtitle: '$locationPercentage% of total',
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
            if (largestFishLocation != null) ...[
              const SizedBox(height: 16),
              _buildLocationStat(
                icon: Icons.emoji_events,
                label: 'Largest Fish Location',
                value: largestFishLocation,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocationStat({
    required IconData icon,
    required String label,
    required String value,
    String? subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
          ),
      ],
    );
  }
}
