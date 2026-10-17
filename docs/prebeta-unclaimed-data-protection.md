# Pre-Beta — Unclaimed-Data Protection Design

Status: **implemented** (`d303008`, `4d3f67e`, `ba07834`)
Branch: `feature/pre-beta-security`
Scope: block ordinary browsing of unclaimed local records; preserve the
explicit claim flow and all Stage 4B semantics. No schema changes, no ZIP
format changes, no cloud sync.

---

## 1. Problem

`OwnershipState.unclaimed` currently grants full app access. Any
signed-in, approved account can freely browse unowned fishing records —
including data restored from a legacy v28 ZIP — because the ownership
gate and the DB-layer guard only engage once a *different* owner exists.
This was deferred from Stage 4B as a pre-beta requirement.

## 2. Model: three states become four presentation cases

`evaluate()` keeps returning `unclaimed | owner | denied` (enum
unchanged — avoids touching Settings and every call site). A second,
independent fact decides presentation when `unclaimed`:

```
hasLocalData = total row count across the 12 user-owned tables > 0
```

| Auth | Owner | hasLocalData | Result |
|---|---|---|---|
| signed in, approved | — | false | **App** (fresh/empty DB — normal access) |
| signed in, approved | — | true  | **Ownership-resolution screen** (claim or sign out) |
| signed in, approved | == uid | — | **App** (owner) |
| signed in, approved | != uid | — | **Denied screen** (existing; no reassignment) |
| signed out / awaiting / revoked | any | any | existing auth screens (unchanged) |

`hasLocalData` counts only the 12 user-owned tables
(`MigrationV29.userOwnedTables`) — the fishing records. A settings-only
database counts as empty: settings aren't per-user owned and a fresh
install can legitimately hold defaults.

### DB-layer guard

`setDataAccessDenied(true)` arms whenever `denied` **or**
(`unclaimed && hasLocalData`). Disarms for `owner` or
(`unclaimed && empty`). Rationale: if the records can't be browsed at
the UI, they must not be reachable through background services or stray
`DatabaseHelper.instance.database` calls either. All legitimate
internals already use `systemDatabase` (unguarded): the claim flow, the
counts query, restore, migration, `createSnapshot` backups, and
recovery — so arming breaks nothing legitimate.

## 3. The ownership-resolution screen

Blocking screen shown by `AuthGate` in place of `widget.child` when
`unclaimed && hasLocalData`:

- **"This is my data — create backup & link"** → existing
  `ClaimDataScreen` flow (verified ZIP → transactional claim →
  validation → owner state → app opens).
- **"Not my data — sign out"** → `AuthService.signOut()` → Sign In.

Copy explains: the data is not yet linked to any account; linking binds
it permanently to the signed-in account; a backup is made first; other
accounts will not see it afterwards.

`ClaimDataScreen` gets a small `blocking` mode (no "Not Now" → replaced
by Sign Out), so the resolution screen reuses the entire existing wizard
rather than duplicating it.

## 4. Authorization to claim — the honest answer

Confirmation cannot *prove* ownership, because unowned data carries no
provenance: v28 records predate accounts entirely, and nothing in them
ties them to a Supabase user. Claim is therefore **establishment, not
verification**: the first approved, signed-in account holding device
possession may claim the unowned data.

That is an appropriate beta boundary because:

1. The data is already physically present and unencrypted on the device
   — anyone with possession could read the SQLite file directly; the
   claim gate is an *attribution and accident-prevention* boundary, not
   a confidentiality boundary against a determined adversary.
2. The screen prevents the real harms: a second account silently
   browsing the primary's records, and a casual mistaken claim.
3. The claim is deliberate and audited: typed confirmation, a required
   verified backup whose name is persisted in `local_account`, and
   `claimed_at`.

To harden establishment without new infrastructure:

- **Explicit confirmation text** — require typing the account's own
  email address (or a confirm phrase) before the claim button enables.
  Cheap, effective against accidental claims.
- **Audit trail without schema change** — record the claimant's email
  inside the existing `claim_db_counts` JSON column
  (`{"_claimed_by": email, ...counts}`) — no v30 migration needed.

Optional deferred hardening (not this stage): admin-side claim
authorization flag in `beta_testers`, or ownership transfer flow.

## 5. Scenario coverage

