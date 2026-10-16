# Stage 4A — Revocation & Reinstatement Test Plan (for review)

Branch: `feature/pre-beta-security` · Device: Moto G15 · Status: **pending
your approval — do not change any Supabase account status yet.**

## How the entitlement check actually works (verified in code)

- `beta_testers.status` — `'invited'` and `'active'` both approve;
  `'revoked'` blocks (`0001_beta_access.sql`).
- `AuthService.refresh()` runs on **app launch** and **Supabase auth
  events**; non-forced checks are throttled to **once per hour**
  (`_entitlementCheckInterval`). Forced checks happen on **sign-in**,
  sign-up, password update, and the Awaiting-Approval "Check Again"
  button.
- There is **no foregrounding re-check and no mid-session polling** — a
  revocation is enforced at the *next* launch or entitlement check, up
  to ~1 hour later. Documented as a known detection lag.
- Offline: a session that was ever approved stays signed in (local-first).
  A revoked account loses its session — see "offline behaviour" below.
- `_kEverApproved` is a **device-wide** preference, not per-account.
- Revocation flow: entitlement check fails → `everApproved` cleared →
  Supabase session signed out → `RevokedScreen` ("Access Removed",
  terminal, sign-out only). **Local data is never deleted.**

## Safety design

All revocation steps use the **second test account**
(`second@example.com` — substitute the real email). Your main account's
data is protected by two independent layers even if a check misbehaves:

1. The `OwnershipGate` hard-denies any non-owner account at the UI
   level ("Data Belongs to Another Account").
2. The `DatabaseHelper` guard throws `StateError` on data access,
   covering background services too.

Your main account's `beta_testers` row is **never modified** during
this test.

## Pre-requisites

1. Second account exists and is verified (email confirmed).
2. Second account on allowlist, status `active`:

   ```sql
   insert into public.beta_testers (email, status)
   values ('second@example.com', 'invited')
   on conflict (email) do update set status = 'active';
   ```

3. Phone online. Main account's data already claimed (owner
   `260fdd8a…` — verified at Stage 4B).

## Procedure

### Step 1 — Baseline: second account is denied at ownership gate
1. Settings → Account → Sign Out (main account).
2. Sign in as `second@example.com` → forced entitlement check →
   approved → **"Data Belongs to Another Account"** screen (terminal,
   Sign Out only). No catches visible.
3. Sign out.

*Expected: entitlement passes, ownership blocks. Main data untouched.*

### Step 2 — Revoke the second account (admin)
1. In the Supabase dashboard SQL editor:

   ```sql
   update public.beta_testers
   set status = 'revoked'
   where email = 'second@example.com';
   ```

### Step 3 — Detection while online
1. Relaunch the app → sign in as `second@example.com`.
2. Sign-in forces an entitlement check → **"Access Removed"** screen —
   "Your catches, trips and photos are still stored on this device."
   Only action offered: "Back to Sign In".

   *(If the device shows the ownership-denial screen instead, the cached
   entitlement is within the 1-hour window — signing in already forces
   a fresh check, so this should not happen; report it if it does.)*
3. Confirm nothing else is reachable — no catches, no settings, no
   navigation.

*Expected: revoked account is locked out entirely.*

### Step 4 — Sign-out / restart / no data loss
1. "Back to Sign In" → force-stop the app → relaunch → Sign In screen.
2. Do **not** sign in yet. I verify via `adb` that the database still
   holds all 76 catches, 262 owned rows, and your owner UUID.

*Expected: data fully preserved; nothing deleted.*

### Step 5 — Reinstatement
1. Dashboard:

   ```sql
   update public.beta_testers
   set status = 'active'
   where email = 'second@example.com';
   ```

2. Sign in as `second@example.com` → forced check → approved →
   **"Data Belongs to Another Account"** (ownership still denies —
   correct: reinstatement restores *entitlement*, not data ownership).
3. Sign out → sign in as **your main account** → full access to all
   data, no claim prompt needed.

*Expected: reinstatement restores entitlement immediately on next
sign-in; ownership layer unchanged.*

