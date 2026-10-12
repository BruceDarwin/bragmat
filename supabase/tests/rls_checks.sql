-- ────────────────────────────────────────────────────────────────────────
-- Stage 4A — RLS / allowlist verification for bragmat-dev
--
-- HOW TO RUN: paste this ENTIRE file into the Supabase SQL Editor as one
-- query and press Run. It executes in a single transaction that ends in
-- ROLLBACK — test users are created and discarded, nothing persists.
--
-- READING RESULTS: each check states its expectation inline.
--   * For SELECT checks the PASS value is printed.
--   * For denied operations the PASS signal is the annotated ERROR
--     (e.g. "ERROR: new row violates row-level security policy…").
--     A savepoint restores the transaction after each expected error,
--     so the script keeps running to the end. If a denied statement
--     instead reports success (INSERT/UPDATE n rows), that check FAILS.
--
-- AUTH NOTE: auth.users rows are inserted directly — they need to exist
-- for is_approved_beta() to join against. These users can never log in
-- (no identities rows, empty password) and are rolled back anyway.
-- ────────────────────────────────────────────────────────────────────────

begin;

-- ═══ SETUP: four test users covering every state ═══════════════════════
-- A = invited + verified   B = verified but NOT invited
-- C = invited + unverified D = invited but status='revoked'
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

-- D gets a profile (created while they were still approved)
insert into public.profiles (id, email) values
  ('d0000000-0000-4000-8000-00000000000d', 'rlstest.d@bragmat.invalid');

-- ═══ CHECK 1: is_approved_beta() across all four states ════════════════
set local role authenticated;

set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-00000000000a","email":"rlstest.a@bragmat.invalid","role":"authenticated","aud":"authenticated"}';
select public.is_approved_beta() as check1_a_expect_TRUE;   -- PASS: t

set local request.jwt.claims = '{"sub":"b0000000-0000-4000-8000-00000000000b","email":"rlstest.b@bragmat.invalid","role":"authenticated","aud":"authenticated"}';
select public.is_approved_beta() as check1_b_expect_FALSE;  -- PASS: f

set local request.jwt.claims = '{"sub":"c0000000-0000-4000-8000-00000000000c","email":"rlstest.c@bragmat.invalid","role":"authenticated","aud":"authenticated"}';
select public.is_approved_beta() as check1_c_expect_FALSE;  -- PASS: f

set local request.jwt.claims = '{"sub":"d0000000-0000-4000-8000-00000000000d","email":"rlstest.d@bragmat.invalid","role":"authenticated","aud":"authenticated"}';
select public.is_approved_beta() as check1_d_expect_FALSE;  -- PASS: f

-- ═══ CHECK 2: uninvited user cannot create a profile ═══════════════════
set local request.jwt.claims = '{"sub":"b0000000-0000-4000-8000-00000000000b","email":"rlstest.b@bragmat.invalid","role":"authenticated","aud":"authenticated"}';
savepoint c2;
insert into public.profiles (id, email)
  values (auth.uid(), 'rlstest.b@bragmat.invalid');          -- PASS: ERROR 42501
rollback to savepoint c2;

-- ═══ CHECK 3: approved user cannot spoof a different email ═════════════
set local request.jwt.claims = '{"sub":"a0000000-0000-4000-8000-00000000000a","email":"rlstest.a@bragmat.invalid","role":"authenticated","aud":"authenticated"}';
savepoint c3;
insert into public.profiles (id, email)
  values (auth.uid(), 'spoofed@bragmat.invalid');            -- PASS: ERROR 42501
rollback to savepoint c3;

-- ═══ CHECK 4: approved user CAN create own profile; cannot touch others ═
insert into public.profiles (id, email)
  values (auth.uid(), 'rlstest.a@bragmat.invalid');          -- PASS: INSERT 0 1
select id, email from public.profiles
  where id = 'b0000000-0000-4000-8000-00000000000b';          -- PASS: 0 rows
update public.profiles set display_name = 'hijack'
  where id = 'b0000000-0000-4000-8000-00000000000b';          -- PASS: UPDATE 0

-- ═══ CHECK 5: non-admin cannot self-invite or modify the allowlist ═════
savepoint c5a;
insert into public.beta_testers (email)
  values ('selfinvite@bragmat.invalid');                     -- PASS: ERROR 42501
rollback to savepoint c5a;

update public.beta_testers set status = 'revoked';           -- PASS: UPDATE 0
select email, status from public.beta_testers;               -- PASS: only own row

-- ═══ CHECK 6: anonymous access fully denied ════════════════════════════
savepoint c6;
set local role anon;
select * from public.profiles;                               -- PASS: permission denied
rollback to savepoint c6;
set local role authenticated;

-- ═══ CHECK 7: revoked user — profile update blocked, deletion allowed ══
set local request.jwt.claims = '{"sub":"d0000000-0000-4000-8000-00000000000d","email":"rlstest.d@bragmat.invalid","role":"authenticated","aud":"authenticated"}';
update public.profiles set display_name = 'x'
  where id = auth.uid();                                     -- PASS: UPDATE 0
select public.request_account_deletion();                    -- PASS: succeeds
select deletion_requested_at is not null as check7_flag_set_expect_TRUE
  from public.profiles where id = auth.uid();                -- PASS: t

-- ═══ DONE — everything above is discarded ══════════════════════════════
rollback;