| Scenario | Behavior |
|---|---|
| Fresh install, empty DB | signed-in approved → app, no prompt |
| v28→v29 migration, unclaimed records | resolution screen at first signed-in launch; claim re-opens app |
| Restore unowned v28 ZIP (any install) | data stays unowned (4B semantics) → resolution screen; claim binds it |
| Restore unowned ZIP onto **claimed** install | restored DB replaces `local_account` → owner lost → unclaimed+data → resolution → original owner re-claims (documented; re-claim is idempotent and safe) |
| Restore different-owner v29 ZIP | blocked by existing 4B owner-mismatch check — unchanged |
| Different approved account signs in | resolution screen; **can** claim (possession model) or sign out — copy warns it binds permanently to *their* account |
| Offline | resolution + claim are fully local → works offline (approved session via remembered per-account state) |
| Claim interrupted (backup OK, claim fails) | stays unclaimed → resolution re-prompts; claim is idempotent, safe to retry |
| Claim interrupted mid-transaction | SQLite transaction rolls back → unclaimed → re-prompt |
| App killed during resolution | state unchanged → re-prompt at next launch |
| Second account signs out, primary back | primary sees resolution → claims → all records bound |

## 6. Affected files

| File | Change |
|---|---|
| `lib/services/ownership_service.dart` | add `hasLocalData()` (sum across `userOwnedTables`); arm guard for `unclaimed && hasLocalData`; extend `evaluate` result caching to include the data flag |
| `lib/screens/auth_gate.dart` | new `_OwnershipResolutionScreen`; `unclaimed` branch resolves empty vs has-data |
| `lib/screens/claim_data_screen.dart` | `blocking` constructor mode (Sign Out instead of "Not Now"); typed-email confirmation gate |
| `lib/services/auth_service.dart` | (separate commit) drop legacy `auth_ever_approved` migration — discard, don't attribute |
| `test/ownership_service_test.dart` / `auth_gate_test.dart` / claim tests | new + updated coverage |
| `lib/screens/settings_screen.dart` | minor: claim tile hidden once claimed (already is); behavior unchanged when unclaimed-empty |

No changes: schema v29, ZIP format, `migration_v29.dart`,
`zip_backup_service.dart`, `local_account` columns.

## 7. Acceptance criteria

1. Empty DB + approved sign-in → straight into the app.
2. Unclaimed records + approved sign-in → resolution screen; zero
   fishing data reachable (UI **and** `database` getter throws).
3. Claim → verified backup created → transactional stamp → all
   `owner_id` set → owner state → app opens. `local_account` records
   owner, `claimed_at`, backup name, counts (+ claimant email).
4. Post-claim: another approved account → denied screen + guard armed.
5. Different-owner v29 restore → still blocked.
6. Unowned v28 restore → unclaimed → resolution, not auto-stamped.
7. Offline: established session + unclaimed data → resolution works;
   claim completes offline.
8. Kill app mid-claim / mid-resolution → safe re-prompt; no partial
   claim (transaction rollback).
9. All existing 231 tests still pass; `flutter analyze` clean.

## 8. Manual test plan (Moto G15)

Prereq: build with fix, install via `safe_install.sh` (data preserved —
device already claimed by primary account).

1. **Baseline**: launch → primary signs in → app opens (owner path).
2. **Second account**: sign in as second → "Data Belongs to Another
   Account" (unchanged).
3. **Restore-to-unclaimed**: back up current data → restore the
   pre-claim v28-style unowned ZIP (or a v29 copy with owner nulled via
   a test build — see note) → launch → resolution screen, no catches
   visible → sign in as primary → claim → verify counts/owner/media.
4. **Wrong-account claim warning**: while unclaimed, sign in as second
   account → resolution screen (copy shows *their* email) → sign out
   instead → sign in as primary → claim.
5. **Interrupted claim**: start claim, force-close during "Claiming…" →
   relaunch → resolution screen, DB intact, re-claim succeeds.
6. **Fresh-equivalent**: (test build or emulator) empty DB → approved
   sign-in → no resolution prompt.
7. **Guard check**: while unclaimed, confirm no data leaks — catches
   screen unreachable; `adb` pull of app logs shows guard armed.

*Note:* producing an "unowned" state on the claimed device needs either
a v28 ZIP restore or a temporary test hook — to be decided at
implementation time; a debug-only `unclaim` affordance is possible but
must not ship in release.

## 9. Explicitly out of scope

- Ownership *transfer* between accounts.
- Encrypting the database at rest.
- Cloud sync, schema v30, backup format changes.
- Admin-mediated claim approval.
