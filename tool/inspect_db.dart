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

    // Media path analysis: how file paths are stored (absolute vs relative)
    // and which directory prefixes are used.
    print('--- media path analysis ---');
    final byPrefix = <String, int>{};
    final uniquePaths = <String>{};
    var absolute = 0;
    var relative = 0;
    Future<void> scan(String table, String column) async {
      try {
        final rows = await db.query(table, columns: [column]);
        for (final row in rows) {
          final p = row[column] as String?;
          if (p == null || p.isEmpty) continue;
          final portable = p.replaceAll('\\', '/');
          uniquePaths.add(portable);
          if (portable.startsWith('/')) {
            absolute++;
            final idx = portable.lastIndexOf('/');
            final dir = idx > 0 ? portable.substring(0, idx) : portable;
            byPrefix['ABS:$dir'] = (byPrefix['ABS:$dir'] ?? 0) + 1;
          } else {
            relative++;
            final idx = portable.lastIndexOf('/');
            final dir = idx > 0 ? portable.substring(0, idx) : '(root)';
            byPrefix['REL:$dir'] = (byPrefix['REL:$dir'] ?? 0) + 1;
          }
        }
      } catch (_) {}
    }
    await scan('catch_media', 'file_path');
    await scan('trip_media', 'file_path');
    await scan('journal_media', 'file_path');
    await scan('catches', 'lure_photo_path');
    print('absolute paths: $absolute, relative paths: $relative');
    print('unique referenced paths: ${uniquePaths.length}');
    final keys = byPrefix.keys.toList()..sort();
    for (final k in keys) {
      print('  $k: ${byPrefix[k]}');
    }
    if (args.contains('--paths')) {
      final sorted = uniquePaths.toList()..sort();
      for (final p in sorted) {
        print('PATH $p');
      }
    }
  } finally {
    await db.close();
  }
}
