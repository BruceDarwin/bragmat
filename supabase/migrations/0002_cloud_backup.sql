-- Stage 4C-1: Cloud backup storage — private `backups` bucket,
-- owner-isolated via storage.objects RLS, plus a security-definer RPC so
-- a user (including a revoked tester) can remove their own backup
-- objects for account closure.
--
-- Depends on 0001_beta_access.sql (public.is_approved_beta()).
-- Apply via Supabase dashboard SQL editor or `supabase db push`.
-- Idempotent: safe to re-run. ROLLBACK: exact procedure in the commented
-- block at the bottom of this file.
--
-- Security model:
--   * `backups` is a PRIVATE bucket — no public URLs, no anon access,
--     downloads via the authenticated storage API only.
--   * Object keys are `{auth.uid()}/<filename>.bzp`; every policy
--     requires the first path segment to equal the caller's uid AND
--     is_approved_beta(). Revoked testers lose ordinary storage access
--     server-side, matching the profiles precedent in 0001.
--   * Objects hold AEAD ciphertext (BRGZ envelope) only — bucket
--     contents are unintelligible to the platform and to admins.
--   * UPDATE is granted so retries/metadata updates are possible, still
--     scoped to the caller's own prefix. The app uploads with
--     upsert: false — identical names fail rather than overwrite.
--   * delete_own_backups() deliberately does NOT check
--     is_approved_beta(): a revoked user must still be able to remove
--     their cloud backups (account closure), even though all ordinary
--     storage access is denied to them. It can only ever touch objects
--     under the caller's own uid prefix.
--     Caveat: deleting storage.objects rows removes the records and all
--     API access; residual object bytes on the storage backend are
--     reclaimed only via the Storage API/dashboard. Acceptable here
--     because every object is ciphertext — noted for completeness.

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

drop policy if exists "backups update own prefix" on storage.objects;
create policy "backups update own prefix"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_approved_beta()
  )
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

-- ── delete_own_backups() ──────────────────────────────────────────────────
-- Removes every `backups` object under the caller's own uid prefix and
-- returns the number of records deleted. SECURITY DEFINER so it works
-- for revoked users whose ordinary storage access is gone. Granted to
-- `authenticated` — any signed-in user may delete their own backups at
-- any time; it can never reach another user's prefix.
create or replace function public.delete_own_backups()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare n int;
begin
  delete from storage.objects
   where bucket_id = 'backups'
     and (storage.foldername(name))[1] = auth.uid()::text;
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.delete_own_backups() from public, anon;
grant execute on function public.delete_own_backups() to authenticated;

-- ── ROLLBACK (exact procedure — review, then run manually if needed) ──────
-- Paste this block into the SQL editor. It removes the RPC, the four
-- policies, every recorded object under the bucket, and the bucket row.
-- Residual bytes on the storage backend (if any) are reclaimed via the
-- Storage API/dashboard.
--
--   revoke execute on function public.delete_own_backups()
--     from authenticated;
--   drop function if exists public.delete_own_backups();
--
--   drop policy if exists "backups delete own prefix" on storage.objects;
--   drop policy if exists "backups update own prefix" on storage.objects;
--   drop policy if exists "backups insert own prefix" on storage.objects;
--   drop policy if exists "backups read own prefix"   on storage.objects;
--
--   delete from storage.objects where bucket_id = 'backups';
--   delete from storage.buckets where id = 'backups';
