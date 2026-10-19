# Stage 4C-5A — Admin runbook (dashboard steps)

Privileged operations performed by the project owner in the Supabase
Dashboard for the **development project only**. Nothing here uses the
service-role key in the app or the repo. Synthetic data only — test
emails end in `.invalid` or `@bragmat.test` and object names start
`apitest_`.

Perform the steps in order. Do not continue past a step whose expected
result fails — report and stop.

## Step 0 — Verify project identity

- Dashboard → project picker. Confirm the project is **bragmat-dev**
  and the URL is `https://xszodjyyueouiktclsvy.supabase.co` (matches
  `.env` `SUPABASE_URL`).
- **Expected**: URL and project ref agree.
- **Rollback**: none (read-only check).

## Step 1 — Apply 0002_cloud_backup.sql

- SQL Editor → New query → paste the entire contents of
  `supabase/migrations/0002_cloud_backup.sql` → Run.
- **Expected**: `Success. No rows returned` (or similar). Verify:
  Storage → a private `backups` bucket exists (public = off);
  Table Editor → `backup_deletion_audit` exists.
- **Rollback** (exact, API-safe — never delete `storage.*` rows):
  1. Empty bucket via Storage dashboard (or leave empty if nothing
     uploaded yet — at this point it is empty).
  2. Storage → `backups` → Delete bucket.
  3. SQL Editor: the drop statements in the migration footer
     (3 policies + audit policy + audit table).
  4. Edge Functions → delete `delete-backups` (if deployed).

## Step 2 — Run the 17 RLS checks

- SQL Editor → paste the entire `supabase/tests/rls_checks_storage.sql`
  → Run.
- The script is one transaction: it creates disposable users/objects,
  runs 17 checks with simulated JWT claims, prints a results table and
  ends in `ROLLBACK` — **nothing persists**.
- **Expected**: every row `pass = true`. Copy the result table back.
- **Failure**: stop, report which check number failed.
- **Rollback**: not needed — transactional by design.

## Step 3 — Deploy the delete-backups Edge Function

- Edge Functions → Deploy new function → name it `delete-backups`.
- Paste the entire `supabase/functions/delete-backups/index.ts`.
- **Verify JWT: leave enabled** (default) — the function also
  re-verifies via `auth.getUser()` internally.
- No secrets to configure — `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
  `SUPABASE_SERVICE_ROLE_KEY` are injected by the runtime.
- **Expected**: function listed as deployed; `POST
  /functions/v1/delete-backups` with no Authorization header returns
  `401` (Step 5 confirms).
- **Rollback**: Edge Functions → `delete-backups` → Delete.

## Step 4 — Create the two synthetic test accounts

Auth → Users → Add user (create user) for each of:

| Account | Email (suggested) | Notes |
|---|---|---|
| A — approved | `cbtest.a@bragmat.test` | tick **Auto Confirm User** |
| R — revoked-later | `cbtest.r@bragmat.test` | tick **Auto Confirm User** |

Then Table Editor → `beta_testers` → insert one row per test email,
`status = invited` (that plus the confirmed email makes
`is_approved_beta()` true for both).

**Do not** put passwords in chat or files inside the repo — place them
in `C:\Users\bruce\bragmat-test.env` (outside the repo):

```
SUPABASE_URL=https://xszodjyyueouiktclsvy.supabase.co
SUPABASE_ANON_KEY=<the anon key from .env>
TEST_A_EMAIL=cbtest.a@bragmat.test
TEST_A_PASSWORD=<A's password>
TEST_R_EMAIL=cbtest.r@bragmat.test
TEST_R_PASSWORD=<R's password>
```

- **Expected**: both users exist in Auth → Users with confirmed emails;
  both emails present in `beta_testers` with status `invited`.
- **Rollback**: Auth → Users → delete both users; delete both
  `beta_testers` rows (and any `profiles` rows they created).

## Step 5 — Hand off to the API test phase

- Tell the agent steps 0–4 are complete. The agent runs
  `tool/cloud_backup_api_checks.dart` — it mints short-lived JWTs from
  `bragmat-test.env` locally and performs all API/EF checks; no
  credential is printed or transmitted anywhere except to Supabase
  Auth itself.
- **Phase boundary**: the script runs **phase 1** while BOTH accounts
  are approved (upload/list/download/cross-user/EF checks + retention).
  When it reports phase-1 results, set `cbtest.r`'s `beta_testers`
  status to **`revoked`**, then the agent runs **phase 2** (revoked-user
  denials + EF-6 account-closure delete).
- **Expected end state**: all checks pass; the `backups` bucket is
  empty; `backup_deletion_audit` holds the expected rows (verify in
  Table Editor: `user_id`, `deleted_count`, `reason` only).
