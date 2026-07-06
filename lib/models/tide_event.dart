/// Tide Event Model
/// 
/// Represents a single high or low tide event from an official tide source.
/// Contains event time, height, and type information.
class TideEvent {
  final String? eventId;
  final String eventType; // "High" or "Low"
  final DateTime eventTime;
  final double height; // Tide height in meters
  final String? stationId;

  TideEvent({
    this.eventId,
    required this.eventType,
    required this.eventTime,
    required this.height,
    this.stationId,
  });

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'eventType': eventType,
      'eventTime': eventTime.toIso8601String(),
      'height': height,
      'stationId': stationId,
    };
  }

  factory TideEvent.fromMap(Map<String, dynamic> map) {
    return TideEvent(
      eventId: map['eventId'] as String?,
      eventType: map['eventType'] as String,
      eventTime: DateTime.parse(map['eventTime'] as String),
      height: map['height'] as double,
      stationId: map['stationId'] as String?,
    );
  }

  TideEvent copyWith({
    String? eventId,
    String? eventType,
    DateTime? eventTime,
    double? height,
    String? stationId,
  }) {
    return TideEvent(
      eventId: eventId ?? this.eventId,
      eventType: eventType ?? this.eventType,
      eventTime: eventTime ?? this.eventTime,
      height: height ?? this.height,
      stationId: stationId ?? this.stationId,
    );
  }
}
