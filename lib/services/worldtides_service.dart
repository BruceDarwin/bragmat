import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/preferences_service.dart';
import '../models/tide_station.dart';
import '../models/tide_event.dart';
import '../helpers/tide_context_helper.dart';
import 'package:flutter/foundation.dart';

/// WorldTides API Service
/// 
/// Integrates with WorldTides v3 API to provide official high/low tide event data.
/// 
/// This service:
/// - Fetches official tide station data for a location
/// - Gets high/low tide events with times and heights
/// - Calculates tide context (time before/after events)
/// - Generates tide context phrases
/// 
/// If the API is not configured or fails, the app will show
/// "Tide context not available" rather than estimated values.

class WorldTidesService {
  static const String _baseUrl = 'https://www.worldtides.info/api/v3';
  
  /// Check if WorldTides API is available and configured
  /// 
  /// Returns true if API key is configured
  Future<bool> isAvailable() async {
    final apiKey = await PreferencesService.getWorldTidesApiKey();
    return apiKey != null && apiKey.isNotEmpty;
  }

  /// Get tide events for a location on a specific date
  /// 
  /// Returns list of tide events including:
  /// - Event type (High/Low)
  /// - Event time
  /// - Tide height
  /// - Station information
  Future<Map<String, dynamic>?> getTideContextForLocation(
    double latitude,
    double longitude,
    DateTime observationTime,
  ) async {
    final apiKey = await PreferencesService.getWorldTidesApiKey();
    
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('WorldTides: No API key configured');
      return null;
    }

    try {
      // Format date for API (YYYY-MM-DD)
      final dateStr = '${observationTime.year}-${observationTime.month.toString().padLeft(2, '0')}-${observationTime.day.toString().padLeft(2, '0')}';
      
      // Build URL with extremes, stations, localtime, timezone, and datum
      final url = Uri.parse('$_baseUrl/extremes').replace(queryParameters: {
        'lat': latitude.toString(),
        'lon': longitude.toString(),
        'date': dateStr,
        'key': apiKey,
        'stations': '1',
        'localtime': '1',
        'timezone': 'auto',
        'datum': 'CD',
      });

      debugPrint('WorldTides: Fetching tide data from $url');

      final response = await http.get(url).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('WorldTides: Request timed out');
          throw Exception('Request timed out');
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('WorldTides: Response received');
        
        // Parse station info
        final stations = data['stations'] as List?;
        String? stationName;
        double? stationDistance;
        
        if (stations != null && stations.isNotEmpty) {
          final station = stations.first;
          stationName = station['name'] as String?;
          stationDistance = (station['distance'] as num?)?.toDouble();
        }

        // Parse tide events
        final extremes = data['extremes'] as List?;
        if (extremes == null || extremes.isEmpty) {
          debugPrint('WorldTides: No tide events returned');
          return null;
        }

        final tideEvents = <TideEvent>[];
        for (final event in extremes) {
          final eventType = event['type'] as String?;
          final eventDateStr = event['date'] as String?;
          final height = (event['height'] as num?)?.toDouble();
          
          if (eventType != null && eventDateStr != null && height != null) {
            try {
              final eventTime = DateTime.parse(eventDateStr);
              tideEvents.add(TideEvent(
                eventType: eventType,
                eventTime: eventTime,
                height: height,
              ));
            } catch (e) {
              debugPrint('WorldTides: Error parsing event time: $e');
            }
          }
        }

        if (tideEvents.isEmpty) {
          debugPrint('WorldTides: No valid tide events parsed');
          return null;
        }

        // Sort events by time
        tideEvents.sort((a, b) => a.eventTime.compareTo(b.eventTime));

        // Calculate tide context
        return _calculateTideContext(
          tideEvents,
          observationTime,
          stationName,
          stationDistance,
        );
      } else if (response.statusCode == 401) {
        debugPrint('WorldTides: Invalid API key');
        return null;
      } else if (response.statusCode == 429) {
        debugPrint('WorldTides: Rate limit exceeded');
        return null;
      } else {
        debugPrint('WorldTides: API error ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('WorldTides: Error fetching tide data: $e');
      return null;
    }
  }

  /// Calculate tide context for an observation time
  /// 
  /// Given tide events and observation time, calculates:
  /// - Previous tide event (type, time, height)
  /// - Next tide event (type, time, height)
  /// - Reference event (nearest to observation time)
  /// - Time before/after reference event
  /// - Tide context phrase
  Map<String, dynamic> _calculateTideContext(
    List<TideEvent> tideEvents,
    DateTime observationTime,
    String? stationName,
    double? stationDistance,
  ) {
    // Find previous and next events
    TideEvent? previousEvent;
    TideEvent? nextEvent;
    
    for (final event in tideEvents) {
      if (event.eventTime.isBefore(observationTime)) {
        previousEvent = event;
      } else if (event.eventTime.isAfter(observationTime)) {
        nextEvent = event;
        break;
      }
    }

    // Determine reference event (nearest to observation time)
    TideEvent? referenceEvent;
    String? relation;
    
    if (previousEvent != null && nextEvent != null) {
      final previousDelta = observationTime.difference(previousEvent.eventTime).abs();
      final nextDelta = nextEvent.eventTime.difference(observationTime).abs();
      
      if (previousDelta < nextDelta) {
        referenceEvent = previousEvent;
        relation = 'After';
      } else {
        referenceEvent = nextEvent;
        relation = 'Before';
      }
    } else if (previousEvent != null) {
      referenceEvent = previousEvent;
      relation = 'After';
    } else if (nextEvent != null) {
      referenceEvent = nextEvent;
      relation = 'Before';
    }

    if (referenceEvent == null) {
      debugPrint('WorldTides: No reference event found');
      return {};
    }

    // Calculate minutes from reference event
    final minutesFromEvent = TideContextHelper.calculateMinutesBetween(
      observationTime,
      referenceEvent.eventTime,
    );

    // Generate context phrase
    final phrase = TideContextHelper.generatePhrase(
      stationName: stationName ?? 'Unknown',
      eventType: referenceEvent.eventType,
      eventTime: referenceEvent.eventTime,
      eventHeight: referenceEvent.height,
      relation: relation ?? 'Unknown',
      minutesFromEvent: minutesFromEvent,
    );

    return {
      'tideStationName': stationName,
      'tideStationDistanceKm': stationDistance,
      'referenceTideEventType': referenceEvent.eventType,
      'referenceTideEventTime': referenceEvent.eventTime,
      'referenceTideEventHeight': referenceEvent.height,
      'referenceTideEventRelation': relation,
      'minutesFromReferenceTideEvent': minutesFromEvent,
      'previousTideEventType': previousEvent?.eventType,
      'previousTideEventTime': previousEvent?.eventTime,
      'previousTideEventHeight': previousEvent?.height,
      'nextTideEventType': nextEvent?.eventType,
      'nextTideEventTime': nextEvent?.eventTime,
      'nextTideEventHeight': nextEvent?.height,
      'tideContextPhrase': phrase,
      'tideContextDataSource': 'WorldTides',
      'tideContextConfidence': 'High',
    };
  }
}
