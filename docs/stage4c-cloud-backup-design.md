# Stage 4C — Cloud Backup via Supabase Storage

Architecture research and design proposal for review.
**No implementation until approved.** No application files, Git branches,
Supabase configuration or data were changed in preparing this document.

Status: **§12 decisions APPROVED 2026-10-17**, subject to the additional
safeguards in §14. **Stage 4C-1 (storage schema/RLS/tests) authorised**
on branch `feature/cloud-backup`. Consent wording (§12.6) approved as
draft — final user-facing copy still requires review before release.

In the primary worktree this file is excluded via `.git/info/exclude`
(local, untracked) so it cannot be staged accidentally by concurrent
sessions; the committed copy lives on `feature/cloud-backup`.

Companion documents:
- `stage4-user-accounts-architecture.md` — Option 1 approved (local-first;
  Supabase is a replication/identity layer). Cloud backup was originally
  numbered "Phase 4B" there; the project renumbered, and cloud backup is
  now Stage 4C. Scope is unchanged: reuse the ZIP pipeline; sync remains
  deferred to a later stage.
- `stage4b-schema-v29-design.md` — ownership (`local_account.owner_id`),
  per-row `uuid`/`owner_id`, `sync_queue`, shipped in 4B.

## 1. Goals and non-goals

### Goals
- Optional, opt-in cloud backup of the complete app state (SQLite DB +
  photos + settings) using the existing portable ZIP format.
- Restore onto a second device (Android ↔ future iPhone) or a wiped/
  replaced phone, after sign-in.
- Privacy preserved end-to-end: fishing locations and photos are
  personal data and must not be readable by anyone but the owner —
  including the platform operator (i.e. Supabase), administrators, and
  anyone who compromises an access token.
- Graceful failure: interrupted uploads/downloads never corrupt remote
  or local state; every step is resumable or idempotent.
- Local ZIP backup remains fully functional and independent of the
  cloud feature.

### Non-goals (explicitly deferred)
- Live multi-device sync (row-level replication via `sync_queue`) —
  remains a future stage. Cloud backup deliberately does **not**
  converge two devices' divergent edits; it replaces a device's state.
- Sharing backups between users, or any admin access to user data.
- Automatic deletion of local data ("free up space" features).
- In-app purchase/subscription for storage quota.

## 2. What already exists (reused, not rebuilt)

| Existing component | Reuse in 4C |
|---|---|
| `ZipBackupService.createBackup` | Produces the byte-identical artifact uploaded to the cloud. VACUUM INTO snapshot + media staging + manifest 2.0. |
| `ZipBackupService.validateBackup` / `restoreBackup` | Cloud restore = download → validate → existing staged restore pipeline (staging dirs, recovery marker, launch recovery) unchanged. |
| Ownership gate in restore | v29 backups carry `owner_id`; the existing `_decideRestoreOwnership` logic already refuses a backup owned by a different account — this is exactly the cloud-restore security check. |
| `BackupFileService` (SAF picker/export) | Unchanged for local files; cloud flow adds a parallel picker listing remote objects. |
| `AuthService` / `AuthBackend` | Session, `userId` (= storage prefix and `owner_id`), beta entitlement. `CloudBackupService` should take the same backend-abstraction approach (fake backend for tests). |
| `ConnectivityService` | Trigger condition for scheduled backups and the "resume upload" signal. |
| `flutter_secure_storage` | Already used for the auth session; reuse for optional on-device passphrase caching. |
| `supabase_flutter` 2.18 | `storage.from(bucket).upload/download/list/remove`, signed URLs. |
| `supabase/migrations/0001_beta_access.sql` | Pattern for the 4C migration: explicit grants, RLS-only enforcement, `is_approved_beta()` reuse. |

## 3. Recommended architecture

```
┌──────────────────────────── device ────────────────────────────┐
│  ZipBackupService.createBackup()                                │
│        → bragmat_backup_<ts>.zip  (manifest 2.0, unchanged)     │
│  BackupEnvelope.encrypt(zip, passphraseKey)                     │
│        → <ts>.bzp  (header + secretstream ciphertext)           │
│  CloudBackupService.upload → storage  backups/{uid}/<file>.bzp  │
└────────────────────────────────────────────────────────────────┘
                           │ HTTPS + anon JWT
                           ▼
              Supabase Storage: private bucket `backups`
              storage.objects RLS: foldername[1] = auth.uid()
                                   AND is_approved_beta()
```

