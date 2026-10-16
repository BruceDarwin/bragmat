# Stage 4B — Schema v29: User Data Ownership & Account Isolation

Design specification for approval. No database changes are implemented
until this document is signed off.

## 1. Current schema (v28) — table inventory & classification

| Table | Role | Classification | v29 treatment |
|---|---|---|---|
| `catches` | core catch records | user-owned | uuid, owner_id, updated_at, triggers |
| `catch_media` | photos → `catches.id` (FK CASCADE*) | user-owned | uuid, owner_id, updated_at, triggers |
| `fishing_trips` | trips | user-owned | uuid, owner_id, updated_at, triggers |
| `trip_media` | photos → `fishing_trips.id` | user-owned | uuid, owner_id, updated_at, triggers |
| `trip_journal` | entries → `fishing_trips.id` | user-owned | uuid, owner_id, triggers (has updated_at) |
| `journal_media` | photos → `trip_journal.id` | user-owned | uuid, owner_id, updated_at, triggers |
| `favourite_spots` | saved spots | user-owned | uuid, owner_id, updated_at, triggers |
| `environmental_conditions` | weather/tide obs → `catches`/`fishing_trips` (nullable FKs) | user-owned | uuid, owner_id, triggers (has updated_at) |
| `user_achievements` | unlocks → `achievements.id` | user-owned | uuid, owner_id, updated_at, triggers |
| `lures` | tackle box (id, name) | user-owned | uuid, owner_id, updated_at, triggers |
| `baits` | tackle box (id, name) | user-owned | uuid, owner_id, updated_at, triggers |
| `fishing_buddies` | buddy names (id, name) | user-owned | uuid, owner_id, updated_at, triggers |
| `fish_types` | seeded lookup; not user-editable (`catches.fish_type` is free text) | shared reference | **unchanged** |
| `achievements` | app-defined catalog (TEXT PK) | shared reference | **unchanged** |
| `tide_cache` | WorldTides response cache | system cache | **unchanged** |

\* **FK audit finding:** all foreign keys are declared but SQLite
enforcement is OFF — no `PRAGMA foreign_keys = ON` / `onConfigure` exists.
CASCADE deletes are currently inert; the app deletes children manually.
Also, several logical relationships are *not* declared as FKs:
`catches.trip_id`, `catches.fishing_buddy_id`, `catches.lure_id`,
`catches.bait_id`, `catches.image_path`/`lure_photo_path` (media refs).

### Settings & session storage
- App settings: `SharedPreferences` (`preferences_service.dart`) — outside
  SQLite. Single-owner-per-installation assumption makes scoping them
  unnecessary in 4B. Documented, unchanged.
- Auth session: flutter_secure_storage via supabase_flutter. `AuthService
  .userId` exposes the Supabase auth UUID — this is the `owner_id` value.

### Pre-existing defect found during audit (fix included in v29)
- `tide_cache` is created only in `onUpgrade` (v27) — missing from
  `_createDB`, so **fresh v28 installs lack the table** (same class of
  bug as the lure columns fixed earlier). v29 `_createDB` will emit it.

## 2. Schema v29 changes

### 2a. New columns on the 12 user-owned tables

```text
uuid        TEXT              -- stable cross-device id (RFC-4122 v4)
owner_id    TEXT              -- Supabase auth user UUID; NULL until claimed
updated_at  TEXT              -- ISO-8601; added where missing (not on
                              --   trip_journal / environmental_conditions)
```

- `uuid` / `owner_id` are NULLABLE at DDL level — populated by migration
  backfill (uuid) and by claim (owner_id). Keeps `ALTER TABLE` trivial
  and old rows valid pre-claim.
- Partial unique index per table:
  `CREATE UNIQUE INDEX idx_<t>_uuid ON <t>(uuid) WHERE uuid IS NOT NULL`.
- **No soft-delete column.** Deletes remain hard deletes (existing app
  semantics unchanged — no query rewrites). Tombstones for future sync
  are captured by `AFTER DELETE` triggers into `sync_queue`, which is
  why every table needs `uuid` (an integer-PK tombstone is meaningless
  cross-device).

### 2b. New table: `local_account` — single-row ownership record

```sql
CREATE TABLE local_account (
  id                 INTEGER PRIMARY KEY CHECK (id = 1),
  owner_id           TEXT,          -- NULL = unclaimed device
  claimed_at         TEXT,
  claim_backup_name  TEXT,          -- backup made during claim wizard
  claim_db_counts    TEXT           -- JSON per-table counts at claim
);
```

`CHECK (id = 1)` enforces one row = one local data owner per install.

