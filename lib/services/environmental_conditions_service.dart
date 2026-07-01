import '../database/database_helper.dart';
import '../models/environmental_condition.dart';
import '../models/catch.dart';
import 'moon_phase_service.dart';
import 'sun_times_service.dart';
import 'weather_service.dart';
import 'package:flutter/foundation.dart';

class EnvironmentalConditionsService {
  static final EnvironmentalConditionsService _instance = EnvironmentalConditionsService._internal();
  factory EnvironmentalConditionsService() => _instance;
  EnvironmentalConditionsService._internal();

  final MoonPhaseService _moonPhaseService = MoonPhaseService();
  final SunTimesService _sunTimesService = SunTimesService();
  final WeatherService _weatherService = WeatherService();

  /// Check if a string value is blank (null, empty, or whitespace only)
  bool _isBlank(String? value) {
    return value == null || value.trim().isEmpty;
  }

  /// Merge manual and API text values, preferring manual if not blank
  String? _useManualOrApiText(String? manualValue, String? apiValue) {
    if (!_isBlank(manualValue)) {
      return manualValue;
    }
    return apiValue;
  }

  /// Merge manual and API numeric values, preferring manual if not null
  double? _useManualOrApiNumber(double? manualValue, double? apiValue) {
    if (manualValue != null) {
      return manualValue;
    }
    return apiValue;
  }

  /// Create a new environmental condition record
  /// Automatically calculates moon phase and sun times if coordinates are provided
  Future<int> createEnvironmentalCondition(EnvironmentalCondition condition) async {
    final db = await DatabaseHelper.instance.database;
    
    // Calculate moon phase and sun times if coordinates are available
    EnvironmentalCondition calculatedCondition = condition;
    if (condition.latitude != null && condition.longitude != null) {
      calculatedCondition = await _calculateEnvironmentalData(condition);
    }
    
    // Set timestamps
    final now = DateTime.now();
    if (calculatedCondition.createdAt == DateTime(0)) {
      calculatedCondition = calculatedCondition.copyWith(createdAt: now);
    }
    if (calculatedCondition.updatedAt == DateTime(0)) {
      calculatedCondition = calculatedCondition.copyWith(updatedAt: now);
    }
    
    return await db.insert('environmental_conditions', calculatedCondition.toMap());
  }

  /// Update an existing environmental condition record
  /// Recalculates moon phase and sun times if coordinates are provided
  Future<int> updateEnvironmentalCondition(EnvironmentalCondition condition) async {
    final db = await DatabaseHelper.instance.database;
    
    // Calculate moon phase and sun times if coordinates are available
    EnvironmentalCondition calculatedCondition = condition;
    if (condition.latitude != null && condition.longitude != null) {
      calculatedCondition = await _calculateEnvironmentalData(condition);
    }
    
    // Update timestamp
    calculatedCondition = calculatedCondition.copyWith(updatedAt: DateTime.now());
    
    return await db.update(
      'environmental_conditions',
      calculatedCondition.toMap(),
      where: 'id = ?',
      whereArgs: [condition.id],
    );
  }

