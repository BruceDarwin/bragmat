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
