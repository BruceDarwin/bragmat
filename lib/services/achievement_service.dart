import '../database/database_helper.dart';
import '../models/achievement.dart';
import '../models/user_achievement.dart';
import 'notification_service.dart';

class AchievementService {
  static final AchievementService _instance = AchievementService._internal();
  factory AchievementService() => _instance;
  AchievementService._internal();

  final NotificationService _notificationService = NotificationService();

  // Achievement definitions
  static final List<Achievement> _allAchievements = [
    // Catch Milestones
    Achievement(
      id: 'first_catch',
      name: 'First Catch',
      description: 'Record your first fish',
      icon: '🎣',
      category: 'Milestone',
    ),
    Achievement(
      id: '10_catches',
      name: '10 Catches',
      description: 'Record 10 catches',
      icon: '🐟',
      category: 'Milestone',
      targetValue: 10,
    ),
    Achievement(
      id: '50_catches',
      name: '50 Catches',
      description: 'Record 50 catches',
      icon: '🐠',
      category: 'Milestone',
      targetValue: 50,
    ),
    Achievement(
      id: '100_catches',
      name: '100 Catches',
      description: 'Record 100 catches',
      icon: '🐡',
      category: 'Milestone',
      targetValue: 100,
    ),
    // Species Achievements
    Achievement(
      id: 'first_species',
      name: 'First Species',
      description: 'Catch your first species',
      icon: '🦈',
      category: 'Species',
    ),
    Achievement(
      id: '5_species',
      name: '5 Species',
      description: 'Catch 5 different species',
      icon: '🐬',
      category: 'Species',
      targetValue: 5,
    ),
    Achievement(
      id: '10_species',
      name: '10 Species',
      description: 'Catch 10 different species',
      icon: '🐳',
      category: 'Species',
      targetValue: 10,
    ),
    // Personal Bests
    Achievement(
      id: 'personal_best',
      name: 'Personal Best',
      description: 'Record a new personal best',
      icon: '⭐',
      category: 'Records',
    ),
    Achievement(
      id: 'metre_fish',
      name: 'Metre Fish',
      description: 'Catch a fish 100 cm or larger',
      icon: '🏆',
      category: 'Records',
      targetValue: 100,
    ),
    // Trip Achievements
    Achievement(
      id: 'first_trip',
      name: 'First Trip',
      description: 'Create first fishing trip',
      icon: '⛵',
      category: 'Trips',
    ),
    Achievement(
      id: 'trip_journal',
      name: 'Trip Journal',
      description: 'Create first journal entry',
      icon: '📝',
      category: 'Trips',
    ),
    Achievement(
      id: '10_trips',
      name: '10 Trips',
      description: 'Record 10 fishing trips',
      icon: '🗺️',
      category: 'Trips',
      targetValue: 10,
    ),
    // Photography
    Achievement(
      id: 'photo_capture',
      name: 'Photo Capture',
      description: 'Add a photo to a catch',
      icon: '📸',
      category: 'Photography',
    ),
    Achievement(
      id: 'photographer',
      name: 'Photographer',
      description: 'Record 100 catch photos',
      icon: '🎞️',
      category: 'Photography',
      targetValue: 100,
    ),
    // Exploration
    Achievement(
      id: 'explorer',
      name: 'Explorer',
      description: 'Save first favourite fishing spot',
      icon: '📍',
      category: 'Exploration',
    ),
    Achievement(
      id: 'adventurer',
      name: 'Adventurer',
      description: 'Save 10 favourite fishing spots',
      icon: '🧭',
      category: 'Exploration',
      targetValue: 10,
    ),
  ];

