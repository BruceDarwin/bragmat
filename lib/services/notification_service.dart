import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Show a temporary notification/snackbar
  void showNotification({
    required String message,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
    Color? backgroundColor,
    Color? textColor,
    SnackBarAction? action,
  }) {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: textColor ?? Colors.white),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: textColor ?? Colors.white),
              ),
            ),
          ],
        ),
        duration: duration,
        backgroundColor: backgroundColor,
        action: action,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Show offline notification
  void showOfflineNotification() {
    showNotification(
      message: 'Offline Fishing Mode Active',
      icon: Icons.cloud_off,
      duration: const Duration(seconds: 5),
      backgroundColor: Colors.orange.shade700,
      textColor: Colors.white,
    );
  }

  /// Show back online notification
  void showBackOnlineNotification() {
    showNotification(
      message: 'Back Online',
      icon: Icons.cloud_done,
      duration: const Duration(seconds: 3),
      backgroundColor: Colors.green.shade700,
      textColor: Colors.white,
    );
  }

  /// Show backup completed notification
  void showBackupCompletedNotification() {
    showNotification(
      message: 'Backup completed successfully',
      icon: Icons.backup,
      duration: const Duration(seconds: 3),
      backgroundColor: Colors.blue.shade700,
      textColor: Colors.white,
    );
  }

  /// Show restore completed notification
  void showRestoreCompletedNotification() {
    showNotification(
      message: 'Restore completed successfully',
      icon: Icons.restore,
      duration: const Duration(seconds: 3),
      backgroundColor: Colors.blue.shade700,
      textColor: Colors.white,
    );
  }

  /// Show achievement unlocked notification
  void showAchievementUnlockedNotification(String achievementName) {
    showNotification(
      message: 'Achievement Unlocked: $achievementName',
      icon: Icons.emoji_events,
      duration: const Duration(seconds: 4),
      backgroundColor: Colors.amber.shade700,
      textColor: Colors.white,
    );
  }

  /// Show new personal best notification
  void showNewPersonalBestNotification(String species, int length) {
    showNotification(
      message: 'New Personal Best: $species ($length cm)',
      icon: Icons.star,
      duration: const Duration(seconds: 4),
      backgroundColor: Colors.purple.shade700,
      textColor: Colors.white,
    );
  }
}
