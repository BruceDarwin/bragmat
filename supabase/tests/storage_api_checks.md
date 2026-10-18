# Stage 4C-1 — Storage API-level verification plan

Complements `rls_checks_storage.sql`. The SQL harness proves the RLS
layer; these checks prove the **physical** behaviour — real uploads,
downloads, API deletes and the `delete-backups` Edge Function — which
SQL-level row checks cannot observe.

## Prerequisites

- `0001_beta_access.sql` + `0002_cloud_backup.sql` applied.
- `supabase functions deploy delete-backups` (edge function deployed).
- Two test accounts: **A** (invited + verified, approved), **R**
  (invited → then `status='revoked'` via dashboard).
- A REST client (curl/Postman) or a small Dart scratch script. All calls
  use the **anon key + user JWT** — never the service key.

Variables: `$URL` = project URL, `$ANON` = anon key, `$JWT_A` / `$JWT_R`
= session access tokens for A / R.

## API checks

| # | Action | Expected |
|---|---|---|
| API-1 | `POST /storage/v1/object/backups/{uidA}/t1.bzp` as A | 200; object exists |
| API-2 | `GET  /storage/v1/object/backups/{uidA}/t1.bzp` as A | 200; bytes match |
| API-3 | `POST .../backups/{uidA}/t1.bzp` again (upsert off) | 4xx — no overwrite |
| API-4 | `POST /storage/v1/object/list/backups` prefix `{uidA}/` as A | lists only A's objects |
| API-5 | Download `{uidR}/...` as A | denied (403/404) |
| API-6 | Upload into `{uidR}/...` as A | denied (400/403) |
| API-7 | `move` or `update` on own object as A | denied — no UPDATE policy |
| API-8 | `remove(['{uidA}/t1.bzp'])` as A | 200; subsequent list shows it gone — **physical delete confirmed** (row + bytes, not just metadata) |
| API-9 | Any of the above as R (revoked) | all denied server-side |
| API-10 | Any storage call with no/invalid JWT | denied |

## Edge Function checks — `POST /functions/v1/delete-backups`

| # | Action | Expected |
|---|---|---|
| EF-1 | No Authorization header | 401 |
| EF-2 | Invalid/expired JWT | 401 |
| EF-3 | A, body `{}` | 200 `{deleted: N}`; `list` confirms `{uidA}/` empty; audit row exists (`user_id`=A, `deleted_count`=N, `reason='user_request'`) |
| EF-4 | A, body `{name: "does_not_exist.bzp"}` | 200 `{deleted:0}` or verified no-op; no error, no other object touched |
| EF-5 | A, body `{name: "../{uidR}/x.bzp"}` or containing `/` | 400 invalid name — R's objects untouched |
| EF-6 | **R (revoked)**, body `{reason: "account_closure"}` | 200; `{uidR}/` emptied; audit row `reason='account_closure'` — this is the account-closure path ordinary RLS denies |
| EF-7 | A again after EF-3 | `{deleted: 0}` — idempotent |

## Sign-off criteria

- Every API/EF check behaves as expected against the live dev project.
- The planted objects are physically gone (Storage dashboard shows the
  bucket empty), not merely absent from `storage.objects`.
- `backup_deletion_audit` contains exactly the expected rows.
