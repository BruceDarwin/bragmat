import 'package:flutter/material.dart';
import '../database/database_helper.dart';

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
          // Total Catches
          _buildStatCard(
            icon: Icons.numbers,
            title: 'Total Catches',
            value: totalCatches.toString(),
            subtitle: 'All time',
          ),
          const SizedBox(height: 16),

          // Largest Fish
          _buildLargestFishCard(),
          const SizedBox(height: 16),

          // Average Length
          _buildStatCard(
            icon: Icons.straighten,
            title: 'Average Length',
            value: '${(_statistics!['averageLength'] as double).toStringAsFixed(1)} cm',
            subtitle: 'Per fish',
          ),
          const SizedBox(height: 16),

          // Most Common Fish Type
          _buildStatCard(
            icon: Icons.set_meal,
            title: 'Most Common Fish',
            value: _statistics!['mostCommonFishType'] as String? ?? 'N/A',
            subtitle: 'By count',
          ),
          const SizedBox(height: 16),

          // Most Common Fishing Buddy
          _buildStatCard(
            icon: Icons.person,
            title: 'Most Common Buddy',
            value: _statistics!['mostCommonFishingBuddy'] as String? ?? 'N/A',
            subtitle: 'By catches',
          ),
          const SizedBox(height: 16),

          // Most Recent Catch
          _buildMostRecentCatchCard(),
          const SizedBox(height: 16),

          // Trip Statistics Section
          _buildStatCard(
            icon: Icons.directions_boat,
            title: 'Total Trips',
            value: _statistics!['totalTrips'].toString(),
            subtitle: 'All time',
          ),
          const SizedBox(height: 16),

          // Most Productive Trip
          _buildStatCard(
            icon: Icons.emoji_events,
            title: 'Most Productive Trip',
            value: _statistics!['mostProductiveTrip'] as String? ?? 'N/A',
            subtitle: 'By catches',
          ),
          const SizedBox(height: 16),

          // Average Catches Per Trip
          _buildStatCard(
            icon: Icons.analytics,
            title: 'Avg Catches Per Trip',
            value: '${(_statistics!['averageCatchesPerTrip'] as double).toStringAsFixed(1)}',
            subtitle: 'Per trip',
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[500],
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLargestFishCard() {
    final largestFish = _statistics!['largestFish'] as Map<String, dynamic>?;
    if (largestFish == null) return const SizedBox.shrink();

    final fishType = largestFish['fishType'] as String;
    final length = largestFish['length'] as int;
    final fishingBuddy = largestFish['fishingBuddy'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.emoji_events,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Largest Fish',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fishType,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDetailItem(Icons.straighten, '$length cm', 'Length'),
                if (fishingBuddy != null)
                  _buildDetailItem(Icons.person, fishingBuddy, 'Caught by'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMostRecentCatchCard() {
    final mostRecentCatch = _statistics!['mostRecentCatch'] as Map<String, dynamic>?;
    if (mostRecentCatch == null) return const SizedBox.shrink();

    final fishType = mostRecentCatch['fishType'] as String;
    final length = mostRecentCatch['length'] as int;
    final date = mostRecentCatch['date'] as DateTime;
    final fishingBuddy = mostRecentCatch['fishingBuddy'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.access_time,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Most Recent Catch',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fishType,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDetailItem(Icons.straighten, '$length cm', 'Length'),
                _buildDetailItem(
                  Icons.calendar_today,
                  '${date.day}/${date.month}/${date.year}',
                  'Date',
                ),
                if (fishingBuddy != null)
                  _buildDetailItem(Icons.person, fishingBuddy, 'Caught by'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: Colors.grey[600],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[500],
              ),
        ),
      ],
    );
  }
}