### 2c. New table: `sync_queue` — dedicated change log

```sql
CREATE TABLE sync_queue (
  seq          INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name   TEXT NOT NULL,
  local_id     INTEGER,
  record_uuid  TEXT,
  operation    TEXT NOT NULL
               CHECK (operation IN ('insert','update','delete')),
  changed_at   TEXT NOT NULL
);
CREATE INDEX idx_sync_queue_table ON sync_queue(table_name, seq);
```

Rationale for a queue over a dirty flag: preserves delete tombstones
(uuids), preserves ordering (`seq`), is auditable/inspectable, and
doesn't require `WHERE dirty=1` filters on every query. Consumption
cursor (last-synced seq) is deferred to the sync stage — nothing is
written to `sync_queue` readers yet; the table is write-only in 4B.

### 2d. Triggers (per user-owned table) — key design choice

DDL triggers keep every existing write path correct **without touching
the ~50+ insert/update sites** across database_helper and the screens:

1. `trg_<t>_identity` `AFTER INSERT` — fills `uuid` (pure-SQL v4 via
   `randomblob`) and `owner_id` (from `local_account` when the device is
   claimed) **only when NULL**. Explicitly-supplied values are kept
   (needed for future cloud restore).
2. `trg_<t>_touch` `AFTER UPDATE` — sets `updated_at`, skipping
   identity-only updates (uuid/owner_id/updated_at) to avoid noise.
   Non-recursive by default (`recursive_triggers` off).
3. `trg_<t>_queue_*` `AFTER INSERT/UPDATE/DELETE` — appends to
   `sync_queue`; INSERT trigger uses a post-update `SELECT` so
   `record_uuid` is populated.

## 3. Migration mechanics (v28 → v29)

- `databaseHelper` version 29; `if (oldVersion < 29) await migrateToV29(db)`
  in `onUpgrade`; logic lives in new `lib/database/migration_v29.dart`.
- sqflite runs `onUpgrade` inside a transaction → **atomic**: any failure
  rolls everything back; next open retries. This gives the required
  transactional + interrupted-migration-recovery properties by
  construction; tests verify by injecting failures mid-migration.
- **Idempotent**: all column adds are `PRAGMA table_info`-guarded (not
  the older try/catch style), tables/triggers/indexes use
  `IF NOT EXISTS`, uuid backfill is `WHERE uuid IS NULL`.
- `_createDB` emits the full v29 shape directly (new installs skip the
  upgrade path) — including the previously-missing `tide_cache`.
- UUIDs: promote `uuid` from transitive to direct pubspec dep for the
  Dart side (claim service, tests); trigger-side generation uses the
  `randomblob` SQL expression. Both produce RFC-4122 v4.

## 4. Ownership claim process (existing-data migration)

Existing rows migrate with `owner_id = NULL` = **unowned**. Nothing is
auto-assigned. Claim is explicit, via Settings → Account → "Link this
device's data to your account" (visible when signed in and unclaimed):

1. Confirm signed in (`auth.userId` non-null).
2. **Required verified backup**: wizard runs
   `ZipBackupService.createBackup()` in-app and requires success —
   recorded as `claim_backup_name`. A stale file on shared storage is
   not accepted; the backup must be produced by the wizard.
3. Pre-checks: `integrity_check`, per-table counts, orphan audit,
   media-path resolution sample → snapshotted to `claim_db_counts`.
4. Single transaction: `INSERT/UPDATE local_account` (owner_id,
   claimed_at) + `UPDATE <each user table> SET owner_id=? WHERE
   owner_id IS NULL`.
5. Post-checks: recount matches snapshot, `owner_id IS NULL` count = 0
   per user table, relationship + media-path spot checks.
6. Idempotent/no-op for the same owner; **refuses** a different owner —
   ownership transfer is out of scope for 4B.

Claim runs fully offline (user.id comes from the cached session; backup
is local).

## 5. Account isolation model

- **One local data owner per installation** (enforced by
  `local_account` CHECK + claim refusal for a second owner).
- New `OwnershipGate` widget inside `AuthGate` after `signedIn`:
  - `owner_id` NULL → allow + non-blocking claim affordance.
  - `owner_id == auth.userId` → allow (works offline via cached session).
  - `owner_id != auth.userId` → terminal "data belongs to a different
    account" screen; sign-out only. **No** data access, delete, or
    silent reassignment.
- Enforcement at the gate, not per-query: all rows share one owner, so
  `WHERE owner_id=?` filters add complexity with zero benefit now.
  Documented as the seam if multi-owner is ever allowed.
