import 'package:flutter_test/flutter_test.dart';
import 'package:bragmat/models/catch.dart';

void main() {
  group('Unidentified Fish Support', () {
    test('Catch model allows null fishType', () {
      final catch1 = Catch(
        fishType: null,
        lengthCm: 50,
        createdAt: DateTime.now(),
      );
      expect(catch1.fishType, isNull);
    });

    test('Catch model preserves null in toMap', () {
      final catch1 = Catch(
        fishType: null,
        lengthCm: 50,
        createdAt: DateTime.now(),
      );
      final map = catch1.toMap();
      expect(map['fish_type'], isNull);
    });

    test('Catch model preserves null in fromMap', () {
      final map = {
        'id': 1,
        'fish_type': null,
        'length_cm': 50,
        'notes': null,
        'created_at': DateTime.now().toIso8601String(),
        'date_caught': null,
        'image_path': null,
        'photo_datetime': null,
        'latitude': null,
        'longitude': null,
        'location': null,
        'fishing_buddy_id': null,
        'trip_id': null,
        'coordinate_source': null,
        'lure_id': null,
        'bait_id': null,
        'lure_size': null,
        'lure_colour': null,
        'lure_photo_path': null,
      };
      final catch1 = Catch.fromMap(map);
      expect(catch1.fishType, isNull);
    });

    test('Catch model preserves empty string as empty string', () {
      final catch1 = Catch(
        fishType: '',
        lengthCm: 50,
        createdAt: DateTime.now(),
      );
      expect(catch1.fishType, '');
    });

    test('Catch copyWith allows setting fishType to null', () {
      final catch1 = Catch(
        fishType: 'Barramundi',
        lengthCm: 50,
        createdAt: DateTime.now(),
      );
      final catch2 = catch1.copyWith(fishType: null);
      expect(catch2.fishType, isNull);
    });

    test('Catch copyWith allows setting fishType to a value', () {
      final catch1 = Catch(
        fishType: null,
        lengthCm: 50,
        createdAt: DateTime.now(),
      );
      final catch2 = catch1.copyWith(fishType: 'Barramundi');
      expect(catch2.fishType, 'Barramundi');
    });

    test('Catch copyWith preserves null when not specified', () {
      final catch1 = Catch(
        fishType: null,
        lengthCm: 50,
        createdAt: DateTime.now(),
      );
      final catch2 = catch1.copyWith(lengthCm: 60);
      expect(catch2.fishType, isNull);
    });

    test('Catch with empty string fishType is treated as unidentified', () {
      final catch1 = Catch(
        fishType: '',
        lengthCm: 50,
        createdAt: DateTime.now(),
      );
      expect(catch1.fishType?.isEmpty ?? true, isTrue);
    });

    test('Catch with null fishType is treated as unidentified', () {
      final catch1 = Catch(
        fishType: null,
        lengthCm: 50,
        createdAt: DateTime.now(),
      );
      expect(catch1.fishType?.isEmpty ?? true, isTrue);
    });

    test('Catch with valid fishType is not unidentified', () {
      final catch1 = Catch(
        fishType: 'Barramundi',
        lengthCm: 50,
        createdAt: DateTime.now(),
      );
      expect(catch1.fishType?.isEmpty ?? true, isFalse);
    });
  });
}
