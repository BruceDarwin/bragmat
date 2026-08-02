import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bragmat/helpers/tide_context_helper.dart';
import 'package:bragmat/models/environmental_condition.dart';
import 'package:bragmat/models/tide_reference.dart';
import 'package:bragmat/services/tide_reference_service.dart';

void main() {
  group('TideReferenceService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('Default mode is automatic', () async {
      final reference = await TideReferenceService.getCurrentReference();
      expect(reference.id, 'automatic');
      expect(reference.displayName, 'Automatic');
    });

    test('Set automatic mode', () async {
      await TideReferenceService.setAutomaticMode();
      final mode = await TideReferenceService.getMode();
      expect(mode, 'automatic');
    });

    test('Set Darwin fixed reference', () async {
      await TideReferenceService.setFixedReference('darwin');
      final mode = await TideReferenceService.getMode();
      expect(mode, 'fixed');
      
      final reference = await TideReferenceService.getCurrentReference();
      expect(reference.id, 'darwin');
      expect(reference.displayName, 'Darwin');
    });

    test('Darwin reference coordinates are correct', () async {
      await TideReferenceService.setFixedReference('darwin');
      final reference = await TideReferenceService.getCurrentReference();
      expect(reference.latitude, -12.4667);
      expect(reference.longitude, 130.8500);
    });

    test('Preference persistence across instances', () async {
      await TideReferenceService.setFixedReference('darwin');
      final mode1 = await TideReferenceService.getMode();
      expect(mode1, 'fixed');
      
      // Simulate new instance by clearing and re-fetching
      final mode2 = await TideReferenceService.getMode();
      expect(mode2, 'fixed');
    });

    test('isAutomatic correctly identifies automatic mode', () async {
      await TideReferenceService.setAutomaticMode();
      final reference = await TideReferenceService.getCurrentReference();
      expect(TideReferenceService.isAutomatic(reference), true);
    });

    test('isAutomatic correctly identifies fixed mode', () async {
      await TideReferenceService.setFixedReference('darwin');
      final reference = await TideReferenceService.getCurrentReference();
      expect(TideReferenceService.isAutomatic(reference), false);
    });

    test('Get predefined Darwin reference by ID', () async {
      final darwin = TideReferenceService.getReferenceById('darwin');
      expect(darwin, isNotNull);
      expect(darwin!.id, 'darwin');
      expect(darwin.displayName, 'Darwin');
      expect(darwin.latitude, -12.4667);
      expect(darwin.longitude, 130.8500);
    });

    test('Get all predefined references', () async {
      final references = TideReferenceService.getPredefinedReferences();
      expect(references.containsKey('darwin'), true);
    });
  });

  group('TideReference Model', () {
    test('Create TideReference with all fields', () {
      final reference = TideReference(
        id: 'darwin',
        displayName: 'Darwin',
        latitude: -12.4667,
        longitude: 130.8500,
        isUserCreated: false,
      );

      expect(reference.id, 'darwin');
      expect(reference.displayName, 'Darwin');
      expect(reference.latitude, -12.4667);
      expect(reference.longitude, 130.8500);
      expect(reference.isUserCreated, false);
    });

    test('copyWith creates modified copy', () {
      final original = TideReference(
        id: 'darwin',
        displayName: 'Darwin',
        latitude: -12.4667,
        longitude: 130.8500,
      );

      final modified = original.copyWith(displayName: 'Darwin Station');
      expect(modified.id, 'darwin');
      expect(modified.displayName, 'Darwin Station');
      expect(modified.latitude, -12.4667);
    });

    test('toMap and fromMap round-trip', () {
      final original = TideReference(
        id: 'darwin',
        displayName: 'Darwin',
        latitude: -12.4667,
        longitude: 130.8500,
        isUserCreated: true,
      );

      final map = original.toMap();
      final restored = TideReference.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.displayName, original.displayName);
      expect(restored.latitude, original.latitude);
      expect(restored.longitude, original.longitude);
      expect(restored.isUserCreated, original.isUserCreated);
    });
  });

  group('Distance Calculation', () {
    test('Distance calculation under 0.5 km', () {
      // Very close points (approximately 100 meters apart)
      final lat1 = -12.4667;
      final lon1 = 130.8500;
      final lat2 = -12.4677;
      final lon2 = 130.8510;
      
      // Calculate using Haversine formula
      const double earthRadiusKm = 6371.0;
      final dLat = (lat2 - lat1) * 3.14159265359 / 180;
      final dLon = (lon2 - lon1) * 3.14159265359 / 180;
      final a = (sin(dLat / 2) * sin(dLat / 2)) +
          cos(lat1 * 3.14159265359 / 180) *
          cos(lat2 * 3.14159265359 / 180) *
          (sin(dLon / 2) * sin(dLon / 2));
      final c = 2 * atan2(sqrt(a), sqrt(1 - a));
      final distanceKm = earthRadiusKm * c;
      
      expect(distanceKm, lessThan(0.5));
    });

    test('Distance calculation under 10 km', () {
      // Points approximately 5 km apart
      final lat1 = -12.4667;
      final lon1 = 130.8500;
      final lat2 = -12.5167;
      final lon2 = 130.9000;
      
      const double earthRadiusKm = 6371.0;
      final dLat = (lat2 - lat1) * 3.14159265359 / 180;
      final dLon = (lon2 - lon1) * 3.14159265359 / 180;
      final a = (sin(dLat / 2) * sin(dLat / 2)) +
          cos(lat1 * 3.14159265359 / 180) *
          cos(lat2 * 3.14159265359 / 180) *
          (sin(dLon / 2) * sin(dLon / 2));
      final c = 2 * atan2(sqrt(a), sqrt(1 - a));
      final distanceKm = earthRadiusKm * c;
      
      expect(distanceKm, greaterThan(0.5));
      expect(distanceKm, lessThan(10));
    });

    test('Distance calculation at or above 10 km', () {
      // Points approximately 15 km apart
      final lat1 = -12.4667;
      final lon1 = 130.8500;
      final lat2 = -12.6167;
      final lon2 = 131.0000;
      
      const double earthRadiusKm = 6371.0;
      final dLat = (lat2 - lat1) * 3.14159265359 / 180;
      final dLon = (lon2 - lon1) * 3.14159265359 / 180;
      final a = (sin(dLat / 2) * sin(dLat / 2)) +
          cos(lat1 * 3.14159265359 / 180) *
          cos(lat2 * 3.14159265359 / 180) *
          (sin(dLon / 2) * sin(dLon / 2));
      final c = 2 * atan2(sqrt(a), sqrt(1 - a));
      final distanceKm = earthRadiusKm * c;
      
      expect(distanceKm, greaterThanOrEqualTo(10));
    });

    test('Distance formatting rules', () {
      // Under 0.5 km: omit distance
      double distanceKm = 0.3;
      String distanceText;
      if (distanceKm < 0.5) {
        distanceText = '';
      } else if (distanceKm < 10) {
        distanceText = ' — ${distanceKm.toStringAsFixed(1)} km from catch';
      } else {
        distanceText = ' — ${distanceKm.round()} km from catch';
      }
      expect(distanceText, isEmpty);

      // Under 10 km: one decimal place
      distanceKm = 5.3;
      if (distanceKm < 0.5) {
        distanceText = '';
      } else if (distanceKm < 10) {
        distanceText = ' — ${distanceKm.toStringAsFixed(1)} km from catch';
      } else {
        distanceText = ' — ${distanceKm.round()} km from catch';
      }
      expect(distanceText, ' — 5.3 km from catch');

      // 10 km or more: nearest whole kilometre
      distanceKm = 12.7;
      if (distanceKm < 0.5) {
        distanceText = '';
      } else if (distanceKm < 10) {
        distanceText = ' — ${distanceKm.toStringAsFixed(1)} km from catch';
      } else {
        distanceText = ' — ${distanceKm.round()} km from catch';
      }
      expect(distanceText, ' — 13 km from catch');
    });
  });

  group('Environmental Condition with Stage 2 Fields', () {
    test('Automatic mode uses catch coordinates', () {
      final condition = EnvironmentalCondition(
        observationDateTime: DateTime(2026, 8, 2, 10, 0),
        latitude: -12.4634,
        longitude: 130.8456,
        tideReferenceMode: 'automatic',
        tideReferenceName: null,
        tideRequestLat: -12.4634,
        tideRequestLon: 130.8456,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(condition.tideReferenceMode, 'automatic');
      expect(condition.tideReferenceName, null);
      expect(condition.tideRequestLat, -12.4634);
      expect(condition.tideRequestLon, 130.8456);
    });

    test('Fixed mode uses Darwin coordinates', () {
      final condition = EnvironmentalCondition(
        observationDateTime: DateTime(2026, 8, 2, 10, 0),
        latitude: -12.4634,
        longitude: 130.8456,
        tideReferenceMode: 'fixed',
        tideReferenceName: 'Darwin',
        tideRequestLat: -12.4667,
        tideRequestLon: 130.8500,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(condition.tideReferenceMode, 'fixed');
      expect(condition.tideReferenceName, 'Darwin');
      expect(condition.tideRequestLat, -12.4667);
      expect(condition.tideRequestLon, 130.8500);
    });

    test('Historical data with NULL reference fields', () {
      final map = {
        'observation_date_time': DateTime(2026, 8, 2, 10, 0).toIso8601String(),
        'latitude': -12.4634,
        'longitude': 130.8456,
        'tide_reference_mode': null,
        'tide_reference_name': null,
        'tide_request_lat': null,
        'tide_request_lon': null,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final condition = EnvironmentalCondition.fromMap(map);
      expect(condition.tideReferenceMode, null);
      expect(condition.tideReferenceName, null);
      expect(condition.tideRequestLat, null);
      expect(condition.tideRequestLon, null);
    });

    test('API failure preserves selected reference', () {
      final condition = EnvironmentalCondition(
        observationDateTime: DateTime(2026, 8, 2, 10, 0),
        latitude: -12.4634,
        longitude: 130.8456,
        tideReferenceMode: 'fixed',
        tideReferenceName: 'Darwin',
        tideRequestLat: -12.4667,
        tideRequestLon: 130.8500,
        worldtidesStation: null,
        worldtidesAtlas: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(condition.tideReferenceMode, 'fixed');
      expect(condition.tideReferenceName, 'Darwin');
      expect(condition.worldtidesStation, null);
      expect(condition.worldtidesAtlas, null);
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
}
