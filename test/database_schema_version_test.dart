import 'dart:io';

import 'package:bragmat/database/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The Settings screen displays the live database schema version
/// (SQLite `user_version`) instead of a hardcoded value. A fresh
/// database is created at version 30; the accessor must report it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDir;

  setUp(() {
    testDir = Directory.systemTemp.createTempSync('schema_version_');
    DatabaseHelper.setTestDatabasePath(p.join(testDir.path, 'bragmat.db'));
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeDatabase();
    DatabaseHelper.clearTestDatabasePath();
    try {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('getSchemaVersion returns the live database user_version', () async {
    expect(await DatabaseHelper.instance.getSchemaVersion(), 30);
  });
}
