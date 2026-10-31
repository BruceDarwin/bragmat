import 'dart:io';

import 'package:path/path.dart' as path;

import '../database/database_helper.dart';
import 'media_storage_service.dart';

/// Read-only integrity report for schema v30 (Phase B diagnostics).
///
/// Every entry is an identifier only — table names, row IDs, stale
/// numeric references and media-relative paths. Reports never contain
/// coordinates, photo contents, or absolute filesystem paths.
class IntegrityDiagnosticsReport {
  /// `PRAGMA foreign_key_check` violations: `table#rowid -> parent`.
  final List<String> foreignKeyViolations;

  /// Dangling soft references in `catches`, keyed by column name
  /// (`lure_id`, `bait_id`, `fishing_buddy_id`, `trip_id`).
  final Map<String, List<String>> softReferenceProblems;

  /// Media rows whose `file_path` resolves to a missing file:
  /// `table#id -> <stored path>`.
  final List<String> missingMediaFiles;

  /// Files inside the managed media directory no row references.
  final List<String> unreferencedMediaFiles;

  /// Files sitting in the quarantine area (previously swept media),
  /// reported separately — they are expected residue, not orphans.
  final List<String> quarantinedFiles;

  const IntegrityDiagnosticsReport({
    required this.foreignKeyViolations,
    required this.softReferenceProblems,
    required this.missingMediaFiles,
    required this.unreferencedMediaFiles,
    required this.quarantinedFiles,
  });

  int get softReferenceCount =>
      softReferenceProblems.values.fold(0, (n, l) => n + l.length);

  /// Number of genuine integrity findings (quarantine is informational).
  int get findingCount =>
      foreignKeyViolations.length +
      softReferenceCount +
      missingMediaFiles.length +
      unreferencedMediaFiles.length;

  /// Human-readable report for the debug Settings dialog and logs.
  String summary() {
    final b = StringBuffer()
      ..writeln('Schema v30 integrity diagnostics (read-only)')
      ..writeln(
          'Declared-FK violations: ${foreignKeyViolations.length}');
    for (final v in foreignKeyViolations) {
      b.writeln('  $v');
    }
    b.writeln('Soft-reference problems: $softReferenceCount');
    softReferenceProblems.forEach((column, items) {
      b.writeln('  catches.$column: ${items.length}');
      for (final i in items) {
        b.writeln('    $i');
      }
    });
    b.writeln('Media rows with missing files: ${missingMediaFiles.length}');
    for (final m in missingMediaFiles) {
      b.writeln('  $m');
    }
    b.writeln(
        'Unreferenced media files on disk: ${unreferencedMediaFiles.length}');
    for (final f in unreferencedMediaFiles) {
      b.writeln('  $f');
    }
    b.writeln('Quarantine inventory: ${quarantinedFiles.length} file(s)');
    for (final q in quarantinedFiles) {
      b.writeln('  $q');
    }
    return b.toString().trimRight();
  }
}

/// Read-only integrity diagnostics. Developer-gated behind
/// [DebugTools.isEnabled] in Settings — never reachable in release.
///
/// Nothing here writes to the database or the filesystem: the checks
/// are `PRAGMA foreign_key_check`, SELECT-only soft-reference queries,
/// file existence checks and directory listings of Bragmat-managed
/// storage (media/ and its sibling quarantine/ — nothing else).
class IntegrityDiagnostics {
  /// (table, path column) pairs that store a media file reference.
  static const _mediaSources = [
    ('catch_media', 'file_path'),
    ('trip_media', 'file_path'),
    ('journal_media', 'file_path'),
    ('catches', 'image_path'),
    ('catches', 'lure_photo_path'),
  ];

  /// (catches column, parent table) pairs for soft references the
  /// schema does not declare as foreign keys.
  static const _softRefs = [
    ('lure_id', 'lures'),
    ('bait_id', 'baits'),
    ('fishing_buddy_id', 'fishing_buddies'),
    ('trip_id', 'fishing_trips'),
  ];

