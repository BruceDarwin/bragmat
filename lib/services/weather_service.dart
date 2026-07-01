import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class WeatherData {
  final String? weatherCondition;
  final double? temperature;
  final double? humidity;
  final double? cloudCover;
  final double? windSpeed;
  final double? windDirection;
  final double? rainfall;
  final String dataSource;

  WeatherData({
    this.weatherCondition,
    this.temperature,
    this.humidity,
    this.cloudCover,
    this.windSpeed,
    this.windDirection,
    this.rainfall,
    required this.dataSource,
  });
}

class WeatherService {
  static final WeatherService _instance = WeatherService._internal();
  factory WeatherService() => _instance;
  WeatherService._internal();

  final String _baseUrl = 'https://api.open-meteo.com/v1';

  /// Safely parse a numeric value (int, double, or string) to double?
  double? _parseNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// Fetch weather data for a location and time
  /// Returns null if the request fails
  Future<WeatherData?> fetchWeather(
    double latitude,
    double longitude,
    DateTime dateTime,
  ) async {
    try {
      // Build URL with current weather parameters
      final url = Uri.parse('$_baseUrl/forecast').replace(queryParameters: {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'current': 'temperature_2m,relative_humidity_2m,cloud_cover,wind_speed_10m,wind_direction_10m,weather_code,precipitation',
        'timezone': 'auto',
      });

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('Weather request timed out');
          throw Exception('Request timeout after 10 seconds');
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseWeatherResponse(data);
      } else {
        debugPrint('Weather API failed with status: ${response.statusCode}');
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error fetching weather: $e');
      rethrow;
    }
  }

  /// Parse Open-Meteo response and extract weather data
  WeatherData _parseWeatherResponse(Map<String, dynamic> data) {
    final current = data['current'] as Map<String, dynamic>?;
    
    if (current == null) {
      debugPrint('No current weather data in response');
      return WeatherData(dataSource: 'Open-Meteo');
    }

    // Extract values using safe numeric parsing
    final temperature = _parseNum(current['temperature_2m']);
    final humidity = _parseNum(current['relative_humidity_2m']);
    final cloudCover = _parseNum(current['cloud_cover']);
    final windSpeed = _parseNum(current['wind_speed_10m']);
    final windDirection = _parseNum(current['wind_direction_10m']);
    final weatherCode = _parseNum(current['weather_code'])?.toInt();
    final precipitation = _parseNum(current['precipitation']);

    // Convert WMO weather code to condition string
    final weatherCondition = _weatherCodeToCondition(weatherCode);

    return WeatherData(
      weatherCondition: weatherCondition,
      temperature: temperature,
      humidity: humidity,
      cloudCover: cloudCover,
      windSpeed: windSpeed,
      windDirection: windDirection,
      rainfall: precipitation,
      dataSource: 'Open-Meteo',
    );
  }

  /// Convert WMO weather code to readable condition
  String _weatherCodeToCondition(int? code) {
    if (code == null) return 'Unknown';

    // WMO Weather Interpretation Codes (WW)
    switch (code) {
      case 0:
        return 'Clear';
      case 1:
      case 2:
      case 3:
        return 'Partly Cloudy';
      case 45:
      case 48:
        return 'Fog';
      case 51:
      case 53:
      case 55:
        return 'Light Rain';
      case 56:
      case 57:
        return 'Freezing Drizzle';
      case 61:
      case 63:
      case 65:
        return 'Rain';
      case 66:
      case 67:
        return 'Freezing Rain';
      case 71:
      case 73:
      case 75:
        return 'Snow';
      case 77:
        return 'Snow Grains';
      case 80:
      case 81:
      case 82:
        return 'Rain Showers';
      case 85:
      case 86:
        return 'Snow Showers';
      case 95:
        return 'Storm';
      case 96:
      case 99:
        return 'Thunderstorm';
      default:
        return 'Unknown';
    }
  }

  /// Convert wind direction degrees to compass direction
  String windDirectionToCompass(double? degrees) {
    if (degrees == null) return 'Unknown';

    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final step = 360 / directions.length;
    
    final index = ((degrees + step / 2) / step).floor() % directions.length;
    return directions[index];
  }
}
