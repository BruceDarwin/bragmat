# Stage 4A — Authentication and Beta Access

Implementation plan and acceptance criteria. Companion to
`stage4-user-accounts-architecture.md` (Option 1 approved).

## 1. Scope

### In scope for 4A

- `supabase_flutter` integration, configured via `--dart-define`
  (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) — never committed.
- Email/password sign-up and sign-in; session persistence and silent
  refresh; offline-capable after first authentication.
- **Server-enforced** beta gate: `beta_testers` allowlist table + RLS +
  `is_approved_beta()` RPC; profiles can only be created by approved
  testers (RLS insert policy).
- Auth gate at app start: signed-out → sign-in screen; signed-in but not
  approved → "awaiting invitation"; revoked → "access removed".
- Session and revocation policy per architecture §5.8 (hourly-throttled
  online entitlement re-check; offline never blocked).
- Account management in Settings: sign-out, switch account, password
  reset (`bragmat://reset-callback` deep link), request account deletion.
- `supabase/migrations/` SQL checked into the repo for you to apply to
  your Supabase project.
- Automated tests with a fake auth backend (no network).

### Explicitly out of scope for 4A (deferred)

- Any change to user-owned data tables (`catches`, `fishing_trips`,
  `catch_media`, …). **No `uuid`/`owner_id`/`updated_at`/`deleted_at`/
  `dirty` columns in 4A** — they are only needed once upload/sync exists.
- Cloud upload, cloud backup, cross-device sync — disabled until
  explicitly approved.
- OAuth / magic links / Sign in with Apple.
- In-app admin console (Supabase dashboard suffices for early beta).
- Schema v29 implementation — **specification below requires your
  confirmation first** (§4).

## 2. Server side (Supabase)

Delivered as `supabase/migrations/0001_beta_access.sql` in this repo —
applied to your Supabase project via dashboard SQL editor or
`supabase db push`.

```sql
beta_testers   (id uuid pk, email citext unique, invited_by uuid,
                invited_at timestamptz, status text in
                ('invited','active','revoked'), notes text)
admins         (user_id uuid pk -> auth.users)
profiles       (id uuid pk -> auth.users cascade, email, display_name,
                created_at, last_seen_at, deletion_requested_at)

RPC is_approved_beta() -> bool      -- security definer; checks caller's
                                    -- jwt email against allowlist status

RLS:
  beta_testers: select own email only; admins all
  admins:       select own row only
  profiles:     select/update own row;
                insert requires is_approved_beta()   -- server-enforced
                                                    -- invitation
```

Server-enforcement properties:

- An uninvited user can create an auth account but cannot create a
  profile and `is_approved_beta()` returns false → gated in-app.
- Admin sets `status='revoked'` → next online check revokes the session
  locally (§5.8 of the architecture doc).
- Only the anon key ships in the app; all enforcement is Postgres-side.

## 3. App-side design

```
main.dart
  └─ MaterialApp
       └─ home: AuthGate
            ├─ Supabase not configured  → MainScreen (dev builds)
            ├─ signed out               → SignInScreen (sign in / create
            │                             account / reset password)
            ├─ signed in, not approved  → AwaitingApprovalScreen
            ├─ revoked                  → RevokedScreen
            └─ approved                 → MainScreen (existing app)
```

- `lib/services/supabase_config.dart` — dart-define config +
  `isConfigured` (empty credentials → bypass gate, app usable; protects
  dev/test builds, not a security hole since beta builds ship configured).
- `lib/services/auth_service.dart` — `AuthService extends ChangeNotifier`
  over an `AuthBackend` interface (`SupabaseAuthBackend` /
  `FakeAuthBackend` for tests). Owns sign-in/up/out, password-reset
  request, entitlement check + throttle, profile upsert, deletion-request
  flag.
- `lib/screens/auth_gate.dart`, `sign_in_screen.dart` — gate + auth UI.
- Settings → new "Account" section: signed-in email, sign out / switch
  account (same flow, data preserved), reset password, request deletion.
- `AndroidManifest.xml` — intent-filter for `bragmat://reset-callback`
  (and future login deep links).

**No database schema change is needed for any of the above** — session is
handled by the Supabase SDK; profile mirror + beta status cache live in
`SharedPreferences`. `account_profile`/`sync_state` tables arrive with the
approved v29 migration.

## 4. Schema v29 — migration specification (FOR CONFIRMATION, not yet implemented)

Proposed when cloud upload/sync is approved (Phase 4C). Specification now
so you can confirm compatibility early.

### 4.1 Changes

For each user-owned table (`catches`, `fishing_trips`, `trip_journal`,
`catch_media`, `trip_media`, `journal_media`, `favourite_spots`,
`fishing_buddies`, `lures`, `baits`, `fish_types`):

