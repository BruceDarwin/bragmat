import '../database/database_helper.dart';
import '../models/environmental_condition.dart';
import '../models/catch.dart';
import 'moon_phase_service.dart';
import 'sun_times_service.dart';
import 'package:flutter/foundation.dart';

class EnvironmentalConditionsService {
  static final EnvironmentalConditionsService _instance = EnvironmentalConditionsService._internal();
  factory EnvironmentalConditionsService() => _instance;
  EnvironmentalConditionsService._internal();

  final MoonPhaseService _moonPhaseService = MoonPhaseService();
  final SunTimesService _sunTimesService = SunTimesService();

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

  /// Calculate environmental data (moon phase, sun times) from coordinates
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

    return condition.copyWith(
      moonPhase: moonInfo.phaseName,
      moonIllumination: moonInfo.illumination,
      sunriseTime: sunInfo?.sunrise,
      sunsetTime: sunInfo?.sunset,
      dataSource: condition.dataSource ?? 'Calculated',
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
    double? tideHeight,
    String? tideMovement,
    String? tideStation,
    String? weatherCondition,
    double? temperature,
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
      tideHeight: tideHeight,
      tideMovement: tideMovement,
      tideStation: tideStation,
      weatherCondition: weatherCondition,
      temperature: temperature,
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
    debugPrint('=== upsertCalculatedConditionsForCatch ===');
    debugPrint('Catch ID: ${catchItem.id}');
    debugPrint('Catch date: ${catchItem.dateCaught?.toIso8601String()}');
    debugPrint('Catch latitude: ${catchItem.latitude}');
    debugPrint('Catch longitude: ${catchItem.longitude}');
    
    if (catchItem.id == null) {
      debugPrint('ERROR: Catch ID is null');
      return null;
    }

    final hasCoordinates = catchItem.latitude != null && catchItem.longitude != null;
    debugPrint('Has coordinates: $hasCoordinates');

    // Get existing environmental condition
    final existing = await getEnvironmentalConditionForCatch(catchItem.id!);
    debugPrint('Existing condition: ${existing != null}');

    final observationDateTime = catchItem.dateCaught ?? catchItem.createdAt;

    // If no coordinates and no existing manual data, delete if exists and return
    if (!hasCoordinates) {
      if (existing != null) {
        // Check if existing has any manual data
        final hasManualData = _hasManualData(existing);
        debugPrint('No coordinates, has manual data: $hasManualData');
        
        if (!hasManualData) {
          debugPrint('No coordinates and no manual data - deleting existing condition');
          await deleteEnvironmentalConditionForCatch(catchItem.id!);
          return null;
        } else {
          debugPrint('No coordinates but has manual data - preserving existing condition');
          return existing;
        }
      } else {
        debugPrint('No coordinates and no existing condition - nothing to do');
        return null;
      }
    }

    // Has coordinates - create or update with calculated values
    debugPrint('Has coordinates - calculating moon/sun values');
    
    final condition = EnvironmentalCondition(
      id: existing?.id,
      catchId: catchItem.id!,
      tripId: null,
      observationDateTime: observationDateTime,
      latitude: catchItem.latitude,
      longitude: catchItem.longitude,
      // Preserve existing manual data
      tideStage: existing?.tideStage,
      tideHeight: existing?.tideHeight,
      tideMovement: existing?.tideMovement,
      tideStation: existing?.tideStation,
      weatherCondition: existing?.weatherCondition,
      temperature: existing?.temperature,
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
      debugPrint('Updating existing condition');
      await updateEnvironmentalCondition(condition);
      savedCondition = condition;
    } else {
      debugPrint('Creating new condition');
      final id = await createEnvironmentalCondition(condition);
      savedCondition = condition.copyWith(id: id);
    }

    debugPrint('Environmental condition saved:');
    debugPrint('  Moon Phase: ${savedCondition.moonPhase}');
    debugPrint('  Moon Illumination: ${savedCondition.moonIllumination?.toStringAsFixed(1)}%');
    debugPrint('  Sunrise: ${savedCondition.sunriseTime?.toIso8601String()}');
    debugPrint('  Sunset: ${savedCondition.sunsetTime?.toIso8601String()}');
    debugPrint('=== End upsertCalculatedConditionsForCatch ===');
    
    return savedCondition;
  }

  /// Check if an environmental condition has any manual data (non-calculated fields)
  bool _hasManualData(EnvironmentalCondition condition) {
    return condition.tideStage != null ||
        condition.tideHeight != null ||
        condition.tideMovement != null ||
        (condition.tideStation != null && condition.tideStation!.isNotEmpty) ||
        condition.weatherCondition != null ||
        condition.temperature != null ||
        condition.windSpeed != null ||
        condition.windDirection != null ||
        condition.barometricPressure != null ||
        condition.rainfall != null ||
        condition.riverFlow != null ||
        condition.waterClarity != null;
  }
}
