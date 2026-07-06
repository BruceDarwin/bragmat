import '../database/database_helper.dart';
import '../models/environmental_condition.dart';
import '../models/catch.dart';
import 'moon_phase_service.dart';
import 'sun_times_service.dart';
import 'weather_service.dart';
import 'tide_service.dart';
import 'worldtides_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

/// Service for managing environmental conditions
/// Handles moon phase, sun times, weather, and tide data
/// 
/// TIDE ARCHITECTURE (post-refactor):
/// - Manual tide fields (tideStage, tideMovement, tideHeight) are for user-entered observations only
/// - Open-Meteo provides weather data only (no tide data)
/// - Manual tide data is marked as "Observed" with "Manual" data source
/// - Future tide integration will use official tide station data (WorldTides API)
/// - Tide context fields (tideContextPhrase, referenceTideEvent*) are for manual tide station observations
/// - Environmental backfill calculates moon, sun, and weather only (preserves manual tide)
class EnvironmentalConditionsService {
  static final EnvironmentalConditionsService _instance = EnvironmentalConditionsService._internal();
  factory EnvironmentalConditionsService() => _instance;
  EnvironmentalConditionsService._internal();

  final MoonPhaseService _moonPhaseService = MoonPhaseService();
  final SunTimesService _sunTimesService = SunTimesService();
  final WeatherService _weatherService = WeatherService();
  final WorldTidesService _worldTidesService = WorldTidesService();

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
  /// Preserves manual tide data - does not overwrite with API data
  Future<int> updateEnvironmentalCondition(EnvironmentalCondition condition) async {
    final db = await DatabaseHelper.instance.database;
    
    // Calculate moon phase and sun times if coordinates are available
    // Do NOT recalculate tide data - preserve manual values
    EnvironmentalCondition calculatedCondition = condition;
    if (condition.latitude != null && condition.longitude != null) {
      calculatedCondition = await _calculateEnvironmentalDataWithoutTide(condition);
    }
    
    // Update timestamp
    calculatedCondition = calculatedCondition.copyWith(updatedAt: DateTime.now());
    
    debugPrint('After calculation - tideStage: ${calculatedCondition.tideStage}');
    debugPrint('After calculation - tideMovement: ${calculatedCondition.tideMovement}');
    debugPrint('After calculation - tideDataSource: ${calculatedCondition.tideDataSource}');
    
    final result = await db.update(
      'environmental_conditions',
      calculatedCondition.toMap(),
      where: 'id = ?',
      whereArgs: [condition.id],
    );
    
    debugPrint('Database update result: $result');
    return result;
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

  /// Diagnostic: Analyze legacy tide data to identify records that may have been
  /// incorrectly populated by old Open-Meteo backfill logic
  /// Returns detailed counts for review before cleanup
  Future<Map<String, dynamic>> diagnoseLegacyTideData() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('environmental_conditions');
    
    int totalRecords = maps.length;
    int manualDataSource = 0;
    int likelyGenerated = 0;
    int likelyManual = 0;
    int hasTideContext = 0;
    int hasTideNotes = 0;
    int hasTideHeight = 0;
    int hasTideStation = 0;
    int hasTideStrength = 0;
    
    for (final map in maps) {
      final tideDataSource = map['tide_data_source'] as String?;
      final tideObservedOrEstimated = map['tide_observed_or_estimated'] as String?;
      final tideStage = map['tide_stage'] as String?;
      final tideMovement = map['tide_movement'] as String?;
      final tideStrength = map['tide_strength'] as String?;
      final tideNotes = map['tide_notes'] as String?;
      final tideHeight = map['tide_height'] as double?;
      final tideStation = map['tide_station'] as String?;
      final tideContextPhrase = map['tide_context_phrase'] as String?;
      
      if (tideDataSource == 'Manual' && tideObservedOrEstimated == 'Observed') {
        manualDataSource++;
        
        // Count indicators of manual entry
        final hasNotes = tideNotes != null && tideNotes.isNotEmpty;
        final hasHeight = tideHeight != null && tideHeight > 0;
        final hasStation = tideStation != null && tideStation.isNotEmpty;
        final hasStrength = tideStrength != null && tideStrength.isNotEmpty && tideStrength != 'Unknown';
        final hasContext = tideContextPhrase != null && tideContextPhrase.isNotEmpty;
        
        if (hasNotes) hasTideNotes++;
        if (hasHeight) hasTideHeight++;
        if (hasStation) hasTideStation++;
        if (hasStrength) hasTideStrength++;
        if (hasContext) hasTideContext++;
        
        // Determine if likely generated vs manual
        // Generated: has tideStage but lacks manual indicators
        // Manual: has manual indicators (notes, height, station, strength, context)
        if (tideStage != null && tideStage.isNotEmpty && tideStage != 'Unknown') {
          if (!hasNotes && !hasHeight && !hasStation && !hasStrength && !hasContext) {
            likelyGenerated++;
          } else {
            likelyManual++;
          }
        }
      }
      
      if (tideContextPhrase != null && tideContextPhrase.isNotEmpty) {
        hasTideContext++;
      }
    }
    
    debugPrint('=== Legacy Tide Data Diagnostic ===');
    debugPrint('Total environmental condition records: $totalRecords');
    debugPrint('Records with tideDataSource = Manual & Observed: $manualDataSource');
    debugPrint('Likely generated (no manual indicators): $likelyGenerated');
    debugPrint('Likely manual (has manual indicators): $likelyManual');
    debugPrint('Records with tide context phrase: $hasTideContext');
    debugPrint('Records with tide notes: $hasTideNotes');
    debugPrint('Records with tide height: $hasTideHeight');
    debugPrint('Records with tide station: $hasTideStation');
    debugPrint('Records with tide strength: $hasTideStrength');
    debugPrint('=== End Diagnostic ===');
    
    return {
      'total_records': totalRecords,
      'manual_data_source': manualDataSource,
      'likely_generated': likelyGenerated,
      'likely_manual': likelyManual,
      'has_tide_context': hasTideContext,
      'has_tide_notes': hasTideNotes,
      'has_tide_height': hasTideHeight,
      'has_tide_station': hasTideStation,
      'has_tide_strength': hasTideStrength,
    };
  }

