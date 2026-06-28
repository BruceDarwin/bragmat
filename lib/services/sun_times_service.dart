import 'dart:convert';
import 'package:http/http.dart' as http;

class SunTimesService {
  static final SunTimesService _instance = SunTimesService._internal();
  factory SunTimesService() => _instance;
  SunTimesService._internal();

  /// Calculate sunrise and sunset times for a given date and location
  /// Returns null if location is not provided or API fails
  Future<SunTimesInfo?> calculateSunTimes(DateTime date, {required double latitude, required double longitude}) async {
    if (latitude == null || longitude == null) {
      return null;
    }

    // Format date for API (YYYY-MM-DD)
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    
    // Build API URL
    final apiUrl = 'https://api.sunrise-sunset.org/json?lat=$latitude&lng=$longitude&date=$dateStr&formatted=0';

    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'];
        
        if (results == null) {
          return null;
        }

        // Parse UTC times from API
        final sunriseUTC = DateTime.parse(results['sunrise']);
        final sunsetUTC = DateTime.parse(results['sunset']);

        // Convert to local device time
        final sunriseLocal = sunriseUTC.toLocal();
        final sunsetLocal = sunsetUTC.toLocal();
        
        return SunTimesInfo(
          sunrise: sunriseLocal,
          sunset: sunsetLocal,
          date: date,
          latitude: latitude,
          longitude: longitude,
          timezoneOffset: 0,
          dataSource: 'sunrise-sunset.org',
        );
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Format time for display (e.g., "7:07 am")
  String formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute;
    final period = hour >= 12 ? 'pm' : 'am';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final displayMinute = minute.toString().padLeft(2, '0');
    return '$displayHour:$displayMinute $period';
  }

  /// Get complete sun times information
  Future<SunTimesInfo?> getSunTimesInfo(DateTime date, {required double latitude, required double longitude}) async {
    return await calculateSunTimes(date, latitude: latitude, longitude: longitude);
  }
}

class SunTimesInfo {
  final DateTime sunrise;
  final DateTime sunset;
  final DateTime date;
  final double latitude;
  final double longitude;
  final double timezoneOffset;
  final String dataSource;

  SunTimesInfo({
    required this.sunrise,
    required this.sunset,
    required this.date,
    required this.latitude,
    required this.longitude,
    required this.timezoneOffset,
    this.dataSource = 'unknown',
  });

  @override
  String toString() {
    final service = SunTimesService();
    return 'Sunrise: ${service.formatTime(sunrise)}, Sunset: ${service.formatTime(sunset)} ($dataSource)';
  }
}