### Step 6 — Cached-window behaviour (optional, ~1 h)
To demonstrate the documented lag rather than wait passively:
1. Sign in as second account (denied at ownership) → leave signed in.
2. Revoke in dashboard → relaunch **within the hour** → still reaches
   the ownership-denial screen (cached entitlement trusted).
3. Sign out → sign in again → forced check → "Access Removed".

*Expected: revocation is detected at the next real entitlement check —
up to 1 hour — not instantly. This is the documented limitation.*

## Offline behaviour (documented, not optional)

| Situation | Behaviour |
|---|---|
| Approved session, device offline | Stays signed in — local-first; entitlement recheck deferred until connectivity + next check window |
| Revoked while **offline** | **Not detected until the next online check** — the revoked session keeps working offline until then (local-first trade-off) |
| Revoked while **online** | Detected at next entitlement check (launch, sign-in, or the hourly throttle) — session signed out, Access Removed |
| After revocation detected | Session is gone → sign-in requires connectivity → **local data is on-device but unreachable** until the account is reinstated or the owner signs in |

## Known limitations being documented (not changed in this test)

- **Detection lag**: up to ~1 hour or the next sign-in/launch — no
  mid-session or foreground polling.
- **`_kEverApproved` is device-wide**: entitlement history is shared
  across accounts on the device; ownership gating is the per-account
  boundary.
- **Revoked = local lockout**: after detection, the data remains on
  device but cannot be reached without a valid session — acceptable for
  beta, worth reviewing before public release.

## Approved decisions (2026-10-16)

1. **Detection**: the 1-hour throttle is accepted for this validation.
   Pre-beta work (recorded, not yet implemented): entitlement recheck
   on return-to-foreground plus periodic online recheck every ~5–15
   min; confirmed revocation denies immediately; transient network
   failure is never treated as revocation.
2. **Local access after revocation**: current behaviour retained —
   approved users keep offline access; offline revocation is
   undetectable; a confirmed revocation denies app access; all local
   records/photos preserved; reinstatement restores access without
   touching data. No local-only bypass mode.
3. **`everApproved`**: confirmed device-wide. **Hole exists** — the
   flag set by an approved account persists on the device (it survives
   ungraceful session loss and reinstalls). When a *different* account
   later holds a session and the entitlement check is **unresolvable**
   (offline, or the `isApprovedBeta` RPC fails/times out mid-sign-in),
   the offline branch reads the *stale device flag* → `signedIn` for an
   account that was never approved → reaches the app. The ownership
   gate still blocks it on a claimed install, but on an **unclaimed**
   install it would browse freely — compounding the unclaimed-data
   issue. Pre-beta correction: key approval history per Supabase user
   ID + account-switching regression tests.
4. **This test**: second account only; primary `beta_testers` row is
   never modified.

## Functional defects recorded during testing

- **DEFECT-1 — `everApproved` is device-wide and cleared on sign-out.**
  - Symptom A (insecurity): a stale flag set by an approved account can
    be read by a different account whose entitlement check is
    unresolvable (offline/RPC failure) → `signedIn` for a never-approved
    account. Only the ownership gate limits the damage on a claimed
    install; an unclaimed install would be browsable.
  - Symptom B (messaging): `signOut()` deletes the flag, so a revoked
    user who signs out and back in sees **"Awaiting Invitation"**
    (never-approved copy) instead of **"Access Removed"** — the revoked
    screen is only reachable while the revoked session is still alive.
  - Required fix (pre-beta): key approval history per Supabase user ID
    (e.g. `auth_ever_approved_<uid>`) and persist it across sign-out so
    that (a) accounts can't inherit each other's approval state and
    (b) a returning revoked user sees "Access Removed". Regression
    tests must cover account switching and sign-out/sign-in cycles.

## Post-test state

- `beta_testers` restored: main `active`, second `active`.
- No data changes to any fishing records; all revocation steps are
  reversible.

---

*Awaiting approval before any `beta_testers` status change.*
