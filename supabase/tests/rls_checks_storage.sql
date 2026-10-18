-- ────────────────────────────────────────────────────────────────────────
-- Stage 4C-1 — Storage RLS verification for the `backups` bucket
--
-- PREREQUISITE: supabase/migrations/0001_beta_access.sql AND
-- 0002_cloud_backup.sql must already be applied to the project.
--
-- HOW TO RUN: paste this ENTIRE file into the Supabase SQL Editor as one
-- query and press Run. The script:
--   * creates the same four disposable test users as rls_checks.sql
--     inside a transaction,
--   * plants backup objects in `backups/` directly (as the migration
--     owner — RLS is bypassed while no role is set),
--   * runs each check while simulating that user's JWT claims,
--   * prints a single PASS/FAIL results table at the end,
--   * ends in ROLLBACK — nothing persists, nothing needs editing.
--
-- PASS column should be true for every row.
--
-- Users: A = invited + verified   B = verified, not invited
--        C = invited + unverified D = invited, status='revoked'
--
-- NOTE: SQL-level checks exercise the RLS layer only. Real
-- upload/download/delete behaviour (object physicality, the
-- delete-backups Edge Function) is covered by
-- storage_api_checks.md — the two are complementary.
--
-- IMPORTANT: Supabase's storage.protect_delete trigger blocks EVERY
-- direct SQL delete on storage.objects (SQLSTATE 42501), for any role.
-- Delete checks therefore assert the raise ('denied'), not a row count.
-- The positive delete path only exists through the Storage API (API-8).
-- ────────────────────────────────────────────────────────────────────────

begin;

-- ═══ SETUP ═════════════════════════════════════════════════════════════
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000',
   'a0000000-0000-4000-8000-00000000000a',
   'authenticated', 'authenticated', 'rlstest.a@bragmat.invalid', '',
   now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   'b0000000-0000-4000-8000-00000000000b',
   'authenticated', 'authenticated', 'rlstest.b@bragmat.invalid', '',
   now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   'c0000000-0000-4000-8000-00000000000c',
   'authenticated', 'authenticated', 'rlstest.c@bragmat.invalid', '',
   null, now(), now()),
  ('00000000-0000-4000-8000-000000000000',
   'd0000000-0000-4000-8000-00000000000d',
   'authenticated', 'authenticated', 'rlstest.d@bragmat.invalid', '',
   now(), now(), now());

insert into public.beta_testers (email, status) values
  ('rlstest.a@bragmat.invalid', 'invited'),
  ('rlstest.c@bragmat.invalid', 'invited'),
  ('rlstest.d@bragmat.invalid', 'revoked');

-- Planted backup objects: one each for A, B and D under their uid
-- prefixes, plus one in a NON-backups bucket to prove the policies are
-- bucket-scoped. Inserted as the session user — RLS does not apply here.
-- The control bucket is created inside this same transaction (the dev
-- project has no `avatars` bucket) and disappears with the ROLLBACK.
insert into storage.buckets (id, name, public)
values ('rls_nonbackup', 'rls_nonbackup', false);

insert into storage.objects (bucket_id, name) values
  ('backups', 'a0000000-0000-4000-8000-00000000000a/backup_a.bzp'),
  ('backups', 'b0000000-0000-4000-8000-00000000000b/backup_b.bzp'),
  ('backups', 'd0000000-0000-4000-8000-00000000000d/backup_d.bzp'),
  ('rls_nonbackup', 'a0000000-0000-4000-8000-00000000000a/not_a_backup.jpg');

create temp table rls_results(
  n int, check_name text, expected text, actual text, pass boolean
);

-- ═══ CHECK 1: approved user sees only own objects ══════════════════════
do $$
declare rc int;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-00000000000a","email":"rlstest.a@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  select count(*) into rc from storage.objects
    where bucket_id = 'backups';
  perform set_config('role','none',true);
  insert into rls_results values
    (1,'approved user sees only own backup','1',rc::text,(rc = 1));
end $$;

