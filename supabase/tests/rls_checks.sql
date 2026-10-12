-- Stage 4A — RLS / allowlist verification script for bragmat-dev.
-- Run sections individually in the Supabase SQL Editor. Every check is
-- inside a transaction that is rolled back, so nothing persists.
--
-- PREREQUISITE — create test users under Authentication → Users →
-- "Add user → Create new user":
--   USER_A  verified@example.com    Auto Confirm ON   + add email to
--                                    beta_testers (status='invited')
--   USER_B  uninvited@example.com   Auto Confirm ON   (NOT allowlisted)
--   USER_C  unverified@example.com  Auto Confirm OFF  (email stays
--                                    unverified; optionally allowlisted
--                                    to prove verification is required)
--   USER_D  revoked@example.com     Auto Confirm ON   + add email to
--                                    beta_testers (status='revoked')
-- Substitute real UUIDs/emails below (Authentication → Users lists them).
--
-- NOTE: is_approved_beta() reads auth.users, so function checks need
-- REAL accounts; request.jwt.claims only supplies the caller identity.

-- ════════════════════════════════════════════════════════════════════
-- CHECK 1 — approved + verified user passes; uninvited, unverified and
--           revoked users all fail
-- ════════════════════════════════════════════════════════════════════
begin;
set local role authenticated;

-- USER_A (invited + verified) — expect TRUE
set local request.jwt.claims =
  '{"sub":"<USER_A_UUID>","email":"verified@example.com","role":"authenticated","aud":"authenticated"}';
select public.is_approved_beta() as user_a_expected_true;

-- USER_B (verified, NOT allowlisted) — expect FALSE
set local request.jwt.claims =
  '{"sub":"<USER_B_UUID>","email":"uninvited@example.com","role":"authenticated","aud":"authenticated"}';
select public.is_approved_beta() as user_b_expected_false;

-- USER_C (allowlisted but email UNVERIFIED) — expect FALSE
set local request.jwt.claims =
  '{"sub":"<USER_C_UUID>","email":"unverified@example.com","role":"authenticated","aud":"authenticated"}';
select public.is_approved_beta() as user_c_expected_false;

-- USER_D (allowlisted but revoked) — expect FALSE
set local request.jwt.claims =
  '{"sub":"<USER_D_UUID>","email":"revoked@example.com","role":"authenticated","aud":"authenticated"}';
select public.is_approved_beta() as user_d_expected_false;
rollback;

-- ════════════════════════════════════════════════════════════════════
-- CHECK 2 — uninvited user cannot create a profile (RLS denies it)
-- ════════════════════════════════════════════════════════════════════
begin;
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"<USER_B_UUID>","email":"uninvited@example.com","role":"authenticated","aud":"authenticated"}';
-- expect: ERROR 42501 row-level security violation
insert into public.profiles (id, email)
  values (auth.uid(), 'uninvited@example.com');
rollback;

-- ════════════════════════════════════════════════════════════════════
-- CHECK 3 — profile email cannot differ from the caller's email
-- ════════════════════════════════════════════════════════════════════
begin;
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"<USER_A_UUID>","email":"verified@example.com","role":"authenticated","aud":"authenticated"}';
-- expect: ERROR 42501 — mismatched email rejected by WITH CHECK
insert into public.profiles (id, email)
  values (auth.uid(), 'spoofed@example.com');
rollback;

-- ════════════════════════════════════════════════════════════════════
-- CHECK 4 — user cannot read or modify another user's profile
-- ════════════════════════════════════════════════════════════════════
begin;
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"<USER_A_UUID>","email":"verified@example.com","role":"authenticated","aud":"authenticated"}';
-- expect: 0 rows (not an error — other users' rows are invisible)
select id, email from public.profiles where id = '<USER_B_UUID>';
-- expect: 0 rows updated
update public.profiles set display_name = 'hijack' where id = '<USER_B_UUID>';
rollback;

-- ════════════════════════════════════════════════════════════════════
-- CHECK 5 — non-admin cannot invite themselves or alter the allowlist
-- ════════════════════════════════════════════════════════════════════
begin;
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"<USER_A_UUID>","email":"verified@example.com","role":"authenticated","aud":"authenticated"}';
-- expect: ERROR 42501 row-level security violation
insert into public.beta_testers (email) values ('selfinvited@example.com');
-- expect: ERROR 42501 (or 0 rows on some PostgREST versions)
update public.beta_testers set status = 'active';
-- expect: only the caller's own row (if allowlisted), never the full list
select email, status from public.beta_testers;
rollback;

-- ════════════════════════════════════════════════════════════════════
-- CHECK 6 — anonymous/unauthenticated access is fully denied
-- ════════════════════════════════════════════════════════════════════
begin;
set local role anon;
-- expect: ERROR — permission denied (no grants to anon)
select * from public.profiles;
rollback;

-- ════════════════════════════════════════════════════════════════════
-- CHECK 7 — revoked user cannot update profile but CAN request deletion
-- ════════════════════════════════════════════════════════════════════
begin;
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"<USER_D_UUID>","email":"revoked@example.com","role":"authenticated","aud":"authenticated"}';
-- expect: 0 rows updated (RLS blocks update for non-approved users)
update public.profiles set display_name = 'x' where id = auth.uid();
-- expect: succeeds — sets deletion_requested_at on own profile
select public.request_account_deletion();
rollback;