  /// Cleanup: Clear legacy tide fields for records that were likely generated
  /// by old Open-Meteo backfill logic
  /// Only clears records that lack manual indicators (notes, height, station, strength, context)
  /// Requires explicit user confirmation before running
  /// Returns count of records cleaned
  Future<int> cleanupLegacyTideData() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('environmental_conditions');
    
    int cleanedCount = 0;
    
    for (final map in maps) {
      final id = map['id'] as int;
      final tideDataSource = map['tide_data_source'] as String?;
      final tideObservedOrEstimated = map['tide_observed_or_estimated'] as String?;
      final tideStage = map['tide_stage'] as String?;
      final tideMovement = map['tide_movement'] as String?;
      final tideStrength = map['tide_strength'] as String?;
      final tideNotes = map['tide_notes'] as String?;
      final tideHeight = map['tide_height'] as double?;
      final tideStation = map['tide_station'] as String?;
      final tideContextPhrase = map['tide_context_phrase'] as String?;
      
      // Only process records marked as Manual/Observed
      if (tideDataSource == 'Manual' && tideObservedOrEstimated == 'Observed') {
        // Check for manual indicators
        final hasNotes = tideNotes != null && tideNotes.isNotEmpty;
        final hasHeight = tideHeight != null && tideHeight > 0;
        final hasStation = tideStation != null && tideStation.isNotEmpty;
        final hasStrength = tideStrength != null && tideStrength.isNotEmpty && tideStrength != 'Unknown';
        final hasContext = tideContextPhrase != null && tideContextPhrase.isNotEmpty;
        
        // Only clear if no manual indicators present
        if (!hasNotes && !hasHeight && !hasStation && !hasStrength && !hasContext) {
          // Clear tide fields
          await db.update(
            'environmental_conditions',
            {
              'tide_stage': null,
              'tide_strength': null,
              'tide_movement': null,
              'tide_height': null,
              'tide_station': null,
              'tide_notes': null,
              'tide_data_source': null,
              'tide_observed_or_estimated': null,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          cleanedCount++;
        }
      }
    }
    
    debugPrint('=== Legacy Tide Data Cleanup ===');
    debugPrint('Records cleaned: $cleanedCount');
    debugPrint('=== End Cleanup ===');
    
    return cleanedCount;
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

  /// Calculate environmental data (moon phase, sun times, weather, tide) from coordinates
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

    // REFACTOR: Do NOT fetch or use Open-Meteo tide data
    // Manual tide fields are preserved for user-entered observations only
    // Future tide integration will use official tide station data (WorldTides)
    // Open-Meteo tide data is not written to manual fields anymore

    // Preserve existing manual tide data - do not overwrite with API data
    String? mergedTideStage = condition.tideStage;
    String? mergedTideMovement = condition.tideMovement;
    double? mergedTideHeight = condition.tideHeight;
    String? mergedTideDataSource = condition.tideDataSource;
    String? mergedTideConfidence = condition.tideConfidence;
    String? mergedDerivedTideStage = condition.derivedTideStage;
    String? mergedTideObservedOrEstimated = condition.tideObservedOrEstimated;
    String? mergedTideDiagnostics = condition.tideDiagnostics;

    // Mark manual tide as observed if present
    if (!_isBlank(condition.tideStage) && condition.tideStage != 'Unknown') {
      mergedTideObservedOrEstimated = 'Observed';
      mergedTideDataSource = 'Manual';
    }

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
      tideStage: mergedTideStage,
      tideMovement: mergedTideMovement,
      tideHeight: mergedTideHeight,
      tideDataSource: mergedTideDataSource,
      tideConfidence: mergedTideConfidence,
      derivedTideStage: mergedDerivedTideStage,
      tideObservedOrEstimated: mergedTideObservedOrEstimated,
      tideDiagnostics: mergedTideDiagnostics,
      dataSource: weatherData != null ? 'Open-Meteo' : (condition.dataSource ?? 'Calculated'),
    );
  }

