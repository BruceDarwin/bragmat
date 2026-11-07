# Bragmat — Project Notes

Flutter fishing log app. Primary dev/test device: Moto G15 (Android).

## Git workflow

- Create a descriptive feature branch for each significant development stage
  (e.g. `feature/portable-zip-backup`, `feature/restore-hardening`).
- Make focused commits with meaningful commit messages.
- Run relevant tests before committing.
- Keep the working tree clean when completing a task.
- Report the branch name, commit hash, test results and any outstanding changes.
- Push completed, tested feature branches to GitHub (`origin`,
  https://github.com/BruceDarwin/bragmat.git) using normal non-destructive
  pushes.
- Do NOT merge into main, create validated release tags, force-push, or
  delete branches without explicit approval.
- Never commit credentials, API secrets, or other sensitive configuration
  values.

## Verification

- `flutter test` — full unit test suite, 361 tests + 1 skipped
  (sqflite tests use sqflite_common_ffi)
- `flutter analyze` — ~181 issues, all pre-existing/baseline
  (lib ~138 + tool/ script `avoid_print` infos); don't add new ones
- `flutter build apk --debug` — Android debug build
- Auth-enabled builds MUST be built with
  `flutter build apk --debug --dart-define-from-file=.env` —
  Supabase credentials are compile-time `String.fromEnvironment` values.
  A build without them **fails closed**: AuthGate shows a "Configuration
  Error" screen and the app cannot be entered unauthenticated
  (`SupabaseConfig.isConfigured` returns false). The only exception is a
  deliberate dev build with `--dart-define=DEV_AUTH_BYPASS=true`, which
  AuthGate honours in debug mode only. Never commit `.env`; it is
  gitignored.
- `tool/safe_install.sh` refuses to install an APK that lacks baked-in
  Supabase configuration (it scans the package for the compiled-in
  `supabase.co` host; values are never printed). Pass
  `--allow-dev-bypass` only for a deliberate `DEV_AUTH_BYPASS` dev build.
- Manual backup/restore verification on the Moto G15 before tagging a
  validated baseline

## Android installs — data-preserving procedure (MANDATORY)

App data (SQLite DB + photos) lives in the app's private storage and is
**destroyed by uninstall**. Never uninstall to install.

**Rules:**

1. NEVER run `flutter install` (it uninstalls+reinstalls on signature or
   version conflicts, wiping all app data). NEVER run `adb uninstall`.
2. ALWAYS install via `tool/safe_install.sh <apk>` — it verifies the APK
   package ID, version code and signing certificate against the installed
   app, refuses downgrades, checks that a `bragmat_backup_*.zip` exists on
   shared storage before updating a data-bearing install, and installs via
   `adb install -r` only.
3. If `adb install -r` fails (signature mismatch, downgrade, etc.) STOP —
   report the error and wait for the user. Do NOT uninstall and retry.
4. Before any significant deployment, confirm a backup exists OUTSIDE the
   app's private storage (e.g. a `bragmat_backup_*.zip` in Downloads, or
   a copy on the PC/cloud).
5. When a new build must be signed differently from what is installed
   (e.g. future release signing), the only data-safe path is: export a ZIP
   backup inside the app first, then approve the data-losing install
   explicitly with the user.
6. `tool/safe_install.sh --check-only` runs all verifications without
   installing — use it to inspect state before any device operation.
7. `tool/inspect_db.dart <db-path>` reads schema version + row counts of a
   SQLite file read-only — use it to verify backup contents.

## Baselines

- `v1.0.0-backup-restore-validated` — portable ZIP backup (create + restore)
  validated on Android, Phase 1+2 complete
- `feature/restore-hardening` — Stage 3 restore hardening, awaiting manual
  device validation
- `v1.0.0-prebeta-security-validated` — Stage 4A/4B local auth, beta
  entitlement, schema-v29 ownership, unclaimed-data protection and safe
  restore. Validated on Moto G15 (2026-10-17): adb install -r preserved all
  data; sign-in persistence, offline access, second-account isolation,
  entitlement recheck and revoke/reinstate all passed. 250/250 tests.
  Verified backup: `Documents\Bragmat Backups\
  bragmat_backup_2026-10-17T15-09-06-925344.zip` (v29, 78 catches).
