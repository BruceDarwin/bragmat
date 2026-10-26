-- WT2: WorldTides proxy usage accounting — credit budgets for the
-- worldtides-proxy Edge Function (supabase/functions/worldtides-proxy).
--
-- Depends on 0001_beta_access.sql (public.admins). Apply via the Supabase
-- dashboard SQL editor or `supabase db push`. Idempotent: safe to re-run.
--
-- Security model:
--   * These tables are NEVER touched by app roles. The Edge Function is
--     the only writer, via the service role; the only reads granted to
--     clients are administrator SELECTs.
--   * worldtides_reserve_credit / worldtides_release_credit are
--     SECURITY DEFINER with search_path='' and execute granted to
--     service_role ONLY — an authenticated client cannot call them
--     directly, so a compromised client cannot mint, inflate or drain
--     counters; it can only hit the proxy, which applies entitlement +
--     validation + quotas on every call.
--   * No fishing coordinates are stored anywhere server-side. The
--     counters are (user_id, cycle, credits) only.
--
-- Subscription-cycle alignment:
--   Counters are keyed by a `cycle` label derived from
--   worldtides_config.cycle_anchor_day — the day-of-month the WorldTides
--   subscription renews (set it after deploy:
--     update public.worldtides_config set value='15'
--       where key='cycle_anchor_day';).
--   The cycle label is the DATE on which the current billing cycle
--   started (e.g. anchor 15 → '2026-10-15' … '2026-11-14'). Changing the
--   anchor automatically starts a fresh counter row — old rows remain as
--   an audit trail.

-- ── Config ─────────────────────────────────────────────────────────────

create table if not exists public.worldtides_config (
  key   text primary key,
  value text not null
);
alter table public.worldtides_config enable row level security;

insert into public.worldtides_config (key, value) values
  ('per_user_cycle_limit', '40'),   -- credits per user per cycle
  ('global_cycle_limit',   '15000'),-- circuit breaker below the 20k plan
  ('cycle_anchor_day',     '1')     -- day-of-month the subscription renews
on conflict (key) do nothing;

-- ── Counters ───────────────────────────────────────────────────────────

create table if not exists public.worldtides_usage (
  user_id    uuid not null references auth.users (id) on delete cascade,
  cycle      date not null,
  credits    integer not null default 0 check (credits >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, cycle)
);
alter table public.worldtides_usage enable row level security;

create table if not exists public.worldtides_budget_global (
  cycle      date primary key,
  credits    integer not null default 0 check (credits >= 0),
  updated_at timestamptz not null default now()
);
alter table public.worldtides_budget_global enable row level security;

-- Administrator-only read access to usage statistics.
drop policy if exists "admins read worldtides usage"
  on public.worldtides_usage;
create policy "admins read worldtides usage"
  on public.worldtides_usage for select to authenticated
  using (exists (select 1 from public.admins where user_id = auth.uid()));

drop policy if exists "admins read worldtides global budget"
  on public.worldtides_budget_global;
create policy "admins read worldtides global budget"
  on public.worldtides_budget_global for select to authenticated
  using (exists (select 1 from public.admins where user_id = auth.uid()));

drop policy if exists "admins read worldtides config"
  on public.worldtides_config;
create policy "admins read worldtides config"
  on public.worldtides_config for select to authenticated
  using (exists (select 1 from public.admins where user_id = auth.uid()));

-- ── Cycle helper ───────────────────────────────────────────────────────
-- Current subscription-cycle start date for a given anchor day-of-month.
create or replace function public.worldtides_cycle_start(p_anchor_day int)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when extract(day from now())::int >= p_anchor_day
      then make_date(extract(year from now())::int,
                     extract(month from now())::int,
                     least(p_anchor_day,
                       extract(day from (date_trunc('month', now())
                         + interval '1 month' - interval '1 day'))::int))
    else make_date(
           extract(year from (now() - interval '1 month'))::int,
           extract(month from (now() - interval '1 month'))::int,
           least(p_anchor_day,
             extract(day from (date_trunc('month', now()))
               - interval '1 day')::int))
  end;
$$;

revoke all on function public.worldtides_cycle_start(int)
  from public, anon, authenticated;

