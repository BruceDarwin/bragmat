// Read-only inspection of a Bragmat SQLite database file.
// Usage: dart run tool/inspect_db.dart <path-to-db>
// Prints schema version and row counts — never writes to the file.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run tool/inspect_db.dart <db-path>');
    return;
  }
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    args[0],
    options: OpenDatabaseOptions(readOnly: true),
  );
  try {
    final v = await db.rawQuery('PRAGMA user_version');
    print('schema version: ${v.first.values.first}');
    const tables = [
      'catches', 'catch_media', 'fishing_trips', 'trip_media',
      'trip_journal', 'journal_media', 'favourite_spots',
      'fish_types', 'lures', 'baits', 'fishing_buddies',
      'environmental_conditions', 'achievements', 'user_achievements',
    ];
    for (final t in tables) {
      try {
        final r = await db.rawQuery('SELECT COUNT(*) AS c FROM "$t"');
        print('$t: ${r.first['c']}');
      } catch (_) {
        print('$t: <missing>');
      }
    }
  } finally {
    await db.close();
  }
}