- Sign-out never deletes local rows/photos (unchanged behavior).
- Known edge (accepted): a second account using the device *pre-claim*
  creates unowned rows that a later claim absorbs — inherent to
  "claim all local data" and stated in the claim dialog.

### FK enforcement — decision point
Declared FKs are inert today. Recommend: **enable
`PRAGMA foreign_keys = ON` via `onConfigure` only if the orphan audit
(§6) is clean**, since it activates CASCADE semantics. If orphans are
found or you prefer zero behavior change in 4B, leave it OFF and
revisit. Your call.

## 6. Validation & audit

Pre/post migration and claim (shared helpers in `migration_v29.dart`):
`PRAGMA integrity_check`; per-table row counts; uuid NULL/duplicate
counts; orphan audit over `catch_media`, `trip_media`, `trip_journal`,
`journal_media`, `user_achievements`, `environmental_conditions` +
undeclared `catches.trip_id/fishing_buddy_id/lure_id/bait_id`; media
path resolution sampling (no path changes expected — claim/migration
never touch `file_path`); `PRAGMA user_version` == 29.

## 7. Backup / restore compatibility

- `BackupManifest.databaseSchemaVersion` already exists →
  `maxSupportedSchemaVersion` bumps to 29.
- **v28 ZIP → v29 app**: restore replaces the DB file (v28) → reopen
  runs onUpgrade → migrated. Tested via the existing restore harness.
- **v29 ZIP → v28 app**: manifest check already refuses — correct.
- v29 snapshot inside a backup carries uuid/owner/queue naturally
  (VACUUM INTO). `sync_queue` contents are left as-is on restore
  (harmless duplicates handled at the future sync stage).

## 8. Implementation plan (files)

| File | Change |
|---|---|
| `lib/database/migration_v29.dart` | NEW — column/index/table/trigger DDL, backfill, audits |
| `lib/database/database_helper.dart` | version 29, upgrade hook, `_createDB` v29 + tide_cache fix |
| `lib/services/ownership_service.dart` | NEW — owner read, claim txn, access check, verification |
| `lib/screens/claim_data_screen.dart` | NEW — backup-verified claim wizard |
| `lib/screens/auth_gate.dart` | insert `OwnershipGate` after signedIn |
| `lib/screens/settings_screen.dart` | claim entry + owner display in Account |
| `lib/models/backup_manifest.dart` | `maxSupportedSchemaVersion` → 29 |
| `pubspec.yaml` | `uuid` → direct dependency |
| `test/migration_v29_test.dart` | NEW |
| `test/ownership_service_test.dart` | NEW |
| `test/auth_gate_test.dart` | extend for ownership states |

Commit order (focused): schema/migration → ownership service + gate +
claim UI → backup manifest bump + tests → docs.

## 9. Acceptance criteria

Automated (each maps to your list):
1. v28→v29 migration preserves all row counts/relationships.
2. Migration on populated DB (catches, media, trips, journal, spots,
   achievements, tackle) — FK chains + media paths untouched.
3. Empty/fresh v29 install — all tables/triggers present.
4. Interrupted migration rolls back to v28; reopen completes cleanly.
5. Repeated migration is a no-op.
6. uuid uniqueness + v4 format across all rows.
7. Claim assigns owner atomically; verified-backup gate enforced.
8. Second-account access denied at gate; data never visible/modifiable.
9. Sign-out preserves data; sign-in as owner restores access; sign-in
   as other account denied — no reassignment.
10. v28 ZIP restore → auto-upgrade → claimable.
11. Offline owner check (cached session) passes.
12. All existing tests pass unmodified (currently 190).

Manual (Moto G15, post-approval): upgrade in place with your 76 catches,
verify data/photos/settings; claim flow with fresh backup; second
account denial; sign-out/sign-in; create backup on v29.

**Open acceptance tests carried over from 4A**: account revocation →
"Access Removed" → reinstatement via `beta_testers.status` (recorded
open; unchanged by this stage).

**Outstanding security requirement (pre-beta gate, recorded 2026-10-16)**:
unclaimed local records are currently browsable by any account that signs
in on the device — including after restoring a legacy unowned backup,
which returns a claimed install to the unclaimed state. Before external
beta testing, an ownership-resolution process must prevent unauthorised
browsing of unclaimed data (e.g. a claim-pinning or lock-out mechanism)
without silently assigning ownership to the first sign-in.

## 10. Explicitly out of scope

Cloud upload/sync execution, cloud media, PowerSync, schema v30+,
ownership transfer, per-account settings scoping, FK-pragma enable
(pending §5 decision), merge to main, release tags.
