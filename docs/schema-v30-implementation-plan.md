# Schema v30 — Implementation Plan and Test Matrix

**Status:** implementation plan only — requires separate approval before
any code change. Companion to `schema-v30-repair-proposal.md`.

## 1. Scope

Repair databases created fresh at v28 by the drifted `_createDB` (which
lacked the v28 additions). Such databases are stamped `user_version = 28`,
so the `oldVersion < 24..28` migration blocks never fire and the defects
persist forever. Databases that already have the objects are untouched —
every repair step is idempotent.

Also covered at no extra cost: any other database missing these objects
(e.g. a restored backup file that originated on a v28 build), because the
restore pipeline already upgrades staged files through `_onUpgrade`.

## 2. Defect inventory to repair

| Object | Missing in drifted v28 | Repair |
|---|---|---|
| `tide_cache` table | yes | `CREATE TABLE IF NOT EXISTS` (v29 definition verbatim) |
| `tide_cache` UNIQUE autoindex `(latitude, longitude, date, datum)` | yes | created with table |
| `idx_tide_cache_location_date` index | yes | `CREATE INDEX IF NOT EXISTS` |
| `environmental_conditions.tide_reference_mode TEXT` | yes | guarded `ALTER TABLE` |
| `…tide_reference_name TEXT` | yes | guarded `ALTER TABLE` |
| `…tide_request_lat REAL` | yes | guarded `ALTER TABLE` |
| `…tide_request_lon REAL` | yes | guarded `ALTER TABLE` |
| `…worldtides_station TEXT` | yes | guarded `ALTER TABLE` |
| `…worldtides_atlas TEXT` | yes | guarded `ALTER TABLE` |
| `…worldtides_response_lat REAL` | yes | guarded `ALTER TABLE` |
| `…worldtides_response_lon REAL` | yes | guarded `ALTER TABLE` |
| `catches.lure_id INTEGER` | yes | guarded `ALTER TABLE` |
| `catches.bait_id INTEGER` | yes | guarded `ALTER TABLE` |
| `catches.lure_size TEXT` | yes | guarded `ALTER TABLE` |
| `catches.lure_colour TEXT` | yes | guarded `ALTER TABLE` |
| `catches.lure_photo_path TEXT` | yes | guarded `ALTER TABLE` |

### Not repaired (verify before approving)

- `environmental_conditions.id` on drifted v28 may be a plain
  `INTEGER PRIMARY KEY` vs `AUTOINCREMENT` in v29 — confirm the exact
  drifted definition from the v28 tag before writing the matrix; if it
  differs, decide whether to leave it (harmless) rather than rebuild
  the table.
- Any index drift beyond `idx_tide_cache_location_date` — the empirical
  diff found none, but the plan re-verifies via `sqlite_master` diff.

## 3. Implementation shape

```dart
// database_helper.dart
version: 30,
...
if (oldVersion < 30) {
  await _repairV28Drift(db);
}

static Future<void> _repairV28Drift(Database db) async {
  // Table-level
  await db.execute('CREATE TABLE IF NOT EXISTS tide_cache (...verbatim...)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tide_cache_location_date ...');

  // Column-level, guarded by PRAGMA table_info
  await _addColumnIfMissing(db, 'environmental_conditions',
      'tide_reference_mode', 'TEXT');
  // … the remaining 7 env columns and 5 catch columns, same helper.
}

static Future<void> _addColumnIfMissing(
    Database db, String table, String column, String typeDef) async {
  final cols = await db.rawQuery('PRAGMA table_info($table)');
  if (!cols.any((c) => c['name'] == column)) {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $typeDef');
  }
}
```

Placement notes:

- Runs **inside** sqflite's upgrade transaction — a failure rolls the
  whole upgrade back, leaving `user_version` at 28 for a clean retry.
- Column definitions are copied verbatim from `_createDB` so type,
  nullability and defaults match a fresh install exactly.
- No row-level data is touched; existing values, indexes and triggers
  are preserved.
- Keep the existing "safety checks" untouched — this migration does not
  replace them.

## 4. Ordering interaction

`_repairV28Drift` runs for every `oldVersion < 30`, including healthy
v29 databases — all steps are guarded no-ops there. For a v28→30 upgrade
the `<29` block still runs `MigrationV29.migrate` (ownership/uuid/sync
tables); the drift repair targets different objects and is safe in
either order relative to it.

## 5. Test matrix

| # | Scenario | Setup | Assertion |
|---|---|---|---|
| T1 | **v28-born parity** | Replay the drifted v28 `_createDB` verbatim (fixture extracted from the v28 tag, committed under `test/fixtures/`), then run real `_onUpgrade` 28→30 | Full-schema parity vs fresh v30 `_createDB`: all tables, all columns (name/type/notnull/dflt), `tide_cache` + both indexes |
| T2 | **v27→30 chain** | Faithful v27 DB → `_onUpgrade` 27→30 | Same full-schema parity; existing parity test extended from 2 tables to all tables |
| T3 | **v1→30 chain** | Faithful v1 DB → full chain | Full-schema parity vs fresh v30 |
| T4 | **Idempotency** | Run `_repairV28Drift` twice on a drifted v28 DB; also apply to a healthy v29 DB | No duplicate-column/table errors; `sqlite_master` unchanged on second run |
| T5 | **Data preservation** | Seed rows into catches, environmental_conditions on the drifted v28 DB before upgrade | Row counts and values identical after 28→30; no dropped/rebuilt tables |
| T6 | **Writable after repair** | After 28→30, insert a catch with `lure_id` set and an env row with tide columns | Inserts succeed; values round-trip |
| T7 | **Rollback on failure** | Inject a failure mid-repair (e.g. force `ALTER` on a corrupt DB handle) | `user_version` remains 28; next open retries and succeeds |
| T8 | **Fresh v30 install** | Clean `_createDB` at v30 | Identical `PRAGMA` dump to T1/T3 repaired DBs (column order excepted) |
| T9 | **Restored drifted backup** | Stage a v28-born DB file, run restore upgrade path | Staged DB reaches v30 parity before promotion |
| T10 | **Parity test widened** | Extend `schema_parity_v29_test.dart` → all tables + `sqlite_master` index diff on 27→30 and 28→30 | Passes; currently-missing drift would fail |

## 6. Validation procedure

1. `flutter test` — all new tests green plus existing 551.
2. Empirical diff (same technique used for the investigation): dump
   `sqlite_master` + `PRAGMA table_info` for fresh v30 vs v28→30 and
   v1→30 — only cosmetic diffs allowed.
3. Emulator dry-run on a synthetic drifted v28 DB before any device
   build is produced.

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Repairing a healthy DB | per-object guards make every step a no-op (T4) |
| Mid-upgrade failure corrupts DB | everything inside the upgrade transaction; version stays 28; retry on next open (T7) |
| A partially-present `tide_cache` (theoretical) | `CREATE TABLE IF NOT EXISTS` leaves it; column guards then top it up — add an assertion in T1 that a partial table reaches column parity |
| Downgrade UX | old builds see `user_version 30` on a DB they expect ≤29 — verify sqflite behaviour (it ignores `onDowngrade` by default); document before shipping |
| Column-order divergence on repaired tables | harmless — SQLite binds by name; parity assertions compare sets, not order |

## 8. Approval needed

- Bump `version` 29→30 in `database_helper.dart`.
- New `_repairV28Drift` + `_addColumnIfMissing` helpers.
- New test file + extended parity test + committed v28 `_createDB`
  fixture.
- Emulator run of the upgrade path on a synthetic v28-born DB.
