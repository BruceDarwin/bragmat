# Schema v30 — Legacy v28 Drift Repair (Design Proposal)

**Status:** proposal only — not implemented. Requires separate approval
before any code change.

## Background

Investigation (October 2026) of the reported v29 fresh-install drift found
two distinct states:

1. **Current `_createDB` at schema v29 is correct.** All v28 tide-reference
   and WorldTides columns are present, and a fresh-v29 database is
   empirically column-equivalent to a database migrated through the full
   v1→v29 chain. Forward drift is fixed.
2. **Databases born at v28 by the drifted `_createDB` are never repaired.**
   At the v28 tag, the tide-reference/WorldTides columns and the
   `tide_cache` table existed only inside `_onUpgrade`, guarded by
   `if (oldVersion < 28)`. A database already stamped `user_version = 28`
   skips every relevant block when opened by v29 (`24–28` guards never
   fire), and no catch-up block exists.

### What an affected v28-born database is missing after upgrade to v29

- Entire `tide_cache` table, `idx_tide_cache_location_date`, and its
  UNIQUE autoindex on `(location_key, date)`.
- `environmental_conditions`: `tide_reference_mode`,
  `tide_reference_name`, `tide_request_lat`, `tide_request_lon`,
  `worldtides_station`, `worldtides_atlas`, `worldtides_response_lat`,
  `worldtides_response_lon` (8 columns).
- `catches`: `lure_id`, `bait_id`, `lure_size`, `lure_colour`,
  `lure_photo_path` (5 columns).

The post-open "safety checks" only cover `catches.trip_id`,
`fishing_buddy_id`, `location`, `latitude`, `longitude` — none of the
above.

## Proposed correction — explicit versioned migration v30

Bump `DatabaseHelper` to `version: 30` and add:

```dart
if (oldVersion < 30) {
  await _repairV28Drift(db);
}
```

`_repairV28Drift` is strictly additive and idempotent:

1. `tide_cache`: `CREATE TABLE IF NOT EXISTS tide_cache (...)` using the
   exact v29 `_createDB` definition, then `CREATE UNIQUE INDEX IF NOT
   EXISTS` / `CREATE INDEX IF NOT EXISTS` for its indexes.
2. Per-column repair for `environmental_conditions` and `catches`:
   read `PRAGMA table_info(<table>)`, and `ALTER TABLE ... ADD COLUMN`
   only for columns absent. Column definitions copied verbatim from
   `_createDB` so type/nullability/defaults match a fresh install.
3. All statements run inside sqflite's existing upgrade transaction —
   failure rolls back and leaves `user_version` at 28, so the next open
   retries cleanly.

This also covers **restored** drifted backups, because the restore
pipeline already stages and upgrades the embedded database through
`_onUpgrade`.

### Explicitly not included

- No changes to rows/data — pure additive DDL.
- No post-open repair (Option B was rejected): an every-open check runs
  outside the migration transaction, needs its own open-lock, and
  bypasses the established versioning contract.
- No `user_version` manipulation other than the standard 29→30 bump.

## Required tests

Extend the schema-parity approach with a **v28-born leg**:

1. Build a genuine fresh-v28 database by replaying the drifted v28
   `_createDB` verbatim (extracted from the v28 tag, committed under
   `test/` as a fixture or literal SQL).
2. Run the real `_onUpgrade` chain 28→30.
3. Assert full parity against a fresh v30 `_createDB`:
   - identical column sets incl. nullability/defaults/PK on all tables;
   - `tide_cache` + both indexes present;
   - all 8 `environmental_conditions` and 5 `catches` columns present.
4. Idempotency: run the repair twice / apply it to an already-correct
   database and assert no duplicate-column errors and unchanged schema.
5. Data preservation: seed rows in a v28-born DB before upgrade and
   assert they survive intact after repair.
6. Update `schema_parity_v29_test.dart` coverage to compare **all**
   tables/indexes on the 27→30 and 28→30 legs (it currently only checks
   two tables on 27→29 and cannot see this defect).

## Risk assessment

- **Low** — additive DDL inside the upgrade transaction, guarded per
  column/table, mirrors the existing `try/catch` migration style.
- Main hazard is false-positive repair on a healthy v29 database; the
  `PRAGMA table_info` guards make each step a no-op in that case.
- `CREATE TABLE IF NOT EXISTS tide_cache` on a database that already has
  a *partial* tide_cache (theoretical) would leave the existing table
  untouched; the column-level guards then bring it to parity.
- Requires one-time version bump; beta devices on v29 upgrade on next
  open. Rollback is simply not opening the DB with v30 (old builds
  refuse/ignore higher `user_version` per sqflite behaviour — verify
  downgrade UX before shipping).
