-- ────────────────────────────────────────────────────────────────────────
-- WT2 — worldtides-proxy quota / privilege verification for bragmat-dev
--
-- HOW TO RUN: after applying 0003_worldtides_proxy.sql, paste this ENTIRE
-- file into the Supabase SQL Editor as one query and press Run. The
-- script:
--   * creates disposable test users inside a transaction,
--   * exercises worldtides_reserve_credit / worldtides_release_credit,
--   * verifies role restrictions (clients cannot call or see them),
--   * prints a single PASS/FAIL results table at the end,
--   * ends in ROLLBACK — nothing persists, nothing needs editing.
--
-- PASS column should be true for every row.
-- ────────────────────────────────────────────────────────────────────────

begin;

-- ═══ SETUP ═════════════════════════════════════════════════════════════
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000',
   'e0000000-0000-4000-8000-00000000000e',
   'authenticated', 'authenticated', 'qttest.user@bragmat.invalid', '',
   now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   'f0000000-0000-4000-8000-00000000000f',
   'authenticated', 'authenticated', 'qttest.admin@bragmat.invalid', '',
   now(), now(), now());

insert into public.admins (user_id) values
  ('f0000000-0000-4000-8000-00000000000f');

-- Shrink limits inside the transaction so quota paths are reachable.
update public.worldtides_config set value = '3'
  where key = 'per_user_cycle_limit';
update public.worldtides_config set value = '5'
  where key = 'global_cycle_limit';

create temp table wt_results(
  n int, check_name text, expected text, actual text, pass boolean
);

-- ═══ CHECK 1: reservation increments user + global counters ═══════════
do $$
declare r text; u int; g int;
begin
  r := public.worldtides_reserve_credit(
         'e0000000-0000-4000-8000-00000000000e');
  select credits into u from public.worldtides_usage
    where user_id = 'e0000000-0000-4000-8000-00000000000e';
  select credits into g from public.worldtides_budget_global
    order by cycle desc limit 1;
  insert into wt_results values
    (1,'first reservation ok','ok',r,(r = 'ok')),
    (2,'user counter incremented','1',u::text,(u = 1)),
    (3,'global counter incremented','1',g::text,(g = 1));
end $$;

-- ═══ CHECK 2: per-user cap enforced atomically ════════════════════════
do $$
declare r text; u int;
begin
  perform public.worldtides_reserve_credit(
            'e0000000-0000-4000-8000-00000000000e');
  perform public.worldtides_reserve_credit(
            'e0000000-0000-4000-8000-00000000000e');
  -- user is now at limit 3; next must fail and leave counters untouched
  r := public.worldtides_reserve_credit(
         'e0000000-0000-4000-8000-00000000000e');
  select credits into u from public.worldtides_usage
    where user_id = 'e0000000-0000-4000-8000-00000000000e';
  insert into wt_results values
    (4,'over-limit reservation refused','user_quota',r,(r='user_quota')),
    (5,'user counter unchanged on refusal','3',u::text,(u = 3));
end $$;

-- ═══ CHECK 3: global cap keeps counters consistent ════════════════════
do $$
declare r text; u int;
begin
  -- global limit is 5, already consumed 3 by user e. Second user can
  -- reserve twice, then must hit 'global_quota' with no partial state.
  perform public.worldtides_reserve_credit(
            'f0000000-0000-4000-8000-00000000000f');
  perform public.worldtides_reserve_credit(
            'f0000000-0000-4000-8000-00000000000f');
  r := public.worldtides_reserve_credit(
         'f0000000-0000-4000-8000-00000000000f');
  select credits into u from public.worldtides_usage
    where user_id = 'f0000000-0000-4000-8000-00000000000f';
  insert into wt_results values
    (6,'global limit refusal','global_quota',r,(r='global_quota')),
    (7,'user reservation rolled back on global refusal','2',u::text,(u=2));
end $$;

-- ═══ CHECK 4: release decrements and floors at zero ═══════════════════
do $$
declare u int; g int;
begin
  perform public.worldtides_release_credit(
            'e0000000-0000-4000-8000-00000000000e');
  select credits into u from public.worldtides_usage
    where user_id = 'e0000000-0000-4000-8000-00000000000e';
  select credits into g from public.worldtides_budget_global
    order by cycle desc limit 1;
  insert into wt_results values
    (8,'release decrements user counter','2',u::text,(u = 2)),
    (9,'release decrements global counter','4',g::text,(g = 4));
  -- floor at zero for a user with no reservations
  perform public.worldtides_release_credit(
            'f0000000-0000-4000-8000-00000000000f');
  perform public.worldtides_release_credit(
            'f0000000-0000-4000-8000-00000000000f');
  perform public.worldtides_release_credit(
            'f0000000-0000-4000-8000-00000000000f');
  select credits into u from public.worldtides_usage
    where user_id = 'f0000000-0000-4000-8000-00000000000f';
  insert into wt_results values
    (10,'release never goes negative','0',u::text,(u = 0));
end $$;

-- ═══ CHECK 5: clients cannot call the privileged functions ════════════
do $$
declare outcome text;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"e0000000-0000-4000-8000-00000000000e","email":"qttest.user@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  begin
    perform public.worldtides_reserve_credit(auth.uid());
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  perform set_config('role','none',true);
  insert into wt_results values
    (11,'authenticated cannot reserve credits','denied',outcome,
     (outcome='denied'));
end $$;

do $$
declare outcome text;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"e0000000-0000-4000-8000-00000000000e","email":"qttest.user@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  begin
    perform public.worldtides_release_credit(auth.uid());
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  perform set_config('role','none',true);
  insert into wt_results values
    (12,'authenticated cannot release credits','denied',outcome,
     (outcome='denied'));
end $$;

-- ═══ CHECK 6: usage stats are administrator-only ══════════════════════
do $$
declare rc int;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"e0000000-0000-4000-8000-00000000000e","email":"qttest.user@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  select count(*) into rc from public.worldtides_usage;
  perform set_config('role','none',true);
  insert into wt_results values
    (13,'non-admin sees no usage rows','0',rc::text,(rc = 0));
end $$;

do $$
declare rc int;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"f0000000-0000-4000-8000-00000000000f","email":"qttest.admin@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  select count(*) into rc from public.worldtides_usage;
  perform set_config('role','none',true);
  insert into wt_results values
    (14,'admin reads usage rows','2',rc::text,(rc = 2));
end $$;

do $$
declare outcome text;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"f0000000-0000-4000-8000-00000000000f","email":"qttest.admin@bragmat.invalid","role":"authenticated","aud":"authenticated"}',true);
  begin
    update public.worldtides_usage set credits = 0;
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  perform set_config('role','none',true);
  insert into wt_results values
    (15,'admin cannot write counters','denied',outcome,
     (outcome='denied'));
end $$;

do $$
declare outcome text; rc int := 0;
begin
  perform set_config('role','anon',true);
  begin
    select count(*) into rc from public.worldtides_usage;
    outcome := 'allowed';
  exception when insufficient_privilege then
    outcome := 'denied';
  end;
  perform set_config('role','none',true);
  insert into wt_results values
    (16,'anon cannot read usage','denied',outcome,(outcome='denied'));
end $$;

-- ═══ RESULTS ═══════════════════════════════════════════════════════════
select n, check_name, expected, actual, pass
  from wt_results order by n;

-- Everything above is discarded — test users, config edits, counters.
rollback;
