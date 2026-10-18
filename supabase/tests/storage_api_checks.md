# Stage 4C-1 — Storage API-level verification plan

Complements `rls_checks_storage.sql`. The SQL harness proves the RLS
layer; these checks prove the **physical** behaviour — real uploads,
downloads, API deletes and the `delete-backups` Edge Function — which
SQL-level row checks cannot observe.

## Prerequisites

- `0001_beta_access.sql` + `0002_cloud_backup.sql` applied.
- `supabase functions deploy delete-backups` (edge function deployed).
- Two DISTINCT authenticated test accounts, both approved at the start:
  - **A** — approved; owns its own objects and attempts cross-account
    access.
  - **T** — approved; uploads its own object so A can attempt
    cross-account reads/writes against real bytes. Afterwards T is
    temporarily `status='revoked'` via dashboard for EF-6, then
    reinstated and the reinstatement verified.
- Cross-account checks must target a REAL object under the OTHER
  account's uid prefix — a revoked account cannot plant one, which is
  why the second identity must be approved during upload.
- A REST client (curl/Postman) or a small Dart scratch script. All calls
  use the **anon key + user JWT** — never the service key. JWTs are
  held in shell variables only; never printed, logged, committed or
  screenshotted.

Variables: `$URL` = project URL, `$ANON` = anon key, `$JWT_A` / `$JWT_T`
= session access tokens for A / T (`$JWT_R` = T's token after
revocation — the token stays valid; server-side state is what changes).

## API checks

| # | Action | Expected |
|---|---|---|
| API-0 | `POST /storage/v1/object/backups/{uidT}/tT.bzp` as T | 200 — plants the real cross-account target object |
| API-1 | `POST /storage/v1/object/backups/{uidA}/t1.bzp` as A | 200; object exists |
| API-2 | `GET  /storage/v1/object/backups/{uidA}/t1.bzp` as A | 200; bytes match |
| API-3 | `POST .../backups/{uidA}/t1.bzp` again (upsert off) | 4xx — no overwrite |
| API-4 | `POST /storage/v1/object/list/backups` prefix `{uidA}/` as A | lists only A's objects |
| API-5 | `GET  /storage/v1/object/backups/{uidT}/tT.bzp` as A | denied (403/404) |
| API-6 | `POST /storage/v1/object/backups/{uidT}/hijack.bzp` as A | denied (400/403) |
| API-7 | `move` or `update` on own object as A | denied — no UPDATE policy |
| API-8 | `remove(['{uidA}/t1.bzp'])` as A | 200; subsequent list shows it gone — **physical delete confirmed** (row + bytes, not just metadata) |
| API-9 | Any of the above as revoked T (`$JWT_R`) | all denied server-side — token still valid; `is_approved_beta()` is what fails |
| API-10 | Any storage call with no/invalid JWT | denied |

## Edge Function checks — `POST /functions/v1/delete-backups`

| # | Action | Expected |
|---|---|---|
| EF-1 | No Authorization header | 401 |
| EF-2 | Invalid/expired JWT | 401 |
| EF-3 | A, body `{}` | 200 `{deleted: N}`; `list` confirms `{uidA}/` empty; audit row exists (`user_id`=A, `deleted_count`=N, `reason='user_request'`) |
| EF-4 | A, body `{name: "does_not_exist.bzp"}` | 200 `{deleted:0}` or verified no-op; no error, no other object touched |
| EF-5 | A, body `{name: "../{uidT}/tT.bzp"}` or containing `/` | 400 invalid name — T's objects untouched |
| EF-6 | **Revoked T** (`$JWT_R`), body `{reason: "account_closure"}` | 200; `{uidT}/` emptied incl. the API-0 object; audit row `reason='account_closure'` — this is the account-closure path ordinary RLS denies |
| EF-7 | A again after EF-3 | `{deleted: 0}` — idempotent |
| EF-8 | T reinstated to `approved`, fresh sign-in | T can upload again — revocation reversal verified end-to-end |

## Sign-off criteria

- Every API/EF check behaves as expected against the live dev project.
- The planted objects are physically gone (Storage dashboard shows the
  bucket empty), not merely absent from `storage.objects`.
- `backup_deletion_audit` contains exactly the expected rows.
- T is reinstated to `approved` in `beta_testers` and the reversal is
  verified (EF-8 or a fresh approved-scope query) before sign-off.
- No real account — in particular the primary account — was modified.