  /// Run every check against the live (ownership-guarded) database.
  static Future<IntegrityDiagnosticsReport> run() async {
    final db = await DatabaseHelper.instance.database;
    final mediaDir = await MediaStorageService.getMediaDirectory();

    // 1. Declared foreign keys — SQLite reports violations even though
    //    enforcement is off.
    final fkRows = await db.rawQuery('PRAGMA foreign_key_check');
    final foreignKeyViolations = fkRows
        .map((r) => '${r['table']}#${r['rowid']} -> ${r['parent']}')
        .toList();

    // 2. Soft references (no declared FK — pragma can't see these).
    final softReferenceProblems = <String, List<String>>{};
    for (final (column, parentTable) in _softRefs) {
      final rows = await db.rawQuery('''
        SELECT c.id AS rid, c.$column AS ref
        FROM catches c
        LEFT JOIN $parentTable p ON p.id = c.$column
        WHERE c.$column IS NOT NULL AND p.id IS NULL
      ''');
      softReferenceProblems[column] = rows
          .map((r) => 'catches#${r['rid']} $column=${r['ref']} (missing)')
          .toList();
    }

    // 3. Media rows pointing at files that are not on disk.
    final missingMediaFiles = <String>[];
    for (final (table, column) in _mediaSources) {
      List<Map<String, Object?>> rows;
      try {
        rows = await db.query(
          table,
          columns: ['id', column],
          where: "$column IS NOT NULL AND $column != ''",
        );
      } catch (_) {
        continue; // Table/column absent in older schemas.
      }
      for (final row in rows) {
        final stored = row[column] as String;
        if (!await MediaStorageService.fileExists(stored)) {
          missingMediaFiles.add('$table#${row['id']} -> ${_safe(stored)}');
        }
      }
    }

    // 4. Files inside media/ that no row references.
    final referenced = <String>{};
    for (final (table, column) in _mediaSources) {
      List<Map<String, Object?>> rows;
      try {
        rows = await db.query(
          table,
          columns: [column],
          where: "$column IS NOT NULL AND $column != ''",
        );
      } catch (_) {
        continue;
      }
      for (final row in rows) {
        final stored = row[column] as String;
        if (path.isAbsolute(stored)) continue; // outside media/ — skip
        referenced.addAll(MediaStorageService.mediaPathVariants(stored));
      }
    }
    final unreferencedMediaFiles = <String>[];
    if (await mediaDir.exists()) {
      await for (final entity in mediaDir.list(recursive: true)) {
        if (entity is! File) continue;
        final rel = path
            .relative(entity.path, from: mediaDir.path)
            .replaceAll('\\', '/');
        if (!referenced.contains(rel)) {
          unreferencedMediaFiles.add(rel);
        }
      }
      unreferencedMediaFiles.sort();
    }

    // 5. Quarantine inventory — informational; these files were
    //    deliberately swept, not orphaned.
    final quarantinedFiles = <String>[];
    final quarantineDir =
        Directory(path.join(mediaDir.parent.path, 'quarantine'));
    if (await quarantineDir.exists()) {
      await for (final entity in quarantineDir.list(recursive: true)) {
        if (entity is! File) continue;
        quarantinedFiles.add(path
            .relative(entity.path, from: quarantineDir.path)
            .replaceAll('\\', '/'));
      }
      quarantinedFiles.sort();
    }

    return IntegrityDiagnosticsReport(
      foreignKeyViolations: foreignKeyViolations,
      softReferenceProblems: softReferenceProblems,
      missingMediaFiles: missingMediaFiles,
      unreferencedMediaFiles: unreferencedMediaFiles,
      quarantinedFiles: quarantinedFiles,
    );
  }

  /// Stored paths are reported verbatim when relative; absolute paths
  /// (out-of-media, e.g. a gallery original) collapse to the basename
  /// so the report never leaks filesystem layout.
  static String _safe(String stored) =>
      path.isAbsolute(stored) ? path.basename(stored) : stored;
}
