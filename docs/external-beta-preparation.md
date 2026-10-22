# External Android Beta — Launch Preparation

Internal runbook for distributing the validated beta to a small external
group (~3–5 testers). Tester-facing steps live in
[beta-tester-guide.md](beta-tester-guide.md).

---

## 1. Release record

| Field | Value |
|---|---|
| Branch | `feature/beta-release-prep` |
| Source commit | `5c9d7ca` — "Gate debug restore tools in release, show live schema version, v10" |
| APK | `release_artifacts/bragmat-beta-v10-release.apk` (63,497,683 bytes) |
| Durable copy | `Documents\Bragmat Backups\bragmat-beta-v10-release.apk` |
| Package | `com.bragmat.app` |
| Version | `1.0.0` · versionCode `10` |
| Signing cert SHA-256 | `e086f084df0be5d342196caafeaa8d163bfa806cdfe2e627d697ed42699f58f1` |
| Cert DN | `CN=Bragmat Release, OU=Development, O=Bragmat, L=Darwin, ST=NT, C=AU` |

### Validation evidence

- **Unit tests:** 591 passed + 1 skip at `5c9d7ca`; `flutter analyze` 174
  baseline issues, none new.
- **Emulator (`com.bragmat.app` release):** full authenticated acceptance
  — sign-in, entitlement, restore of synthetic dataset, cross-account
  restore rejection, revoke/reinstate, session persistence, v8→v9 and
  v9→v10 upgrades preserving data. Cloud Backup absent; debug tooling
  verified absent in release; Database Version shows live `user_version`.
- **Moto G15 (physical):** parallel install alongside dev app; restore of
  the real 81-catch backup verified field-for-field against the source
  archive (schema v30, `quick_check` ok, ownership, counts, tide/GPS
  provenance, all 62 media files); regression suite on disposable
  records (add/edit/delete, camera+gallery photos with EXIF GPS,
  automatic+fixed tide refs, env recalc, clean deletion, ZIP backup);
  offline operation; session persistence over ~1 day idle and across the
  v9→v10 upgrade.
- **Security:** non-debuggable; `DEV_AUTH_BYPASS` absent; no secrets or
  test credentials in the APK; Cloud Backup fail-closed.

### Known limitations for testers

- **Cloud Backup is off** — data lives on the device only. Testers should
  use Settings → Backup Data and keep the zip off the phone.
- **WorldTides key not bundled** — see §4.
- **Deep-link scheme caveat** does not apply to external testers (they
  will not have the dev package installed).
- **Sign-up email delivery** uses Supabase's default SMTP — see §2.

## 2. Inviting testers (Supabase `beta_testers`)

Beta access is enforced server-side: a user enters the app only if their
`auth.users` email is **verified** *and* present in
`public.beta_testers` with `status` `invited` or `active`
(`is_approved_beta()` — `supabase/migrations/0001_beta_access.sql`).

### Per tester

1. Get the tester's email — this must be the exact address they sign up
   with.
2. Add it to the allowlist (SQL editor or service-role; requires an
   `admins` row for your user):

   ```sql
   insert into public.beta_testers (email, notes)
   values ('tester@example.com', 'Firstname — device model');
   ```

   Status defaults to `invited`; set `'active'` once onboarded if you
   want the roster to reflect real usage.
3. Send them the tester guide + APK. Order matters little — they can
   install before or after being added, but **invite before they
   sign up** to avoid them landing on "Awaiting Invitation".

### What the tester experiences

Sign Up → Supabase confirmation email → tap link → deep link
`bragmat://auth-callback` opens the app and verifies → Sign In →
entitlement check passes → My Catches. Uninvited sign-ups see
"Awaiting Invitation" and can re-check after being added.

### Caveats

- **Default SMTP rate limits:** Supabase free-tier email is slow and
  capped. For 3–5 testers it works, but confirmation mails can arrive
  late or land in spam. For anything larger, configure custom SMTP —
  *needs approval* (Supabase config change).
