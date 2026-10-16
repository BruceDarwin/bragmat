# Stage 4B — Foreign-Key & Orphan Audit (v28 real data)

Audit tool: `tool/audit_fk.dart` (run via `dart run tool/audit_fk.dart <db>`
from the project root; `--upgrade-copy` audits a migrated v29 copy).

Status: **findings recorded for a later data-quality review.** No rows were
deleted or repaired. `PRAGMA foreign_keys` remains OFF in Stage 4B —
enabling it requires a separate review and approval.

## Why orphans exist

`PRAGMA foreign_keys` has never been enabled, so all `ON DELETE CASCADE`
clauses declared in the schema are inert. Deletes that should have cascaded
left child rows behind. `PRAGMA integrity_check` still returns `ok` —
these are logical orphans, not corruption.

## Findings on the real v28 database (76 catches)

| Relation | Orphan rows | Detail |
|---|---|---|
| `environmental_conditions.catch_id` → `catches.id` (declared CASCADE) | 11 | references deleted catches {32, 33, 35, 40, 44, 48, 56, 57, 58, 59, 60} |
| `catch_media.catch_id` → `catches.id` (declared CASCADE) | 5 | references deleted catches {10, 13, 16, 57, 60} |
| `catches.lure_id` → `lures.id` (undeclared FK) | 1 | references missing lure id = 1 |

Total: **17 historical orphan references.**

## Post-migration verification

A copy of the real v28 database was upgraded to v29 (`--upgrade-copy`):

- All row counts identical (76 catches, 79 catch_media, 5 trips, etc.).
- Same 17 orphans carried forward — **the migration introduced none.**
- `PRAGMA integrity_check` = `ok` on the v29 copy.

## Impact assessment

- Environmental-condition orphans are invisible to the catch-detail UI
  (joined by catch_id) but still counted in the table — harmless, recoverable.
- `catch_media` orphans reference file paths that may still exist on disk —
  do NOT bulk-delete without checking the files first.
- `catches.lure_id → 1` is a dangling reference rendered as "no lure".

## Deferred decisions (needs separate review)

1. Whether to repair/delete the 17 rows or keep them as historical data.
2. Whether to enable `PRAGMA foreign_keys` — would activate the declared
   cascades for *new* writes only; existing orphans remain either way.
3. `catches.lure_id`/`bait_id`/`fishing_buddy_id`/`trip_id` are undeclared
   FKs — worth declaring in a future schema version if enforcement is
   ever turned on.
