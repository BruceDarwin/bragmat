import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// Tide information derived from Open-Meteo Marine API
class TideInfo {
  final double? tideHeight;
  final TideMovement tideMovement;
  final TideStage derivedTideStage;
  final DateTime? previousTideTime;
  final double? previousTideHeight;
  final DateTime? nextTideTime;
  final double? nextTideHeight;
  final String dataSource;
  final TideConfidence confidence;
  final String? notes;
  final Map<String, dynamic> diagnostics;

  TideInfo({
    this.tideHeight,
    this.tideMovement = TideMovement.unknown,
    this.derivedTideStage = TideStage.unknown,
    this.previousTideTime,
    this.previousTideHeight,
    this.nextTideTime,
    this.nextTideHeight,
    this.dataSource = 'Open-Meteo Marine',
    this.confidence = TideConfidence.low,
    this.notes,
    Map<String, dynamic>? diagnostics,
  }) : diagnostics = diagnostics ?? {};

  Map<String, dynamic> toMap() {
    return {
      'tideHeight': tideHeight,
      'tideMovement': tideMovement.toString(),
      'derivedTideStage': derivedTideStage.toString(),
      'previousTideTime': previousTideTime?.toIso8601String(),
      'previousTideHeight': previousTideHeight,
      'nextTideTime': nextTideTime?.toIso8601String(),
      'nextTideHeight': nextTideHeight,
      'dataSource': dataSource,
      'confidence': confidence.toString(),
      'notes': notes,
    };
  }

  static TideInfo? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    
    return TideInfo(
      tideHeight: map['tideHeight'] as double?,
      tideMovement: _parseTideMovement(map['tideMovement']),
      derivedTideStage: _parseTideStage(map['derivedTideStage']),
      previousTideTime: map['previousTideTime'] != null 
          ? DateTime.parse(map['previousTideTime']) 
          : null,
      previousTideHeight: map['previousTideHeight'] as double?,
      nextTideTime: map['nextTideTime'] != null 
          ? DateTime.parse(map['nextTideTime']) 
          : null,
      nextTideHeight: map['nextTideHeight'] as double?,
      dataSource: map['dataSource'] as String? ?? 'Open-Meteo Marine',
      confidence: _parseTideConfidence(map['confidence']),
      notes: map['notes'] as String?,
    );
  }

  static TideMovement _parseTideMovement(String? value) {
    switch (value) {
      case 'TideMovement.rising':
        return TideMovement.rising;
      case 'TideMovement.falling':
        return TideMovement.falling;
      case 'TideMovement.slack':
        return TideMovement.slack;
      default:
        return TideMovement.unknown;
    }
  }

  static TideStage _parseTideStage(String? value) {
    switch (value) {
      case 'TideStage.runIn':
        return TideStage.runIn;
      case 'TideStage.runOut':
        return TideStage.runOut;
      case 'TideStage.slackHigh':
        return TideStage.slackHigh;
      case 'TideStage.slackLow':
        return TideStage.slackLow;
      default:
        return TideStage.unknown;
    }
  }

  static TideConfidence _parseTideConfidence(String? value) {
    switch (value) {
      case 'TideConfidence.high':
        return TideConfidence.high;
      case 'TideConfidence.medium':
        return TideConfidence.medium;
      default:
        return TideConfidence.low;
    }
  }
}

enum TideMovement {
  rising,
  falling,
  slack,
  unknown,
}

enum TideStage {
  runIn,
  runOut,
  slackHigh,
  slackLow,
  unknown,
}

enum TideConfidence {
  low,
  medium,
  high,
}

/// Service for fetching and deriving tide information from Open-Meteo Marine API
class TideService {
  static const String _baseUrl = 'https://marine-api.open-meteo.com/v1/marine';
  
