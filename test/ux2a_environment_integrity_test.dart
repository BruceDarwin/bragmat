// UX-2A — Environmental data integrity & provenance tests:
//  - re-saving an unchanged record preserves stored dataSource
//  - manual-only edits (clarity/flow/tide) keep automatic provenance
//  - an intentional weather override reclassifies as 'Manual'
//  - populated records do not re-fetch Open-Meteo on save
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/models/catch.dart' as bragmat;
import 'package:bragmat/models/environmental_condition.dart';
import 'package:bragmat/services/environmental_conditions_service.dart';
import 'package:bragmat/services/weather_service.dart';
import 'package:bragmat/services/worldtides_service.dart';

class _CountingWeather implements WeatherService {
  int calls = 0;

  @override
  Future<WeatherData?> fetchWeather(
      double latitude, double longitude, DateTime dateTime) async {
    calls++;
    return null;
  }

  @override
  String windDirectionToCompass(double? degrees) => 'N';
}

class _CountingWorldTides implements WorldTidesService {
  int calls = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Map<String, dynamic>?> getTideContextForLocation(
      double latitude, double longitude, DateTime dateTime) async {
    calls++;
    return null;
  }
}

EnvironmentalCondition _base({
  int? id,
  int? catchId = 42,
  String dataSource = 'Open-Meteo',
  double? temp = 31.5,
  String? weather = 'Clear',
  double? wind = 12.0,
  double? humidity = 70.0,
  String? clarity,
  String? flow,
}) {
  final now = DateTime(2026, 7, 3, 9, 0);
  return EnvironmentalCondition(
    id: id,
    catchId: catchId,
    observationDateTime: now,
    latitude: -12.4634,
    longitude: 130.8456,
    weatherCondition: weather,
    temperature: temp,
    humidity: humidity,
    windSpeed: wind,
    dataSource: dataSource,
    waterClarity: clarity,
    riverFlow: flow,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late EnvironmentalConditionsService service;
  late _CountingWeather weather;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() {
    service = EnvironmentalConditionsService();
    weather = _CountingWeather();
    service.weatherService = weather;
  });

  Future<void> insertCatchRow(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('catches', conflictAlgorithm: ConflictAlgorithm.replace, {
      'id': id,
      'fish_type': 'Barramundi',
      'length_cm': 80,
      'latitude': -12.4634,
      'longitude': 130.8456,
      'created_at': DateTime(2026, 7, 3).toIso8601String(),
      'updated_at': DateTime(2026, 7, 3).toIso8601String(),
    });
  }

  Future<void> seedRecord(
      {String dataSource = 'Open-Meteo', int catchId = 42}) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('environmental_conditions');
    await insertCatchRow(catchId);
    await service.createEnvironmentalCondition(
        _base(catchId: catchId, dataSource: dataSource));
  }

  test('update on a populated record does not re-fetch weather', () async {
    await service.updateEnvironmentalCondition(_base());
    expect(weather.calls, 0);
  });

  test('update on an empty record may fetch weather', () async {
    await service.updateEnvironmentalCondition(
        _base(temp: null, weather: null, wind: null, humidity: null));
    expect(weather.calls, 1);
  });

  test('re-save with identical values preserves Open-Meteo provenance',
      () async {
    await seedRecord(dataSource: 'Open-Meteo');
    await service.saveEnvironmentalConditionForCatch(
      42, DateTime(2026, 7, 3, 9, 0), -12.4634, 130.8456,
      weatherCondition: 'Clear',
      temperature: 31.5,
      humidity: 70.0,
      windSpeed: 12.0,
    );
    final saved = await service.getEnvironmentalConditionForCatch(42);
    expect(saved!.dataSource, 'Open-Meteo');
  });

  test('manual-only edit keeps automatic provenance', () async {
    await seedRecord(dataSource: 'Open-Meteo');
    await service.saveEnvironmentalConditionForCatch(
      42, DateTime(2026, 7, 3, 9, 0), -12.4634, 130.8456,
      weatherCondition: 'Clear',
      temperature: 31.5,
      humidity: 70.0,
      windSpeed: 12.0,
      waterClarity: 'Clear',
      riverFlow: 'Normal',
    );
    final saved = await service.getEnvironmentalConditionForCatch(42);
    expect(saved!.dataSource, 'Open-Meteo');
    expect(saved.waterClarity, 'Clear');
  });

  test('intentional weather override reclassifies as Manual', () async {
    await seedRecord(dataSource: 'Open-Meteo');
    await service.saveEnvironmentalConditionForCatch(
      42, DateTime(2026, 7, 3, 9, 0), -12.4634, 130.8456,
      weatherCondition: 'Clear',
      temperature: 28.0, // user changed temperature
      humidity: 70.0,
      windSpeed: 12.0,
    );
    final saved = await service.getEnvironmentalConditionForCatch(42);
    expect(saved!.dataSource, 'Manual');
  });

  test('new record with no existing data is Manual', () async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('environmental_conditions');
    await insertCatchRow(43);
    await service.saveEnvironmentalConditionForCatch(
      43, DateTime(2026, 7, 3, 9, 0), -12.4634, 130.8456,
      weatherCondition: 'Clear',
      temperature: 31.5,
    );
    final saved = await service.getEnvironmentalConditionForCatch(43);
    expect(saved!.dataSource, 'Manual');
  });

  test("stored 'Unknown' condition does not read as an override",
      () async {
    // The form normalises 'Unknown'->null on submit; a stored 'Unknown'
    // must compare equal so provenance isn't falsely flipped.
    await seedRecord(dataSource: 'Open-Meteo');
    final db = await DatabaseHelper.instance.database;
    await db.update('environmental_conditions',
        {'weather_condition': 'Unknown', 'wind_direction': 'Unknown'},
        where: 'catch_id = ?', whereArgs: [42]);
    await service.saveEnvironmentalConditionForCatch(
      42, DateTime(2026, 7, 3, 9, 0), -12.4634, 130.8456,
      weatherCondition: null, // 'Unknown' selected -> submitted as null
      temperature: 31.5,
      humidity: 70.0,
      windSpeed: 12.0,
      windDirection: null,
    );
    final saved = await service.getEnvironmentalConditionForCatch(42);
    expect(saved!.dataSource, 'Open-Meteo');
  });

  test('partially populated record preserves provenance', () async {
    await seedRecord(dataSource: 'Calculated');
    final db = await DatabaseHelper.instance.database;
    await db.update(
        'environmental_conditions',
        {'temperature': null, 'humidity': null, 'wind_speed': null},
        where: 'catch_id = ?', whereArgs: [42]);
    await service.saveEnvironmentalConditionForCatch(
      42, DateTime(2026, 7, 3, 9, 0), -12.4634, 130.8456,
      weatherCondition: 'Clear', // only condition recorded historically
    );
    final saved = await service.getEnvironmentalConditionForCatch(42);
    expect(saved!.dataSource, 'Calculated');
  });

  test('deliberately cleared weather stays cleared, no refetch',
      () async {
    await seedRecord(dataSource: 'Open-Meteo');
    await service.saveEnvironmentalConditionForCatch(
      42, DateTime(2026, 7, 3, 9, 0), -12.4634, 130.8456,
      // All weather fields deliberately cleared by the user.
      weatherCondition: null,
      temperature: null,
      humidity: null,
      cloudCover: null,
      windSpeed: null,
      windDirection: null,
      barometricPressure: null,
      rainfall: null,
    );
    final saved = await service.getEnvironmentalConditionForCatch(42);
    expect(saved!.temperature, isNull);
    expect(saved.weatherCondition, isNull);
    expect(weather.calls, 0);
  });

  test('ordinary save of existing record does not fetch WorldTides',
      () async {
    await seedRecord(dataSource: 'Open-Meteo');
    final tides = _CountingWorldTides();
    service.worldTidesService = tides;
    final catchItem = bragmat.Catch(
      id: 42, fishType: 'Red Snapper', lengthCm: 25,
      createdAt: DateTime(2026, 7, 3),
      dateCaught: DateTime(2026, 7, 3, 9, 0),
      latitude: -12.4634, longitude: 130.8456,
    );
    await service.upsertCalculatedConditionsForCatch(catchItem);
    expect(tides.calls, 0);
  });

  test('new catch may fetch WorldTides', () async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('environmental_conditions');
    await insertCatchRow(44);
    final tides = _CountingWorldTides();
    service.worldTidesService = tides;
    final catchItem = bragmat.Catch(
      id: 44, fishType: 'Barramundi', lengthCm: 60,
      createdAt: DateTime(2026, 7, 3),
      dateCaught: DateTime(2026, 7, 3, 9, 0),
      latitude: -12.4634, longitude: 130.8456,
    );
    await service.upsertCalculatedConditionsForCatch(catchItem);
    expect(tides.calls, 1);
  });

  test('zero vs null values preserved', () async {
    await seedRecord(dataSource: 'Manual');
    await service.saveEnvironmentalConditionForCatch(
      42, DateTime(2026, 7, 3, 9, 0), -12.4634, 130.8456,
      weatherCondition: 'Clear',
      temperature: 0.0, // legitimate zero, not missing
      humidity: 70.0,
      windSpeed: 12.0,
    );
    final saved = await service.getEnvironmentalConditionForCatch(42);
    expect(saved!.temperature, 0.0);
  });
}
