// Regression tests for AchievementService against a real (ffi) database.
//
// Covers the strict-SQLite fix: the unique-species query previously used
// a double-quoted empty literal (fish_type != "") which sqlite builds with
// DQS disabled (sqflite_common_ffi) reject as an unknown column — aborting
// the whole save path. Single-quoted literal works on every engine.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bragmat/database/database_helper.dart';
import 'package:bragmat/models/catch.dart' as model;
import 'package:bragmat/services/achievement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;

  setUp(() {
    testDir = Directory.systemTemp.createTempSync('bragmat_achv_test_');
    DatabaseHelper.setTestDatabasePath(p.join(testDir.path, 'bragmat.db'));
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    if (await testDir.exists()) await testDir.delete(recursive: true);
  });

  test('evaluateCatchAchievements completes on a strict-sqlite engine '
      'with species-bearing catches present', () async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
        'catches',
        model.Catch(
          lengthCm: 45,
          fishType: 'Barramundi',
          createdAt: DateTime(2026, 8, 2),
          dateCaught: DateTime(2026, 8, 2),
        ).toMap());
    await db.insert(
        'catches',
        model.Catch(
          lengthCm: 30,
          fishType: '',
          createdAt: DateTime(2026, 8, 3),
          dateCaught: DateTime(2026, 8, 3),
        ).toMap());

    // Must not throw — the old "" literal raised "no such column" here.
    await AchievementService().evaluateCatchAchievements();
  });
}
