# Stage 4C → Photo Metadata handover

Status: `feature/stage4-integration` @ `7aa01b6` — all work committed and
pushed. Stage 4C validated at `3874db9` (this commit adds the record only).

## What the next stage inherits

- Supabase `bragmat-dev` (`xszodjyyueouiktclsvy`) is live: private
  `backups` bucket, `delete-backups` Edge Function, RLS + audit table.
  Do NOT re-apply migrations — `0002_cloud_backup.sql` is already
  deployed (it is idempotent, but redeployment is unnecessary).
- Cloud restore is fail-closed: missing or mismatched recorded sha256
  aborts before decrypt/restore. Unit + live coverage exists
  (`cloud_backup_service_test.dart`, `cloud_live_e2e_test.dart`).
- `test/cloud_live_e2e_test.dart` is opt-in via
  `--dart-define=CLOUD_E2E_CREDS_FILE=<path>` — the creds file is
  operator-created, never committed.
- Backups bucket is empty; test account T
  (`bragmat.test.t@bragmat.invalid`) was reinstated to `invited`.
- Cloud Backup UI: backup rows are tappable (restore); delete is a
  separate icon. Cloud Backup on the G15 is OFF and untouched.

## Boundaries carried forward

- Moto G15 released from active testing — ANY device change for Photo
  Metadata needs a fresh explicit approval from the user.
- No merge to `main`, no release tag until the user approves.
- Photo Metadata work stays isolated on its own branch/worktree.
- The user's dataset was never uploaded to the cloud — that exclusion
  stands unless the user explicitly approves otherwise.
- Existing off-device backups (`Documents\Bragmat Backups\` and
  `/sdcard/Download`) must remain untouched.

## Environment notes

- Auth builds: `flutter build apk --debug --dart-define-from-file=.env`;
  install ONLY via `tool/safe_install.sh` (never `flutter install` /
  `adb uninstall`).
- Tests: `flutter test` (325 passing; sqflite via `sqflite_common_ffi`,
  libsodium dll path in test files).
- Emulator `Pixel_9` was the working AVD (currently shut down);
  `Pixel_8` is stale — don't use it.
