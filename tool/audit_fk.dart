// FK/orphan audit — Stage 4B requirement.
//
//   dart run tool/audit_fk.dart <db-path>
//
// Reports for the given SQLite file:
//   - PRAGMA foreign_key_check on all declared FKs
//   - orphan scan over declared AND undeclared relationships
//     (MigrationV29.orphanAudit)
//   - per-table counts for the 12 user-owned tables
//
// FK enforcement stays OFF in Stage 4B — this reports; it does not
// change enforcement. To audit a v28 backup: extract database.sqlite
// from the ZIP and point this at it. To audit the post-upgrade state:
// open a copy with version 29 + DatabaseHelper.upgradeDatabase first.

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bragmat/database/migration_v29.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
        'usage: dart run tool/audit_fk.dart <db-path> [--upgrade-copy]');
    exit(2);
  }
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  var dbPath = args[0];
  if (args.contains('--upgrade-copy')) {
    // Audit the post-v29 state: copy the file, run the upgrade on the
    // copy, then audit that.
    final copy =
        p.join(p.dirname(dbPath), '${p.basename(dbPath)}.v29copy');
    await File(dbPath).copy(copy);
    final up = await openDatabase(copy,
        version: 29, onUpgrade: (db, o, n) => MigrationV29.migrate(db));
    await up.close();
    dbPath = copy;
    print('upgraded copy: $dbPath');
  }

  final db = await openDatabase(dbPath, readOnly: true);
  try {
    final ver = await db.rawQuery('PRAGMA user_version');
    print('user_version: ${ver.first.values.first}');

    print('\n-- per-table counts (user-owned) --');
    final counts = await MigrationV29.userTableCounts(db);
    counts.forEach((t, c) => print('  $t: $c'));

    print('\n-- declared FK check (PRAGMA foreign_key_check) --');
    try {
      final fkViolations = await db.rawQuery('PRAGMA foreign_key_check');
      if (fkViolations.isEmpty) {
        print('  clean — no declared-FK violations');
      } else {
        for (final v in fkViolations) {
          print('  VIOLATION: $v');
        }
      }
    } catch (e) {
      print('  foreign_key_check failed: $e');
    }

    print('\n-- orphan audit (declared + undeclared relations) --');
    final findings = await MigrationV29.orphanAudit(db);
    if (findings.isEmpty) {
      print('  clean — no orphans');
    } else {
      for (final f in findings) {
        print('  ORPHAN: $f');
      }
    }

    print('\n-- orphan detail (dangling values) --');
    for (final (label, sql) in [
      (
        'env.catch_id',
        'SELECT DISTINCT catch_id AS v FROM environmental_conditions '
            'WHERE catch_id IS NOT NULL AND catch_id NOT IN '
            '(SELECT id FROM catches)'
      ),
      (
        'env.trip_id',
        'SELECT DISTINCT trip_id AS v FROM environmental_conditions '
            'WHERE trip_id IS NOT NULL AND trip_id NOT IN '
            '(SELECT id FROM fishing_trips)'
      ),
      (
        'catch_media.catch_id',
        'SELECT DISTINCT catch_id AS v FROM catch_media '
            'WHERE catch_id IS NOT NULL AND catch_id NOT IN '
            '(SELECT id FROM catches)'
      ),
      (
        'catches.trip_id',
        'SELECT DISTINCT trip_id AS v FROM catches '
            'WHERE trip_id IS NOT NULL AND trip_id NOT IN '
            '(SELECT id FROM fishing_trips)'
      ),
      (
        'catches.buddy_id',
        'SELECT DISTINCT fishing_buddy_id AS v FROM catches '
            'WHERE fishing_buddy_id IS NOT NULL AND fishing_buddy_id NOT IN '
            '(SELECT id FROM fishing_buddies)'
      ),
      (
        'catches.lure_id',
        'SELECT DISTINCT lure_id AS v FROM catches '
            'WHERE lure_id IS NOT NULL AND lure_id NOT IN '
            '(SELECT id FROM lures)'
      ),
      (
        'catches.bait_id',
        'SELECT DISTINCT bait_id AS v FROM catches '
            'WHERE bait_id IS NOT NULL AND bait_id NOT IN '
            '(SELECT id FROM baits)'
      ),
    ]) {
      try {
        final rows = await db.rawQuery(sql);
        if (rows.isNotEmpty) {
          print('  $label -> ${rows.map((r) => r['v']).toList()}');
        }
      } catch (_) {}
    }

    print('\n-- integrity_check --');
    final ic = await db.rawQuery('PRAGMA integrity_check');
    print('  ${ic.first.values.first}');
  } finally {
    await db.close();
  }
}
