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

- `flutter test` — full unit test suite (sqflite tests use sqflite_common_ffi)
- `flutter analyze` — ~145 pre-existing lint issues; don't add new ones
- `flutter build apk --debug` — Android debug build
- Manual backup/restore verification on the Moto G15 before tagging a
  validated baseline

## Baselines

- `v1.0.0-backup-restore-validated` — portable ZIP backup (create + restore)
  validated on Android, Phase 1+2 complete
- `feature/restore-hardening` — Stage 3 restore hardening, awaiting manual
  device validation
