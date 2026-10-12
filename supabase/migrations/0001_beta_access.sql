-- Stage 4A: Beta access control — server-enforced invitation allowlist.
-- Apply via Supabase dashboard SQL editor or `supabase db push`.
--
-- Security model:
--   * Only the anon key ships in the app; ALL enforcement is Postgres-side.
--   * Any user can create an auth account, but only allowlisted emails can
--     create a profile (profiles insert policy) and pass is_approved_beta().
--   * Admins (rows in `admins`) manage the allowlist via the dashboard.
--   * status='revoked' blocks approval and is detected by the app's
--     entitlement re-check on next online launch.

create extension if not exists citext;

-- ── beta_testers ──────────────────────────────────────────────────────────
create table if not exists public.beta_testers (
  id          uuid primary key default gen_random_uuid(),
  email       citext not null unique,
  invited_by  uuid references auth.users (id),
  invited_at  timestamptz not null default now(),
  status      text not null default 'invited'
              check (status in ('invited', 'active', 'revoked')),
  notes       text
);
alter table public.beta_testers enable row level security;

-- ── admins ────────────────────────────────────────────────────────────────
create table if not exists public.admins (
  user_id uuid primary key references auth.users (id)
);
alter table public.admins enable row level security;

create policy "admins read own row"
  on public.admins for select to authenticated
  using (user_id = auth.uid());

-- Allowlist: a user may check whether THEIR OWN email is listed;
-- admins can read and modify everything.
create policy "users check own beta status"
  on public.beta_testers for select to authenticated
  using (email = (auth.jwt() ->> 'email'));

create policy "admins manage testers"
  on public.beta_testers for all to authenticated
  using (exists (select 1 from public.admins where user_id = auth.uid()))
  with check (exists (select 1 from public.admins where user_id = auth.uid()));

-- ── is_approved_beta ──────────────────────────────────────────────────────
-- Security-definer so authenticated callers can test their own email
-- against the allowlist without needing broad read access.
create or replace function public.is_approved_beta()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.beta_testers
    where email = (auth.jwt() ->> 'email')::citext
      and status in ('invited', 'active')
  );
$$;

revoke all on function public.is_approved_beta() from public;
grant execute on function public.is_approved_beta() to authenticated;

-- ── profiles ──────────────────────────────────────────────────────────────
create table if not exists public.profiles (
  id                     uuid primary key references auth.users (id)
                         on delete cascade,
  email                  citext not null,
  display_name           text,
  created_at             timestamptz not null default now(),
  last_seen_at           timestamptz,
  deletion_requested_at  timestamptz
);
alter table public.profiles enable row level security;

create policy "users read own profile"
  on public.profiles for select to authenticated
  using (id = auth.uid());

create policy "users update own profile"
  on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Server-enforced invitation: a profile row can only be created while the
-- caller's email is on the beta allowlist.
create policy "profiles insert only for approved testers"
  on public.profiles for insert to authenticated
  with check (id = auth.uid() and public.is_approved_beta());