```sql
ALTER TABLE <t> ADD COLUMN uuid TEXT;          -- then backfill + unique index
ALTER TABLE <t> ADD COLUMN owner_id TEXT;      -- NULL = pre-account local data
ALTER TABLE <t> ADD COLUMN updated_at TEXT;    -- ISO-8601; backfill from
                                               -- existing created_at where
                                               -- present, else migration time
ALTER TABLE <t> ADD COLUMN deleted_at TEXT;    -- tombstone, NULL = live
ALTER TABLE <t> ADD COLUMN dirty INTEGER NOT NULL DEFAULT 0;
CREATE UNIQUE INDEX idx_<t>_uuid ON <t>(uuid);
```

Plus new tables:

```sql
account_profile (user_id TEXT PRIMARY KEY, email, display_name,
                 linked_at, last_sync_at)
sync_state      (table_name TEXT PRIMARY KEY, last_pulled_at TEXT)
```

All additive — no column is removed, renamed, re-typed or given a NOT NULL
constraint without a default.

### 4.2 Compatibility with existing data

- `uuid` backfilled with freshly generated UUIDs; `updated_at` backfilled
  from `created_at` where present else migration timestamp; `owner_id`
  and `deleted_at` left NULL; `dirty = 0`.
- All existing queries continue to work — no existing column changes.
- Write paths get a `before`/`after` trigger or service-level stamping of
  `updated_at`/`dirty` (chosen at implementation; triggers preferred —
  they cover every writer including future ones).
- Deletes in sync scope become tombstones (`deleted_at = now`) — decision
  on soft-delete rollout per table deferred to 4C approval.

### 4.3 Compatibility with ZIP backup/restore

- The backup pipeline snapshots the whole DB file (`VACUUM INTO`) — new
  columns and tables are included automatically; no format change needed.
- `manifest.json` records `databaseSchemaVersion`; restore already rejects
  backups newer than the running app (schema ≤ current check) — a v29
  backup restored on a v28 app is correctly refused.
- A v28 backup restored on a v29 app: restore installs the v28 file, then
  the existing `onUpgrade` path migrates it to v29 on next open. Requires
  one addition: after a restore, run `_migrateToV29`-equivalent on the
  swapped-in DB if `user_version` < 29 — already covered because the
  restore pipeline reopens through the normal `openDatabase`/`onUpgrade`
  path. Verified by an added round-trip test.
- Media-relative paths unaffected.

### 4.4 What changes for users

Nothing visible. Data is untouched; ownership is only stamped when a user
links an account and approves upload (opt-in prompt + ZIP backup offer
first, per approved decision 5).

## 5. Acceptance criteria for Stage 4A

1. `flutter test` — full suite green, plus new auth/beta-gate tests
   (fake backend).
2. `flutter analyze` — no new issues beyond the 145 pre-existing.
3. `flutter build apk --debug` succeeds.
4. With Supabase configured: sign-up with an **uninvited** email →
   "awaiting invitation" screen; no profile row created (RLS blocks it).
5. Invited email → sign-up → profile row exists → app enters normally.
6. Kill + relaunch with no connectivity → app opens normally
   (offline-after-auth).
7. Admin revokes tester → next online launch → "access removed" screen;
   local data (catches/photos) intact and browsable.
8. Sign-out → sign-in screen; data still present after signing back in.
9. Password reset email flow lands on `bragmat://reset-callback` and
   allows setting a new password.
10. ZIP backup + restore still pass existing tests; a restore performed
    while signed in keeps working.
11. No network calls to user data tables/buckets exist in the codebase
    (grep-verifiable: no `storage.from` / no PostgREST calls to entity
    tables — only `beta_testers`/`profiles`/`is_approved_beta` RPC).

## 6. Manual test prerequisites (yours)

- A Supabase project (hosted, free tier) — you create it; I cannot.
- Apply `supabase/migrations/0001_beta_access.sql` in the SQL editor.
- Insert your email into `beta_testers` (`status='invited'`) and your
  `auth.users` id into `admins` after first sign-up.
- Build with:
  `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
  (same flags for `flutter build apk --debug`).
- Enable email provider in Supabase Auth settings; set Site URL /
  additional redirect URLs to include `bragmat://reset-callback`.

## 7. Risks / notes

- **No live backend in this environment** — all auth code is unit-tested
  against a fake backend; end-to-end verification happens on your device
  against your project (criteria 4–9).
- Email confirmation: recommend *off* for the beta (invite allowlist is
  already the gate); otherwise sign-up needs an email-confirm step.
- The `bragmat://` scheme must also be added to the iOS `Info.plist` when
  the iOS build happens — recorded for the MacBook work.