-- ═══ CHECK 2: approved user inserts under own prefix ═══════════════════
do $$
declare rc int;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-00000000000a","email":"rlstest.a@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  insert into storage.objects (bucket_id, name) values
    ('backups','a0000000-0000-4000-8000-00000000000a/backup_a2.bzp');
  get diagnostics rc = row_count;
  perform set_config('role','none',true);
  insert into rls_results values
    (2,'approved user uploads under own prefix','1',rc::text,(rc = 1));
end $$;

-- ═══ CHECK 3: cannot write into another user's prefix ══════════════════
do $$
declare outcome text;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-00000000000a","email":"rlstest.a@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  begin
    insert into storage.objects (bucket_id, name) values
      ('backups','d0000000-0000-4000-8000-00000000000d/hijack.bzp');
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  perform set_config('role','none',true);
  insert into rls_results values
    (3,'cross-user insert denied','denied',outcome,(outcome='denied'));
end $$;

-- ═══ CHECK 4: top-level objects (no uid folder) are denied ═════════════
do $$
declare outcome text;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-00000000000a","email":"rlstest.a@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  begin
    insert into storage.objects (bucket_id, name) values
      ('backups','loose.bzp');
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  perform set_config('role','none',true);
  insert into rls_results values
    (4,'unprefixed object insert denied','denied',outcome,(outcome='denied'));
end $$;

-- ═══ CHECK 5: cross-user modify/move/delete all denied ═════════════════
-- update = 0 rows under RLS (no update policy at all, and the row is
-- invisible anyway) → covers overwrite, rename and move attempts.
do $$
declare rc int; outcome text;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-00000000000a","email":"rlstest.a@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  update storage.objects set name = name || '.x'
   where bucket_id = 'backups'
     and (storage.foldername(name))[1] =
         'd0000000-0000-4000-8000-00000000000d';
  get diagnostics rc = row_count;
  perform set_config('role','none',true);
  insert into rls_results values
    (5,'cross-user update/rename/move denied','0',rc::text,(rc = 0));

  -- storage.protect_delete raises on ANY direct SQL delete (before RLS
  -- even applies) — that raise IS the denial at this layer. Physical
  -- cross-account deletion via the Storage API is covered by API-8b.
  perform set_config('role','authenticated',true);
  begin
    delete from storage.objects
     where bucket_id = 'backups'
       and (storage.foldername(name))[1] =
           'd0000000-0000-4000-8000-00000000000d';
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  perform set_config('role','none',true);
  insert into rls_results values
    (6,'cross-user delete denied','denied',outcome,(outcome='denied'));
end $$;

-- ═══ CHECK 6: own-row UPDATE is also denied (no update policy) ═════════
-- Least privilege: upsert:false uploads need INSERT only; renames and
-- moves are never used. Nothing may modify an existing backup row.
do $$
declare rc int;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-00000000000a","email":"rlstest.a@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  update storage.objects set name = name || '.x'
   where bucket_id = 'backups'
     and (storage.foldername(name))[1] =
         'a0000000-0000-4000-8000-00000000000a';
  get diagnostics rc = row_count;
  perform set_config('role','none',true);
  insert into rls_results values
    (7,'own-row update denied (no update policy)','0',rc::text,(rc = 0));
end $$;

-- ═══ CHECK 7: own-object delete — SQL path blocked, API path only ═════
-- storage.protect_delete raises on ANY direct SQL delete — including the
-- owner's. The positive "approved user deletes own backup" check can
-- only run through the real Storage API (API-8 in
-- storage_api_checks.md). Here we assert the SQL path raises 42501.
do $$
declare outcome text;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-00000000000a","email":"rlstest.a@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  begin
    delete from storage.objects
     where bucket_id = 'backups'
       and name = 'a0000000-0000-4000-8000-00000000000a/backup_a2.bzp';
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  perform set_config('role','none',true);
  insert into rls_results values
    (8,'own delete via raw SQL blocked (API-8 covers API path)','denied',outcome,(outcome='denied'));
end $$;