  /// Get environmental condition by ID
  Future<EnvironmentalCondition?> getEnvironmentalConditionById(int id) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'environmental_conditions',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (maps.isEmpty) return null;
    return EnvironmentalCondition.fromMap(maps.first);
  }

  /// Get environmental condition for a catch
  Future<EnvironmentalCondition?> getEnvironmentalConditionForCatch(int catchId) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'environmental_conditions',
      where: 'catch_id = ?',
      whereArgs: [catchId],
    );
    
    if (maps.isEmpty) return null;
    return EnvironmentalCondition.fromMap(maps.first);
  }

  /// Get environmental condition for a trip
  Future<EnvironmentalCondition?> getEnvironmentalConditionForTrip(int tripId) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'environmental_conditions',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
    
    if (maps.isEmpty) return null;
    return EnvironmentalCondition.fromMap(maps.first);
  }

  /// Get all environmental conditions for a trip
  Future<List<EnvironmentalCondition>> getEnvironmentalConditionsForTrip(int tripId) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'environmental_conditions',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'observation_date_time ASC',
    );
    
    return maps.map((map) => EnvironmentalCondition.fromMap(map)).toList();
  }

  /// Delete an environmental condition
  Future<int> deleteEnvironmentalCondition(int id) async {
    final db = await DatabaseHelper.instance.database;
    return await db.delete(
      'environmental_conditions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete environmental condition for a catch
  Future<int> deleteEnvironmentalConditionForCatch(int catchId) async {
    final db = await DatabaseHelper.instance.database;
    return await db.delete(
      'environmental_conditions',
      where: 'catch_id = ?',
      whereArgs: [catchId],
    );
  }

  /// Delete environmental condition for a trip
  Future<int> deleteEnvironmentalConditionForTrip(int tripId) async {
    final db = await DatabaseHelper.instance.database;
    return await db.delete(
      'environmental_conditions',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
  }

  /// Calculate environmental data (moon phase, sun times, weather) from coordinates
  Future<EnvironmentalCondition> _calculateEnvironmentalData(EnvironmentalCondition condition) async {
    if (condition.latitude == null || condition.longitude == null) {
      return condition;
    }

    // Calculate moon phase
    final moonInfo = _moonPhaseService.getMoonPhaseInfo(
      condition.observationDateTime,
      latitude: condition.latitude,
      longitude: condition.longitude,
    );

    // Calculate sun times (now async)
    final sunInfo = await _sunTimesService.getSunTimesInfo(
      condition.observationDateTime,
      latitude: condition.latitude!,
      longitude: condition.longitude!,
    );

    // Fetch weather data (non-blocking, continues on failure)
    WeatherData? weatherData;
    try {
      weatherData = await _weatherService.fetchWeather(
        condition.latitude!,
        condition.longitude!,
        condition.observationDateTime,
      );
    } catch (e) {
      debugPrint('Weather fetch failed, continuing without weather data: $e');
    }

    // Convert wind direction degrees to compass if available
    String? windDirectionCompass;
    if (weatherData?.windDirection != null) {
      windDirectionCompass = _weatherService.windDirectionToCompass(weatherData!.windDirection);
    }

    // Merge manual and API weather values
    final mergedWeatherCondition = _useManualOrApiText(condition.weatherCondition, weatherData?.weatherCondition);
    final mergedTemperature = _useManualOrApiNumber(condition.temperature, weatherData?.temperature);
    final mergedHumidity = _useManualOrApiNumber(condition.humidity, weatherData?.humidity);
    final mergedCloudCover = _useManualOrApiNumber(condition.cloudCover, weatherData?.cloudCover);
    final mergedWindSpeed = _useManualOrApiNumber(condition.windSpeed, weatherData?.windSpeed);
    final mergedWindDirection = _useManualOrApiText(condition.windDirection, windDirectionCompass);
    final mergedRainfall = _useManualOrApiNumber(condition.rainfall, weatherData?.rainfall);

    return condition.copyWith(
      moonPhase: moonInfo.phaseName,
      moonIllumination: moonInfo.illumination,
      sunriseTime: sunInfo?.sunrise,
      sunsetTime: sunInfo?.sunset,
      weatherCondition: mergedWeatherCondition,
      temperature: mergedTemperature,
      humidity: mergedHumidity,
      cloudCover: mergedCloudCover,
      windSpeed: mergedWindSpeed,
      windDirection: mergedWindDirection,
      rainfall: mergedRainfall,
      dataSource: weatherData != null ? 'Open-Meteo' : (condition.dataSource ?? 'Calculated'),
    );
  }

  /// Create or update environmental condition for a catch
  /// This is a convenience method for the Add/Edit Catch screen
  Future<int> saveEnvironmentalConditionForCatch(
    int catchId,
    DateTime observationDateTime,
    double? latitude,
    double? longitude, {
    String? tideStage,
    String? tideStrength,
    String? tideNotes,
    double? tideHeight,
    String? tideMovement,
    String? tideStation,
    String? weatherCondition,
    double? temperature,
    double? humidity,
    double? cloudCover,
    double? windSpeed,
    String? windDirection,
    double? barometricPressure,
    double? rainfall,
    String? riverFlow,
    String? waterClarity,
    String? notes,
  }) async {
    // Check if environmental condition already exists for this catch
    final existing = await getEnvironmentalConditionForCatch(catchId);
    
    final condition = EnvironmentalCondition(
      id: existing?.id,
      catchId: catchId,
      tripId: null,
      observationDateTime: observationDateTime,
      latitude: latitude,
      longitude: longitude,
      tideStage: tideStage,
      tideStrength: tideStrength,
      tideNotes: tideNotes,
      tideHeight: tideHeight,
      tideMovement: tideMovement,
      tideStation: tideStation,
      weatherCondition: weatherCondition,
      temperature: temperature,
      humidity: humidity,
      cloudCover: cloudCover,
      windSpeed: windSpeed,
      windDirection: windDirection,
      barometricPressure: barometricPressure,
      rainfall: rainfall,
      riverFlow: riverFlow,
      waterClarity: waterClarity,
      dataSource: 'Manual',
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    if (existing != null) {
      return await updateEnvironmentalCondition(condition);
    } else {
      return await createEnvironmentalCondition(condition);
    }
  }

  /// Get formatted environmental summary for display
  String getEnvironmentalSummary(EnvironmentalCondition? condition) {
    if (condition == null) return 'No conditions recorded';

    final parts = <String>[];

    if (condition.moonPhase != null) {
      parts.add('Moon: ${condition.moonPhase}');
    }

    if (condition.sunsetTime != null) {
      parts.add('Sunset: ${_sunTimesService.formatTime(condition.sunsetTime!)}');
    }

    if (condition.tideStage != null && condition.tideStage != 'Unknown') {
      parts.add('Tide: ${condition.tideStage}');
    }

    if (condition.weatherCondition != null && condition.weatherCondition != 'Unknown') {
      parts.add('Weather: ${condition.weatherCondition}');
    }

    if (condition.windDirection != null && condition.windDirection != 'Unknown') {
      if (condition.windSpeed != null) {
        parts.add('Wind: ${condition.windDirection} ${condition.windSpeed} km/h');
      } else {
        parts.add('Wind: ${condition.windDirection}');
      }
    }

    if (condition.waterClarity != null && condition.waterClarity != 'Unknown') {
      parts.add('Water: ${condition.waterClarity}');
    }

    return parts.isEmpty ? 'No conditions recorded' : parts.join(', ');
  }

  /// Upsert calculated environmental conditions for a catch
  /// This method should be called after every successful catch save/update
  /// It handles calculated conditions (moon/sun) separately from manual conditions
  Future<EnvironmentalCondition?> upsertCalculatedConditionsForCatch(Catch catchItem) async {
    if (catchItem.id == null) {
      debugPrint('ERROR: Catch ID is null');
      return null;
    }

    final hasCoordinates = catchItem.latitude != null && catchItem.longitude != null;

    // Get existing environmental condition
    final existing = await getEnvironmentalConditionForCatch(catchItem.id!);

    final observationDateTime = catchItem.dateCaught ?? catchItem.createdAt;

    // If no coordinates and no existing manual data, delete if exists and return
    if (!hasCoordinates) {
      if (existing != null) {
        // Check if existing has any manual data
        final hasManualData = _hasManualData(existing);
        
        if (!hasManualData) {
          await deleteEnvironmentalConditionForCatch(catchItem.id!);
          return null;
        } else {
          return existing;
        }
      } else {
        return null;
      }
    }
    
    final condition = EnvironmentalCondition(
      id: existing?.id,
      catchId: catchItem.id!,
      tripId: null,
      observationDateTime: observationDateTime,
      latitude: catchItem.latitude,
      longitude: catchItem.longitude,
      // Preserve existing manual data
      tideStage: existing?.tideStage,
      tideStrength: existing?.tideStrength,
      tideNotes: existing?.tideNotes,
      tideHeight: existing?.tideHeight,
      tideMovement: existing?.tideMovement,
      tideStation: existing?.tideStation,
      weatherCondition: existing?.weatherCondition,
      temperature: existing?.temperature,
      humidity: existing?.humidity,
      cloudCover: existing?.cloudCover,
      windSpeed: existing?.windSpeed,
      windDirection: existing?.windDirection,
      barometricPressure: existing?.barometricPressure,
      rainfall: existing?.rainfall,
      riverFlow: existing?.riverFlow,
      waterClarity: existing?.waterClarity,
      dataSource: existing?.dataSource ?? 'Calculated',
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    EnvironmentalCondition savedCondition;
    if (existing != null) {
      await updateEnvironmentalCondition(condition);
      savedCondition = condition;
    } else {
      final id = await createEnvironmentalCondition(condition);
      savedCondition = condition.copyWith(id: id);
    }
    
    return savedCondition;
  }

  /// Check if an environmental condition has any manual data (non-calculated fields)
  bool _hasManualData(EnvironmentalCondition condition) {
    return condition.tideStage != null ||
        condition.tideStrength != null ||
        !_isBlank(condition.tideNotes) ||
        condition.tideHeight != null ||
        condition.tideMovement != null ||
        !_isBlank(condition.tideStation) ||
        !_isBlank(condition.weatherCondition) ||
        condition.temperature != null ||
        condition.humidity != null ||
        condition.cloudCover != null ||
        condition.windSpeed != null ||
        !_isBlank(condition.windDirection) ||
        condition.barometricPressure != null ||
        condition.rainfall != null ||
        condition.riverFlow != null ||
        condition.waterClarity != null;
  }

  /// Get catch counts grouped by tide stage for a trip
  /// Returns a map of tide stage to catch count
  Future<Map<String, int>> catchesByTideStage(int tripId) async {
    final db = await DatabaseHelper.instance.database;
    final catches = await db.query(
      'catches',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
    
    final tideStageCounts = <String, int>{};
    
    for (final catchMap in catches) {
      final catchId = catchMap['id'] as int;
      final condition = await getEnvironmentalConditionForCatch(catchId);
      
      if (condition != null && condition.tideStage != null && condition.tideStage != 'Unknown') {
        tideStageCounts[condition.tideStage!] = (tideStageCounts[condition.tideStage!] ?? 0) + 1;
      }
    }
    
    return tideStageCounts;
  }

  /// Get catch counts grouped by tide strength for a trip
  /// Returns a map of tide strength to catch count
  Future<Map<String, int>> catchesByTideStrength(int tripId) async {
    final db = await DatabaseHelper.instance.database;
    final catches = await db.query(
      'catches',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
    
    final tideStrengthCounts = <String, int>{};
    
    for (final catchMap in catches) {
      final catchId = catchMap['id'] as int;
      final condition = await getEnvironmentalConditionForCatch(catchId);
      
      if (condition != null && condition.tideStrength != null) {
        tideStrengthCounts[condition.tideStrength!] = (tideStrengthCounts[condition.tideStrength!] ?? 0) + 1;
      }
    }
    
    return tideStrengthCounts;
  }

  /// Get the most successful tide stage for a trip
  /// Returns the tide stage with the highest catch count, or null if no data
  Future<String?> mostSuccessfulTideStage(int tripId) async {
    final stageCounts = await catchesByTideStage(tripId);
    
    if (stageCounts.isEmpty) return null;
    
    final mostSuccessful = stageCounts.entries.reduce((a, b) => a.value > b.value ? a : b);
    return mostSuccessful.key;
  }

  /// Get the most successful tide strength for a trip
  /// Returns the tide strength with the highest catch count, or null if no data
  Future<String?> mostSuccessfulTideStrength(int tripId) async {
    final strengthCounts = await catchesByTideStrength(tripId);
    
    if (strengthCounts.isEmpty) return null;
    
    final mostSuccessful = strengthCounts.entries.reduce((a, b) => a.value > b.value ? a : b);
    return mostSuccessful.key;
  }

  /// Get catch counts grouped by weather condition for a trip
  /// Returns a map of weather condition to catch count
  Future<Map<String, int>> catchesByWeatherCondition(int tripId) async {
    final db = await DatabaseHelper.instance.database;
    final catches = await db.query(
      'catches',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
    
    final weatherConditionCounts = <String, int>{};
    
    for (final catchMap in catches) {
      final catchId = catchMap['id'] as int;
      final condition = await getEnvironmentalConditionForCatch(catchId);
      
      if (condition != null && condition.weatherCondition != null && condition.weatherCondition != 'Unknown') {
        weatherConditionCounts[condition.weatherCondition!] = (weatherConditionCounts[condition.weatherCondition!] ?? 0) + 1;
      }
    }
    
    return weatherConditionCounts;
  }

  /// Get catch counts grouped by wind direction for a trip
  /// Returns a map of wind direction to catch count
  Future<Map<String, int>> catchesByWindDirection(int tripId) async {
    final db = await DatabaseHelper.instance.database;
    final catches = await db.query(
      'catches',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
    
    final windDirectionCounts = <String, int>{};
    
    for (final catchMap in catches) {
      final catchId = catchMap['id'] as int;
      final condition = await getEnvironmentalConditionForCatch(catchId);
      
      if (condition != null && condition.windDirection != null && condition.windDirection != 'Unknown') {
        windDirectionCounts[condition.windDirection!] = (windDirectionCounts[condition.windDirection!] ?? 0) + 1;
      }
    }
    
    return windDirectionCounts;
  }

  /// Get catch counts grouped by wind strength for a trip
  /// Returns a map of wind strength category to catch count
  /// Categories: Calm (<10 km/h), Light (10-20 km/h), Moderate (20-30 km/h), Strong (>30 km/h)
  Future<Map<String, int>> catchesByWindStrength(int tripId) async {
    final db = await DatabaseHelper.instance.database;
    final catches = await db.query(
      'catches',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
    
    final windStrengthCounts = <String, int>{};
    
    for (final catchMap in catches) {
      final catchId = catchMap['id'] as int;
      final condition = await getEnvironmentalConditionForCatch(catchId);
      
      if (condition != null && condition.windSpeed != null) {
        final speed = condition.windSpeed!;
        String category;
        if (speed < 10) {
          category = 'Calm';
        } else if (speed < 20) {
          category = 'Light';
        } else if (speed < 30) {
          category = 'Moderate';
        } else {
          category = 'Strong';
        }
        windStrengthCounts[category] = (windStrengthCounts[category] ?? 0) + 1;
      }
    }
    
    return windStrengthCounts;
  }

  /// Get average temperature for all catches in a trip
  /// Returns null if no temperature data available
  Future<double?> averageCatchTemperature(int tripId) async {
    final db = await DatabaseHelper.instance.database;
    final catches = await db.query(
      'catches',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
    
    final temperatures = <double>[];
    
    for (final catchMap in catches) {
      final catchId = catchMap['id'] as int;
      final condition = await getEnvironmentalConditionForCatch(catchId);
      
      if (condition != null && condition.temperature != null) {
        temperatures.add(condition.temperature!);
      }
    }
    
    if (temperatures.isEmpty) return null;
    
    return temperatures.reduce((a, b) => a + b) / temperatures.length;
  }

  /// Get average humidity for all catches in a trip
  /// Returns null if no humidity data available
  Future<double?> averageCatchHumidity(int tripId) async {
    final db = await DatabaseHelper.instance.database;
    final catches = await db.query(
      'catches',
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
    
    final humidities = <double>[];
    
    for (final catchMap in catches) {
      final catchId = catchMap['id'] as int;
      final condition = await getEnvironmentalConditionForCatch(catchId);
      
      if (condition != null && condition.humidity != null) {
        humidities.add(condition.humidity!);
      }
    }
    
    if (humidities.isEmpty) return null;
    
    return humidities.reduce((a, b) => a + b) / humidities.length;
  }

  // ==================== Environmental Insights Methods ====================

  /// Get all environmental conditions with catch data for analysis
  Future<List<Map<String, dynamic>>> _getEnvironmentalDataWithCatches() async {
    final db = await DatabaseHelper.instance.database;
    
    final results = await db.rawQuery('''
      SELECT 
        ec.*,
        c.fish_type,
        c.length_cm,
        c.date_caught
      FROM environmental_conditions ec
      INNER JOIN catches c ON ec.catch_id = c.id
      ORDER BY c.date_caught DESC
    ''');
    
    return results;
  }

  /// Get most common moon phase
  /// Returns {phase: String, count: int} or null if no data
  Future<Map<String, dynamic>?> mostCommonMoonPhase({int minCount = 3}) async {
    final data = await _getEnvironmentalDataWithCatches();
    final moonPhases = <String, int>{};
    
    for (final row in data) {
      final phase = row['moon_phase'] as String?;
      if (phase != null && phase.isNotEmpty) {
        moonPhases[phase] = (moonPhases[phase] ?? 0) + 1;
      }
    }
    
    if (moonPhases.isEmpty) return null;
    
    String? mostCommon;
    int maxCount = 0;
    moonPhases.forEach((phase, count) {
      if (count > maxCount) {
        maxCount = count;
        mostCommon = phase;
      }
    });
    
    if (maxCount < minCount) return null;
    
    return {'phase': mostCommon, 'count': maxCount};
  }

  /// Get most successful moon phase (by average fish length)
  /// Returns {phase: String, count: int, avgLength: double} or null if no data
  Future<Map<String, dynamic>?> mostSuccessfulMoonPhaseInsights({int minCount = 3}) async {
    final data = await _getEnvironmentalDataWithCatches();
    final moonPhases = <String, List<double>>{};
    
    for (final row in data) {
      final phase = row['moon_phase'] as String?;
      final length = row['length_cm'] as int?;
      if (phase != null && phase.isNotEmpty && length != null) {
        moonPhases.putIfAbsent(phase, () => []).add(length.toDouble());
      }
    }
    
    if (moonPhases.isEmpty) return null;
    
    String? mostSuccessful;
    double maxAvgLength = 0;
    int maxCount = 0;
    
    moonPhases.forEach((phase, lengths) {
      if (lengths.length >= minCount) {
        final avgLength = lengths.reduce((a, b) => a + b) / lengths.length;
        if (avgLength > maxAvgLength) {
          maxAvgLength = avgLength;
          mostSuccessful = phase;
          maxCount = lengths.length;
        }
      }
    });
    
    if (mostSuccessful == null) return null;
    
    return {'phase': mostSuccessful, 'count': maxCount, 'avgLength': maxAvgLength};
  }

  /// Get most common tide stage
  /// Returns {stage: String, count: int} or null if no data
  Future<Map<String, dynamic>?> mostCommonTideStage({int minCount = 3}) async {
    final data = await _getEnvironmentalDataWithCatches();
    final tideStages = <String, int>{};
    
    for (final row in data) {
      final stage = row['tide_stage'] as String?;
      if (stage != null && stage.isNotEmpty) {
        tideStages[stage] = (tideStages[stage] ?? 0) + 1;
      }
    }
    
    if (tideStages.isEmpty) return null;
    
    String? mostCommon;
    int maxCount = 0;
    tideStages.forEach((stage, count) {
      if (count > maxCount) {
        maxCount = count;
        mostCommon = stage;
      }
    });
    
    if (maxCount < minCount) return null;
    
    return {'stage': mostCommon, 'count': maxCount};
  }

  /// Get most successful tide stage (by average fish length)
  /// Returns {stage: String, count: int, avgLength: double} or null if no data
  Future<Map<String, dynamic>?> mostSuccessfulTideStageInsights({int minCount = 3}) async {
    final data = await _getEnvironmentalDataWithCatches();
    final tideStages = <String, List<double>>{};
    
    for (final row in data) {
      final stage = row['tide_stage'] as String?;
      final length = row['length_cm'] as int?;
      if (stage != null && stage.isNotEmpty && length != null) {
        tideStages.putIfAbsent(stage, () => []).add(length.toDouble());
      }
    }
    
    if (tideStages.isEmpty) return null;
    
    String? mostSuccessful;
    double maxAvgLength = 0;
    int maxCount = 0;
    
    tideStages.forEach((stage, lengths) {
      if (lengths.length >= minCount) {
        final avgLength = lengths.reduce((a, b) => a + b) / lengths.length;
        if (avgLength > maxAvgLength) {
          maxAvgLength = avgLength;
          mostSuccessful = stage;
          maxCount = lengths.length;
        }
      }
    });
    
    if (mostSuccessful == null) return null;
    
    return {'stage': mostSuccessful, 'count': maxCount, 'avgLength': maxAvgLength};
  }

  /// Get most common weather condition
  /// Returns {condition: String, count: int} or null if no data
  Future<Map<String, dynamic>?> mostCommonWeather({int minCount = 3}) async {
    final data = await _getEnvironmentalDataWithCatches();
    final weatherConditions = <String, int>{};
    
    for (final row in data) {
      final condition = row['weather_condition'] as String?;
      if (condition != null && condition.isNotEmpty) {
        weatherConditions[condition] = (weatherConditions[condition] ?? 0) + 1;
      }
    }
    
    if (weatherConditions.isEmpty) return null;
    
    String? mostCommon;
    int maxCount = 0;
    weatherConditions.forEach((condition, count) {
      if (count > maxCount) {
        maxCount = count;
        mostCommon = condition;
      }
    });
    
    if (maxCount < minCount) return null;
    
    return {'condition': mostCommon, 'count': maxCount};
  }

  /// Get most successful weather condition (by average fish length)
  /// Returns {condition: String, count: int, avgLength: double} or null if no data
  Future<Map<String, dynamic>?> mostSuccessfulWeatherInsights({int minCount = 3}) async {
    final data = await _getEnvironmentalDataWithCatches();
    final weatherConditions = <String, List<double>>{};
    
    for (final row in data) {
      final condition = row['weather_condition'] as String?;
      final length = row['length_cm'] as int?;
      if (condition != null && condition.isNotEmpty && length != null) {
        weatherConditions.putIfAbsent(condition, () => []).add(length.toDouble());
      }
    }
    
    if (weatherConditions.isEmpty) return null;
    
    String? mostSuccessful;
    double maxAvgLength = 0;
    int maxCount = 0;
    
    weatherConditions.forEach((condition, lengths) {
      if (lengths.length >= minCount) {
        final avgLength = lengths.reduce((a, b) => a + b) / lengths.length;
        if (avgLength > maxAvgLength) {
          maxAvgLength = avgLength;
          mostSuccessful = condition;
          maxCount = lengths.length;
        }
      }
    });
    
    if (mostSuccessful == null) return null;
    
    return {'condition': mostSuccessful, 'count': maxCount, 'avgLength': maxAvgLength};
  }

  /// Get most common wind direction
  /// Returns {direction: String, count: int} or null if no data
  Future<Map<String, dynamic>?> mostCommonWindDirection({int minCount = 3}) async {
    final data = await _getEnvironmentalDataWithCatches();
    final windDirections = <String, int>{};
    
    for (final row in data) {
      final direction = row['wind_direction'] as String?;
      if (direction != null && direction.isNotEmpty) {
        windDirections[direction] = (windDirections[direction] ?? 0) + 1;
      }
    }
    
    if (windDirections.isEmpty) return null;
    
    String? mostCommon;
    int maxCount = 0;
    windDirections.forEach((direction, count) {
      if (count > maxCount) {
        maxCount = count;
        mostCommon = direction;
      }
    });
    
    if (maxCount < minCount) return null;
    
    return {'direction': mostCommon, 'count': maxCount};
  }

  /// Get most successful wind direction (by average fish length)
  /// Returns {direction: String, count: int, avgLength: double} or null if no data
  Future<Map<String, dynamic>?> mostSuccessfulWindDirectionInsights({int minCount = 3}) async {
    final data = await _getEnvironmentalDataWithCatches();
    final windDirections = <String, List<double>>{};
    
    for (final row in data) {
      final direction = row['wind_direction'] as String?;
      final length = row['length_cm'] as int?;
      if (direction != null && direction.isNotEmpty && length != null) {
        windDirections.putIfAbsent(direction, () => []).add(length.toDouble());
      }
    }
    
    if (windDirections.isEmpty) return null;
    
    String? mostSuccessful;
    double maxAvgLength = 0;
    int maxCount = 0;
    
    windDirections.forEach((direction, lengths) {
      if (lengths.length >= minCount) {
        final avgLength = lengths.reduce((a, b) => a + b) / lengths.length;
        if (avgLength > maxAvgLength) {
          maxAvgLength = avgLength;
          mostSuccessful = direction;
          maxCount = lengths.length;
        }
      }
    });
    
    if (mostSuccessful == null) return null;
    
    return {'direction': mostSuccessful, 'count': maxCount, 'avgLength': maxAvgLength};
  }

  /// Get average catch temperature insights
  /// Returns {avg: double, min: double, max: double, minCatch: Map, maxCatch: Map} or null if no data
  Future<Map<String, dynamic>?> averageCatchTemperatureInsights() async {
    final data = await _getEnvironmentalDataWithCatches();
    final temperatures = <double>[];
    Map<String, dynamic>? minCatch;
    Map<String, dynamic>? maxCatch;
    double? minTemp;
    double? maxTemp;
    
    for (final row in data) {
      final temp = row['temperature'] as double?;
      if (temp != null) {
        temperatures.add(temp);
        if (minTemp == null || temp < minTemp) {
          minTemp = temp;
          minCatch = {
            'temperature': temp,
            'fishType': row['fish_type'],
            'dateCaught': row['date_caught'],
          };
        }
        if (maxTemp == null || temp > maxTemp) {
          maxTemp = temp;
          maxCatch = {
            'temperature': temp,
            'fishType': row['fish_type'],
            'dateCaught': row['date_caught'],
          };
        }
      }
    }
    
    if (temperatures.isEmpty) return null;
    
    final avg = temperatures.reduce((a, b) => a + b) / temperatures.length;
    
    return {
      'avg': avg,
      'min': minTemp,
      'max': maxTemp,
      'minCatch': minCatch,
      'maxCatch': maxCatch,
    };
  }

  /// Get environmental insights summary
  /// Returns a map with all insights data
  Future<Map<String, dynamic>> getEnvironmentalInsights() async {
    final results = <String, dynamic>{};
    
    results['mostCommonMoonPhase'] = await mostCommonMoonPhase();
    results['mostSuccessfulMoonPhase'] = await mostSuccessfulMoonPhaseInsights();
    results['mostCommonTideStage'] = await mostCommonTideStage();
    results['mostSuccessfulTideStage'] = await mostSuccessfulTideStageInsights();
    results['mostCommonWeather'] = await mostCommonWeather();
    results['mostSuccessfulWeather'] = await mostSuccessfulWeatherInsights();
    results['mostCommonWindDirection'] = await mostCommonWindDirection();
    results['mostSuccessfulWindDirection'] = await mostSuccessfulWindDirectionInsights();
    results['averageTemperature'] = await averageCatchTemperatureInsights();
    
    return results;
  }
}