**Single-artifact design:** one encrypted blob per backup. The plaintext
ZIP never leaves the device; the ZIP format itself is unchanged, so the
entire validated restore pipeline applies verbatim after decryption.

### 3.1 Storage layout

- One private bucket: `backups`. `public = false`, `allowed_mime_types`
  = `application/octet-stream` (or unset — ciphertext has no meaningful
  MIME), per-bucket file-size limit set explicitly.
- Object key: `{auth.uid()}/{filename}.bzp` — first path segment is the
  owner UUID, enabling the standard storage RLS pattern:
  `(storage.foldername(name))[1] = auth.uid()::text`.
- An index object is **not** needed: `storage.from('backups').list(uid)`
  returns the user's backup listing directly.

### 3.2 RLS policies (new migration `0002_cloud_backup.sql`)

```sql
insert into storage.buckets (id, name, public)
  values ('backups', 'backups', false) on conflict do nothing;

-- Users manage objects only under their own uid prefix, and only
-- while approved for beta (revoked users lose cloud access
-- server-side, matching the profiles policy).
create policy "backups: own prefix"
  on storage.objects for all to authenticated
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
```

Notes:
- No `anon` access; no public URLs; downloads use the authenticated
  `download` API, not signed URLs (no reason to hand out bearer-free
  links to private data).
- Revocation already signs the user out app-side; the
  `is_approved_beta()` clause makes the denial server-side too, matching
  the 4A profiles precedent.
- Decision point §10.4: whether revoked/departed users' objects are
  purged server-side (manual admin op, since service key never ships).

## 4. Encryption design — the core decision

### 4.1 Threat model

The backup contains the user's complete fishing history: GPS
coordinates of favourite spots, personal photographs **with EXIF
preserved byte-for-byte** (`copyPhotoToStorage` deliberately keeps
EXIF), journal text, and the owner's identity. The
`incident-2026-10-16-fbf3475` document demonstrates this data is
sensitive in practice, not just in principle.

Threats considered:
- Misconfigured or buggy RLS policy exposing objects cross-user.
- Compromised/stolen JWT (device theft, token leak) → unauthenticated
  download of another copy of the data under the victim's identity.
- Supabase platform access (operator, support tooling, breach of the
  storage backend). Hosted- Supabase encrypts at rest, but the platform
  holds the keys.
- The accidental-commit incident class: backups are self-contained
  high-value files; any copy that escapes is total.

### 4.2 Options compared

| | A. RLS only (plaintext ZIP) | B. E2EE, device key | C. E2EE, passphrase (recommended) |
|---|---|---|---|
| What encrypts | TLS in transit + at-rest (platform key) | Random key in `flutter_secure_storage` | Key derived from user passphrase (Argon2id) |
| Supabase/operator can read | **Yes** | No | No |
| Token theft + RLS bypass exposes data | **Yes** | No | No |
| Restore on a new device | Works | **Key gone with the phone** unless key is separately backed up | Works — user re-enters passphrase |
| UX | Zero friction | Zero friction | Passphrase at enable + at restore (optional "remember on this device") |
| Lost secret consequence | — | Backup unrecoverable if key lost | Backup unrecoverable — mitigated by recovery code + local ZIP fallback |

- **A** is honest only if we accept "Supabase can read your fishing
  spots." Given the explicit privacy requirement and preserved EXIF GPS,
  this is not recommended as the only mode.
- **B** fails the headline use case: the phone is lost/broken and the
  user restores to a new phone — the decryption key died with the
  device. A separate key-escrow mechanism would be needed, reintroducing
  the passphrase problem anyway.
- **C** is the recommended design: user-chosen backup passphrase →
  Argon2id (memory-hard) → XChaCha20-Poly1305. Passphrase is requested
  once when enabling cloud backup (with a shown recovery code), and on
  every restore onto a new device. Optional per-device "remember"
  stores the passphrase in `flutter_secure_storage` (same protection as
  the auth session); it is never stored anywhere else and never leaves
  the device.

