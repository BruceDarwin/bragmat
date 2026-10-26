import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tide_event.dart';
import '../services/secure_storage_service.dart';
import '../services/supabase_config.dart';
import '../database/database_helper.dart';
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

  /// Edge Function name for the authenticated proxy path (WT2). The
  /// WorldTides key lives only as a server-side secret — never in the app.
  static const String proxyFunctionName = 'worldtides-proxy';

  /// Test seam — replaces the real HTTP GET against the WorldTides API
  /// (direct-key path). Never set from app code.
  static Future<http.Response> Function(Uri url)? httpGetForTesting;

  /// Test seam — replaces the Supabase Edge Function call (proxy path).
  /// Never set from app code.
  static Future<Map<String, dynamic>?> Function({
    required double latitude,
    required double longitude,
    required String date,
  })? proxyFetchForTesting;

  /// Test seam — overrides proxy-session availability. Never set from
  /// app code.
  static bool? proxySessionForTesting;

  /// Check if tide data can be fetched: either a locally stored API key
  /// (direct integration) or an authenticated Supabase session that can
  /// reach the beta-proxy (entitlement is enforced server-side — no
  /// client-side entitlement lookup is performed here).
  Future<bool> isAvailable() async {
    final apiKey = await SecureStorageService.getWorldTidesApiKey();
    if (apiKey != null && apiKey.isNotEmpty) return true;
    return _hasProxySession();
  }

  /// Whether an authenticated Supabase session exists for the proxy path.
  /// Entitlement is intentionally NOT checked here — the Edge Function
  /// enforces it per request, which keeps this call offline-safe and free.
  static bool _hasProxySession() {
    if (proxySessionForTesting != null) return proxySessionForTesting!;
    try {
      if (!SupabaseConfig.isConfigured) return false;
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      // Supabase not initialised (tests, unconfigured builds).
      return false;
    }
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
    final storedKey = await SecureStorageService.getWorldTidesApiKey();
    final apiKey =
        (storedKey != null && storedKey.isNotEmpty) ? storedKey : null;

    if (apiKey == null && !_hasProxySession()) {
      return null;
    }

    try {
      final data = await _fetchTideData(apiKey, latitude, longitude, observationTime);
      if (data == null) {
        return null;
      }
      
      final stationInfo = _parseStationInfo(data);
      final tideEvents = _parseTideEvents(data);
      
      if (tideEvents.isEmpty) {
        return null;
      }
      
      if (!_validateTideCredibility(tideEvents, latitude, longitude)) {
        return null;
      }
      
      final localTideEvents = _convertToLocalTime(tideEvents);
      final localObservationTime = observationTime.toLocal();
      
      return _calculateTideContext(
        localTideEvents,
        localObservationTime,
        stationInfo['name'],
        stationInfo['atlas'],
        stationInfo['responseLat'],
        stationInfo['responseLon'],
      );
    } catch (e) {
      debugPrint('WorldTides: Error fetching tide data: $e');
      return null;
    }
  }

  /// Fetch tide data with caching. A non-null [apiKey] calls the WorldTides
  /// API directly; a null key uses the authenticated Supabase proxy
  /// (`worldtides-proxy` Edge Function), which enforces beta entitlement and
  /// credit budgets server-side.
  Future<Map<String, dynamic>?> _fetchTideData(
    String? apiKey,
    double latitude,
    double longitude,
    DateTime observationTime,
  ) async {
    final dateStr = '${observationTime.year}-${observationTime.month.toString().padLeft(2, '0')}-${observationTime.day.toString().padLeft(2, '0')}';
    
    // Check cache first
    final cachedData = await DatabaseHelper.instance.getCachedTideData(latitude, longitude, dateStr);
    if (cachedData != null) {
      // Reconstruct expected API response format from cached data
      // Cache stores metadata in worldtides_* fields, but _parseStationInfo expects station/atlas/responseLat/responseLon
      final reconstructedData = {
        'extremes': cachedData['extremes'],
        'station': cachedData['worldtides_station'],
        'atlas': cachedData['worldtides_atlas'],
        'responseLat': cachedData['worldtides_response_lat'],
        'responseLon': cachedData['worldtides_response_lon'],
      };
      return reconstructedData;
    }
    
    // Not in cache — fetch. A local key uses the direct WorldTides API;
    // without one the authenticated proxy is used (its response body has
    // the same shape, so parsing and caching below are unchanged).
    int? statusCode;
    Map<String, dynamic>? data;
    if (apiKey != null) {
      final url = Uri.parse('$_baseUrl').replace(queryParameters: {
        'extremes': '',
        'lat': latitude.toString(),
        'lon': longitude.toString(),
        'date': dateStr,
        'key': apiKey,
        'days': '3',
        'datum': 'CD',
      });

      final get = httpGetForTesting ?? http.get;
      final response = await get(url).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('WorldTides: Request timed out');
          throw Exception('Request timed out');
        },
      );
      statusCode = response.statusCode;
      if (statusCode == 200) {
        data = json.decode(response.body) as Map<String, dynamic>;
      }
    } else {
      data = await _fetchViaProxy(latitude, longitude, dateStr);
      if (data != null) statusCode = 200;
    }

    if (statusCode == 200 && data != null) {
      // Cache the response for future use
      final extremes = data['extremes'] as List?;
      if (extremes != null && extremes.isNotEmpty) {
        final stationInfo = _parseStationInfo(data);
        await DatabaseHelper.instance.cacheTideData(
          latitude,
          longitude,
          dateStr,
          extremes,
          worldtidesStation: stationInfo['name'] as String?,
          worldtidesAtlas: stationInfo['atlas'] as String?,
          worldtidesResponseLat: stationInfo['responseLat'] as double?,
          worldtidesResponseLon: stationInfo['responseLon'] as double?,
        );
      }

      return data;
    } else if (statusCode == 401) {
      debugPrint('WorldTides: Invalid API key');
      return null;
    } else if (statusCode == 429) {
      debugPrint('WorldTides: Rate limit exceeded');
      return null;
    } else {
      debugPrint('WorldTides: API error $statusCode');
      return null;
    }
  }

  /// Fetch tide data through the authenticated Supabase proxy. The Edge
  /// Function adds the API key server-side, enforces beta entitlement and
  /// per-user/global credit budgets, and returns the WorldTides JSON body
  /// with the same shape the direct API produces.
  Future<Map<String, dynamic>?> _fetchViaProxy(
    double latitude,
    double longitude,
    String dateStr,
  ) async {
    try {
      final fetcher = proxyFetchForTesting ?? _invokeProxy;
      return await fetcher(
        latitude: latitude,
        longitude: longitude,
        date: dateStr,
      );
    } catch (e) {
      debugPrint('WorldTides: proxy request failed');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _invokeProxy({
    required double latitude,
    required double longitude,
    required String date,
  }) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        proxyFunctionName,
        body: {
          'lat': latitude,
          'lon': longitude,
          'date': date,
          'days': 3,
          'datum': 'CD',
        },
      );
      if (response.status != 200) {
        debugPrint('WorldTides: proxy returned status ${response.status}');
        return null;
      }
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return null;
    } catch (_) {
      // Never surface internal details — the caller treats all proxy
      // failures identically (graceful degradation to "Not recorded").
      return null;
    }
  }

  /// Parse station information from API response
  /// 
  /// The WorldTides API returns a 'station' field with the station name when
  /// a named station is used. When using the global model (FES2022), the 'station'
  /// field is absent and 'atlas' indicates the model used.
  /// 
  /// Also parses 'atlas', 'responseLat', and 'responseLon' for metadata.
  Map<String, dynamic?> _parseStationInfo(Map<String, dynamic> data) {
    final station = data['station'] as String?;
    final atlas = data['atlas'] as String?;
    final responseLat = (data['responseLat'] as num?)?.toDouble();
    final responseLon = (data['responseLon'] as num?)?.toDouble();
    
    return {
      'name': station,
      'atlas': atlas,
      'responseLat': responseLat,
      'responseLon': responseLon,
    };
  }

  /// Parse tide events from API response
  List<TideEvent> _parseTideEvents(Map<String, dynamic> data) {
    final extremes = data['extremes'] as List?;
    if (extremes == null || extremes.isEmpty) {
      return [];
    }

    final tideEvents = <TideEvent>[];
    for (final event in extremes) {
      final eventType = event['type'] as String?;
      final eventDateStr = event['date'] as String?;
      final height = (event['height'] as num?)?.toDouble();
      
      if (eventType != null && eventDateStr != null && height != null) {
        try {
          DateTime eventTime;
          if (eventDateStr.endsWith('Z') || eventDateStr.contains('+') || eventDateStr.contains('-')) {
            eventTime = DateTime.parse(eventDateStr);
          } else {
            eventTime = DateTime.parse('${eventDateStr}Z');
          }
          
          tideEvents.add(TideEvent(
            eventType: eventType,
            eventTime: eventTime,
            height: height,
          ));
        } catch (e) {
          // Skip events with invalid time format
        }
      }
    }

    tideEvents.sort((a, b) => a.eventTime.compareTo(b.eventTime));
    return tideEvents;
  }

  /// Convert UTC tide events to local time
  List<TideEvent> _convertToLocalTime(List<TideEvent> tideEvents) {
    return tideEvents.map((event) {
      final localTime = event.eventTime.toLocal();
      return TideEvent(
        eventType: event.eventType,
        eventTime: localTime,
        height: event.height,
      );
    }).toList();
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
    String? atlas,
    double? responseLat,
    double? responseLon,
  ) {
    final referenceEvent = _findReferenceEvent(tideEvents, observationTime);
    if (referenceEvent == null) {
      return {};
    }
    
    final previousEvent = _findPreviousEvent(tideEvents, observationTime);
    final nextEvent = _findNextEvent(tideEvents, observationTime);
    final relation = _determineRelation(observationTime, referenceEvent);
    
    final minutesFromEvent = TideContextHelper.calculateMinutesBetween(
      observationTime,
      referenceEvent.eventTime,
    );

    final phrase = TideContextHelper.generatePhrase(
      stationName: stationName,
      eventType: referenceEvent.eventType,
      eventTime: referenceEvent.eventTime,
      eventHeight: referenceEvent.height,
      relation: relation,
      minutesFromEvent: minutesFromEvent,
    );

    return {
      'tideStationName': stationName,
      'worldtidesAtlas': atlas,
      'worldtidesResponseLat': responseLat,
      'worldtidesResponseLon': responseLon,
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

  /// Find the reference tide event (nearest to observation time)
  TideEvent? _findReferenceEvent(List<TideEvent> tideEvents, DateTime observationTime) {
    TideEvent? previousEvent = _findPreviousEvent(tideEvents, observationTime);
    TideEvent? nextEvent = _findNextEvent(tideEvents, observationTime);
    
    if (previousEvent != null && nextEvent != null) {
      final previousDelta = observationTime.difference(previousEvent.eventTime).abs();
      final nextDelta = nextEvent.eventTime.difference(observationTime).abs();
      return previousDelta < nextDelta ? previousEvent : nextEvent;
    } else if (previousEvent != null) {
      return previousEvent;
    } else if (nextEvent != null) {
      return nextEvent;
    }
    
    return null;
  }

  /// Find the previous tide event before observation time
  TideEvent? _findPreviousEvent(List<TideEvent> tideEvents, DateTime observationTime) {
    TideEvent? previousEvent;
    for (final event in tideEvents) {
      if (event.eventTime.isBefore(observationTime)) {
        previousEvent = event;
      } else {
        break;
      }
    }
    return previousEvent;
  }

  /// Find the next tide event after observation time
  TideEvent? _findNextEvent(List<TideEvent> tideEvents, DateTime observationTime) {
    for (final event in tideEvents) {
      if (event.eventTime.isAfter(observationTime)) {
        return event;
      }
    }
    return null;
  }

  /// Determine the relation to the reference event
  String _determineRelation(DateTime observationTime, TideEvent referenceEvent) {
    if (observationTime.isAfter(referenceEvent.eventTime)) {
      return 'After';
    } else {
      return 'Before';
    }
  }

  /// Validate tide data credibility for Darwin region
  /// 
  /// Darwin has very high tides (typically 4-7m range)
  /// If returned tide heights are too low, the datum may be wrong
  bool _validateTideCredibility(List<TideEvent> tideEvents, double latitude, double longitude) {
    // Check if location is in Darwin region (approximate bounds)
    final isDarwinRegion = latitude >= -13.0 && latitude <= -11.0 && 
                           longitude >= 130.0 && longitude <= 132.0;
    
    if (!isDarwinRegion) {
      // For non-Darwin locations, accept any reasonable tide data
      return true;
    }
    
    // For Darwin, validate that high tides are at least 4m
    final highTides = tideEvents.where((e) => e.eventType.toLowerCase() == 'high').toList();
    
    if (highTides.isEmpty) {
      return true;
    }
    
    // Check if any high tide meets Darwin's typical range
    final hasCredibleHeight = highTides.any((tide) => tide.height >= 4.0);
    
    if (!hasCredibleHeight) {
      // Darwin tide height validation failed
      return false;
    }
    
    return true;
  }
}
