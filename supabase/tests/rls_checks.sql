-- ────────────────────────────────────────────────────────────────────────
-- Stage 4A — RLS / allowlist verification for bragmat-dev
--
-- HOW TO RUN: paste this ENTIRE file into the Supabase SQL Editor as one
-- query and press Run. The script:
--   * creates four disposable test users inside a transaction,
--   * runs each check while simulating that user's JWT claims,
--   * prints a single PASS/FAIL results table at the end,
--   * ends in ROLLBACK — nothing persists, nothing needs editing.
--
-- PASS column should be true for every row.
--
-- AUTH NOTE: auth.users rows are inserted directly so the
-- is_approved_beta() join has real users to find. They can never log in
-- (no identities, empty password) and are rolled back anyway.
-- ────────────────────────────────────────────────────────────────────────

begin;

-- ═══ SETUP ═════════════════════════════════════════════════════════════
-- A = invited + verified   B = verified, not invited
-- C = invited + unverified D = invited, status='revoked'
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

-- D owns a profile (created while still approved)
insert into public.profiles (id, email) values
  ('d0000000-0000-4000-8000-00000000000d', 'rlstest.d@bragmat.invalid');

create temp table rls_results(
  n int, check_name text, expected text, actual text, pass boolean
);

-- Each check: set role + JWT claims, run the operation, reset role to
-- 'none' (session user), then record the outcome. Resetting before the
-- results write is required — temp tables are privilege-checked too.

-- ═══ CHECK 1: is_approved_beta() across all four states ════════════════
do $$
declare r boolean;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-00000000000a","email":"rlstest.a@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  select public.is_approved_beta() into r;
  perform set_config('role','none',true);
  insert into rls_results values
    (1,'invited + verified user is approved','true',r::text,(r = true));
end $$;

do $$
declare r boolean;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"b0000000-0000-4000-8000-00000000000b","email":"rlstest.b@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  select public.is_approved_beta() into r;
  perform set_config('role','none',true);
  insert into rls_results values
    (2,'uninvited user is NOT approved','false',r::text,(r = false));
end $$;

do $$
declare r boolean;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"c0000000-0000-4000-8000-00000000000c","email":"rlstest.c@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  select public.is_approved_beta() into r;
  perform set_config('role','none',true);
  insert into rls_results values
    (3,'invited + UNVERIFIED user is NOT approved','false',r::text,(r = false));
end $$;

do $$
declare r boolean;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"d0000000-0000-4000-8000-00000000000d","email":"rlstest.d@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  select public.is_approved_beta() into r;
  perform set_config('role','none',true);
  insert into rls_results values
    (4,'revoked user is NOT approved','false',r::text,(r = false));
end $$;

-- ═══ CHECK 2: uninvited user cannot create a profile ═══════════════════
do $$
declare outcome text;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"b0000000-0000-4000-8000-00000000000b","email":"rlstest.b@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  begin
    insert into public.profiles (id, email)
      values (auth.uid(), 'rlstest.b@bragmat.invalid');
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  perform set_config('role','none',true);
  insert into rls_results values
    (5,'uninvited profile insert denied','denied',outcome,(outcome='denied'));
end $$;

-- ═══ CHECK 3: profile email cannot differ from caller's email ══════════
do $$
declare outcome text;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-00000000000a","email":"rlstest.a@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  begin
    insert into public.profiles (id, email)
      values (auth.uid(), 'spoofed@bragmat.invalid');
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  perform set_config('role','none',true);
  insert into rls_results values
    (6,'profile email spoof denied','denied',outcome,(outcome='denied'));
end $$;

-- ═══ CHECK 4: own profile insert works; other users invisible ══════════
do $$
declare rc int;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-00000000000a","email":"rlstest.a@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  insert into public.profiles (id, email)
    values (auth.uid(), 'rlstest.a@bragmat.invalid');
  get diagnostics rc = row_count;
  perform set_config('role','none',true);
  insert into rls_results values
    (7,'approved user inserts own profile','1',rc::text,(rc = 1));

  perform set_config('role','authenticated',true);
  select count(*) into rc from public.profiles
    where id = 'b0000000-0000-4000-8000-00000000000b';
  update public.profiles set display_name = 'hijack'
    where id = 'b0000000-0000-4000-8000-00000000000b';
  get diagnostics rc = row_count;
  perform set_config('role','none',true);
  insert into rls_results values
    (8,'other user''s profile unmodifiable','0',rc::text,(rc = 0));
end $$;

-- ═══ CHECK 5: non-admin cannot modify the allowlist ════════════════════
do $$
declare outcome text; rc int;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-00000000000a","email":"rlstest.a@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  begin
    insert into public.beta_testers (email)
      values ('selfinvite@bragmat.invalid');
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  update public.beta_testers set status = 'revoked';
  get diagnostics rc = row_count;
  perform set_config('role','none',true);
  insert into rls_results values
    (9,'self-invite denied','denied',outcome,(outcome='denied'));
  insert into rls_results values
    (10,'non-admin cannot modify allowlist','0',rc::text,(rc = 0));
end $$;

do $$
declare rc int;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-00000000000a","email":"rlstest.a@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  select count(*) into rc from public.beta_testers;
  perform set_config('role','none',true);
  insert into rls_results values
    (11,'allowlist read shows own row only','1',rc::text,(rc = 1));
end $$;

-- ═══ CHECK 6: anonymous access fully denied ════════════════════════════
do $$
declare outcome text; rc int;
begin
  perform set_config('role','anon',true);
  begin
    select count(*) into rc from public.profiles;
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  perform set_config('role','none',true);
  insert into rls_results values
    (12,'anon cannot read profiles','denied',outcome,(outcome='denied'));
end $$;

-- ═══ CHECK 7: revoked user — update blocked, deletion request allowed ══
do $$
declare rc int; flag boolean;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"d0000000-0000-4000-8000-00000000000d","email":"rlstest.d@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  update public.profiles set display_name = 'x' where id = auth.uid();
  get diagnostics rc = row_count;
  perform public.request_account_deletion();
  select deletion_requested_at is not null into flag
    from public.profiles where id = auth.uid();
  perform set_config('role','none',true);
  insert into rls_results values
    (13,'revoked user cannot update profile','0',rc::text,(rc = 0));
  insert into rls_results values
    (14,'revoked user can request deletion','true',flag::text,(flag = true));
end $$;

-- ═══ RESULTS ═══════════════════════════════════════════════════════════
select n, check_name, expected, actual, pass
  from rls_results order by n;

-- Everything above is discarded — test users, allowlist rows, results.
rollback;
