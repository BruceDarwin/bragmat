# Stage 4 — User Accounts and Access Management

Architecture proposal for review. **No implementation until approved.**

Status: Draft — awaiting decisions listed in §8.

## 1. Goals

- Supabase authentication and user profiles.
- Invitation-only access for beta testers.
- Full offline operation after initial authentication.
- Secure ownership of catches, trips, photos, journal entries and fishing locations.
- Migration of existing local data to registered accounts.
- A foundation for cloud backup and Android↔iPhone synchronisation.
- Administrator capabilities for managing beta access.
- Integration with the existing ZIP backup/restore pipeline.

## 2. Core architectural decision: local-first

**Proposal: remain local-first. The on-device SQLite database stays the source of
truth for all app features. Supabase is a replication and identity layer, not a
query layer.**

Rationale:

- Every existing screen, query and service already works against sqflite.
  Cloud-first would require rewriting the data layer and would break offline use —
  unacceptable for a fishing app used on the water.
- Sync then becomes an additive subsystem (a `SyncService`) that pushes/pulls
  deltas in the background, rather than a rewrite.
- The hardened restore machinery (staging, recovery markers, launch recovery) is
  reused for both initial cloud pull and cloud-restore.

## 3. Supabase components

| Component | Use |
|---|---|
| `supabase_flutter` SDK | Auth, Postgres access, Storage, session persistence |
| Supabase Auth | Email + password (recommended for beta — see §8.2) |
| Postgres | `profiles`, `beta_testers`, synced entity tables |
| Storage | Private `media` bucket (photos), private `backups` bucket (ZIP archives) |
| Row Level Security | `owner_id = auth.uid()` on every user table; storage RLS mirrors it |
| Edge Functions (optional) | Invite administration, welcome emails |

**Key handling:** only the *anon* key and project URL ship in the app — they are
public by design; RLS enforces isolation. The *service_role* key is never shipped
or committed. Configuration via `--dart-define` / `.env`, consistent with the
existing secrets handling (e.g. the WorldTides key file is never committed).

## 4. Local database changes (schema v29)

Existing autoincrement `id` primary keys collide across devices, so synced
entities need stable UUIDs. Proposed additions to all user-owned tables
(`catches`, `fishing_trips`, `trip_journal`, `catch_media`, `trip_media`,
`journal_media`, `favourite_spots`, `fishing_buddies`, `lures`, `baits`,
`fish_types` for user-added types):

| Column | Type | Purpose |
|---|---|---|
| `uuid` | TEXT UNIQUE | Stable cross-device identity |
| `owner_id` | TEXT NULL | Supabase user UUID; NULL = pre-account local data |
| `updated_at` | TEXT | For delta sync and last-writer-wins conflict resolution |
| `deleted_at` | TEXT NULL | Tombstone — soft deletes propagate via sync |
| `dirty` | INTEGER DEFAULT 0 | Needs push; cleared on successful sync |

Migration v29: add columns, backfill `uuid` + `updated_at` for existing rows,
leave `owner_id` NULL until account link. All existing queries continue to work
unchanged (new columns are additive; deletes become tombstone writes in sync
scope only — see §8.4 decision on whether delete becomes soft-delete now or
per-table).

New local tables:

- `account_profile` — cached profile: `user_id`, `email`, `display_name`,
  `invited_at`, `linked_at`, last sync watermark.
- `sync_state` — per-table `last_pulled_at` watermarks for delta pull.

## 5. Feature design

### 5.1 Authentication

- `supabase_flutter` persists the session (secure storage); silent refresh on
  launch. App opens straight into normal use when a valid session exists.
- **Offline:** after the first successful sign-in the app is fully functional
  offline. Sign-in failures due to no connectivity are non-blocking for an
  existing session. Data access never depends on the network.
- Sign-out preserves local data; a second sign-in on the same device reconciles
  by `owner_id`.

### 5.2 Invitation-only beta (recommended: allowlist)

- Signup itself stays enabled, but a `beta_testers` table (email → invited_by,
  invited_at, status) gates access.
- On first authenticated launch, an RPC/`beta_testers` lookup runs. Not on the
  list → "awaiting invitation" screen, no data access.
- Alternative considered (§8.3): invite *codes* required to create the profile
  row, enforced by an RLS insert policy. Stricter (blocks uninvited profiles) but
  adds a code-distribution step and a failure mode if a code is typed wrong.

### 5.3 Ownership and security

- All writes stamp `owner_id = auth.uid()`; all sync reads are scoped by RLS
  `owner_id = auth.uid()`.
