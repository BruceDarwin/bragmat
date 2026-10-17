-- Stage 4C-1: Cloud backup storage — private `backups` bucket,
-- owner-isolated via storage.objects RLS, plus an audit table written by
-- the delete-backups Edge Function (supabase/functions/delete-backups).
--
-- Depends on 0001_beta_access.sql (public.is_approved_beta()).
-- Apply via Supabase dashboard SQL editor or `supabase db push`.
-- Idempotent: safe to re-run. ROLLBACK: procedure at the bottom of this
-- file — note that FILES and the BUCKET are removed via the Storage
-- API/dashboard, never by deleting storage.* rows directly (SQL metadata
-- deletion orphans physical objects).
--
-- Security model:
--   * `backups` is a PRIVATE bucket — no public URLs, no anon access;
--     downloads via the authenticated storage API only.
--   * Object keys are `{auth.uid()}/<filename>.bzp`; every policy
--     requires the first path segment to equal the caller's uid AND
--     is_approved_beta(). Revoked testers lose ordinary storage access
--     server-side, matching the profiles precedent in 0001.
--   * Objects hold AEAD ciphertext (BRGZ envelope) only — bucket
--     contents are unintelligible to the platform and to admins.
--   * NO UPDATE policy: the app uploads with upsert:false (identical
--     names fail rather than overwrite) and never renames/moves objects.
--     Least privilege — UPDATE can be re-added by a later migration if
--     resumable-upload finalisation ever needs it.
--   * Deletion of one's own backups goes through the delete-backups
--     Edge Function, which authenticates the caller, restricts deletion
--     to the caller's uid prefix, uses the Storage API (service role,
--     server-side only) so physical objects are actually removed, and
--     works for revoked users for account closure.

-- ── Bucket ────────────────────────────────────────────────────────────────
-- file_size_limit NULL → inherits the project global limit (50 MB on the
-- Free plan). allowed_mime_types NULL → ciphertext has no meaningful
-- MIME type; restrict nothing at the bucket level.
insert into storage.buckets (id, name, public)
values ('backups', 'backups', false)
on conflict (id) do nothing;

-- ── Policies ──────────────────────────────────────────────────────────────
-- One policy per operation for auditability. Identical predicate
-- throughout: bucket = 'backups', first path segment = caller's uid,
-- caller currently approved for beta.

drop policy if exists "backups read own prefix" on storage.objects;
create policy "backups read own prefix"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_approved_beta()
  );

drop policy if exists "backups insert own prefix" on storage.objects;
create policy "backups insert own prefix"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_approved_beta()
  );

drop policy if exists "backups delete own prefix" on storage.objects;
create policy "backups delete own prefix"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_approved_beta()
  );

-- ── Deletion audit ────────────────────────────────────────────────────────
-- Written only by the delete-backups Edge Function via the service role
-- (which bypasses RLS). No INSERT grant is given to app roles.
-- Holds counts and uids only — never filenames, sizes or content.
create table if not exists public.backup_deletion_audit (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id),
  deleted_count integer not null,
  reason        text not null default 'user_request'
                check (reason in ('user_request', 'account_closure')),
  created_at    timestamptz not null default now()
);
alter table public.backup_deletion_audit enable row level security;

-- Users may read their own audit rows (transparency); nobody else.
drop policy if exists "audit read own rows" on public.backup_deletion_audit;
create policy "audit read own rows"
  on public.backup_deletion_audit for select to authenticated
  using (user_id = auth.uid());

grant select on public.backup_deletion_audit to authenticated;
-- Deliberately no insert/update/delete grants for app roles.

-- ── ROLLBACK (exact procedure — review, then execute in order) ────────────
-- Order matters: objects must be emptied through the Storage API BEFORE
-- the bucket is removed, and the bucket must be removed through the
-- Storage API/dashboard — never by deleting storage.* rows directly.
--
-- STEP 1 — Empty the bucket through the Storage API:
--   Dashboard → Storage → backups → select all files → Delete, or:
--   for each user prefix, call the delete-backups Edge Function while it
--   is still deployed, or an admin uses a service-role client:
--       storage.from('backups').remove(['<uid>/<file>.bzp', ...])
--
-- STEP 2 — Delete the bucket through the Storage API:
--   Dashboard → Storage → backups → Delete bucket, or service-role:
--       storage.deleteBucket('backups')   (requires the bucket be empty)
--
-- STEP 3 — Remove the schema objects with SQL:
--   drop policy if exists "backups delete own prefix" on storage.objects;
--   drop policy if exists "backups insert own prefix" on storage.objects;
--   drop policy if exists "backups read own prefix"   on storage.objects;
--   drop policy if exists "audit read own rows"
--     on public.backup_deletion_audit;
--   drop table if exists public.backup_deletion_audit;
--
-- STEP 4 — Delete the Edge Function:
--   supabase functions delete delete-backups  (or dashboard)
