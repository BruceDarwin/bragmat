class EnvironmentalCondition {
  final int? id;
  final int? catchId;
  final int? tripId;
  final DateTime observationDateTime;
  final double? latitude;
  final double? longitude;
  final String? moonPhase;
  final double? moonIllumination;
  final DateTime? sunriseTime;
  final DateTime? sunsetTime;
  final String? tideStage;
  final String? tideStrength;
  final String? tideNotes;
  final double? tideHeight;
  final String? tideMovement;
  final String? tideStation;
  final String? tideDataSource;
  final String? tideConfidence;
  final String? derivedTideStage;
  final String? tideObservedOrEstimated;
  final String? tideDiagnostics;
  // Tide Context fields (deprecated - kept for backward compatibility)
  final String? tideStationName;
  final double? tideStationDistanceKm;
  // Tide Reference and WorldTides Source fields
  final String? tideReferenceMode; // 'automatic' or 'fixed'
  final String? tideReferenceName; // 'Catch location' or 'Darwin' etc.
  final double? tideRequestLat; // Coordinates sent to API
  final double? tideRequestLon;
  final String? worldtidesStation; // Station name from API response
  final String? worldtidesAtlas; // Atlas/model from API response
  final double? worldtidesResponseLat; // Response coordinates from API
  final double? worldtidesResponseLon;
  final String? referenceTideEventType; // High / Low
  final DateTime? referenceTideEventTime;
  final double? referenceTideEventHeight;
  final String? referenceTideEventRelation; // Before / After
  final int? minutesFromReferenceTideEvent;
  final String? previousTideEventType;
  final DateTime? previousTideEventTime;
  final double? previousTideEventHeight;
  final String? nextTideEventType;
  final DateTime? nextTideEventTime;
  final double? nextTideEventHeight;
  final String? tideContextPhrase;
  final String? tideContextDataSource;
  final String? tideContextConfidence;
  final String? weatherCondition;
  final double? temperature;
  final double? humidity;
  final double? cloudCover;
  final double? windSpeed;
  final String? windDirection;
  final double? barometricPressure;
  final double? rainfall;
  final String? riverFlow;
  final String? waterClarity;
  final String? dataSource;
  final DateTime createdAt;
  final DateTime updatedAt;

  EnvironmentalCondition({
    this.id,
    this.catchId,
    this.tripId,
    required this.observationDateTime,
    this.latitude,
    this.longitude,
    this.moonPhase,
    this.moonIllumination,
    this.sunriseTime,
    this.sunsetTime,
    this.tideStage,
    this.tideStrength,
    this.tideNotes,
    this.tideHeight,
    this.tideMovement,
    this.tideStation,
    this.tideDataSource,
    this.tideConfidence,
    this.derivedTideStage,
    this.tideObservedOrEstimated,
    this.tideDiagnostics,
    // Tide Context fields (deprecated - kept for backward compatibility)
    this.tideStationName,
    this.tideStationDistanceKm,
    // Tide Reference and WorldTides Source fields
    this.tideReferenceMode,
    this.tideReferenceName,
    this.tideRequestLat,
    this.tideRequestLon,
    this.worldtidesStation,
    this.worldtidesAtlas,
    this.worldtidesResponseLat,
    this.worldtidesResponseLon,
    this.referenceTideEventType,
    this.referenceTideEventTime,
    this.referenceTideEventHeight,
    this.referenceTideEventRelation,
    this.minutesFromReferenceTideEvent,
    this.previousTideEventType,
    this.previousTideEventTime,
    this.previousTideEventHeight,
    this.nextTideEventType,
    this.nextTideEventTime,
    this.nextTideEventHeight,
    this.tideContextPhrase,
    this.tideContextDataSource,
    this.tideContextConfidence,
    this.weatherCondition,
    this.temperature,
    this.humidity,
    this.cloudCover,
    this.windSpeed,
    this.windDirection,
    this.barometricPressure,
    this.rainfall,
    this.riverFlow,
    this.waterClarity,
    this.dataSource,
    required this.createdAt,
    required this.updatedAt,
  });

  // Convert to map for database operations
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'catch_id': catchId,
      'trip_id': tripId,
      'observation_date_time': observationDateTime.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'moon_phase': moonPhase,
      'moon_illumination': moonIllumination,
      'sunrise_time': sunriseTime?.toIso8601String(),
      'sunset_time': sunsetTime?.toIso8601String(),
      'tide_stage': tideStage,
      'tide_strength': tideStrength,
      'tide_notes': tideNotes,
      'tide_height': tideHeight,
      'tide_movement': tideMovement,
      'tide_station': tideStation,
      'tide_data_source': tideDataSource,
      'tide_confidence': tideConfidence,
      'derived_tide_stage': derivedTideStage,
      'tide_observed_or_estimated': tideObservedOrEstimated,
      'tide_diagnostics': tideDiagnostics,
      // Tide Context fields (deprecated - kept for backward compatibility)
      'tide_station_name': tideStationName,
      'tide_station_distance_km': tideStationDistanceKm,
      // Tide Reference and WorldTides Source fields
      'tide_reference_mode': tideReferenceMode,
      'tide_reference_name': tideReferenceName,
      'tide_request_lat': tideRequestLat,
      'tide_request_lon': tideRequestLon,
      'worldtides_station': worldtidesStation,
      'worldtides_atlas': worldtidesAtlas,
      'worldtides_response_lat': worldtidesResponseLat,
      'worldtides_response_lon': worldtidesResponseLon,
      'reference_tide_event_type': referenceTideEventType,
      'reference_tide_event_time': referenceTideEventTime?.toIso8601String(),
      'reference_tide_event_height': referenceTideEventHeight,
      'reference_tide_event_relation': referenceTideEventRelation,
      'minutes_from_reference_tide_event': minutesFromReferenceTideEvent,
      'previous_tide_event_type': previousTideEventType,
      'previous_tide_event_time': previousTideEventTime?.toIso8601String(),
      'previous_tide_event_height': previousTideEventHeight,
      'next_tide_event_type': nextTideEventType,
      'next_tide_event_time': nextTideEventTime?.toIso8601String(),
      'next_tide_event_height': nextTideEventHeight,
      'tide_context_phrase': tideContextPhrase,
      'tide_context_data_source': tideContextDataSource,
      'tide_context_confidence': tideContextConfidence,
      'weather_condition': weatherCondition,
      'temperature': temperature,
      'humidity': humidity,
      'cloud_cover': cloudCover,
      'wind_speed': windSpeed,
      'wind_direction': windDirection,
      'barometric_pressure': barometricPressure,
      'rainfall': rainfall,
      'river_flow': riverFlow,
      'water_clarity': waterClarity,
      'data_source': dataSource,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Create from map
  factory EnvironmentalCondition.fromMap(Map<String, dynamic> map) {
    return EnvironmentalCondition(
      id: map['id'] as int?,
      catchId: map['catch_id'] as int?,
      tripId: map['trip_id'] as int?,
      observationDateTime: DateTime.parse(map['observation_date_time'] as String),
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      moonPhase: map['moon_phase'] as String?,
      moonIllumination: map['moon_illumination'] as double?,
      sunriseTime: map['sunrise_time'] != null 
          ? DateTime.parse(map['sunrise_time'] as String) 
          : null,
      sunsetTime: map['sunset_time'] != null 
          ? DateTime.parse(map['sunset_time'] as String) 
          : null,
      tideStage: map['tide_stage'] as String?,
      tideStrength: map['tide_strength'] as String?,
      tideNotes: map['tide_notes'] as String?,
      tideHeight: map['tide_height'] as double?,
      tideMovement: map['tide_movement'] as String?,
      tideStation: map['tide_station'] as String?,
      tideDataSource: map['tide_data_source'] as String?,
      tideConfidence: map['tide_confidence'] as String?,
      derivedTideStage: map['derived_tide_stage'] as String?,
      tideObservedOrEstimated: map['tide_observed_or_estimated'] as String?,
      tideDiagnostics: map['tide_diagnostics'] as String?,
      // Tide Context fields (deprecated - kept for backward compatibility)
      tideStationName: map['tide_station_name'] as String?,
      tideStationDistanceKm: map['tide_station_distance_km'] as double?,
      // Tide Reference and WorldTides Source fields
      tideReferenceMode: map['tide_reference_mode'] as String?,
      tideReferenceName: map['tide_reference_name'] as String?,
      tideRequestLat: map['tide_request_lat'] as double?,
      tideRequestLon: map['tide_request_lon'] as double?,
      worldtidesStation: map['worldtides_station'] as String?,
      worldtidesAtlas: map['worldtides_atlas'] as String?,
      worldtidesResponseLat: map['worldtides_response_lat'] as double?,
      worldtidesResponseLon: map['worldtides_response_lon'] as double?,
      referenceTideEventType: map['reference_tide_event_type'] as String?,
      referenceTideEventTime: map['reference_tide_event_time'] != null
          ? DateTime.parse(map['reference_tide_event_time'] as String)
          : null,
      referenceTideEventHeight: map['reference_tide_event_height'] as double?,
      referenceTideEventRelation: map['reference_tide_event_relation'] as String?,
      minutesFromReferenceTideEvent: map['minutes_from_reference_tide_event'] as int?,
      previousTideEventType: map['previous_tide_event_type'] as String?,
      previousTideEventTime: map['previous_tide_event_time'] != null
          ? DateTime.parse(map['previous_tide_event_time'] as String)
          : null,
      previousTideEventHeight: map['previous_tide_event_height'] as double?,
      nextTideEventType: map['next_tide_event_type'] as String?,
      nextTideEventTime: map['next_tide_event_time'] != null
          ? DateTime.parse(map['next_tide_event_time'] as String)
          : null,
      nextTideEventHeight: map['next_tide_event_height'] as double?,
      tideContextPhrase: map['tide_context_phrase'] as String?,
      tideContextDataSource: map['tide_context_data_source'] as String?,
      tideContextConfidence: map['tide_context_confidence'] as String?,
      weatherCondition: map['weather_condition'] as String?,
      temperature: map['temperature'] as double?,
      humidity: map['humidity'] as double?,
      cloudCover: map['cloud_cover'] as double?,
      windSpeed: map['wind_speed'] as double?,
      windDirection: map['wind_direction'] as String?,
      barometricPressure: map['barometric_pressure'] as double?,
      rainfall: map['rainfall'] as double?,
      riverFlow: map['river_flow'] as String?,
      waterClarity: map['water_clarity'] as String?,
      dataSource: map['data_source'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  // Create a copy with updated fields
  EnvironmentalCondition copyWith({
    int? id,
    int? catchId,
    int? tripId,
    DateTime? observationDateTime,
    double? latitude,
    double? longitude,
    String? moonPhase,
    double? moonIllumination,
    DateTime? sunriseTime,
    DateTime? sunsetTime,
    String? tideStage,
    String? tideStrength,
    String? tideNotes,
    double? tideHeight,
    String? tideMovement,
    String? tideStation,
    String? tideDataSource,
    String? tideConfidence,
    String? derivedTideStage,
    String? tideObservedOrEstimated,
    String? tideDiagnostics,
    // Tide Context fields (deprecated - kept for backward compatibility)
    String? tideStationName,
    double? tideStationDistanceKm,
    // Tide Reference and WorldTides Source fields
    String? tideReferenceMode,
    String? tideReferenceName,
    double? tideRequestLat,
    double? tideRequestLon,
    String? worldtidesStation,
    String? worldtidesAtlas,
    double? worldtidesResponseLat,
    double? worldtidesResponseLon,
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
    String? dataSource,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EnvironmentalCondition(
      id: id ?? this.id,
      catchId: catchId ?? this.catchId,
      tripId: tripId ?? this.tripId,
      observationDateTime: observationDateTime ?? this.observationDateTime,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      moonPhase: moonPhase ?? this.moonPhase,
      moonIllumination: moonIllumination ?? this.moonIllumination,
      sunriseTime: sunriseTime ?? this.sunriseTime,
      sunsetTime: sunsetTime ?? this.sunsetTime,
      tideStage: tideStage ?? this.tideStage,
      tideStrength: tideStrength ?? this.tideStrength,
      tideNotes: tideNotes ?? this.tideNotes,
      tideHeight: tideHeight ?? this.tideHeight,
      tideMovement: tideMovement ?? this.tideMovement,
      tideStation: tideStation ?? this.tideStation,
      tideDataSource: tideDataSource ?? this.tideDataSource,
      tideConfidence: tideConfidence ?? this.tideConfidence,
      derivedTideStage: derivedTideStage ?? this.derivedTideStage,
      tideObservedOrEstimated: tideObservedOrEstimated ?? this.tideObservedOrEstimated,
      tideDiagnostics: tideDiagnostics ?? this.tideDiagnostics,
      // Tide Context fields (deprecated - kept for backward compatibility)
      tideStationName: tideStationName ?? this.tideStationName,
      tideStationDistanceKm: tideStationDistanceKm ?? this.tideStationDistanceKm,
      // Tide Reference and WorldTides Source fields
      tideReferenceMode: tideReferenceMode ?? this.tideReferenceMode,
      tideReferenceName: tideReferenceName ?? this.tideReferenceName,
      tideRequestLat: tideRequestLat ?? this.tideRequestLat,
      tideRequestLon: tideRequestLon ?? this.tideRequestLon,
      worldtidesStation: worldtidesStation ?? this.worldtidesStation,
      worldtidesAtlas: worldtidesAtlas ?? this.worldtidesAtlas,
      worldtidesResponseLat: worldtidesResponseLat ?? this.worldtidesResponseLat,
      worldtidesResponseLon: worldtidesResponseLon ?? this.worldtidesResponseLon,
      referenceTideEventType: referenceTideEventType ?? this.referenceTideEventType,
      referenceTideEventTime: referenceTideEventTime ?? this.referenceTideEventTime,
      referenceTideEventHeight: referenceTideEventHeight ?? this.referenceTideEventHeight,
      referenceTideEventRelation: referenceTideEventRelation ?? this.referenceTideEventRelation,
      minutesFromReferenceTideEvent: minutesFromReferenceTideEvent ?? this.minutesFromReferenceTideEvent,
      previousTideEventType: previousTideEventType ?? this.previousTideEventType,
      previousTideEventTime: previousTideEventTime ?? this.previousTideEventTime,
      previousTideEventHeight: previousTideEventHeight ?? this.previousTideEventHeight,
      nextTideEventType: nextTideEventType ?? this.nextTideEventType,
      nextTideEventTime: nextTideEventTime ?? this.nextTideEventTime,
      nextTideEventHeight: nextTideEventHeight ?? this.nextTideEventHeight,
      tideContextPhrase: tideContextPhrase ?? this.tideContextPhrase,
      tideContextDataSource: tideContextDataSource ?? this.tideContextDataSource,
      tideContextConfidence: tideContextConfidence ?? this.tideContextConfidence,
      weatherCondition: weatherCondition ?? this.weatherCondition,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      cloudCover: cloudCover ?? this.cloudCover,
      windSpeed: windSpeed ?? this.windSpeed,
      windDirection: windDirection ?? this.windDirection,
      barometricPressure: barometricPressure ?? this.barometricPressure,
      rainfall: rainfall ?? this.rainfall,
      riverFlow: riverFlow ?? this.riverFlow,
      waterClarity: waterClarity ?? this.waterClarity,
      dataSource: dataSource ?? this.dataSource,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Create a copy with tide-result fields cleared
  /// Used when reference changes and recalculation fails or is skipped
  /// Preserves manual tide observations and unrelated environmental data
  EnvironmentalCondition clearTideResults() {
    return EnvironmentalCondition(
      id: id,
      catchId: catchId,
      tripId: tripId,
      observationDateTime: observationDateTime,
      latitude: latitude,
      longitude: longitude,
      moonPhase: moonPhase,
      moonIllumination: moonIllumination,
      sunriseTime: sunriseTime,
      sunsetTime: sunsetTime,
      // Preserve manual tide observations
      tideStage: tideStage,
      tideStrength: tideStrength,
      tideNotes: tideNotes,
      tideHeight: tideHeight,
      tideMovement: tideMovement,
      tideStation: tideStation,
      tideDataSource: tideDataSource,
      tideConfidence: tideConfidence,
      derivedTideStage: derivedTideStage,
      tideObservedOrEstimated: tideObservedOrEstimated,
      tideDiagnostics: tideDiagnostics,
      // Tide Context fields (deprecated - kept for backward compatibility)
      tideStationName: tideStationName,
      tideStationDistanceKm: tideStationDistanceKm,
      // Tide Reference and WorldTides Source fields - preserve reference info
      tideReferenceMode: tideReferenceMode,
      tideReferenceName: tideReferenceName,
      tideRequestLat: tideRequestLat,
      tideRequestLon: tideRequestLon,
      // CLEAR WorldTides metadata
      worldtidesStation: null,
      worldtidesAtlas: null,
      worldtidesResponseLat: null,
      worldtidesResponseLon: null,
      // CLEAR tide event values derived from previous reference
      referenceTideEventType: null,
      referenceTideEventTime: null,
      referenceTideEventHeight: null,
      referenceTideEventRelation: null,
      minutesFromReferenceTideEvent: null,
      previousTideEventType: null,
      previousTideEventTime: null,
      previousTideEventHeight: null,
      nextTideEventType: null,
      nextTideEventTime: null,
      nextTideEventHeight: null,
      // CLEAR tide context phrase
      tideContextPhrase: null,
      tideContextDataSource: null,
      tideContextConfidence: null,
      // Preserve weather and other environmental data
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
      dataSource: dataSource,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  // Tide stage options
  static const List<String> tideStages = [
    'High Tide',
    'Low Tide',
    'Run-In Tide',
    'Run-Out Tide',
    'Slack High',
    'Slack Low',
    'Unknown',
  ];

  // Tide strength options
  static const List<String> tideStrengths = [
    'Very Weak',
    'Weak',
    'Moderate',
    'Strong',
    'Very Strong',
  ];

  // Wind direction options
  static const List<String> windDirections = [
    'N',
    'NE',
    'E',
    'SE',
    'S',
    'SW',
    'W',
    'NW',
    'Unknown',
  ];

  // Weather condition options
  static const List<String> weatherConditions = [
    'Clear',
    'Partly Cloudy',
    'Cloudy',
    'Overcast',
    'Rain',
    'Storm',
    'Snow',
    'Fog',
    'Unknown',
  ];

  // Water clarity options
  static const List<String> waterClarities = [
    'Clear',
    'Slightly Dirty',
    'Dirty',
    'Very Dirty',
    'Unknown',
  ];

  // Data source options
  static const List<String> dataSources = [
    'Manual',
    'Calculated',
    'API',
    'Unknown',
  ];
}