  /// Fetch tide information for a specific location and time
  ///
  /// Returns null if the API call fails or data is unavailable
  static Future<TideInfo?> getTideInfo({
    required double latitude,
    required double longitude,
    required DateTime catchTime,
  }) async {
    final diagnostics = <String, dynamic>{};
    diagnostics['latitude'] = latitude;
    diagnostics['longitude'] = longitude;
    diagnostics['catchTime'] = catchTime.toIso8601String();
    diagnostics['called'] = true;

    try {
      // Format date for API request (past_days=1 to get historical data)
      final dateStr = DateFormat('yyyy-MM-dd').format(catchTime);

      // Build API URL
      final url = Uri.parse('$_baseUrl?'
          'latitude=$latitude&'
          'longitude=$longitude&'
          'hourly=sea_level_height_msl&'
          'past_days=1&'
          'forecast_days=7&'
          'timezone=auto');

      diagnostics['apiUrl'] = url.toString();

      // Fetch data
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      diagnostics['statusCode'] = response.statusCode;
      diagnostics['responseReceived'] = true;

      if (response.statusCode != 200) {
        diagnostics['error'] = 'Status code ${response.statusCode}';
        return TideInfo(
          diagnostics: diagnostics,
        );
      }

      final data = json.decode(response.body);
      diagnostics['rawResponse'] = data.toString().substring(0, data.toString().length > 500 ? 500 : data.toString().length);

      // Extract hourly sea level data
      final hourly = data['hourly'];
      if (hourly == null) {
        diagnostics['error'] = 'No hourly data in response';
        return TideInfo(
          diagnostics: diagnostics,
        );
      }

      final times = List<String>.from(hourly['time'] ?? []);
      final seaLevels = List<dynamic>.from(hourly['sea_level_height_msl'] ?? []);

      diagnostics['hourlyRecordCount'] = times.length;
      diagnostics['seaLevelRecordCount'] = seaLevels.length;

      if (times.isEmpty || seaLevels.isEmpty) {
        diagnostics['error'] = 'Empty hourly data';
        return TideInfo(
          diagnostics: diagnostics,
        );
      }

      diagnostics['firstTime'] = times.first;
      diagnostics['lastTime'] = times.last;
      diagnostics['firstSeaLevel'] = seaLevels.first;
      diagnostics['lastSeaLevel'] = seaLevels.last;

      // Find the hourly value closest to catch time
      final catchIndex = _findClosestTimeIndex(times, catchTime);
      if (catchIndex == -1) {
        diagnostics['error'] = 'Could not find matching time index';
        return TideInfo(
          diagnostics: diagnostics,
        );
      }

      diagnostics['catchIndex'] = catchIndex;
      diagnostics['matchedTime'] = times[catchIndex];

      final currentHeight = seaLevels[catchIndex] as double?;
      if (currentHeight == null) {
        diagnostics['error'] = 'Sea level at catch index is null';
        return TideInfo(
          diagnostics: diagnostics,
        );
      }

      diagnostics['currentHeight'] = currentHeight;

      // Get previous and next hour values for movement detection
      final previousHeight = catchIndex > 0
          ? seaLevels[catchIndex - 1] as double?
          : null;
      final nextHeight = catchIndex < seaLevels.length - 1
          ? seaLevels[catchIndex + 1] as double?
          : null;

      diagnostics['previousHeight'] = previousHeight;
      diagnostics['nextHeight'] = nextHeight;

      // Determine tide movement
      TideMovement movement = TideMovement.unknown;
      TideStage stage = TideStage.unknown;

      if (previousHeight != null && nextHeight != null) {
        final prevDiff = currentHeight - previousHeight;
        final nextDiff = nextHeight - currentHeight;

        diagnostics['prevDiff'] = prevDiff;
        diagnostics['nextDiff'] = nextDiff;

        // Check if overall trend is rising or falling
        if (prevDiff > 0.01 && nextDiff > 0.01) {
          movement = TideMovement.rising;
          stage = TideStage.runIn;
        } else if (prevDiff < -0.01 && nextDiff < -0.01) {
          movement = TideMovement.falling;
          stage = TideStage.runOut;
        } else if (prevDiff.abs() < 0.01 && nextDiff.abs() < 0.01) {
          movement = TideMovement.slack;
          // Try to determine if slack high or low based on surrounding values
          stage = _determineSlackStage(seaLevels, catchIndex);
        } else {
          // Mixed signals - use the larger change
          if (nextDiff.abs() > prevDiff.abs()) {
            if (nextDiff > 0) {
              movement = TideMovement.rising;
              stage = TideStage.runIn;
            } else {
              movement = TideMovement.falling;
              stage = TideStage.runOut;
            }
          } else {
            if (prevDiff > 0) {
              movement = TideMovement.rising;
              stage = TideStage.runIn;
            } else {
              movement = TideMovement.falling;
              stage = TideStage.runOut;
            }
          }
        }
      } else if (previousHeight != null) {
        // Only have previous value
        final diff = currentHeight - previousHeight;
        diagnostics['diff'] = diff;
        if (diff > 0.01) {
          movement = TideMovement.rising;
          stage = TideStage.runIn;
        } else if (diff < -0.01) {
          movement = TideMovement.falling;
          stage = TideStage.runOut;
        } else {
          movement = TideMovement.slack;
        }
      } else if (nextHeight != null) {
        // Only have next value
        final diff = nextHeight - currentHeight;
        diagnostics['diff'] = diff;
        if (diff > 0.01) {
          movement = TideMovement.rising;
          stage = TideStage.runIn;
        } else if (diff < -0.01) {
          movement = TideMovement.falling;
          stage = TideStage.runOut;
        } else {
          movement = TideMovement.slack;
        }
      }

      diagnostics['derivedMovement'] = movement.toString();
      diagnostics['derivedStage'] = stage.toString();

      // Find approximate previous and next tide times (simplified)
      final previousTideInfo = _findPreviousTide(seaLevels, catchIndex);
      final nextTideInfo = _findNextTide(seaLevels, catchIndex);

      diagnostics['previousTideInfo'] = previousTideInfo;
      diagnostics['nextTideInfo'] = nextTideInfo;

      return TideInfo(
        tideHeight: currentHeight,
        tideMovement: movement,
        derivedTideStage: stage,
        previousTideTime: previousTideInfo != null
            ? DateTime.parse(times[previousTideInfo['index']])
            : null,
        previousTideHeight: previousTideInfo?['height'] as double?,
        nextTideTime: nextTideInfo != null
            ? DateTime.parse(times[nextTideInfo['index']])
            : null,
        nextTideHeight: nextTideInfo?['height'] as double?,
        dataSource: 'Open-Meteo Marine',
        confidence: TideConfidence.low, // Model-based data, low confidence
        notes: 'Model-based tide estimate. Not suitable for navigation. May be inaccurate in coastal areas.',
        diagnostics: diagnostics,
      );

    } catch (e) {
      // Silently fail - don't block catch saving
      diagnostics['error'] = e.toString();
      diagnostics['exception'] = true;
      return TideInfo(
        diagnostics: diagnostics,
      );
    }
  }
  