### 4.3 Recommended envelope format

A small unencrypted header precedes the ciphertext so a downloader can
detect and parametrise decryption without touching the manifest:

```
magic      "BRGZ" version byte 0x01            (5 bytes)
kdf        0x01 = argon2id                     (1 byte)
salt       16 bytes
opslimit   uint32 LE
memlimit   uint32 LE (KiB)
ciphertext XChaCha20-Poly1305 secretstream     (streaming, ~8 MiB chunks,
           one ABYTES tag per chunk — files are decryptable as a stream
           and truncation/tamper is detected per chunk and at the end)
```

Implementation library: **`sodium_libs`** (libsodium bindings, already
mature on pub.dev, Android + iOS). It provides `crypto_pwhash`
(Argon2id) and `crypto_secretstream_xchacha20poly1305` — the streaming
primitive is important because a 500 MB archive should never be held
in memory as plaintext on either path. Alternative considered:
`cryptography` package (pure-Dart Argon2id + XChaCha20) — acceptable,
but libsodium's secretstream and battle-tested KDF parameters are the
better fit.

After decryption to a temp `.zip`, the **existing** `validateBackup`
and `restoreBackup` consume it unchanged. Integrity is doubly covered:
AEAD detects tampering; `integrity_check` catches structural issues.

### 4.4 Manifest compatibility

Keep `backupVersion` at `2.0` for cloud backups — encryption lives in
the envelope, not the manifest, so the strict version check in
`BackupManifest.validate` needs **no change** and old app builds can
still restore a downloaded+decrypted archive. Optional additive fields
(`ownerId`, `uploadedFrom` platform) may be added without bumping the
version, since validation only checks known required fields.

A decrypted cloud backup is therefore indistinguishable from a local
ZIP — it can also be exported/shared through the existing UI, and any
local `bragmat_backup_*.zip` remains a fully independent escape hatch.
The `.bzp` envelope should also be exported alongside if "Save a copy"
is ever offered for cloud entries.

## 5. User consent and UX

Cloud backup is **off by default** and requires an explicit enable flow:

1. Settings → Backup → "Cloud backup" → enable sheet explaining:
   - what is uploaded (complete copy of records + photos),
   - that it is encrypted on the device before upload, and that the
     passphrase is unrecoverable,
   - that photos keep their embedded location data (which is why
     encryption matters),
   - where it is stored (Supabase project region).
2. Set/confirm passphrase (min length enforced, strength hint) → show
   recovery code → user must confirm they saved it. Optional:
   "remember on this device" (secure storage).
3. Consent is recorded in `SharedPreferences` (timestamp + version of
   the consent text shown) — auditable, local, revocable.
