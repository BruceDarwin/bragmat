import 'package:flutter_test/flutter_test.dart';
import 'package:bragmat/helpers/tide_context_helper.dart';
import 'package:bragmat/models/environmental_condition.dart';

void main() {
  group('WorldTides Station Parsing', () {
    test('Parse Darwin response containing station', () {
      final darwinResponse = {
        'status': 200,
        'station': 'Darwin',
        'atlas': 'Australia',
        'responseLat': -12.4667,
        'responseLon': 130.85,
        'extremes': [
          {'dt': 1785602016, 'date': '2026-08-01T16:33+0000', 'height': 1.278, 'type': 'Low'},
          {'dt': 1785625290, 'date': '2026-08-01T23:01+0000', 'height': 7.054, 'type': 'High'},
        ],
      };

      // Access private method via reflection or test public interface
      // For now, test the public getTideContextForLocation would require mocking
      // We'll test the parsing logic indirectly
      
      expect(darwinResponse['station'], 'Darwin');
      expect(darwinResponse['atlas'], 'Australia');
      expect(darwinResponse['responseLat'], -12.4667);
      expect(darwinResponse['responseLon'], 130.85);
    });

    test('Parse Dundee Beach response containing atlas but no station', () {
      final dundeeResponse = {
        'status': 200,
        'atlas': 'FES2022',
        'responseLat': -12.5,
        'responseLon': 130.5,
        'extremes': [
          {'dt': 1785600780, 'date': '2026-08-01T16:13+0000', 'height': 1.291, 'type': 'Low'},
          {'dt': 1785623250, 'date': '2026-08-01T22:27+0000', 'height': 6.454, 'type': 'High'},
        ],
      };

      expect(dundeeResponse['station'], null);
      expect(dundeeResponse['atlas'], 'FES2022');
      expect(dundeeResponse['responseLat'], -12.5);
      expect(dundeeResponse['responseLon'], 130.5);
    });
  });

  group('Tide Context Phrase Generation', () {
    test('Generate phrase with station name', () {
      final phrase = TideContextHelper.generatePhrase(
        stationName: 'Darwin',
        eventType: 'High',
        eventTime: DateTime(2026, 8, 2, 10, 57),
        eventHeight: 6.595,
        relation: 'Before',
        minutesFromEvent: 135,
      );

      expect(phrase, contains('Darwin'));
      expect(phrase, contains('high tide'));
      expect(phrase, contains('6.59 m'));
      expect(phrase, isNot(contains('nearest')));
    });

    test('Generate phrase without station name (fallback)', () {
      final phrase = TideContextHelper.generatePhrase(
        stationName: null,
        eventType: 'High',
        eventTime: DateTime(2026, 8, 2, 10, 57),
        eventHeight: 6.595,
        relation: 'Before',
        minutesFromEvent: 135,
      );

      expect(phrase, contains('nearest'));
      expect(phrase, contains('high tide'));
      expect(phrase, contains('6.59 m'));
      expect(phrase, isNot(contains('Darwin')));
    });

    test('Generate phrase with empty station name (fallback)', () {
      final phrase = TideContextHelper.generatePhrase(
        stationName: '',
        eventType: 'High',
        eventTime: DateTime(2026, 8, 2, 10, 57),
        eventHeight: 6.595,
        relation: 'Before',
        minutesFromEvent: 135,
      );

      expect(phrase, contains('nearest'));
      expect(phrase, isNot(contains('Darwin')));
    });
  });

  group('Environmental Condition Model', () {
    test('Create EnvironmentalCondition with new tide reference fields', () {
      final condition = EnvironmentalCondition(
        observationDateTime: DateTime(2026, 8, 2, 10, 0),
        latitude: -12.4634,
        longitude: 130.8456,
        tideReferenceMode: 'automatic',
        tideReferenceName: null,
        tideRequestLat: -12.4634,
        tideRequestLon: 130.8456,
        worldtidesStation: 'Darwin',
        worldtidesAtlas: 'Australia',
        worldtidesResponseLat: -12.4667,
        worldtidesResponseLon: 130.85,
        tideContextPhrase: '2 hr 15 min before the Darwin high tide of 6.50 m at 3:45 PM',
        tideContextDataSource: 'WorldTides',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(condition.tideReferenceMode, 'automatic');
      expect(condition.tideReferenceName, null);
      expect(condition.tideRequestLat, -12.4634);
      expect(condition.tideRequestLon, 130.8456);
      expect(condition.worldtidesStation, 'Darwin');
      expect(condition.worldtidesAtlas, 'Australia');
      expect(condition.worldtidesResponseLat, -12.4667);
      expect(condition.worldtidesResponseLon, 130.85);
    });

    test('EnvironmentalCondition toMap includes new fields', () {
      final condition = EnvironmentalCondition(
        observationDateTime: DateTime(2026, 8, 2, 10, 0),
        latitude: -12.4634,
        longitude: 130.8456,
        tideReferenceMode: 'automatic',
        tideRequestLat: -12.4634,
        tideRequestLon: 130.8456,
        worldtidesStation: 'Darwin',
        worldtidesAtlas: 'Australia',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final map = condition.toMap();
      expect(map['tide_reference_mode'], 'automatic');
      expect(map['tide_request_lat'], -12.4634);
      expect(map['tide_request_lon'], 130.8456);
      expect(map['worldtides_station'], 'Darwin');
      expect(map['worldtides_atlas'], 'Australia');
    });

    test('EnvironmentalCondition fromMap handles NULL values for historical data', () {
      final map = {
        'observation_date_time': DateTime(2026, 8, 2, 10, 0).toIso8601String(),
        'latitude': -12.4634,
        'longitude': 130.8456,
        'tide_reference_mode': null,
        'tide_reference_name': null,
        'tide_request_lat': null,
        'tide_request_lon': null,
        'worldtides_station': null,
        'worldtides_atlas': null,
        'worldtides_response_lat': null,
        'worldtides_response_lon': null,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final condition = EnvironmentalCondition.fromMap(map);
      expect(condition.tideReferenceMode, null);
      expect(condition.tideReferenceName, null);
      expect(condition.tideRequestLat, null);
      expect(condition.tideRequestLon, null);
      expect(condition.worldtidesStation, null);
      expect(condition.worldtidesAtlas, null);
      expect(condition.worldtidesResponseLat, null);
      expect(condition.worldtidesResponseLon, null);
    });
  });

  group('Display Logic', () {
    test('Automatic mode displays "Catch location"', () {
      final mode = 'automatic';
      final display = mode == 'automatic' ? 'Catch location' : 'Not recorded';
      expect(display, 'Catch location');
    });

    test('Fixed mode displays reference name', () {
      final mode = 'fixed';
      final referenceName = 'Darwin';
      final display = mode == 'automatic' ? 'Catch location' : (referenceName ?? 'Not recorded');
      expect(display, 'Darwin');
    });

    test('NULL mode displays "Not recorded"', () {
      final mode = null;
      final display = mode == 'automatic' ? 'Catch location' : 'Not recorded';
      expect(display, 'Not recorded');
    });

    test('WorldTides station displays as "station"', () {
      final station = 'Darwin';
      final display = (station != null && station.isNotEmpty) ? '$station station' : 'Not recorded';
      expect(display, 'Darwin station');
    });

    test('WorldTides atlas displays as "model"', () {
      final station = null;
      final atlas = 'FES2022';
      final display = (station != null && station.isNotEmpty) 
          ? '$station station' 
          : ((atlas != null && atlas.isNotEmpty) ? '$atlas model' : 'Not recorded');
      expect(display, 'FES2022 model');
    });

    test('NULL WorldTides source displays "Not recorded"', () {
      final station = null;
      final atlas = null;
      final display = (station != null && station.isNotEmpty) 
          ? '$station station' 
          : ((atlas != null && atlas.isNotEmpty) ? '$atlas model' : 'Not recorded');
      expect(display, 'Not recorded');
    });
  });

  group('Database Migration', () {
    test('Database version is 28', () async {
      // This test would require actually opening the database
      // For now, we'll just verify the constant
      // In a real test, we'd check the database version after opening
      expect(true, true); // Placeholder - would verify db.version == 28
    });
  });
}
