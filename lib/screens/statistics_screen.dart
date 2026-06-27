import 'package:flutter/material.dart';
import 'dart:io';
import '../database/database_helper.dart';
import '../services/achievement_service.dart';
import 'catch_details_screen.dart';
import 'trip_details_screen.dart';
import 'achievements_screen.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  Map<String, dynamic>? _statistics;
  Map<String, dynamic>? _achievementStats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    final stats = await DatabaseHelper.instance.getStatistics();
    final achievementStats = await AchievementService().getAchievementStats();
    if (mounted) {
      setState(() {
        _statistics = stats;
        _achievementStats = achievementStats;
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
          // Lifetime Fishing Section
          _buildSectionTitle('Lifetime Fishing'),
          const SizedBox(height: 8),
          _buildLifetimeFishingSection(),
          const SizedBox(height: 24),

          // Highlights Section
          _buildSectionTitle('Highlights'),
          const SizedBox(height: 8),
          _buildHighlightsSection(),
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

  Widget _buildLifetimeFishingSection() {
    final totalCatches = _statistics!['totalCatches'] as int;
    final totalSpecies = _statistics!['totalSpecies'] as int;
    final totalTrips = _statistics!['totalTrips'] as int;
    final totalPhotos = _statistics!['totalPhotos'] as int;
    
    final unlockedCount = _achievementStats?['unlockedCount'] as int? ?? 0;
    final totalCount = _achievementStats?['totalCount'] as int? ?? 0;
    final completionPercentage = _achievementStats?['completionPercentage'] as int? ?? 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildLifetimeCard(
                icon: Icons.catching_pokemon,
                value: totalCatches.toString(),
                label: 'Total Catches',
                subtitle: 'All time',
                onTap: () {
                  // Navigate to catches tab (would need to implement tab navigation)
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildLifetimeCard(
                icon: Icons.category,
                value: totalSpecies.toString(),
                label: 'Species',
                subtitle: 'Unique fish',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildLifetimeCard(
                icon: Icons.directions_boat,
                value: totalTrips.toString(),
                label: 'Trips',
                subtitle: 'Fishing trips',
                onTap: () {
                  // Navigate to trips tab
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildLifetimeCard(
                icon: Icons.emoji_events,
                value: '$unlockedCount/$totalCount',
                label: 'Achievements',
                subtitle: '$completionPercentage% complete',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AchievementsScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLifetimeCard({
    required IconData icon,
    required String value,
    required String label,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: onTap != null ? 2 : 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[500],
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightsSection() {
    final largestFish = _statistics!['largestFish'] as Map<String, dynamic>?;
    final mostCommonFishType = _statistics!['mostCommonFishType'] as String?;
    final mostProductiveLocation = _statistics!['mostProductiveLocation'] as String?;
    final mostProductiveLocationCount = _statistics!['mostProductiveLocationCount'] as int?;
    final totalPhotos = _statistics!['totalPhotos'] as int;

    return Column(
      children: [
        _buildHighlightRow(
          icon: Icons.emoji_events,
          title: 'Personal Best',
          value: largestFish != null 
              ? '${largestFish['fishType']} (${largestFish['length']} cm)'
              : 'No catches yet',
          onTap: largestFish != null ? () async {
            final fishId = largestFish['id'] as int?;
            if (fishId != null) {
              final catchItem = await DatabaseHelper.instance.getCatch(fishId);
              if (catchItem != null && mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CatchDetailsScreen(catchItem: catchItem),
                  ),
                );
              }
            }
          } : null,
        ),
        const SizedBox(height: 12),
        _buildHighlightRow(
          icon: Icons.favorite,
          title: 'Most Caught Species',
          value: mostCommonFishType ?? 'No catches yet',
        ),
        const SizedBox(height: 12),
        _buildHighlightRow(
          icon: Icons.location_on,
          title: 'Favourite Location',
          value: mostProductiveLocation != null
              ? '$mostProductiveLocation ($mostProductiveLocationCount catches)'
              : 'No location data',
        ),
        const SizedBox(height: 12),
        _buildHighlightRow(
          icon: Icons.photo_library,
          title: 'Catch Photos',
          value: totalPhotos > 0 ? '$totalPhotos photos' : 'No photos yet',
        ),
      ],
    );
  }

  Widget _buildHighlightRow({
    required IconData icon,
    required String title,
    required String value,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: onTap != null ? 2 : 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
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
              const SizedBox(width: 16),
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
                      value,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onTap != null)
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
                  'Species Statistics',
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
              final smallestLength = fishType['smallestLength'] as int?;
              
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildDetailChip(Icons.straighten, 'Avg: ${avgLength.toStringAsFixed(1)} cm'),
                        if (largestLength != null)
                          _buildDetailChip(Icons.emoji_events, 'Largest: $largestLength cm'),
                        if (smallestLength != null)
                          _buildDetailChip(Icons.trending_down, 'Smallest: $smallestLength cm'),
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

    final displayRecords = speciesRecords.take(10).toList();
    final hasMore = speciesRecords.length > 10;

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
                const Spacer(),
                if (hasMore)
                  TextButton(
                    onPressed: () {
                      // TODO: Navigate to full species records screen
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('View All coming soon')),
                      );
                    },
                    child: const Text('View All'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ...displayRecords.map((record) {
              final fishType = record['fishType'] as String;
              final length = record['length'] as int;
              final catchId = record['id'] as int?;
              final photoPath = record['photoPath'] as String?;
              final dateCaught = record['dateCaught'] as DateTime?;
              final location = record['location'] as String?;

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
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              fishType,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '$length cm',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                            if (dateCaught != null) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 12,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${dateCaught.day}/${dateCaught.month}/${dateCaught.year}',
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
                            if (location != null && location.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    size: 12,
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
