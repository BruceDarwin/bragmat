# Catch Deletion — Orphan Records: Diagnosis and Correction Plan

**Status:** proposal only — no fix implemented. The failing regression
tests on `feature/catch-delete-orphans` (commit `40fa26c`,
`test/catch_delete_orphan_test.dart`) are the defect evidence.

## 1. Root cause

Two independent gaps:

1. **`PRAGMA foreign_keys` is never enabled.** `openDatabase()` is called
   without `onConfigure`, and SQLite defaults `foreign_keys` OFF per
   connection. The schema *declares*
   `FOREIGN KEY (catch_id) REFERENCES catches(id) ON DELETE CASCADE` on
   `catch_media` and `environmental_conditions`, but the clauses are
   inert. `deleteCatch` (database_helper.dart:1288) is a bare
   `DELETE FROM catches WHERE id = ?`.
2. **No code deletes media files.** `deleteCatch`,
   `deleteCatchMedia` and `deleteAllMediaForCatch` delete rows only;
   `MediaStorageService.deletePhoto` exists but is never called from a
   deletion path.

### Affected objects

- `catch_media` rows for the deleted catch.
- `environmental_conditions` rows for the deleted catch.
- Physical files under `<app-support>/bragmat/media/catches/` referenced
  by `catch_media.file_path`, plus legacy `catches.image_path` and
  `catches.lure_photo_path` files.

Device evidence (Moto G15, post-validation): 7 orphan `catch_media` rows,
12 orphan `environmental_conditions` rows — accumulated over the app's
lifetime; the disposable test catch contributed 2 + 1.

## 2. FK relationship review (complete graph)

| Child table | Parent | ON DELETE | Activated if `PRAGMA foreign_keys=ON` |
|---|---|---|---|
| `catch_media.catch_id` | catches | CASCADE | catch delete also removes media rows |
| `environmental_conditions.catch_id` | catches | CASCADE | catch delete also removes env rows |
| `trip_media.trip_id` | fishing_trips | CASCADE | trip delete removes trip media rows |
| `trip_journal.trip_id` | fishing_trips | CASCADE | trip delete removes journal rows |
| `journal_media.journal_entry_id` | trip_journal | CASCADE | journal delete removes its media rows |
| `environmental_conditions.trip_id` | fishing_trips | CASCADE | trip delete removes trip env rows |
| `user_achievements.achievement_id` | achievements | CASCADE | achievement def delete removes unlocks |
| `catches.trip_id` | fishing_trips | **none** | catches survive trip deletion — important: trips do NOT wipe catches |

Enabling the pragma globally therefore changes semantics for **trip and
journal deletes too**, not just catches. Those cascades look correct, but
they are new runtime behaviour and need explicit sign-off.

## 3. Proposed correction (future deletions)

**Phase 1 — explicit transactional cleanup (recommended first step,
narrowest blast radius):**

```dart
Future<int> deleteCatch(int id) async {
  final db = await instance.database;
  final filePaths = <String>{};
  final result = await db.transaction((txn) async {
    final media = await txn.query('catch_media',
        columns: ['file_path'], where: 'catch_id = ?', whereArgs: [id]);
    filePaths.addAll(media.map((m) => m['file_path'] as String));
    final legacy = await txn.query('catches',
        columns: ['image_path', 'lure_photo_path'],
        where: 'id = ?', whereArgs: [id]);
    for (final c in legacy) {
      for (final k in const ['image_path', 'lure_photo_path']) {
        final v = c[k] as String?;
        if (v != null && v.isNotEmpty) filePaths.add(v);
      }
    }
    await txn.delete('environmental_conditions',
        where: 'catch_id = ?', whereArgs: [id]);
    await txn.delete('catch_media',
        where: 'catch_id = ?', whereArgs: [id]);
    return txn.delete('catches', where: 'id = ?', whereArgs: [id]);
  });
  // Files deleted only when no remaining row references them.
  for (final rel in filePaths) {
    final stillUsed = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM catch_media WHERE file_path = ?',
        [rel]);
    if ((stillUsed.first['n'] as int) == 0) {
      await MediaStorageService.deletePhoto(rel);
    }
  }
  return result;
}
```

Notes:
- Row deletes happen in one transaction — either all gone or none.
- File deletion is outside the transaction and guarded by a
  shared-path re-check (`COUNT(*) … WHERE file_path = ?`) so a file
  referenced by another catch's row is never unlinked.
- No pragma change → zero behaviour change for trips/journals.

**Phase 2 — optional defense-in-depth (needs review sign-off):**
`onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')`. Only after
confirming the trip/journal/achievement cascade semantics in §2 are
desired. Note: pragma ON does NOT fix already-orphaned rows and does NOT
delete files — Phase 1 is still required either way.

## 4. Historical-orphan cleanup procedure (separate, device-safe)

Designed for verification and rollback; run only with an approved,
verified off-device ZIP backup in hand.

1. **Audit** (read-only, e.g. `tool/inspect_db.dart` extension or a
   debug diagnostics run):
   ```sql
   SELECT COUNT(*) FROM catch_media cm
     WHERE NOT EXISTS (SELECT 1 FROM catches c WHERE c.id = cm.catch_id);
   SELECT COUNT(*) FROM environmental_conditions e
     WHERE NOT EXISTS (SELECT 1 FROM catches c WHERE c.id = e.catch_id);
   PRAGMA foreign_key_check;  -- once pragma-enabled builds exist
   ```
   Record counts and the orphan `file_path` list.
2. **Backup:** fresh in-app ZIP → pulled off-device → CRC + counts
   verified (the established preflight procedure).
3. **Row cleanup:** `DELETE FROM catch_media WHERE NOT EXISTS (…)` and
   the same for `environmental_conditions`, in one transaction.
   Idempotent; re-run is a no-op.
4. **File quarantine (not delete):** move `file_path`s no longer
   referenced by any row into `bragmat/media/_quarantine/`, and scan the
   media dir for unreferenced files → same quarantine.
5. **Verify:** app launch, catch list/detail render, photo thumbnails,
   `quick_check`, expected counts.
6. **Commit or rollback:** after a soak period delete `_quarantine/`.
   Rollback path = in-app ZIP restore (which re-creates the DB and media
   wholesale) or moving quarantined files back.
7. Nothing is deleted outright until step 6; the ZIP backup is the
   outermost safety net.

## 5. Regression tests

On `feature/catch-delete-orphans` (`test/catch_delete_orphan_test.dart`)
— all currently FAIL, proving the defect; they gate the Phase-1 fix:

1. `deleteCatch removes its catch_media rows` (multi-photo).
2. `deleteCatch removes its environmental_conditions row`.
3. `deleteCatch deletes its physical media files`.
4. `deleteCatch preserves a file still referenced by another catch`
   (shared-path guard).
5. `deleteCatch leaves other catches untouched`.

Suggested additions when implementing: legacy `image_path` /
`lure_photo_path` cleanup, trip-delete behaviour matrix (Phase 2), and a
cleanup-procedure test driving the quarantine flow on a temp media dir.

## 6. Approval needed

- Phase-1 `deleteCatch` rewrite (transactional row deletes + guarded file
  unlink).
- Phase-2 `PRAGMA foreign_keys = ON` — only after the §2 cascade
  semantics are approved.
- Historical-cleanup run on the Moto G15 — requires an approved fresh
  backup first; the audit step alone is read-only and safe to run now.
