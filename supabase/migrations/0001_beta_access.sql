-- Stage 4A: Beta access control — server-enforced invitation allowlist.
-- Revised for the bragmat-dev project (automatic Data API exposure is
-- disabled, so all grants are explicit). Apply via Supabase dashboard
-- SQL editor or `supabase db push`. Idempotent: safe to re-run.
--
-- Security model:
--   * Only the publishable (anon) key ships in the app; ALL enforcement
--     is Postgres-side. The service_role key must never appear in the app.
--   * Beta approval requires BOTH an allowlist entry AND a verified
--     email (auth.users.email_confirmed_at) — the JWT email claim alone
--     is never trusted.
--   * Profile emails must equal the authenticated user's verified email.
--   * Uninvited users can create auth accounts but can read nothing,
--     create no profile and fail is_approved_beta().
--   * status='revoked' immediately blocks approval and all profile
--     writes; revoked users may still read their own profile and request
--     account deletion via the request_account_deletion() RPC.
--   * Only members of `admins` can manage the allowlist.

create extension if not exists citext;

-- ── Tables ────────────────────────────────────────────────────────────────

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

create table if not exists public.admins (
  user_id uuid primary key references auth.users (id)
);
alter table public.admins enable row level security;

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

-- ── is_approved_beta() ────────────────────────────────────────────────────
-- SECURITY DEFINER hardening per Supabase guidance:
--   * set search_path = '' and fully qualify every object — prevents
--     search-path hijacking of unqualified names.
--   * stable (read-only), single pre-computed expression.
--   * reads auth.users so approval requires a VERIFIED email —
--     (auth.jwt() ->> 'email') alone would accept an unverified claim.
--   * execute revoked from public/anon; granted to authenticated only.
create or replace function public.is_approved_beta()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from auth.users u
    join public.beta_testers t on t.email = u.email
    where u.id = auth.uid()
      and u.email_confirmed_at is not null
      and t.status in ('invited', 'active')
  );
$$;

revoke all on function public.is_approved_beta() from public, anon;
grant execute on function public.is_approved_beta() to authenticated;

-- ── request_account_deletion() ────────────────────────────────────────────
-- Any authenticated user may flag their own profile for deletion —
-- including revoked testers, whose profile UPDATE rights are otherwise
-- gone. Runs SECURITY DEFINER so it bypasses the update RLS for this
-- single audited write.
create or replace function public.request_account_deletion()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.profiles
     set deletion_requested_at = now()
   where id = auth.uid();
$$;

revoke all on function public.request_account_deletion() from public, anon;
grant execute on function public.request_account_deletion() to authenticated;

-- ── RLS policies ──────────────────────────────────────────────────────────

-- admins: members may read their own row (used by the app to detect
-- admin status). Nobody else can see the admin list; inserts are
-- performed manually via SQL by the project owner.
drop policy if exists "admins read own row" on public.admins;
create policy "admins read own row"
  on public.admins for select to authenticated
  using (user_id = auth.uid());

-- beta_testers: a user may check whether THEIR OWN email is listed —
-- nothing more. Only admins can enumerate or modify the allowlist.
drop policy if exists "users check own beta status" on public.beta_testers;
create policy "users check own beta status"
  on public.beta_testers for select to authenticated
  using (email = (auth.jwt() ->> 'email')::citext);

drop policy if exists "admins manage testers" on public.beta_testers;
create policy "admins manage testers"
  on public.beta_testers for all to authenticated
  using (exists (select 1 from public.admins where user_id = auth.uid()))
  with check (exists (select 1 from public.admins where user_id = auth.uid()));

-- profiles: read own row only. Revoked users keep read access (their
-- profile — including deletion_requested_at — remains visible to them
-- and to admins).
drop policy if exists "users read own profile" on public.profiles;
create policy "users read own profile"
  on public.profiles for select to authenticated
  using (id = auth.uid());

-- INSERT: server-enforced invitation AND email integrity — the stored
-- email must equal the caller's verified email claim. Unverified email
-- changes never reach the JWT, so this cannot be spoofed.
drop policy if exists "profiles insert only for approved testers"
  on public.profiles;
create policy "profiles insert only for approved testers"
  on public.profiles for insert to authenticated
  with check (
    id = auth.uid()
    and public.is_approved_beta()
    and email = (auth.jwt() ->> 'email')::citext
  );

-- UPDATE: requires active beta status (revoked users lose all write
-- access immediately, server-side) and preserves email integrity.
drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile"
  on public.profiles for update to authenticated
  using (
    id = auth.uid()
    and public.is_approved_beta()
    and email = (auth.jwt() ->> 'email')::citext
  )
  with check (
    id = auth.uid()
    and public.is_approved_beta()
    and email = (auth.jwt() ->> 'email')::citext
  );

-- No DELETE policy on profiles — users cannot delete their own row;
-- admins process deletions via the dashboard/service role.

-- ── Grants ────────────────────────────────────────────────────────────────
-- Automatic Data API exposure is disabled in this project, so grants are
-- explicit. A grant opens the table to the role in principle; every row
-- and operation is still governed by the RLS policies above.

revoke all on public.profiles, public.beta_testers, public.admins
  from anon, authenticated;

grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.beta_testers to authenticated;
grant select on public.admins to authenticated;
