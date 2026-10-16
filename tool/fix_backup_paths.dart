// Rewrites stale media references inside a backup ZIP's database.
//
// Reads a bragmat_backup_*.zip, fixes file paths in the embedded
// database.sqlite so they point at the relative locations the media files
// are actually stored under inside the archive (media/<subdir>/<basename>),
// and writes a corrected ZIP copy. The original archive is never modified.
//
// Usage:
//   dart run tool/fix_backup_paths.dart <in.zip> <out.zip>
//
// Prints a per-table report and flags any references that cannot be
// resolved against archive contents (ambiguities / genuinely missing).
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _mediaSources = [
  ('catch_media', 'file_path'),
  ('trip_media', 'file_path'),
  ('journal_media', 'file_path'),
  ('catches', 'lure_photo_path'),
];

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: dart run tool/fix_backup_paths.dart <in.zip> <out.zip>');
    exit(2);
  }
  final inPath = args[0];
  final outPath = args[1];

  // --- decode archive ---
  final archive = ZipDecoder().decodeBytes(await File(inPath).readAsBytes());

  // Map media basename -> subdir (catches/trips/journals/lures) from the
  // archive. Flag basenames that appear in more than one subdir.
  final basenameToSubdir = <String, String>{};
  final ambiguous = <String>{};
  for (final f in archive.files) {
    if (!f.isFile || !f.name.startsWith('media/')) continue;
    final parts = f.name.split('/');
    if (parts.length != 3) continue;
    final subdir = parts[1];
    final base = parts[2];
    if (basenameToSubdir.containsKey(base) && basenameToSubdir[base] != subdir) {
      ambiguous.add(base);
    } else {
      basenameToSubdir[base] = subdir;
    }
  }
  print('archive media files: ${basenameToSubdir.length}');

  // --- extract + open database ---
  final dbEntry = archive.files.firstWhere(
    (f) => f.isFile && f.name == 'database.sqlite',
    orElse: () => throw StateError('database.sqlite missing from archive'),
  );
  final tempDir = await Directory.systemTemp.createTemp('fix_backup_');
  final dbFile = File(p.join(tempDir.path, 'database.sqlite'));
  await dbFile.writeAsBytes(dbEntry.content as List<int>);

  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(dbFile.path);

  Future<void> checkIntegrity(String label) async {
    final r = await db.rawQuery('PRAGMA integrity_check');
    final ok = r.length == 1 && r.first.values.first == 'ok';
    print('integrity_check ($label): ${ok ? 'ok' : r.first.values.first}');
    if (!ok) exit(1);
  }

  Future<int> count(String table) async {
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM "$table"');
    return r.first['c'] as int;
  }

  try {
    await checkIntegrity('before');
    final countsBefore = <String, int>{
      for (final t in const [
        'catches', 'fishing_trips', 'catch_media', 'trip_media',
        'trip_journal', 'journal_media', 'favourite_spots',
      ])
        t: await count(t),
    };

    // --- rewrite paths ---
    var updated = 0;
    var alreadyOk = 0;
    final unresolved = <String>[];
    final remapLog = <String>[];

    Future<void> fix(String table, String column) async {
      List<Map<String, Object?>> rows;
      try {
        rows = await db.query(table);
      } catch (_) {
        return; // table absent in this schema
      }
      for (final row in rows) {
        final oldPath = row[column] as String?;
        if (oldPath == null || oldPath.isEmpty) continue;
        final portable = oldPath.replaceAll('\\', '/');
        final base = portable.split('/').last;
        final subdir = basenameToSubdir[base];
        if (subdir == null) {
          unresolved.add('$table#${row['id']}: $oldPath');
          continue;
        }
        final newPath = '$subdir/$base';
        if (portable == newPath) {
          alreadyOk++;
          continue;
        }
        await db.update(table, {column: newPath},
            where: 'id = ?', whereArgs: [row['id']]);
        updated++;
        remapLog.add('$table#${row['id']}: $oldPath  ->  $newPath');
      }
    }

    for (final (table, column) in _mediaSources) {
      await fix(table, column);
    }

    // --- post-checks ---
    await checkIntegrity('after');
    for (final e in countsBefore.entries) {
      final after = await count(e.key);
      if (after != e.value) {
        print('ROW COUNT CHANGED ${e.key}: ${e.value} -> $after  (unexpected!)');
      }
    }

    print('--- rewrite report ---');
    print('rows updated: $updated');
    print('rows already correct: $alreadyOk');
    if (ambiguous.isNotEmpty) {
      print('AMBIGUOUS basenames (present in >1 archive subdir):');
      for (final b in ambiguous) {
        print('  $b');
      }
    }
    if (unresolved.isNotEmpty) {
      print('UNRESOLVED refs (basename not in archive) — left unchanged:');
      for (final u in unresolved) {
        print('  $u');
      }
    }
    print('--- remaps ---');
    for (final l in remapLog) {
      print(l);
    }
  } finally {
    await db.close();
  }

  // --- write corrected zip (all entries preserved, db replaced) ---
  final out = Archive();
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final data = f.name == 'database.sqlite'
        ? await dbFile.readAsBytes()
        : f.content as List<int>;
    out.addFile(ArchiveFile(f.name, data.length, data));
  }
  final outFile = File(outPath);
  await outFile.parent.create(recursive: true);
  final encoder = ZipEncoder();
  await outFile.writeAsBytes(encoder.encode(out)!);
  print('wrote $outPath (${await outFile.length()} bytes)');
}