  /// Find the index in the times array closest to the target time
  static int _findClosestTimeIndex(List<String> times, DateTime targetTime) {
    int closestIndex = -1;
    int minDiff = Duration.microsecondsPerDay;
    
    for (int i = 0; i < times.length; i++) {
      final time = DateTime.parse(times[i]);
      final diff = (time.difference(targetTime)).abs().inSeconds;
      
      if (diff < minDiff) {
        minDiff = diff;
        closestIndex = i;
      }
    }
    
    return closestIndex;
  }
  
  /// Determine if slack is high or low based on surrounding values
  static TideStage _determineSlackStage(List<dynamic> seaLevels, int index) {
    // Look at values before and after to determine if we're at a peak or trough
    final before = index > 2 ? seaLevels[index - 2] as double? : null;
    final after = index < seaLevels.length - 3 ? seaLevels[index + 2] as double? : null;
    final current = seaLevels[index] as double?;
    
    if (before != null && after != null && current != null) {
      if (current > before && current > after) {
        return TideStage.slackHigh;
      } else if (current < before && current < after) {
        return TideStage.slackLow;
      }
    }
    
    return TideStage.unknown;
  }
  
  /// Find the previous high or low tide (simplified - finds local extremum)
  static Map<String, dynamic>? _findPreviousTide(List<dynamic> seaLevels, int startIndex) {
    if (startIndex <= 1) return null;
    
    // Look backwards for a local extremum
    for (int i = startIndex - 1; i >= 1; i--) {
      final prev = seaLevels[i - 1] as double?;
      final current = seaLevels[i] as double?;
      final next = seaLevels[i + 1] as double?;
      
      if (prev != null && current != null && next != null) {
        // Local maximum
        if (current > prev && current > next) {
          return {'index': i, 'height': current, 'type': 'high'};
        }
        // Local minimum
        if (current < prev && current < next) {
          return {'index': i, 'height': current, 'type': 'low'};
        }
      }
    }
    
    return null;
  }
  
  /// Find the next high or low tide (simplified - finds local extremum)
  static Map<String, dynamic>? _findNextTide(List<dynamic> seaLevels, int startIndex) {
    if (startIndex >= seaLevels.length - 2) return null;
    
    // Look forwards for a local extremum
    for (int i = startIndex + 1; i < seaLevels.length - 1; i++) {
      final prev = seaLevels[i - 1] as double?;
      final current = seaLevels[i] as double?;
      final next = seaLevels[i + 1] as double?;
      
      if (prev != null && current != null && next != null) {
        // Local maximum
        if (current > prev && current > next) {
          return {'index': i, 'height': current, 'type': 'high'};
        }
        // Local minimum
        if (current < prev && current < next) {
          return {'index': i, 'height': current, 'type': 'low'};
        }
      }
    }
    
    return null;
  }
}
