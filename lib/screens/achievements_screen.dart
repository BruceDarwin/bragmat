import 'package:flutter/material.dart';
import '../models/achievement.dart';
import '../services/achievement_service.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  final AchievementService _achievementService = AchievementService();
  Map<String, dynamic>? _stats;
  Map<String, List<Achievement>>? _achievementsByCategory;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final stats = await _achievementService.getAchievementStats();
    final achievementsByCategory = await _achievementService.getAchievementsByCategory();

    setState(() {
      _stats = stats;
      _achievementsByCategory = achievementsByCategory;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Achievements'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatsCard(),
                    const SizedBox(height: 24),
                    _buildAchievementsList(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatsCard() {
    final unlockedCount = _stats!['unlockedCount'] as int;
    final totalCount = _stats!['totalCount'] as int;
    final completionPercentage = _stats!['completionPercentage'] as int;
    final mostRecent = _stats!['mostRecent'] as Achievement?;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$unlockedCount / $totalCount',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$completionPercentage%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Achievements Unlocked',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            if (mostRecent != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    mostRecent.icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Most Recent',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          mostRecent.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAchievementsList() {
    if (_achievementsByCategory == null || _achievementsByCategory!.isEmpty) {
      return const Center(child: Text('No achievements available'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _achievementsByCategory!.entries.map((entry) {
        final category = entry.key;
        final achievements = entry.value;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              category,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...achievements.map((achievement) => _buildAchievementCard(achievement)),
            const SizedBox(height: 24),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildAchievementCard(Achievement achievement) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: achievement.isUnlocked ? 4 : 1,
      color: achievement.isUnlocked ? Colors.white : Colors.grey[100],
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: achievement.isUnlocked
                ? Colors.blue.withOpacity(0.1)
                : Colors.grey.withOpacity(0.3),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Center(
            child: Text(
              achievement.icon,
              style: const TextStyle(fontSize: 28),
            ),
          ),
        ),
        title: Text(
          achievement.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: achievement.isUnlocked ? Colors.black : Colors.grey[600],
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              achievement.description,
              style: TextStyle(
                color: achievement.isUnlocked ? Colors.grey[700] : Colors.grey[500],
              ),
            ),
            if (achievement.isUnlocked && achievement.unlockedDate != null)
              Text(
                'Unlocked ${_formatDate(achievement.unlockedDate!)}',
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (!achievement.isUnlocked && achievement.targetValue != null)
              Text(
                'Progress: ${_getProgress(achievement)}',
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        trailing: achievement.isUnlocked
            ? const Icon(Icons.check_circle, color: Colors.green, size: 28)
            : const Icon(Icons.lock, color: Colors.grey, size: 28),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'today';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _getProgress(Achievement achievement) {
    // This is a simplified progress display
    // In a full implementation, you'd track actual progress values
    return 'In progress...';
  }
}