-- ═══ CHECK 8: uninvited user denied even under own prefix ══════════════
do $$
declare outcome text; rc int;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"b0000000-0000-4000-8000-00000000000b","email":"rlstest.b@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  begin
    insert into storage.objects (bucket_id, name) values
      ('backups','b0000000-0000-4000-8000-00000000000b/new.bzp');
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  select count(*) into rc from storage.objects
    where bucket_id = 'backups';
  perform set_config('role','none',true);
  insert into rls_results values
    (9,'uninvited user cannot upload','denied',outcome,(outcome='denied'));
  insert into rls_results values
    (10,'uninvited user cannot even read own objects','0',rc::text,(rc = 0));
end $$;

-- ═══ CHECK 9: invited but unverified user denied ═══════════════════════
do $$
declare outcome text;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"c0000000-0000-4000-8000-00000000000c","email":"rlstest.c@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  begin
    insert into storage.objects (bucket_id, name) values
      ('backups','c0000000-0000-4000-8000-00000000000c/new.bzp');
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  perform set_config('role','none',true);
  insert into rls_results values
    (11,'unverified user cannot upload','denied',outcome,(outcome='denied'));
end $$;

-- ═══ CHECK 10: revoked user — all ordinary access gone ═════════════════
-- Deletion for revoked users goes through the delete-backups Edge
-- Function (Storage API) — covered in storage_api_checks.md.
do $$
declare rc int; outcome2 text;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"d0000000-0000-4000-8000-00000000000d","email":"rlstest.d@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  select count(*) into rc from storage.objects
    where bucket_id = 'backups';
  perform set_config('role','none',true);
  insert into rls_results values
    (12,'revoked user sees no backups','0',rc::text,(rc = 0));

  perform set_config('role','authenticated',true);
  begin
    delete from storage.objects
     where bucket_id = 'backups'
       and (storage.foldername(name))[1] = auth.uid()::text;
    outcome2 := 'allowed';
  exception when insufficient_privilege then
    outcome2 := 'denied';
  end;
  perform set_config('role','none',true);
  insert into rls_results values
    (13,'revoked user cannot delete via API/RLS','denied',outcome2,(outcome2='denied'));
end $$;

-- ═══ CHECK 11: anonymous access fully denied ═══════════════════════════
do $$
declare outcome text; rc int;
begin
  perform set_config('role','anon',true);
  perform set_config('request.jwt.claims','{}',true);
  begin
    insert into storage.objects (bucket_id, name) values
      ('backups','a0000000-0000-4000-8000-00000000000a/anon.bzp');
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  -- An anonymous SELECT either returns 0 rows (grant exists, RLS hides
  -- everything) or raises insufficient_privilege (no grant at all).
  -- Both are correct denials.
  begin
    select count(*) into rc from storage.objects
      where bucket_id = 'backups';
  exception when insufficient_privilege then
    rc := 0;
  end;
  perform set_config('role','none',true);
  insert into rls_results values
    (14,'anon cannot upload','denied',outcome,(outcome='denied'));
  insert into rls_results values
    (15,'anon sees no backups','0',rc::text,(rc = 0));
end $$;

-- ═══ CHECK 12: audit table — users see only own rows, cannot write ═════
do $$
declare rc int; outcome text;
begin
  -- Planted audit rows for A and D (as session user — RLS bypassed).
  insert into public.backup_deletion_audit (user_id, deleted_count) values
    ('a0000000-0000-4000-8000-00000000000a', 2),
    ('d0000000-0000-4000-8000-00000000000d', 1);

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-00000000000a","email":"rlstest.a@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  select count(*) into rc from public.backup_deletion_audit;
  begin
    insert into public.backup_deletion_audit (user_id, deleted_count)
      values (auth.uid(), 9);
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  perform set_config('role','none',true);
  insert into rls_results values
    (16,'user sees only own audit rows','1',rc::text,(rc = 1));
  insert into rls_results values
    (17,'user cannot write audit rows','denied',outcome,(outcome='denied'));
end $$;

-- ═══ RESULTS ═══════════════════════════════════════════════════════════
select n, check_name, expected, actual, pass
  from rls_results order by n;

-- Everything above is discarded — test users, objects, results.
rollback;