- Stage 4C cloud backup — **validated at commit `3874db9`** on
  `feature/stage4-integration` (2026-10-18). Supabase `bragmat-dev`:
  private `backups` bucket, `delete-backups` Edge Function, RLS harness
  17/17, storage API + Edge Function batteries pass, 7/7 live E2E.
  Restore requires the recorded sha256 digest — missing or mismatched
  metadata fails closed before decrypt/restore. Moto G15 non-destructive
  validation: `install -r` preserved everything (78 catches, 81 media
  refs, 5 trips, v29, `quick_check` ok, session + ownership + offline
  all intact). **Deliberately excluded**: real-device cloud upload and
  cloud restore of the user's dataset — only synthetic emulator data
  touched the cloud. Bucket left empty; cloud backup on the device
  remains disabled/untouched. 325/325 unit tests. Not merged, no tag.

## Pending beta v14 integration checklist (user directives — not yet approved)

Components awaiting combination into a v14 candidate, in order of approval:

- `feature/beta-cleanup @ 4181a45` — Settings debug gating + SQLite
  Integrity Phase A (transactional deletes, JSON restore remap) and
  Phase B (read-only diagnostics). Accepted.
- `test/fk-enforcement-validation @ d299c54` — Phase C1 validation of
  `PRAGMA foreign_keys=ON`: compatible (659 pass, one real defect fixed).
  Enabling enforcement permanently still requires explicit approval.
- `feature/icon-dfinal @ 61a352a` — D-Final icon assets (scale 1.762,
  optical centre). Accepted; branch frozen unchanged.

When v14 is approved, the integration must include:

1. Moto G15 real-device icon check — launcher icon, app drawer,
   recent-apps thumbnail and Android themed (monochrome) icon.
2. Same approved icon assets carried into the iOS build unchanged.
3. Final integration report distinguishing regenerated files from
   unchanged-but-verified assets (adaptive XML, background PNGs,
   xxxhdpi monochrome were verified but not rewritten).
4. Read-only FK diagnostic of the device DB via ZIP backup extract +
   `tool/audit_fk.dart` before enabling enforcement on-device.

No push, merge, tag or beta distribution until explicitly approved.

## iOS-3C — arm64e packaging fix (validated 2026-11-07)

**Root cause**: `sodium_libs` v3.4.6+4 declares an SPM `binaryTarget`
downloading `libsodium-1.0.20-darwin.zip`, whose xcframework device slice
contains an `arm64e` binary. Apple's App Store Connect rejects uploads
containing `arm64e` (error 91011). The arm64e slice is a pointer-auth
hardware extension for newer devices (A12+, M1+) — Apple requires either
no arm64e or explicit opt-in, and rejects plain arm64e frameworks.

**Fix — dependency_overrides**: `pubspec.yaml` `dependency_overrides:
sodium_libs: path: local_packages/sodium_libs` — a project-local copy of
the same v3.4.6+4 package with `darwin/sodium_libs/Package.swift`
binaryTarget rewritten to `path: "Libraries/libsodium.xcframework"`
(the url+checksum form was replaced). The local package is populated at
build time: `ios-testflight` yaml step downloads the same
`libsodium-1.0.20-darwin.zip` (upstream checksum verified), extracts the
xcframework to `local_packages/.../Libraries/`, strips `arm64e` via
`lipo -remove`, updates `Info.plist` SupportedArchitectures, and SPM
resolves the local `path:` target — surviving `.packages` regeneration.

**Validated**: Codemagic `ios-testflight` on `d6536b2` →
`bragmat.ipa` (arm64-only embedded, app + framework signatures valid,
App Store Connect upload succeeded — no 91011). 714/714 Flutter tests.
Pub-cache untouched; Android, crypto (Argon2id + XChaCha20-Poly1305),
and backup formats unchanged.

**Outstanding**: `sodium_libs` is discontinued (replaced by `sodium`).
Longer-term: migrate to `sodium` or vendor libsodium directly — the
override remains a stable interim fix.
