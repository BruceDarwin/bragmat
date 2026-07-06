import 'package:intl/intl.dart';

/// Helper class for generating tide context phrases
/// 
/// This class handles the logic for creating human-readable tide context
/// phrases like "1 hr 35 min before the Darwin high tide of 6.37 m at 3:09 pm"
class TideContextHelper {
  /// Generate a tide context phrase from the given parameters
  /// 
  /// Example output: "1 hr 35 min before the Darwin high tide of 6.37 m at 3:09 pm"
  /// If stationName is a fallback (like "Nearest WorldTides station"), it will be omitted
  static String generatePhrase({
    required String? stationName,
    required String eventType, // "High" or "Low"
    required DateTime eventTime,
    required double eventHeight,
    required String relation, // "Before" or "After"
    required int minutesFromEvent,
  }) {
    final timeFormatter = DateFormat('h:mm a');
    final formattedTime = timeFormatter.format(eventTime);
    
    // Format minutes
    String timeRelation;
    if (minutesFromEvent < 60) {
      timeRelation = '$minutesFromEvent min';
    } else {
      final hours = minutesFromEvent ~/ 60;
      final mins = minutesFromEvent % 60;
      if (mins == 0) {
        timeRelation = '$hours hr';
      } else {
        timeRelation = '$hours hr $mins min';
      }
    }
    
    // Build phrase
    final relationLower = relation.toLowerCase();
    final eventTypeLower = eventType.toLowerCase();
    
    // Check if stationName is a fallback - if so, omit it from the phrase
    final isFallbackStation = stationName == null ||
                              stationName.isEmpty ||
                              stationName == 'Unknown' ||
                              stationName == 'Nearest WorldTides station';
    
    if (isFallbackStation) {
      // Omit station name, use "the nearest" instead
      return '$timeRelation $relationLower the nearest $eventTypeLower tide of ${eventHeight.toStringAsFixed(2)} m at $formattedTime';
    } else {
      // Include genuine station name
      return '$timeRelation $relationLower the $stationName $eventTypeLower tide of ${eventHeight.toStringAsFixed(2)} m at $formattedTime';
    }
  }
  
  /// Calculate minutes between two times
  static int calculateMinutesBetween(DateTime from, DateTime to) {
    return to.difference(from).inMinutes.abs();
  }
  
  /// Determine if a catch time is before or after a tide event
  static String determineRelation(DateTime catchTime, DateTime eventTime) {
    return catchTime.isBefore(eventTime) ? 'Before' : 'After';
  }
  
  /// Format time for display (e.g., "3:09 pm")
  static String formatTime(DateTime time) {
    return DateFormat('h:mm a').format(time);
  }
  
  /// Get tide time band for grouping catches
  /// 
  /// Returns a string like "0-1 hr before high", "1-2 hr after low", etc.
  static String getTideTimeBand({
    required String relation,
    required String eventType,
    required int minutesFromEvent,
  }) {
    final band = (minutesFromEvent / 60).floor();
    
    if (band == 0) {
      return '0-1 hr ${relation.toLowerCase()} $eventType.toLowerCase()';
    } else if (band == 1) {
      return '1-2 hr ${relation.toLowerCase()} $eventType.toLowerCase()';
    } else if (band == 2) {
      return '2-3 hr ${relation.toLowerCase()} $eventType.toLowerCase()';
    } else {
      return '3+ hr ${relation.toLowerCase()} $eventType.toLowerCase()';
    }
  }
}

/// Tide event type enum
enum TideEventType {
  high,
  low,
}

/// Tide event relation enum
enum TideEventRelation {
  before,
  after,
}

/// Tide context data source enum
enum TideContextDataSource {
  manual,
  worldTides,
  openMeteo,
}

/// Tide context confidence enum
enum TideContextConfidence {
  high,
  medium,
  low,
}