  // Initialize achievements in database
  Future<void> initializeAchievements() async {
    try {
      final db = await DatabaseHelper.instance.database;
      
      // Check if achievements table exists
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='achievements'"
      );
      
      if (tables.isEmpty) {
        // Table doesn't exist yet, skip initialization
        return;
      }
      
      for (final achievement in _allAchievements) {
        final existing = await db.query(
          'achievements',
          where: 'id = ?',
          whereArgs: [achievement.id],
        );
        
        if (existing.isEmpty) {
          await db.insert('achievements', achievement.toDefinitionMap());
        }
      }
    } catch (e) {
      // Silently handle initialization errors
      // This can happen during database migration
    }
  }

  // Get all achievements with user progress
  Future<List<Achievement>> getAllAchievements() async {
    final db = await DatabaseHelper.instance.database;
    
    final achievementsResult = await db.query('achievements');
    
    // If achievements table is empty, initialize it
    if (achievementsResult.isEmpty) {
      await initializeAchievements();
      // Query again after initialization
      final retryResult = await db.query('achievements');
      if (retryResult.isNotEmpty) {
        achievementsResult.clear();
        achievementsResult.addAll(retryResult);
      }
    }
    
    final userAchievementsResult = await db.query('user_achievements');
    
    final userAchievementMap = <String, UserAchievement>{};
    for (final map in userAchievementsResult) {
      final userAchievement = UserAchievement.fromMap(map);
      userAchievementMap[userAchievement.achievementId] = userAchievement;
    }
    
    return achievementsResult.map((map) {
      final achievement = Achievement.fromMap(map);
      final userAchievement = userAchievementMap[achievement.id];
      
      if (userAchievement != null) {
        return achievement.copyWith(
          isUnlocked: true,
          unlockedDate: userAchievement.unlockedDate,
        );
      }
      return achievement;
    }).toList();
  }

  // Get achievements by category
  Future<Map<String, List<Achievement>>> getAchievementsByCategory() async {
    final allAchievements = await getAllAchievements();
    final categoryMap = <String, List<Achievement>>{};
    
    for (final achievement in allAchievements) {
      if (!categoryMap.containsKey(achievement.category)) {
        categoryMap[achievement.category] = [];
      }
      categoryMap[achievement.category]!.add(achievement);
    }
    
    return categoryMap;
  }

  // Get achievement statistics
  Future<Map<String, dynamic>> getAchievementStats() async {
    final allAchievements = await getAllAchievements();
    final unlockedCount = allAchievements.where((a) => a.isUnlocked).length;
    final totalCount = allAchievements.length;
    final completionPercentage = totalCount > 0 
        ? (unlockedCount / totalCount * 100).round() 
        : 0;
    
    final mostRecent = allAchievements
        .where((a) => a.isUnlocked && a.unlockedDate != null)
        .toList()
        ..sort((a, b) => b.unlockedDate!.compareTo(a.unlockedDate!));
    
    return {
      'unlockedCount': unlockedCount,
      'totalCount': totalCount,
      'completionPercentage': completionPercentage,
      'mostRecent': mostRecent.isNotEmpty ? mostRecent.first : null,
    };
  }

  // Check if achievement is unlocked
  Future<bool> isAchievementUnlocked(String achievementId) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.query(
      'user_achievements',
      where: 'achievement_id = ?',
      whereArgs: [achievementId],
    );
    return result.isNotEmpty;
  }

  // Unlock achievement
  Future<void> unlockAchievement(String achievementId) async {
    final alreadyUnlocked = await isAchievementUnlocked(achievementId);
    if (alreadyUnlocked) return;
    
    final db = await DatabaseHelper.instance.database;
    final achievement = _allAchievements.firstWhere((a) => a.id == achievementId);
    
    await db.insert('user_achievements', {
      'achievement_id': achievementId,
      'unlocked_date': DateTime.now().toIso8601String(),
    });
    
    // Show notification
    _notificationService.showAchievementUnlockedNotification(achievement.name);
  }

  // Evaluate achievements after catch
  Future<void> evaluateCatchAchievements() async {
    final db = await DatabaseHelper.instance.database;
    
    // Total catches
    final catchCount = await db.rawQuery('SELECT COUNT(*) as count FROM catches');
    final totalCatches = catchCount.first['count'] as int;
    
    // Unique species
    final speciesResult = await db.rawQuery('SELECT COUNT(DISTINCT fish_type) as count FROM catches');
    final uniqueSpecies = speciesResult.first['count'] as int;
    
    // Photos
    final photoResult = await db.rawQuery('SELECT COUNT(*) as count FROM catch_media');
    final totalPhotos = photoResult.first['count'] as int;
    
    // Largest fish
    final largestResult = await db.rawQuery('SELECT MAX(length_cm) as max FROM catches');
    final largestFish = largestResult.first['max'] as int?;
    
    // Check and unlock achievements
    if (totalCatches >= 1) await unlockAchievement('first_catch');
    if (totalCatches >= 10) await unlockAchievement('10_catches');
    if (totalCatches >= 50) await unlockAchievement('50_catches');
    if (totalCatches >= 100) await unlockAchievement('100_catches');
    
    if (uniqueSpecies >= 1) await unlockAchievement('first_species');
    if (uniqueSpecies >= 5) await unlockAchievement('5_species');
    if (uniqueSpecies >= 10) await unlockAchievement('10_species');
    
    if (totalPhotos >= 1) await unlockAchievement('photo_capture');
    if (totalPhotos >= 100) await unlockAchievement('photographer');
    
    if (largestFish != null && largestFish >= 100) {
      await unlockAchievement('metre_fish');
    }
  }

  // Evaluate achievements after trip
  Future<void> evaluateTripAchievements() async {
    final db = await DatabaseHelper.instance.database;
    
    // Total trips
    final tripCount = await db.rawQuery('SELECT COUNT(*) as count FROM fishing_trips');
    final totalTrips = tripCount.first['count'] as int;
    
    // Check and unlock achievements
    if (totalTrips >= 1) await unlockAchievement('first_trip');
    if (totalTrips >= 10) await unlockAchievement('10_trips');
  }

  // Evaluate achievements after journal entry
  Future<void> evaluateJournalAchievements() async {
    await unlockAchievement('trip_journal');
  }

  // Evaluate achievements after favourite spot
  Future<void> evaluateExplorationAchievements() async {
    final db = await DatabaseHelper.instance.database;
    
    // Total favourite spots
    final spotCount = await db.rawQuery('SELECT COUNT(*) as count FROM favourite_spots');
    final totalSpots = spotCount.first['count'] as int;
    
    // Check and unlock achievements
    if (totalSpots >= 1) await unlockAchievement('explorer');
    if (totalSpots >= 10) await unlockAchievement('adventurer');
  }

  // Evaluate personal best achievement
  Future<void> evaluatePersonalBest(int lengthCm) async {
    final db = await DatabaseHelper.instance.database;
    
    // Get current personal best for this species
    final speciesResult = await db.rawQuery(
      'SELECT MAX(length_cm) as max FROM catches WHERE fish_type = ?',
      [lengthCm]
    );
    
    // This is a simplified check - in practice you'd need to compare with previous best
    // For now, we'll unlock it whenever a significant catch is recorded
    if (lengthCm >= 50) {
      await unlockAchievement('personal_best');
    }
  }
}