4. Disabling cloud backup asks whether to also delete remote objects
   (client-side `remove` over the user's own prefix — RLS-safe).

Scheduled backups (§8) are a **separate** toggle inside the cloud-backup
section, not implied by enabling the feature.

Restore-on-new-device entry point: after sign-in on an install with an
empty/unclaimed database, `AuthGate`/`OwnershipGate` offers "Restore
from cloud backup" alongside "Start fresh" — listing remote backups and
prompting for the passphrase. This is the flow that motivates E2EE
design C.

## 6. Storage costs and limits

Current Supabase hosted limits (verified October 2026):

| | Free | Pro ($25/mo) |
|---|---|---|
| File storage | 1 GB | 100 GB, then $0.0213/GB-mo |
| Max single object | **50 MB** | 500 GB (configurable) |
| Egress | 5 GB | 250 GB |
| Inactivity pause | project paused after ~1 week | n/a |

Sizing: the encrypted blob ≈ plaintext ZIP size (secretstream adds
~17 B per 8 MiB chunk — negligible). The DB alone is ~1–5 MB; photos
dominate. The device's last full backup was 22.5 MB — already near the
50 MB free-tier per-object cap, and photo-heavy users will exceed both
50 MB/object and 1 GB total quickly.

Consequences:

- **The 50 MB per-object cap is the binding constraint on the Free
  plan**, not the 1 GB total. A whole-archive design hard-fails on Free
  once a user's archive crosses 50 MB.
- Mitigations, in order of preference:
  1. Accept it: document that cloud backup on the Free project supports
     archives ≤ 50 MB; surface a clear error (the API returns 413) and
     offer local ZIP. Move the project to Pro when real usage requires —
     Pro's 100 GB covers hundreds of beta-scale archives.
  2. Keep-last-N retention (§7) bounds total size regardless of plan.
  3. (Future stage) split architecture — encrypted DB-only backups are
     permanently tiny; media uploads per-file with dedup — this is also
     exactly what the deferred media-sync design needs, so it should not
     be built twice. Recommended as the *future* convergent design, not
     for initial 4C.
- Egress is only spent on restore (rare) — fine at any tier.
- Inactivity pause (Free, ~1 week no API calls) interacts badly with a
  backup service: a paused project rejects uploads. The app must surface
  "backup service temporarily unavailable — retrying" rather than
  failing opaque; the scheduled-upload retry path covers this naturally.

## 7. Retention policy

Supabase Storage has no built-in TTL/lifecycle on this plan — retention
is **client-enforced**:

- Keep the **3 most recent** backups per user (configurable constant).
  After each successful upload + verification, list `{uid}/` and delete
  older objects beyond the window.
- Retention deletion only ever runs against objects the client itself
  created under its own prefix — RLS makes cross-user deletion
  impossible by construction.
- Manual "Delete all cloud backups" in Settings (with the disable flow
  above) — required for account-deletion hygiene; the 4A account-deletion
  workflow should note that remote backup objects must be removed (they
  can only be removed by the user client-side, or by an admin via
  dashboard/service key if the user is already gone — §10.4).

Rationale for 3: one corruption event should not age out every good
copy; 3 gives a bad-backup buffer without unbounded growth.

## 8. Backup scheduling

No background daemon exists today, and Android/iOS background execution
is the least reliable part of any mobile design. Staged:

1. **Stage 1 (recommended baseline): opportunistic.** On app launch and
   on `ConnectivityService` regain, if (enabled) ∧ (scheduled ON) ∧
   (last successful upload older than the chosen interval — daily/weekly)
   → run the create→encrypt→upload job in the foreground app lifecycle.
   Zero new dependencies, works identically on Android and iOS, and fits
   actual usage (the app is opened when fishing).
2. **Stage 2 (optional later): true background.** `workmanager`
   (Android `WorkManager`) / `BGTaskScheduler` (iOS). Known caveats:
   Android quotas, iOS discretion, both need the passphrase — which
   forces "remember on this device" ON, a consent consequence to
   disclose. Not needed for beta.

Upload execution notes:
- Use `upload` (single-shot) for ≤ ~50 MB archives; for larger archives
  on Pro, Supabase supports TUS resumable uploads server-side, but
  `supabase_flutter` has **no built-in resumable API** — it would need
  `tus_client_dart` against the `upload/resumable` endpoint. Defer: at
  expected archive sizes, single-shot + retry is acceptable.
- Progress callback wired to the existing `_runWithProgress` UI pattern.
- Uploads marked complete only after a verifying `list()` confirms the
  object with the expected size; interrupted single-shot uploads leave
  no partial object (Supabase stores objects transactionally), so retry
  is simply re-upload.

## 9. Failure recovery

| Failure | Handling |
|---|---|
| Upload interrupted (network drop, app kill) | Object never commits server-side; retry re-creates it. Local temp ZIP already cleaned by `createBackup`. |
| Upload completes but verification fails | Delete object; alert; keep local copy option via existing export. |
| Download interrupted/corrupt | AEAD/auth-tag failure or ZIP validation failure → error before any staging; live data untouched (restore never begins). |
| Wrong passphrase | AEAD failure on first chunk → clear "incorrect passphrase" path; no state changed. |
| Restore fails mid-swap | The existing staged-restore machinery handles it identically (`.stage`/`.restore` markers, launch recovery). Cloud adds nothing new here — this is the main reason to keep the single-artifact design. |
| Storage quota exceeded / object too large | 413/quota error → message + suggest local ZIP + record last-error in cloud-backup status. |
| Project paused (Free inactivity) | Indistinguishable from network failure → retry on next trigger; status shows last-attempt error. |
| Conflicting concurrent uploads (two devices) | Deterministic timestamped names make collisions vanishingly rare; `upsert: false` makes an accidental same-name upload fail rather than overwrite. |

## 10. Options comparison summary

| Option | Effort | Free-tier fit | Notes |
|---|---|---|---|
| **1. Whole encrypted ZIP → `backups` bucket (recommended)** | Lowest — reuses 100% of backup + restore pipeline | ≤ 50 MB/object cap is the limit; 1 GB total | Simple, auditable, identical artifact to local backup |
| 2. Encrypted DB-only + incremental encrypted media objects | High — remote index, per-file upload queue, lazy/eager media restore | Excellent (dedup; objects tiny) | Converges with the deferred sync design; build when sync lands, not twice |
| 3. Plaintext ZIP (RLS only) | Lowest | Same as 1 | Fails the privacy bar (operator-readable, EXIF GPS); rejected |
| 4. Third-party storage (Drive/iCloud via SAF/share sheet) | Low-ish | n/a | Already possible today — user exports ZIP to Drive manually; worth documenting as the zero-build alternative, but not an in-app feature (per-provider APIs, OAuth, review burden) |

**Recommendation: Option 1 + design C encryption**, accepting the 50 MB
Free-plan object cap as a documented limit, migrating to Option 2's
media-split only when sync work begins or Pro-tier economics justify it.

## 11. Staged implementation plan

| Phase | Deliverable | Depends on |
|---|---|---|
| **4C-1 Server** | `supabase/migrations/0002_cloud_backup.sql`: `backups` bucket + storage RLS (+ approved-beta clause); applied via dashboard like 0001 | Approval of this doc |
| **4C-2 Crypto core** | `BackupEnvelope` (sodium_libs; argon2id + secretstream; header format §4.3); unit tests incl. truncation/tamper detection; passphrase strength + recovery-code helpers | — |
| **4C-3 Upload/download service** | `CloudBackupService` behind a `CloudBackupBackend` interface (mirrors `AuthBackend`/`FakeAuthBackend` for tests): enable/consent state, create→encrypt→upload→verify, list, download→decrypt→hand to existing restore, retention keep-3, delete-all | 4C-1, 4C-2 |
| **4C-4 Settings UI** | Cloud-backup section: enable flow + consent record, passphrase, "Back up now", remote backup list w/ size/date, restore picker, disable/delete | 4C-3 |
| **4C-5 New-device restore UX** | Post-sign-in offer on unclaimed/empty installs; passphrase prompt; feeds the same restore | 4C-3 |
| **4C-6 Scheduling** | Opt-in daily/weekly, opportunistic triggers (launch + connectivity regain); last-upload + last-error status in Settings | 4C-4 |
| Deferred | TUS resumable uploads; background scheduling (workmanager/BGTask); media-split architecture; Pro-plan decision driven by real sizes | later stage |

New dependencies: `sodium_libs` only (mature, Android+iOS). Everything
else reuses existing packages — `workmanager` and `tus_client_dart`
appear only if the deferred items are taken up.

Verification per phase: `flutter test` (fake backend — no network),
`flutter analyze` (no new issues), `flutter build apk --debug
--dart-define-from-file=.env`, then manual Moto G15 validation per the
AGENTS.md install procedure (including a real backup existing outside
app storage first). Server-side: extend `supabase/tests/rls_checks.sql`
with cross-user storage access checks.

## 12. Decisions requiring approval

User preferences confirmed 2026-10-17 (in principle, pending formal
implementation approval):

1. **Encryption mode** — ✅ **Confirmed: C (passphrase E2EE).**
   Consequences: Supabase/admins cannot read backups; restore requires
   the passphrase on every new device; passphrase loss = unrecoverable
   backup, mitigated by recovery code, optional per-device "remember",
   and the independent local-ZIP path.
2. **Per-object size on Free tier** — ✅ **Confirmed: accept the 50 MB
   cap** with a clear error + local-backup fallback; Pro deferred until
   real usage demands it (see §6).
3. **Retention** — ✅ **Confirmed: keep-last-3 verified** client-enforced.
   "Verified" = retention pruning runs only after the new upload's
   size-verifying `list()` succeeds, so a failed upload never ages out
   a good copy.
4. **Scheduling** — ✅ **Confirmed: manual first; opportunistic auto
   (launch + connectivity regain) as the later 4C-6 toggle.** True
   background jobs deferred.
5. **Revoked/departed users' objects** — ✅ **Confirmed:** user-initiated
   deletion via `delete_own_backups()` RPC (works even after revocation,
   implemented in 0002), plus administrator-assisted deletion for
   exceptional cases and account closure.
6. **Consent text** — ✅ **Confirmed:** explicit opt-in consent required.
   Draft copy approved in principle; final user-facing wording to be
   reviewed before release.

## 13. Risks

- **Passphrase loss = unrecoverable backups.** Mitigated by recovery
  code, "remember on this device", and the always-available local ZIP —
  but it must be stated plainly in the enable flow.
- **Single-artifact size cap.** Already covered; if beta users'
  archives grow past 50 MB the answer is Pro or the media-split design,
  not a code hack.
- **Two-writers divergence.** Cloud backup replaces, never merges; a user
  restoring an old backup onto a device with newer local data is
  protected by the existing restore preview/confirmation, but the UI
  should display each remote backup's manifest statistics so the user
  picks knowingly.
- **Added crypto dependency** must support 64-bit Android + iOS;
  `sodium_libs` ships prebuilt binaries for both — verify on the Moto
  G15 during manual validation.

## 14. Approved additional safeguards (binding on all 4C stages)

1. **Independent recovery code.** The recovery code is an independent
   decryption secret, not a re-encoding of the passphrase: the archive
   key is a random 32-byte `XChaCha20-Poly1305` key; the envelope carries
   two key-wrap slots — one wrapping it with the passphrase-derived key
   (Argon2id), one with the recovery-code-derived key. Either secret
   alone restores.
2. **Envelope versioning.** `BRGZ` magic + version byte (§4.3). A
   decryptor MUST reject unknown versions and MUST implement every
   version it has ever emitted, so archives stay restorable across app
   upgrades. Version bumps only for breaking changes (new KDF/cipher);
   additive header fields reuse the current version.
3. **Key structure (documented for implementation):**
   `archive_key` (random, per backup) → wraps data; `passphrase_key` =
   Argon2id(passphrase, salt_p); `recovery_key` =
   Argon2id(recovery_code, salt_r). Envelope header stores both salts,
   both KDF params, and both wrapped copies of `archive_key`. Rotating
   the passphrase re-wraps `archive_key` only — no re-encryption.
4. **Upload verification beyond size.** After upload, verify
   (a) the object exists via `list()`, (b) stored size matches, and
   (c) a SHA-256 of the uploaded blob equals a value the client recorded
   — stored in object `metadata` (user_metadata) or a companion
   `{name}.sha256` object. Restore verifies the same hash before
   attempting decryption.
5. **Retention prunes only verified backups.** Older objects are removed
   only after the new backup passes check (4) in full.
6. **Temp-file hygiene.** Decrypted ZIPs are written only inside
   private application storage (`getApplicationSupportDirectory` or a
   dedicated temp subdir), never shared storage, and are deleted in a
   `finally` after restore — success or failure.
7. **Revocation-proof deletion.** `delete_own_backups()` RPC (security
   definer, no `is_approved_beta()` requirement) guarantees a revoked
   user can still remove their cloud backups — shipped in 0002.
8. **No sensitive logging.** Passphrases, recovery codes, archive keys,
   decrypted content and fishing coordinates must never reach
   `debugPrint`/logs/crash reporting — including inside error messages.
9. **No sync, no format change.** Stage 4C adds no row-level sync and
   does not alter the v29 snapshot/manifest format — the uploaded
   artifact is the same ZIP the local pipeline produces.
