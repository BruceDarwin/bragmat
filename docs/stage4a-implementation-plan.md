# Stage 4A — Authentication and Beta Access

Implementation plan and acceptance criteria. Companion to
`stage4-user-accounts-architecture.md` (Option 1 approved).

## 1. Scope

### In scope for 4A

- `supabase_flutter` integration, configured via `--dart-define`
  (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) — never committed. **Only the
  publishable/anon key is ever used; the service-role key must never
  appear in the app or this repo.**
- Email/password sign-up and sign-in **with Supabase email confirmation
  enabled**: sign-up produces no session until the emailed link is
  tapped; a "verify your email" screen offers resend; the confirmation
  and password-recovery links share the `bragmat://auth-callback`
  deep link.
- Session persistence and silent refresh; offline-capable after first
  authentication.
- **Server-enforced** beta gate: `beta_testers` allowlist table + RLS +
  `is_approved_beta()` RPC; profiles can only be created by approved
  testers (RLS insert policy), and profile updates also require active
  status so a revoked tester loses server access immediately.
- Auth gate at app start: signed-out → sign-in; verification pending →
  check-your-email; signed-in but not approved → "awaiting invitation";
  revoked → "access removed"; recovery session → set-new-password.
- Session and revocation policy per architecture §5.8 (hourly-throttled
  online entitlement re-check; offline never blocked).
- Account management in Settings: sign-out, switch account, password
  reset request, request account deletion.
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

RPC is_approved_beta() -> bool      -- security definer; joins auth.users —
                                    -- requires allowlist entry AND
                                    -- email_confirmed_at (verified email)
RPC request_account_deletion()      -- security definer; flags own profile;
                                    -- callable even when revoked

RLS:
  beta_testers: select own email only; admins all
  admins:       select own row only
  profiles:     select own row;
                insert/update require is_approved_beta() AND
                email = caller's verified JWT email
Grants:         explicit to `authenticated` only (automatic Data API
                exposure is disabled); nothing granted to `anon`
```

Server-enforcement properties:

- An uninvited or unverified user can create an auth account but cannot
  create a profile and `is_approved_beta()` returns false → gated in-app.
- Profile emails cannot differ from the caller's verified email.
- `status='revoked'` immediately blocks approval and all profile writes
  server-side; the app's next online check signs the session out.
- Revoked users can still read their own profile and request deletion
  via the RPC.
- Only `admins` members can manage the allowlist; only the anon key
  ships in the app; all enforcement is Postgres-side.

## 3. App-side design

```
main.dart
  └─ MaterialApp
       └─ home: AuthGate
            ├─ Supabase not configured   → MainScreen (dev builds)
            ├─ recovery session          → ResetPasswordScreen
            │                              (set new password → updateUser)
            ├─ signed out                → SignInScreen (sign in /
            │                              create account / reset email)
            ├─ email verification pending → EmailVerificationScreen
            │                              (resend link / back)
            ├─ signed in, not approved   → AwaitingApprovalScreen
            ├─ revoked                   → RevokedScreen
            └─ approved                  → MainScreen (existing app)
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

## 6. Supabase setup — step by step

Project `bragmat-dev` already exists and the `bragmat://auth-callback`
redirect URL is configured. Remaining steps:

### 6.1 Apply the schema

1. **SQL Editor** → **New query** → paste the full contents of
   `supabase/migrations/0001_beta_access.sql` → **Run**. The migration is
   idempotent — safe to re-run. Expected: success, no rows.
2. Verify under **Table Editor** that `beta_testers`, `admins` and
   `profiles` exist, each showing RLS enabled.

### 6.2 Verify the policies (optional but recommended)

3. Create the four test accounts described at the top of
   `supabase/tests/rls_checks.sql` (Authentication → Users → Add user;
   one with **Auto Confirm OFF**), substitute their UUIDs/emails into the
   script, and run each `begin; … rollback;` block in the SQL Editor.
   Every expectation is annotated in the file — it covers unverified,
   uninvited and revoked users, cross-user profile access, self-invite
   attempts and anonymous access.

### 6.3 Create your initial approved account

4. Invite yourself first — either **Table Editor** → `beta_testers` →
   Insert row (`email` = your address, `status` = `invited`), or SQL:
   `insert into public.beta_testers (email) values ('you@example.com');`
5. Build/run the app with dart-defines (§6.4) → **Create an account**
   with the same email → the "Verify your email" screen appears.
6. Tap the confirmation link in the email (opens the app) → **Sign in**
   → entitlement check passes → you're in.
7. Make yourself an admin — **Authentication → Users** → copy your UUID →
   SQL Editor:
   `insert into public.admins (user_id) values ('<your-uuid>');`
8. Invite other testers the same way as step 4; revoke anyone by setting
   their `beta_testers.status = 'revoked'`.

### 6.4 Authentication configuration (already done)

- **Email** provider enabled with **Confirm email ON** — required, do not
  disable (approval now also checks `email_confirmed_at` server-side).
- **Redirect URLs** include `bragmat://auth-callback` — serves both
  signup-confirmation and password-recovery emails; the app distinguishes
  them by token type.

### 6.5 Credentials and build

9. **Settings → API**: copy **Project URL** and the **anon public** key
   (labelled `anon` / `public` / `publishable`). **Never use the
   `service_role` key** — it bypasses RLS and must not ship in the app.
10. Run / build with:

    ```
    flutter run \
      --dart-define=SUPABASE_URL=https://<project>.supabase.co \
      --dart-define=SUPABASE_ANON_KEY=<anon-key>

    flutter build apk --debug \
      --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
    ```

    Optionally keep them in a local `.env` (gitignored) and pass them
    through your shell.

### 6.6 What each key is for

| Key | Where it lives | Purpose |
|---|---|---|
| Project URL | App (dart-define) | API endpoint |
| `anon`/`publishable` | App (dart-define) | Public client key — all access governed by RLS |
| `service_role` | **Nowhere in the app/repo** | Admin only (dashboard, scripts); bypasses RLS |
| DB password | Supabase only | Direct Postgres admin; not used by the app |

## 7. Acceptance criteria — device test additions

In addition to §5:

12. Sign-up sends a confirmation email; the app shows "Verify your
    email"; tapping the link opens the app; sign-in then succeeds.
13. Unverified sign-in shows a clear "not verified" message.
14. Reset request → email link → app opens to **Set New Password** →
    update succeeds → signed in normally.
15. A revoked tester's profile updates fail server-side (RLS), not just
    in-app — verifiable in the dashboard by attempting an update as that
    user.

## 8. Deferred functionality (not in 4A)

Account deletion is currently a **request workflow** only: the app sets
`deletion_requested_at` on the profile; an admin performs the actual
`auth.users` deletion in the Supabase dashboard (requires the
service-role key, which must never ship in the app). Deferred to later
phases: an admin console for processing deletions, any automated
deletion of cloud data (no cloud data exists in 4A anyway), and a
device-side "delete my local data too" option — local data is
deliberately preserved today.

Also deferred: schema v29 columns, cloud backup, synchronisation, OAuth,
in-app admin console, iOS deep-link config (`bragmat://` in Info.plist —
recorded for the MacBook work).

## 9. Risks / notes

- **No live backend in this environment** — all auth code is unit-tested
  against a fake backend; end-to-end verification happens on your device
  against your project.
- SMTP deliverability: Supabase's default email sender is rate-limited
  and may land in spam; a custom SMTP provider can be configured later.
- With email confirmation ON, an unverified user cannot authenticate at
  all — so the beta check only ever runs for verified accounts, which is
  the desired ordering.
