import 'package:shared_preferences/shared_preferences.dart';

class CurrentTripService {
  static const String _currentTripKey = 'current_trip_id';

  static Future<void> setCurrentTrip(int? tripId) async {
    final prefs = await SharedPreferences.getInstance();
    if (tripId == null) {
      await prefs.remove(_currentTripKey);
    } else {
      await prefs.setInt(_currentTripKey, tripId);
    }
  }

  static Future<int?> getCurrentTripId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_currentTripKey);
  }

  static Future<void> clearCurrentTrip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentTripKey);
  }
}
