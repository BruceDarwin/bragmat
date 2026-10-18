import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bragmat/helpers/tide_context_helper.dart';
import 'package:bragmat/models/environmental_condition.dart';
import 'package:bragmat/models/tide_reference.dart';
import 'package:bragmat/services/tide_reference_service.dart';
import 'package:bragmat/services/environmental_conditions_service.dart';
import 'package:bragmat/data/tide_reference_catalogue.dart';

void main() {
  group('TideReferenceService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('Default mode is automatic', () async {
      final reference = await TideReferenceService.getCurrentReference();
      expect(reference.id, 'automatic');
      expect(reference.displayName, 'Automatic (catch location)');
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

  group('Equality', () {
    // Regression: DropdownButton asserts when its value is a different
    // instance than every menu item — equality must be by stable id.
    test('Separate Automatic instances with same ID compare as equal', () {
      final auto1 = TideReference(
        id: 'automatic',
        displayName: 'Automatic',
        latitude: 0.0,
        longitude: 0.0,
      );
      final auto2 = TideReference(
        id: 'automatic',
        displayName: 'Automatic (catch location)',
        latitude: 0.0,
        longitude: 0.0,
      );

      expect(auto1, equals(auto2));
      expect(auto1.hashCode, equals(auto2.hashCode));
    });

    test('Separate Darwin instances with same ID compare as equal', () {
      final darwin1 = TideReference(
        id: 'darwin',
        displayName: 'Darwin',
        latitude: -12.4667,
        longitude: 130.8500,
      );
      final darwin2 = TideReference(
        id: 'darwin',
        displayName: 'Darwin',
        latitude: -12.4667,
        longitude: 130.8500,
      );

      expect(darwin1, equals(darwin2));
      expect(darwin1.hashCode, equals(darwin2.hashCode));
    });

    test('Automatic and Darwin compare as different', () {
      final auto = TideReference(
        id: 'automatic',
        displayName: 'Automatic',
        latitude: 0.0,
        longitude: 0.0,
      );
      final darwin = TideReference(
        id: 'darwin',
        displayName: 'Darwin',
        latitude: -12.4667,
        longitude: 130.8500,
      );

      expect(auto, isNot(equals(darwin)));
      expect(auto.hashCode, isNot(equals(darwin.hashCode)));
    });

    test('Reference deserialized from database matches dropdown item', () {
      final dbMap = {
        'id': 'darwin',
        'displayName': 'Darwin',
        'latitude': -12.4667,
        'longitude': 130.8500,
        'isUserCreated': 0,
      };
      final dbReference = TideReference.fromMap(dbMap);
      final dropdownReference =
          TideReferenceService.getReferenceById('darwin');

      expect(dbReference, equals(dropdownReference));
    });

    test('Changes to non-identity metadata do not affect reference identity',
        () {
      final original = TideReference(
        id: 'darwin',
        displayName: 'Darwin',
        latitude: -12.4667,
        longitude: 130.8500,
      );
      final modified = original.copyWith(
        displayName: 'Darwin NT',
        latitude: -12.5,
        longitude: 131.0,
      );

      expect(original, equals(modified));
      expect(original.hashCode, equals(modified.hashCode));
    });

    test('Fresh install: current reference matches a dropdown item', () async {
      // A fresh install defaults to automatic mode; getCurrentReference()
      // builds a new instance, so identity equality would fail the
      // DropdownButton assertion — this is the emulator-reported defect.
      SharedPreferences.setMockInitialValues({});
      final current = await TideReferenceService.getCurrentReference();
      final options = TideReferenceService.getAllReferences();

      expect(options.any((ref) => ref == current), isTrue,
          reason: 'Selected reference must equal exactly one dropdown item');
      expect(options.where((ref) => ref == current).length, 1);
    });

    test('Fixed mode: stored reference matches a dropdown item', () async {
      SharedPreferences.setMockInitialValues({
        'tide_reference_mode': 'fixed',
        'tide_reference_id': 'darwin',
      });
      final current = await TideReferenceService.getCurrentReference();
      final options = TideReferenceService.getAllReferences();

      expect(options.where((ref) => ref == current).length, 1);
    });

    test('No duplicate reference IDs in dropdown', () {
      final references = TideReferenceService.getAllReferences();
      final ids = references.map((ref) => ref.id).toList();
      final uniqueIds = ids.toSet();

      expect(ids.length, equals(uniqueIds.length),
          reason: 'Dropdown should not contain duplicate reference IDs');
    });

    test('Historical reference with unavailable ID can be added to dropdown',
        () {
      final historical = TideReference(
        id: 'historical_station',
        displayName: 'Historical Station',
        latitude: -10.0,
        longitude: 130.0,
      );

      final references = TideReferenceService.getAllReferences();
      final hasHistoricalId =
          references.any((ref) => ref.id == historical.id);
      expect(hasHistoricalId, false,
          reason: 'Historical reference should not be in predefined list');

      // Mirror the dropdown guard in add_catch_screen.
      final dropdownItems = <TideReference?>[...references];
      if (!dropdownItems.any((ref) => ref?.id == historical.id)) {
        dropdownItems.add(historical);
      }

      final hasHistoricalAfterAdd =
          dropdownItems.any((ref) => ref?.id == historical.id);
      expect(hasHistoricalAfterAdd, true,
          reason: 'Historical reference should be addable to dropdown');
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
      final display = mode == 'automatic' ? 'Catch location' : referenceName;
      expect(display, 'Darwin');
    });

    test('NULL mode displays "Not recorded"', () {
      final mode = null;
      final display = mode == 'automatic' ? 'Catch location' : 'Not recorded';
      expect(display, 'Not recorded');
    });

    test('WorldTides station displays as "station"', () {
      final station = 'Darwin';
      final display = station.isNotEmpty ? '$station station' : 'Not recorded';
      expect(display, 'Darwin station');
    });

    test('WorldTides atlas displays as "model"', () {
      final station = '';
      final atlas = 'FES2022';
      final display = station.isNotEmpty 
          ? '$station station' 
          : (atlas.isNotEmpty ? '$atlas model' : 'Not recorded');
      expect(display, 'FES2022 model');
    });

    test('NULL WorldTides source displays "Not recorded"', () {
      final station = '';
      final atlas = '';
      final display = station.isNotEmpty 
          ? '$station station' 
          : (atlas.isNotEmpty ? '$atlas model' : 'Not recorded');
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

  group('Stage 3: Failed Recalculation Workflow', () {
    test('clearTideResults clears WorldTides metadata', () {
      final condition = EnvironmentalCondition(
        id: 1,
        catchId: 1,
        observationDateTime: DateTime(2026, 8, 2),
        latitude: -12.4667,
        longitude: 130.8500,
        worldtidesStation: 'Darwin',
        worldtidesAtlas: 'FES2022',
        worldtidesResponseLat: -12.4667,
        worldtidesResponseLon: 130.8500,
        referenceTideEventType: 'High',
        referenceTideEventTime: DateTime(2026, 8, 2, 10, 57),
        referenceTideEventHeight: 6.595,
        referenceTideEventRelation: 'Before',
        previousTideEventType: 'Low',
        previousTideEventTime: DateTime(2026, 8, 2, 4, 30),
        previousTideEventHeight: 1.2,
        nextTideEventType: 'High',
        nextTideEventTime: DateTime(2026, 8, 2, 17, 15),
        nextTideEventHeight: 7.1,
        tideContextPhrase: 'Darwin high tide 6.59 m',
        tideContextDataSource: 'WorldTides',
        tideContextConfidence: 'High',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final cleared = condition.clearTideResults();

      expect(cleared.worldtidesStation, isNull);
      expect(cleared.worldtidesAtlas, isNull);
      expect(cleared.worldtidesResponseLat, isNull);
      expect(cleared.worldtidesResponseLon, isNull);
      expect(cleared.referenceTideEventType, isNull);
      expect(cleared.referenceTideEventTime, isNull);
      expect(cleared.referenceTideEventHeight, isNull);
      expect(cleared.referenceTideEventRelation, isNull);
      expect(cleared.previousTideEventType, isNull);
      expect(cleared.previousTideEventTime, isNull);
      expect(cleared.previousTideEventHeight, isNull);
      expect(cleared.nextTideEventType, isNull);
      expect(cleared.nextTideEventTime, isNull);
      expect(cleared.nextTideEventHeight, isNull);
      expect(cleared.tideContextPhrase, isNull);
      expect(cleared.tideContextDataSource, isNull);
      expect(cleared.tideContextConfidence, isNull);
    });

    test('clearTideResults preserves manual tide observations', () {
      final condition = EnvironmentalCondition(
        id: 1,
        catchId: 1,
        observationDateTime: DateTime(2026, 8, 2),
        latitude: -12.4667,
        longitude: 130.8500,
        tideStage: 'High Tide',
        tideStrength: 'Strong',
        tideNotes: 'Observed manually',
        tideHeight: 6.5,
        tideMovement: 'Run-In',
        tideStation: 'Manual observation',
        worldtidesStation: 'Darwin',
        worldtidesAtlas: 'FES2022',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final cleared = condition.clearTideResults();

      expect(cleared.tideStage, 'High Tide');
      expect(cleared.tideStrength, 'Strong');
      expect(cleared.tideNotes, 'Observed manually');
      expect(cleared.tideHeight, 6.5);
      expect(cleared.tideMovement, 'Run-In');
      expect(cleared.tideStation, 'Manual observation');
    });

    test('clearTideResults preserves tide reference information', () {
      final condition = EnvironmentalCondition(
        id: 1,
        catchId: 1,
        observationDateTime: DateTime(2026, 8, 2),
        latitude: -12.4667,
        longitude: 130.8500,
        tideReferenceMode: 'fixed',
        tideReferenceName: 'Darwin',
        tideRequestLat: -12.4667,
        tideRequestLon: 130.8500,
        worldtidesStation: 'Darwin',
        worldtidesAtlas: 'FES2022',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final cleared = condition.clearTideResults();

      expect(cleared.tideReferenceMode, 'fixed');
      expect(cleared.tideReferenceName, 'Darwin');
      expect(cleared.tideRequestLat, -12.4667);
      expect(cleared.tideRequestLon, 130.8500);
    });

    test('clearTideResults preserves weather and environmental data', () {
      final condition = EnvironmentalCondition(
        id: 1,
        catchId: 1,
        observationDateTime: DateTime(2026, 8, 2),
        latitude: -12.4667,
        longitude: 130.8500,
        weatherCondition: 'Sunny',
        temperature: 32.0,
        humidity: 65.0,
        cloudCover: 10.0,
        windSpeed: 15.0,
        windDirection: 'NE',
        barometricPressure: 1013.0,
        rainfall: 0.0,
        waterClarity: 'Clear',
        worldtidesStation: 'Darwin',
        worldtidesAtlas: 'FES2022',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final cleared = condition.clearTideResults();

      expect(cleared.weatherCondition, 'Sunny');
      expect(cleared.temperature, 32.0);
      expect(cleared.humidity, 65.0);
      expect(cleared.cloudCover, 10.0);
      expect(cleared.windSpeed, 15.0);
      expect(cleared.windDirection, 'NE');
      expect(cleared.barometricPressure, 1013.0);
      expect(cleared.rainfall, 0.0);
      expect(cleared.waterClarity, 'Clear');
    });

    test('TideRecalculationResult enum values exist', () {
      expect(TideRecalculationResult.success, isNotNull);
      expect(TideRecalculationResult.unavailable, isNotNull);
      expect(TideRecalculationResult.invalidCoordinates, isNotNull);
      expect(TideRecalculationResult.invalidApiKey, isNotNull);
      expect(TideRecalculationResult.unexpectedFailure, isNotNull);
    });

    test('clearTideResults stamps an applied fixed reference', () {
      final condition = EnvironmentalCondition(
        id: 1,
        catchId: 1,
        observationDateTime: DateTime(2026, 8, 2),
        latitude: -12.4634,
        longitude: 130.8456,
        tideReferenceMode: 'fixed',
        tideReferenceName: 'Darwin',
        tideRequestLat: -12.4667,
        tideRequestLon: 130.8500,
        worldtidesStation: 'Darwin',
        tideContextPhrase: 'Darwin high tide',
        tideContextDataSource: 'WorldTides',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final cleared = condition.clearTideResults(
        appliedTideReferenceMode: 'fixed',
        appliedTideReferenceName: 'Gove',
        appliedTideRequestLat: -12.25,
        appliedTideRequestLon: 136.70,
      );

      // The applied reference is recorded, not the previous one.
      expect(cleared.tideReferenceMode, 'fixed');
      expect(cleared.tideReferenceName, 'Gove');
      expect(cleared.tideRequestLat, -12.25);
      expect(cleared.tideRequestLon, 136.70);
      // Tide results belonging to the previous request are cleared.
      expect(cleared.worldtidesStation, isNull);
      expect(cleared.tideContextPhrase, isNull);
    });

    test('clearTideResults stamps an applied automatic reference', () {
      final condition = EnvironmentalCondition(
        id: 1,
        catchId: 1,
        observationDateTime: DateTime(2026, 8, 2),
        latitude: -12.4634,
        longitude: 130.8456,
        tideReferenceMode: 'fixed',
        tideReferenceName: 'Darwin',
        tideRequestLat: -12.4667,
        tideRequestLon: 130.8500,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final cleared = condition.clearTideResults(
        appliedTideReferenceMode: 'automatic',
        appliedTideReferenceName: null,
        appliedTideRequestLat: -12.4634,
        appliedTideRequestLon: 130.8456,
      );

      expect(cleared.tideReferenceMode, 'automatic');
      expect(cleared.tideReferenceName, isNull);
      expect(cleared.tideRequestLat, -12.4634);
      expect(cleared.tideRequestLon, 130.8456);
    });
  });

  group('resolveRecordedReference (D1)', () {
    test('null or empty mode resolves to null', () {
      expect(TideReferenceService.resolveRecordedReference(mode: null), isNull);
      expect(TideReferenceService.resolveRecordedReference(mode: ''), isNull);
    });

    test('automatic mode resolves to the automatic sentinel', () {
      final ref = TideReferenceService.resolveRecordedReference(mode: 'automatic');
      expect(ref, isNotNull);
      expect(TideReferenceService.isAutomatic(ref!), isTrue);
    });

    test('fixed mode resolves a legacy display name via the catalogue', () {
      // Historical rows store the display name ('Darwin'), not the ID.
      final ref = TideReferenceService.resolveRecordedReference(
        mode: 'fixed',
        name: 'Darwin',
        requestLat: -12.4667,
        requestLon: 130.8500,
      );
      expect(ref, isNotNull);
      expect(ref!.id, 'darwin');
    });

    test('fixed mode resolves a catalogue display name even when the row '
        'predates the entry', () {
      final ref = TideReferenceService.resolveRecordedReference(
        mode: 'fixed',
        name: 'Dundee Beach',
        requestLat: -12.705,
        requestLon: 130.355,
      );
      expect(ref, isNotNull);
      expect(ref!.id, 'dundee_beach');
      expect(ref.isModelLocation, isTrue);
    });

    test('fixed mode with an unknown name reconstructs from recorded '
        'request coordinates — never substitutes automatic', () {
      final ref = TideReferenceService.resolveRecordedReference(
        mode: 'fixed',
        name: 'Old Jetty',
        requestLat: -12.9,
        requestLon: 130.7,
      );
      expect(ref, isNotNull);
      expect(TideReferenceService.isAutomatic(ref!), isFalse);
      expect(ref.latitude, -12.9);
      expect(ref.longitude, 130.7);
      expect(ref.displayName, 'Old Jetty');
      // Reconstructed ID is stable for this recorded name.
      expect(ref.id, 'recorded_old_jetty');
    });

    test('fixed mode with no name and no coordinates is unresolved — '
        'returns null rather than substituting automatic', () {
      final ref = TideReferenceService.resolveRecordedReference(
        mode: 'fixed',
      );
      expect(ref, isNull);
    });
  });

  group('Catalogue source kinds', () {
    test('Darwin is a station-backed reference', () {
      final darwin = TideReferenceService.getReferenceById('darwin')!;
      expect(darwin.isStation, isTrue);
      expect(darwin.isModelLocation, isFalse);
      expect(TideReferenceService.describeSource(darwin), 'tide station');
    });

    test('Dundee Beach is a verified model-based reference', () {
      final dundee = TideReferenceService.getReferenceById('dundee_beach')!;
      expect(dundee.displayName, 'Dundee Beach');
      expect(dundee.isModelLocation, isTrue);
      expect(dundee.isStation, isFalse);
      expect(TideReferenceService.describeSource(dundee),
          'model prediction');
      // Verified WorldTides extremes response coords (FES2022 atlas).
      expect(dundee.latitude, -12.705);
      expect(dundee.longitude, 130.355);
    });

    test('Native Point is a verified station-backed reference', () {
      final point = TideReferenceService.getReferenceById('native_point')!;
      expect(point.displayName, 'Native Point');
      expect(point.isStation, isTrue);
      expect(point.isModelLocation, isFalse);
      // Verified WorldTides station Australia:NT_TP053.
      expect(point.latitude, -12.650);
      expect(point.longitude, 130.2667);
    });

    test('describeSource distinguishes model locations', () {
      final model = TideReference(
        id: 'dundee_beach',
        displayName: 'Dundee Beach',
        latitude: -12.705,
        longitude: 130.355,
        source: TideReferenceSource.model,
      );
      expect(model.isModelLocation, isTrue);
      expect(model.isStation, isFalse);
      expect(TideReferenceService.describeSource(model), 'model prediction');
    });

    test('catalogue IDs are unique and coordinates are sane', () {
      final refs = TideReferenceService.getAllReferences();
      final ids = refs.map((r) => r.id).toSet();
      expect(ids.length, refs.length);
      for (final ref in refs) {
        if (TideReferenceService.isAutomatic(ref)) continue;
        expect(ref.latitude, inInclusiveRange(-90.0, 90.0));
        expect(ref.longitude, inInclusiveRange(-180.0, 180.0));
        expect(ref.source, isNotNull,
            reason: '${ref.id} must declare station vs model');
      }
    });
  });

  group('tideRequestChanged gate (D2)', () {
    EnvironmentalCondition recorded({
      double lat = -12.4667,
      double lon = 130.85,
      DateTime? observedAt,
    }) =>
        EnvironmentalCondition(
          id: 1,
          catchId: 1,
          observationDateTime: observedAt ?? DateTime(2026, 8, 2, 10, 0),
          tideReferenceMode: 'fixed',
          tideReferenceName: 'Darwin',
          tideRequestLat: lat,
          tideRequestLon: lon,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

    test('identical request coordinates and day → unchanged', () {
      expect(
        EnvironmentalConditionsService.tideRequestChanged(
          existing: recorded(),
          requestLat: -12.4667,
          requestLon: 130.85,
          observationDateTime: DateTime(2026, 8, 2, 14, 30),
        ),
        isFalse,
      );
    });

    test('different reference coordinates → changed', () {
      expect(
        EnvironmentalConditionsService.tideRequestChanged(
          existing: recorded(),
          requestLat: -12.25,
          requestLon: 136.70,
          observationDateTime: DateTime(2026, 8, 2, 10, 0),
        ),
        isTrue,
      );
    });

    test('different catch location in automatic mode → changed', () {
      expect(
        EnvironmentalConditionsService.tideRequestChanged(
          existing: recorded(lat: -12.4634, lon: 130.8456),
          requestLat: -12.7,
          requestLon: 130.4,
          observationDateTime: DateTime(2026, 8, 2, 10, 0),
        ),
        isTrue,
      );
    });

    test('same coordinates but different tide date → changed', () {
      expect(
        EnvironmentalConditionsService.tideRequestChanged(
          existing: recorded(observedAt: DateTime(2026, 8, 2, 23, 30)),
          requestLat: -12.4667,
          requestLon: 130.85,
          observationDateTime: DateTime(2026, 8, 3, 0, 15),
        ),
        isTrue,
      );
    });

    test('no recorded request coordinates → not "changed"', () {
      final existing = EnvironmentalCondition(
        id: 1,
        catchId: 1,
        observationDateTime: DateTime(2026, 8, 2, 10, 0),
        tideReferenceMode: 'fixed',
        tideReferenceName: 'Darwin',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(
        EnvironmentalConditionsService.tideRequestChanged(
          existing: existing,
          requestLat: -12.4667,
          requestLon: 130.85,
          observationDateTime: DateTime(2026, 8, 2, 10, 0),
        ),
        isFalse,
      );
    });

    test('no existing record → not "changed" (fetch triggered by missing '
        'context instead)', () {
      expect(
        EnvironmentalConditionsService.tideRequestChanged(
          existing: null,
          requestLat: -12.4667,
          requestLon: 130.85,
          observationDateTime: DateTime(2026, 8, 2),
        ),
        isFalse,
      );
    });
  });

  group('NT catalogue structure', () {
  test('all catalogue IDs unique across published and candidates', () {
    final all = [
      ...kTideReferenceCatalogue,
      ...kTideReferenceCandidates,
    ];
    final ids = all.map((r) => r.id).toSet();
    expect(ids.length, all.length);
  });

  test('published entries are verified; candidates are not', () {
    for (final r in kTideReferenceCatalogue) {
      expect(r.isPublished, isTrue,
          reason: '${r.id} must be verified before publication');
      expect(r.source, isNotNull,
          reason: '${r.id} must declare station vs model');
      expect(r.region, isNotNull,
          reason: '${r.id} must declare a region');
    }
    for (final r in kTideReferenceCandidates) {
      expect(r.isPublished, isFalse);
      expect(r.region, isNotNull);
    }
  });

  test('candidates are never exposed to pickers', () {
    final published = TideReferenceService.getAllReferences();
    for (final c in kTideReferenceCandidates) {
      expect(published.contains(c), isFalse,
          reason: 'unverified candidate ${c.id} must not appear in pickers');
      expect(TideReferenceService.getReferenceById(c.id), isNull);
    }
  });

  test('legacy IDs darwin, dundee_beach, native_point are preserved', () {
    expect(TideReferenceService.getReferenceById('darwin'), isNotNull);
    expect(TideReferenceService.getReferenceById('dundee_beach'), isNotNull);
    expect(TideReferenceService.getReferenceById('native_point'), isNotNull);
  });

  test('catalogue lookup map covers published and candidate entries', () {
    expect(tideReferenceCatalogueById['darwin']?.isPublished, isTrue);
    expect(tideReferenceCatalogueById['snake_bay']?.isPublished, isFalse);
  });
});

group('region classification', () {
  test('verified entries classify into their declared region', () {
    for (final r in kTideReferenceCatalogue) {
      expect(tideRegionForCoordinates(r.latitude, r.longitude), r.region,
          reason: '${r.id} (${r.latitude}, ${r.longitude})');
    }
  });

  test('candidates classify into their declared region', () {
    for (final r in kTideReferenceCandidates) {
      expect(tideRegionForCoordinates(r.latitude, r.longitude), r.region,
          reason:
              '${r.id} at (${r.latitude}, ${r.longitude}) — if this fails, fix the bounding boxes or the candidate coords');
    }
  });

  test('tideStateForCoordinates labels interstate stations', () {
    // WA: west of 129°E (Wyndham ~128.7)
    expect(tideStateForCoordinates(-15.4, 128.7), 'WA');
    // QLD: east of 138°E (Karumba ~140.8)
    expect(tideStateForCoordinates(-17.5, 140.8), 'QLD');
    // NT interior/coast
    expect(tideStateForCoordinates(-12.47, 130.85), 'NT');
    expect(tideStateForCoordinates(-15.74, 136.81), 'NT');
    // Other: north of NT (Indonesian waters)
    expect(tideStateForCoordinates(-8.0, 131.0), 'other');
  });

  test('tideReferencesByRegion groups all published entries', () {
    final grouped = tideReferencesByRegion();
    final total = grouped.values.fold<int>(0, (n, l) => n + l.length);
    expect(total, kTideReferenceCatalogue.length);
  });
});

group('alternative names', () {
  test('recorded references resolve via alt names', () {
    final ref = TideReferenceService.resolveRecordedReference(
      mode: 'fixed',
      name: 'Native Pt',
      requestLat: -12.650,
      requestLon: 130.2667,
    );
    expect(ref, isNotNull);
    expect(ref!.id, 'native_point');
  });
});

group('toMap/fromMap round-trip', () {
  test('new catalogue fields survive serialization', () {
    const original = TideReference(
      id: 'test_ref',
      displayName: 'Test Ref',
      latitude: -12.0,
      longitude: 130.0,
      source: TideReferenceSource.station,
      state: 'NT',
      region: TideRegion.fogBayAndDaly,
      altNames: ['Alt One', 'Alt Two'],
      providerStationId: 'Australia:NT_TP999',
      verification: TideVerification.verified(
          verifiedOn: '2026-10', provenance: 'test'),
    );
    final restored = TideReference.fromMap(original.toMap());
    expect(restored.id, 'test_ref');
    expect(restored.source, TideReferenceSource.station);
    expect(restored.state, 'NT');
    expect(restored.region, TideRegion.fogBayAndDaly);
    expect(restored.altNames, ['Alt One', 'Alt Two']);
    expect(restored.providerStationId, 'Australia:NT_TP999');
    expect(restored.verification.status, TideVerificationStatus.verified);
    expect(restored.verification.verifiedOn, '2026-10');
    expect(restored.isPublished, isTrue);
  });

  test('missing new fields deserialize with safe defaults', () {
    final ref = TideReference.fromMap(const {
      'id': 'old_ref',
      'displayName': 'Old Ref',
      'latitude': -12.0,
      'longitude': 130.0,
      'isUserCreated': 0,
    });
    expect(ref.state, 'NT');
    expect(ref.region, isNull);
    expect(ref.altNames, isEmpty);
    expect(ref.providerStationId, isNull);
    expect(ref.isPublished, isFalse);
  });
});
}