- Media uploads go to `media/{uid}/{relative path}` — object key embeds the
  owner; a storage RLS policy enforces it, and the existing relative-path media
  model maps directly onto it.
- Private buckets with signed URLs only. Nothing is public.

### 5.4 Local data migration

On first account link on a device that already has data:

1. Recommend (and offer) a ZIP backup first — the hardened pipeline gives a
   free, tested safety net.
2. Assign `owner_id` and backfill `uuid`/`updated_at` on all existing rows.
3. Initial bulk upload (rows then media) as a resumable job — per-entity,
   idempotent on `uuid` so retrying after interruption is safe.
4. Decision needed (§8.5): auto-upload everything vs. opt-in "move my data to
   the account" prompt.

### 5.5 Cloud backup (reuses the ZIP pipeline)

- `ZipBackupService` output uploads to `backups/{uid}/bragmat_backup_*.zip`.
- Restore = download → existing validate → restore → recovery pipeline unchanged.
- Manifest gains `owner_id` and `format` fields (version 2.1); the validator
  stays backwards-compatible with 2.0 archives.
- This is deliberately sequenced before full sync (§6): it delivers real
  cross-device value immediately at a fraction of the cost of sync.

### 5.6 Synchronisation

- **Push:** rows with `dirty = 1` upserted by `uuid` (idempotent); tombstoned
  rows send `deleted_at`.
- **Pull:** rows where `updated_at > last_pulled_at` applied locally.
- **Conflicts:** last-writer-wins on `updated_at` per row initially —
  acceptable for a single user across two devices. Manual resolution can be
  added later (§8.6).
- **Media:** content-addressed by relative path; upload-if-absent, matching the
  never-overwrite semantics already proven in media promotion.
- **Interruption safety:** every push/pull is idempotent; re-running converges.
- Runs on connectivity regain + app foreground; no background daemon needed for
  beta.

### 5.7 Administration

- `is_admin` flag (or `admins` allowlist table); admins bypass the beta gate.
- Admin screens in-app: list testers, add/remove invitations, view status.
  For earliest beta the Supabase dashboard can be used instead — decision §8.7.

## 6. Implementation phases

| Phase | Scope | Deliverable |
|---|---|---|
| 4A | Supabase project, schema v29 (uuid/owner/timestamps/dirty), auth + session persistence, beta-allowlist gate, profiles | Signed-in users, ownership stamped, still fully local |
| 4B | Cloud ZIP backup/restore via existing pipeline to private bucket | Working cross-device backup/restore |
| 4C | Delta sync engine (push/pull, tombstones, media upload/download) | Live Android↔iPhone sync |
| 4D | In-app admin console, invite management, polish | Beta-management UI |

Each phase is independently testable and shippable; 4A is mandatory groundwork,
4B is high-value/low-risk, 4C is the large one, 4D can overlap 4C.

## 7. Risks

- **Schema migration** — v29 touches every user table; needs the same rigor as
  the restore work (migration tests, rollback story = ZIP backup).
- **Sensitive data** — catches carry GPS coordinates of fishing spots. Sync and
  cloud backup move that to a third-party cloud; needs an explicit user-facing
  privacy decision (§8.8).
- **Free-tier limits** — Supabase free tier is ~500 MB database + 1 GB storage;
  photo-heavy users may exceed it during beta.
- **Delete semantics** — introducing tombstones changes what "delete" means for
  synced rows; UI and cleanup jobs must respect `deleted_at`.

## 8. Decisions requiring approval

1. **Supabase hosted vs self-hosted** — recommend hosted (free tier) for beta.
2. **Auth method** — recommend email + password. Magic links need deep-link
   config; OAuth (Google) triggers the App Store requirement to also offer
   Sign in with Apple — defer all OAuth for beta.
3. **Invite model** — recommend allowlist gating (§5.2) over invite codes.
4. **Soft-delete scope** — tombstones on all synced tables now (recommended,
   one migration) vs. only where needed.
5. **Data migration policy** — auto-upload existing data on first link vs.
   explicit opt-in prompt (recommend opt-in + ZIP backup offer).
6. **Conflict policy** — last-writer-wins (recommended) vs. manual resolution.
7. **Admin surface** — in-app admin screens vs. Supabase dashboard for beta.
8. **Location privacy** — confirm storing GPS-bearing catches/spots in Supabase
   is acceptable, and whether the privacy copy needs updating.
9. **Cloud backup encryption** — rely on private bucket + RLS (recommended for
   beta) vs. client-side-encrypted archives (adds password management).