  /// Calculate environmental data WITHOUT tide (moon, sun, weather only)
  /// Used when updating existing conditions to preserve manual tide data
  Future<EnvironmentalCondition> _calculateEnvironmentalDataWithoutTide(EnvironmentalCondition condition) async {
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

    // Preserve existing tide data - do NOT recalculate
    String? mergedTideDataSource = condition.tideDataSource;
    String? mergedTideObservedOrEstimated = condition.tideObservedOrEstimated;

    // If manual tide exists, ensure it's marked as Manual
    if (!_isBlank(condition.tideStage) && condition.tideStage != 'Unknown') {
      mergedTideObservedOrEstimated = 'Observed';
      mergedTideDataSource = 'Manual';
    }

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
      // Preserve tide data as-is
      tideStage: condition.tideStage,
      tideMovement: condition.tideMovement,
      tideHeight: condition.tideHeight,
      tideDataSource: mergedTideDataSource,
      tideConfidence: condition.tideConfidence,
      derivedTideStage: condition.derivedTideStage,
      tideObservedOrEstimated: mergedTideObservedOrEstimated,
      tideDiagnostics: condition.tideDiagnostics,
      // Preserve WorldTides tide context fields
      tideStationName: condition.tideStationName,
      tideStationDistanceKm: condition.tideStationDistanceKm,
      referenceTideEventType: condition.referenceTideEventType,
      referenceTideEventTime: condition.referenceTideEventTime,
      referenceTideEventHeight: condition.referenceTideEventHeight,
      referenceTideEventRelation: condition.referenceTideEventRelation,
      minutesFromReferenceTideEvent: condition.minutesFromReferenceTideEvent,
      previousTideEventType: condition.previousTideEventType,
      previousTideEventTime: condition.previousTideEventTime,
      previousTideEventHeight: condition.previousTideEventHeight,
      nextTideEventType: condition.nextTideEventType,
      nextTideEventTime: condition.nextTideEventTime,
      nextTideEventHeight: condition.nextTideEventHeight,
      tideContextPhrase: condition.tideContextPhrase,
      tideContextDataSource: condition.tideContextDataSource,
      tideContextConfidence: condition.tideContextConfidence,
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
    // Tide context fields
    String? tideStationName,
    String? referenceTideEventType,
    DateTime? referenceTideEventTime,
    double? referenceTideEventHeight,
    String? referenceTideEventRelation,
    int? minutesFromReferenceTideEvent,
    String? previousTideEventType,
    DateTime? previousTideEventTime,
    double? previousTideEventHeight,
    String? nextTideEventType,
    DateTime? nextTideEventTime,
    double? nextTideEventHeight,
    String? tideContextPhrase,
    String? tideContextDataSource,
    String? tideContextConfidence,
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
    
    // Determine tide data source and observation type
    String? mergedTideDataSource = existing?.tideDataSource;
    String? mergedTideObservedOrEstimated = existing?.tideObservedOrEstimated;
    
    // If manual tide data is being saved, mark as Manual
    if (tideStage != null || tideMovement != null || tideHeight != null) {
      mergedTideDataSource = 'Manual';
      mergedTideObservedOrEstimated = 'Observed';
    }
    
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
      // Tide context fields
      tideStationName: tideStationName,
      referenceTideEventType: referenceTideEventType,
      referenceTideEventTime: referenceTideEventTime,
      referenceTideEventHeight: referenceTideEventHeight,
      referenceTideEventRelation: referenceTideEventRelation,
      minutesFromReferenceTideEvent: minutesFromReferenceTideEvent,
      previousTideEventType: previousTideEventType,
      previousTideEventTime: previousTideEventTime,
      previousTideEventHeight: previousTideEventHeight,
      nextTideEventType: nextTideEventType,
      nextTideEventTime: nextTideEventTime,
      nextTideEventHeight: nextTideEventHeight,
      tideContextPhrase: tideContextPhrase,
      tideContextDataSource: tideContextDataSource,
      tideContextConfidence: tideContextConfidence,
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
      // Preserve existing automated tide data
      tideDataSource: mergedTideDataSource,
      tideConfidence: existing?.tideConfidence,
      derivedTideStage: existing?.derivedTideStage,
      tideObservedOrEstimated: mergedTideObservedOrEstimated,
      tideDiagnostics: existing?.tideDiagnostics,
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
  /// It handles calculated conditions (moon/sun/weather) and official tide context
  /// Preserves manual tide observations (does not overwrite)
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
    
    // Fetch official tide context from WorldTides if available
    // Only fetch if: no existing context, or date/time changed, or coordinates changed
    Map<String, dynamic>? tideContext;
    final shouldFetchWorldTides = await _shouldFetchWorldTidesContext(
      existing,
      catchItem,
      observationDateTime,
    );
    
    if (shouldFetchWorldTides && await _worldTidesService.isAvailable()) {
      try {
        tideContext = await _worldTidesService.getTideContextForLocation(
          catchItem.latitude!,
          catchItem.longitude!,
          observationDateTime,
        );
      } catch (e) {
        debugPrint('WorldTides: Error fetching tide context: $e');
        // Continue without tide context - don't fail the catch save
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
      // Use official tide context if available, otherwise preserve existing
      tideStationName: tideContext?['tideStationName'] ?? existing?.tideStationName,
      tideStationDistanceKm: tideContext?['tideStationDistanceKm'] ?? existing?.tideStationDistanceKm,
      referenceTideEventType: tideContext?['referenceTideEventType'] ?? existing?.referenceTideEventType,
      referenceTideEventTime: tideContext?['referenceTideEventTime'] ?? existing?.referenceTideEventTime,
      referenceTideEventHeight: tideContext?['referenceTideEventHeight'] ?? existing?.referenceTideEventHeight,
      referenceTideEventRelation: tideContext?['referenceTideEventRelation'] ?? existing?.referenceTideEventRelation,
      minutesFromReferenceTideEvent: tideContext?['minutesFromReferenceTideEvent'] ?? existing?.minutesFromReferenceTideEvent,
      previousTideEventType: tideContext?['previousTideEventType'] ?? existing?.previousTideEventType,
      previousTideEventTime: tideContext?['previousTideEventTime'] ?? existing?.previousTideEventTime,
      previousTideEventHeight: tideContext?['previousTideEventHeight'] ?? existing?.previousTideEventHeight,
      nextTideEventType: tideContext?['nextTideEventType'] ?? existing?.nextTideEventType,
      nextTideEventTime: tideContext?['nextTideEventTime'] ?? existing?.nextTideEventTime,
      nextTideEventHeight: tideContext?['nextTideEventHeight'] ?? existing?.nextTideEventHeight,
      tideContextPhrase: tideContext?['tideContextPhrase'] ?? existing?.tideContextPhrase,
      tideContextDataSource: tideContext?['tideContextDataSource'] ?? existing?.tideContextDataSource,
      tideContextConfidence: tideContext?['tideContextConfidence'] ?? existing?.tideContextConfidence,
      // Preserve existing automated tide data
      tideDataSource: existing?.tideDataSource,
      tideConfidence: existing?.tideConfidence,
      derivedTideStage: existing?.derivedTideStage,
      tideObservedOrEstimated: existing?.tideObservedOrEstimated,
      tideDiagnostics: existing?.tideDiagnostics,
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
      debugPrint('Environmental: Updating existing condition for catch ${catchItem.id}');
      await updateEnvironmentalCondition(condition);
      savedCondition = condition;
    } else {
      debugPrint('Environmental: Creating new condition for catch ${catchItem.id}');
      final id = await createEnvironmentalCondition(condition);
      savedCondition = condition.copyWith(id: id);
    }
    
    return savedCondition;
  }

  /// Determine if WorldTides context should be fetched
  /// 
  /// Returns true if:
  /// - No existing WorldTides context exists
  /// - Date/time has changed significantly
  /// - GPS coordinates have changed
  Future<bool> _shouldFetchWorldTidesContext(
    EnvironmentalCondition? existing,
    Catch catchItem,
    DateTime observationDateTime,
  ) async {
    // No existing context - fetch
    if (existing == null) {
      return true;
    }
    
    // No existing WorldTides context - fetch
    if (existing.tideContextDataSource != 'WorldTides' ||
        existing.tideContextPhrase == null ||
        existing.tideContextPhrase!.isEmpty) {
      return true;
    }
    
    // Check if date/time changed (more than 1 hour difference)
    final existingTime = existing.observationDateTime;
    if (existingTime == null) {
      return true;
    }
    
    final timeDifference = observationDateTime.difference(existingTime).abs();
    if (timeDifference.inHours > 1) {
      return true;
    }
    
    // Check if coordinates changed
    final existingLat = existing.latitude;
    final existingLon = existing.longitude;
    final newLat = catchItem.latitude;
    final newLon = catchItem.longitude;
    
    if (existingLat == null || existingLon == null || newLat == null || newLon == null) {
      return true;
    }
    
    // If coordinates changed by more than ~100 meters (0.001 degrees)
    final latDiff = (existingLat - newLat).abs();
    final lonDiff = (existingLon - newLon).abs();
    
    if (latDiff > 0.001 || lonDiff > 0.001) {
      return true;
    }
    
    // Context is still valid - don't fetch
    return false;
  }

  /// Check if an environmental condition has any manual data (non-calculated fields)
  bool _hasManualData(EnvironmentalCondition condition) {
    return condition.tideStage != null ||
        condition.tideStrength != null ||
        !_isBlank(condition.tideNotes) ||
        condition.tideHeight != null ||
        condition.tideMovement != null ||
        !_isBlank(condition.tideStation) ||
        !_isBlank(condition.tideStationName) ||
        condition.referenceTideEventType != null ||
        condition.referenceTideEventTime != null ||
        condition.referenceTideEventHeight != null ||
        condition.referenceTideEventRelation != null ||
        condition.tideContextPhrase != null ||
        !_isBlank(condition.weatherCondition) ||
        condition.temperature != null ||
        condition.humidity != null ||
        condition.cloudCover != null ||
        condition.windSpeed != null ||
        !_isBlank(condition.windDirection) ||
        condition.barometricPressure != null ||
        condition.rainfall != null ||
        condition.riverFlow != null ||
        condition.waterClarity != null ||
        condition.tideObservedOrEstimated == 'Observed';
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

  /// Recalculate environmental data for all catches
  /// Populates missing automatic data while preserving manual observations
  /// Returns a summary of the operation
  Future<Map<String, int>> recalculateEnvironmentalDataForAllCatches({
    Function(int processed, int updated, int skipped)? onProgress,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final catches = await db.query('catches');
    
    int processed = 0;
    int updated = 0;
    int skipped = 0;
    int failed = 0;
    
    debugPrint('=== Starting Environmental Data Recalculation ===');
    debugPrint('Total catches to process: ${catches.length}');
    
    for (final catchMap in catches) {
      processed++;
      
      try {
        final catchId = catchMap['id'] as int;
        final latitude = catchMap['latitude'] as double?;
        final longitude = catchMap['longitude'] as double?;
        final dateCaught = catchMap['date_caught'] != null
            ? DateTime.parse(catchMap['date_caught'] as String)
            : DateTime.parse(catchMap['created_at'] as String);
        
        // Skip if no coordinates
        if (latitude == null || longitude == null) {
          debugPrint('Catch $catchId: skipped (no coordinates)');
          skipped++;
          if (onProgress != null) {
            onProgress(processed, updated, skipped);
          }
          continue;
        }
        
        // Get existing environmental condition
        final existing = await getEnvironmentalConditionForCatch(catchId);
        
        debugPrint('Catch $catchId: existing condition = ${existing != null}');
        if (existing != null) {
          debugPrint('  Existing tideStage: ${existing.tideStage}');
          debugPrint('  Existing tideMovement: ${existing.tideMovement}');
          debugPrint('  Existing tideDataSource: ${existing.tideDataSource}');
          debugPrint('  Existing derivedTideStage: ${existing.derivedTideStage}');
        }
        
        // Build new condition preserving manual data
        // Treat null/empty/Unknown as missing for backfill purposes
        final hasManualTideStage = !_isBlank(existing?.tideStage) && existing?.tideStage != 'Unknown';
        final hasManualTideMovement = !_isBlank(existing?.tideMovement);
        final hasManualWeather = !_isBlank(existing?.weatherCondition);
        
        final condition = EnvironmentalCondition(
          id: existing?.id,
          catchId: catchId,
          tripId: null,
          observationDateTime: dateCaught,
          latitude: latitude,
          longitude: longitude,
          // Preserve manual tide data only if present and not Unknown
          tideStage: hasManualTideStage ? existing?.tideStage : null,
          tideStrength: existing?.tideStrength,
          tideNotes: existing?.tideNotes,
          tideHeight: existing?.tideHeight,
          tideMovement: hasManualTideMovement ? existing?.tideMovement : null,
          tideStation: existing?.tideStation,
          // Preserve manual tide context
          tideStationName: existing?.tideStationName,
          tideStationDistanceKm: existing?.tideStationDistanceKm,
          referenceTideEventType: existing?.referenceTideEventType,
          referenceTideEventTime: existing?.referenceTideEventTime,
          referenceTideEventHeight: existing?.referenceTideEventHeight,
          referenceTideEventRelation: existing?.referenceTideEventRelation,
          minutesFromReferenceTideEvent: existing?.minutesFromReferenceTideEvent,
          previousTideEventType: existing?.previousTideEventType,
          previousTideEventTime: existing?.previousTideEventTime,
          previousTideEventHeight: existing?.previousTideEventHeight,
          nextTideEventType: existing?.nextTideEventType,
          nextTideEventTime: existing?.nextTideEventTime,
          nextTideEventHeight: existing?.nextTideEventHeight,
          tideContextPhrase: existing?.tideContextPhrase,
          tideContextDataSource: existing?.tideContextDataSource,
          tideContextConfidence: existing?.tideContextConfidence,
          // Preserve manual weather data only if present
          weatherCondition: hasManualWeather ? existing?.weatherCondition : null,
          temperature: existing?.temperature,
          humidity: existing?.humidity,
          cloudCover: existing?.cloudCover,
          windSpeed: existing?.windSpeed,
          windDirection: existing?.windDirection,
          barometricPressure: existing?.barometricPressure,
          rainfall: existing?.rainfall,
          riverFlow: existing?.riverFlow,
          waterClarity: existing?.waterClarity,
          // Preserve existing automated data
          tideDataSource: existing?.tideDataSource,
          tideConfidence: existing?.tideConfidence,
          derivedTideStage: existing?.derivedTideStage,
          tideObservedOrEstimated: existing?.tideObservedOrEstimated,
          tideDiagnostics: existing?.tideDiagnostics,
          dataSource: existing?.dataSource ?? 'Calculated',
          createdAt: existing?.createdAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
        );
        
        // REFACTOR: Calculate automatic data WITHOUT tide (moon, sun, weather only)
        // Open-Meteo tide data is no longer used for backfill
        // Manual tide data is preserved, WorldTides integration for official tide context
        final calculatedCondition = await _calculateEnvironmentalDataWithoutTide(condition);
        
        debugPrint('Catch $catchId: calculated moonPhase = ${calculatedCondition.moonPhase}');
        debugPrint('Catch $catchId: calculated weatherCondition = ${calculatedCondition.weatherCondition}');
        
        // Fetch WorldTides context if available and no existing context
        Map<String, dynamic>? tideContext;
        if (await _worldTidesService.isAvailable() && 
            (existing?.tideContextDataSource != 'WorldTides' || existing?.tideContextPhrase == null)) {
          try {
            tideContext = await _worldTidesService.getTideContextForLocation(
              latitude,
              longitude,
              dateCaught,
            );
            if (tideContext != null && tideContext.isNotEmpty) {
              debugPrint('Catch $catchId: WorldTides context fetched during backfill');
            }
          } catch (e) {
            debugPrint('Catch $catchId: WorldTides fetch failed during backfill: $e');
          }
        }
        
        // Merge: use calculated data only if manual data is missing
        final mergedCondition = EnvironmentalCondition(
          id: calculatedCondition.id,
          catchId: calculatedCondition.catchId,
          tripId: calculatedCondition.tripId,
          observationDateTime: calculatedCondition.observationDateTime,
          latitude: calculatedCondition.latitude,
          longitude: calculatedCondition.longitude,
          // Moon/sun: always use calculated (no manual override)
          moonPhase: calculatedCondition.moonPhase,
          moonIllumination: calculatedCondition.moonIllumination,
          sunriseTime: calculatedCondition.sunriseTime,
          sunsetTime: calculatedCondition.sunsetTime,
          // Manual tide: preserve if present, otherwise use calculated
          tideStage: hasManualTideStage ? existing?.tideStage : calculatedCondition.tideStage,
          tideStrength: existing?.tideStrength ?? calculatedCondition.tideStrength,
          tideNotes: existing?.tideNotes ?? calculatedCondition.tideNotes,
          tideHeight: existing?.tideHeight ?? calculatedCondition.tideHeight,
          tideMovement: hasManualTideMovement ? existing?.tideMovement : calculatedCondition.tideMovement,
          tideStation: existing?.tideStation ?? calculatedCondition.tideStation,
          // Tide context: use WorldTides if fetched, otherwise preserve manual
          tideStationName: tideContext?['tideStationName'] ?? existing?.tideStationName,
          tideStationDistanceKm: tideContext?['tideStationDistanceKm'] ?? existing?.tideStationDistanceKm,
          referenceTideEventType: tideContext?['referenceTideEventType'] ?? existing?.referenceTideEventType,
          referenceTideEventTime: tideContext?['referenceTideEventTime'] ?? existing?.referenceTideEventTime,
          referenceTideEventHeight: tideContext?['referenceTideEventHeight'] ?? existing?.referenceTideEventHeight,
          referenceTideEventRelation: tideContext?['referenceTideEventRelation'] ?? existing?.referenceTideEventRelation,
          minutesFromReferenceTideEvent: tideContext?['minutesFromReferenceTideEvent'] ?? existing?.minutesFromReferenceTideEvent,
          previousTideEventType: tideContext?['previousTideEventType'] ?? existing?.previousTideEventType,
          previousTideEventTime: tideContext?['previousTideEventTime'] ?? existing?.previousTideEventTime,
          previousTideEventHeight: tideContext?['previousTideEventHeight'] ?? existing?.previousTideEventHeight,
          nextTideEventType: tideContext?['nextTideEventType'] ?? existing?.nextTideEventType,
          nextTideEventTime: tideContext?['nextTideEventTime'] ?? existing?.nextTideEventTime,
          nextTideEventHeight: tideContext?['nextTideEventHeight'] ?? existing?.nextTideEventHeight,
          tideContextPhrase: tideContext?['tideContextPhrase'] ?? existing?.tideContextPhrase,
          tideContextDataSource: tideContext?['tideContextDataSource'] ?? existing?.tideContextDataSource,
          tideContextConfidence: tideContext?['tideContextConfidence'] ?? existing?.tideContextConfidence,
          // Weather: use calculated only if manual is missing
          weatherCondition: hasManualWeather ? existing?.weatherCondition : calculatedCondition.weatherCondition,
          temperature: existing?.temperature ?? calculatedCondition.temperature,
          humidity: existing?.humidity ?? calculatedCondition.humidity,
          cloudCover: existing?.cloudCover ?? calculatedCondition.cloudCover,
          windSpeed: existing?.windSpeed ?? calculatedCondition.windSpeed,
          windDirection: existing?.windDirection ?? calculatedCondition.windDirection,
          barometricPressure: existing?.barometricPressure ?? calculatedCondition.barometricPressure,
          rainfall: existing?.rainfall ?? calculatedCondition.rainfall,
          // Water: preserve manual
          riverFlow: existing?.riverFlow,
          waterClarity: existing?.waterClarity,
          // Automated tide data: use calculated
          tideDataSource: calculatedCondition.tideDataSource,
          tideConfidence: calculatedCondition.tideConfidence,
          derivedTideStage: calculatedCondition.derivedTideStage,
          tideObservedOrEstimated: calculatedCondition.tideObservedOrEstimated,
          tideDiagnostics: calculatedCondition.tideDiagnostics,
          dataSource: calculatedCondition.dataSource,
          createdAt: calculatedCondition.createdAt,
          updatedAt: DateTime.now(),
        );
        
        debugPrint('Catch $catchId: merged tideStage = ${mergedCondition.tideStage}');
        debugPrint('Catch $catchId: merged tideMovement = ${mergedCondition.tideMovement}');
        debugPrint('Catch $catchId: merged derivedTideStage = ${mergedCondition.derivedTideStage}');
        
        // Save or update
        if (existing != null) {
          await updateEnvironmentalCondition(mergedCondition);
        } else {
          await createEnvironmentalCondition(mergedCondition);
        }
        
        updated++;
        debugPrint('Catch $catchId: updated');
        
        // Rate limiting: delay between API calls
        await Future.delayed(const Duration(milliseconds: 200));
        
      } catch (e) {
        failed++;
        debugPrint('Error processing catch: $e');
      }
      
      if (onProgress != null) {
        onProgress(processed, updated, skipped);
      }
    }
    
    debugPrint('=== Environmental Data Recalculation Complete ===');
    debugPrint('Processed: $processed');
    debugPrint('Updated: $updated');
    debugPrint('Skipped: $skipped');
    debugPrint('Failed: $failed');
    
    return {
      'processed': processed,
      'updated': updated,
      'skipped': skipped,
      'failed': failed,
    };
  }
}