-- ── worldtides_reserve_credit(p_user) ──────────────────────────────────
-- Atomically reserves one credit for p_user in the current cycle.
-- Returns 'ok' | 'user_quota' | 'global_quota'.
--
-- Atomicity: each conditional upsert holds the row lock, so concurrent
-- callers serialize on the (user, cycle) and cycle rows — a burst of
-- parallel requests cannot overdraw either counter. The whole function
-- runs in one transaction; a mid-function failure rolls back everything.
create or replace function public.worldtides_reserve_credit(p_user uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_limit   int;
  v_global_limit int;
  v_anchor       int;
  v_cycle        date;
begin
  select value::int into v_user_limit
    from public.worldtides_config where key = 'per_user_cycle_limit';
  select value::int into v_global_limit
    from public.worldtides_config where key = 'global_cycle_limit';
  select value::int into v_anchor
    from public.worldtides_config where key = 'cycle_anchor_day';
  v_user_limit   := coalesce(v_user_limit, 40);
  v_global_limit := coalesce(v_global_limit, 15000);
  v_anchor       := greatest(1, least(31, coalesce(v_anchor, 1)));
  v_cycle        := public.worldtides_cycle_start(v_anchor);

  -- Per-user reservation: guarded increment — the WHERE clause is
  -- evaluated under the row lock, so the cap can never be exceeded.
  insert into public.worldtides_usage (user_id, cycle, credits)
    values (p_user, v_cycle, 1)
  on conflict (user_id, cycle) do update
      set credits    = public.worldtides_usage.credits + 1,
          updated_at = now()
      where public.worldtides_usage.credits < v_user_limit;

  if not found then
    return 'user_quota';
  end if;

  -- Global reservation, same pattern.
  insert into public.worldtides_budget_global (cycle, credits)
    values (v_cycle, 1)
  on conflict (cycle) do update
      set credits    = public.worldtides_budget_global.credits + 1,
          updated_at = now()
      where public.worldtides_budget_global.credits < v_global_limit;

  if not found then
    -- Keep the two counters consistent — undo the user reservation.
    update public.worldtides_usage
       set credits    = credits - 1,
           updated_at = now()
     where user_id = p_user and cycle = v_cycle;
    return 'global_quota';
  end if;

  return 'ok';
end;
$$;

revoke all on function public.worldtides_reserve_credit(uuid)
  from public, anon, authenticated;
grant execute on function public.worldtides_reserve_credit(uuid)
  to service_role;

-- ── worldtides_release_credit(p_user) ──────────────────────────────────
-- Releases one previously reserved credit — used only when WorldTides
-- explicitly reports the upstream call as unbilled (callCount = 0).
-- Floors at zero; never goes negative under retry races.
create or replace function public.worldtides_release_credit(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anchor int;
  v_cycle  date;
begin
  select value::int into v_anchor
    from public.worldtides_config where key = 'cycle_anchor_day';
  v_anchor := greatest(1, least(31, coalesce(v_anchor, 1)));
  v_cycle  := public.worldtides_cycle_start(v_anchor);

  update public.worldtides_usage
     set credits    = greatest(0, credits - 1),
         updated_at = now()
   where user_id = p_user and cycle = v_cycle;

  update public.worldtides_budget_global
     set credits    = greatest(0, credits - 1),
         updated_at = now()
   where cycle = v_cycle;
end;
$$;

revoke all on function public.worldtides_release_credit(uuid)
  from public, anon, authenticated;
grant execute on function public.worldtides_release_credit(uuid)
  to service_role;

-- ── Grants ─────────────────────────────────────────────────────────────
-- Locked-down project (explicit grants only): clients get SELECT through
-- the admin-gated policies above; the Edge Function writes via
-- service_role.
revoke all on public.worldtides_usage,
              public.worldtides_budget_global,
              public.worldtides_config
  from anon, authenticated;

grant select on public.worldtides_usage,
                public.worldtides_budget_global,
                public.worldtides_config
  to authenticated;

grant select, insert, update on public.worldtides_usage,
                                public.worldtides_budget_global
  to service_role;
grant select on public.worldtides_config to service_role;

-- ── ROLLBACK (exact procedure — review, then execute in order) ─────────
--   revoke execute on function public.worldtides_release_credit(uuid)
--     from service_role;
--   revoke execute on function public.worldtides_reserve_credit(uuid)
--     from service_role;
--   drop function if exists public.worldtides_release_credit(uuid);
--   drop function if exists public.worldtides_reserve_credit(uuid);
--   drop function if exists public.worldtides_cycle_start(int);
--   drop table if exists public.worldtides_usage;
--   drop table if exists public.worldtides_budget_global;
--   drop table if exists public.worldtides_config;
--   Delete the Edge Function:
--     supabase functions delete worldtides-proxy  (or dashboard)