- **Revoking:** `update beta_testers set status = 'revoked'` takes effect
  on the next entitlement refresh (app foregrounding); local data is
  retained on their device by design.
- No self-service invite flow exists — the allowlist is managed by SQL
  by an admin only.

## 3. APK distribution options

| Option | Effort | Tester experience | Notes |
|---|---|---|---|
| **Firebase App Distribution** | Low — one-time console setup, no code changes | Email invite → guided install → automatic update notices | Free; standard for this group size; needs a Firebase project (Google account). **Recommended.** |
| Play Internal App Sharing | Low if a Play Console account exists | Tap a Play link → installs like a store app | Play Console account costs US$25 one-off; APK upload accepted; simplest for non-technical testers if the account exists |
| Play Closed Testing track | High — store listing, review, privacy policy | Full Play install | Overkill for 3–5 users |
| Direct APK (Drive/email/USB) | Zero | Manual "install unknown apps" step | Free and already proven (this is how the G15 got it); fine for the initial group if you prefer zero new infrastructure; no update channel |

**Recommendation:** Firebase App Distribution — purpose-built for this
scale, gives email invites and in-app update prompts for later builds,
and needs no code or server changes (the APK is uploaded as-is; the
release signing already satisfies it). Direct sideloading is the
zero-setup fallback for the very first testers. *Choosing and setting up
a channel needs your approval — it involves creating a Firebase or Play
project.*

## 4. WorldTides key provisioning

The app ships **no** WorldTides key — each install needs one for official
tide context (without it: weather/moon data works, tide fields can be
entered manually, the app is fully usable).

| Approach | Security | Tester effort | Cost |
|---|---|---|---|
| **Each tester registers a free key** at worldtides.info and pastes it in Settings → API Keys | Best — keys aren't shared; each has its own quota | Medium (~5 min) | Free tier per tester |
| One shared beta key you control, distributed privately | Moderate — key shared across the group; rotate on abuse | Lowest | One key's quota shared; WorldTides free tier may be thin for 5 devices |

**Recommended:** tester-owned keys (guide covers the steps). If a tester
balks, hand them a shared key directly — never commit it or post it in
docs/chats it can't be deleted from. *A shared key would need creating —
needs approval.*

## 5. Feedback and defect reporting

Keep it lightweight for 3–5 non-technical testers:

- **Channel:** one email thread (or a WhatsApp/Signal group). No issue
  trackers, no forms.
- **Ask for:** what they did, what happened vs expected, a screenshot,
  phone model, rough time.
- **Triage (admin side):** file confirmed defects as GitHub issues with a
  `beta-tester` label; ask testers for an in-app backup zip or screenshot
  of the offending catch/detail when data state matters.
- **Known answers to rehearse:** "Awaiting Invitation" → wrong/uninvited
  email; no tide numbers → no WorldTides key; Play Protect warning →
  expected for sideloaded beta.
- **Weekly-ish nudge:** testers often stay quiet; a short "how's it
  going?" with one specific ask ("log this weekend's catch") yields more
  signal than open-ended requests.

## 6. Decisions needing approval before launch

1. **Distribution channel** — Firebase App Distribution recommended;
  involves creating a Firebase project (no code change).
2. **Inviting the testers** — SQL inserts into `beta_testers` once you
  confirm the email list.
3. **WorldTides provisioning** — tester-owned keys (recommended, no
  action) vs one shared beta key (needs creating).
4. **Supabase custom SMTP** — optional; only if default email delivery
  proves too slow during onboarding.
5. **Pushing `feature/beta-release-prep` / tagging the validated build** —
  currently local only; tag `v1.0.0-beta.1` (or similar) would mark the
  distributed commit.

## 7. Launch checklist (when approved)

- [ ] Distribution channel chosen and set up
- [ ] Tester emails collected; `beta_testers` rows inserted
- [ ] Tester guide + APK sent to each tester
- [ ] WorldTides approach communicated
- [ ] Feedback channel opened; first-week check-in scheduled
- [ ] Release tag created (optional, on approval)
