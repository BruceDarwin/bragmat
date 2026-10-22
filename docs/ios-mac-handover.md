# Bragmat iOS — Mac Build &amp; Validation Checklist

Handover for the first macOS session on `feature/ios-prep`. Everything
below assumes a clean checkout of this branch. **Nothing here requires
an Apple Developer account until step 6** (physical device); TestFlight
is out of scope for this stage.

---

## 1. Environment

| Requirement | Notes |
|---|---|
| macOS | 15 (Sequoia) or newer |
| Xcode | 16.x — install from App Store, then `sudo xcodebuild -license accept` and `xcodebuild -runFirstLaunch` |
| CocoaPods | `sudo gem install cocoapods` (or `brew install cocoapods`) — required; the iOS project uses plugin pods |
| Flutter | Same channel/major as Windows (`flutter --version` to compare); `flutter doctor` must show iOS toolchain green |
| Repo | `git clone` / fetch, checkout `feature/ios-prep`, then `flutter pub get` |

## 2. First simulator build

```bash
flutter pub get
cd ios && pod install --repo-update && cd ..
flutter build ios --simulator --dart-define-from-file=.env
flutter run -d 'iPhone' --dart-define-from-file=.env   # pick a simulator device
```

`.env` is the same file as on Windows (copy it over — it is gitignored,
never commit it). Supabase credentials are compile-time; without them the
app deliberately shows "Configuration Error".

**Expected first-build issues:**

- **Pod install resolves a dozen plugin pods** (sqflite,
  flutter_secure_storage, geolocator, image_picker, file_selector,
  share_plus, sodium_libs, connectivity_plus, app_links, …) — first run
  is slow but should be clean.
- **`sodium_libs` pod** compiles a bundled XCFramework — watch for
  architecture issues on Intel Macs (arm64 simulator only is fine).
- **Minimum-deployment warnings** if any pod still declares iOS 12 —
  the project floor is 15.0; raise `platform :ios` in the generated
  `ios/Podfile` if a pod complains.
- **Swift/AppDelegate** — the template uses the implicit-engine style
  (`FlutterImplicitEngineDelegate`); no edits expected.
- **`.env` missing** → Configuration Error screen (intended).

## 3. iOS project state already prepared (Windows)

- Bundle ID `com.bragmat.app` (all three configs; tests target
  `com.bragmat.app.RunnerTests`)
- Deployment target **iOS 15.0**
- Info.plist: camera / photo-library / location usage descriptions,
  `bragmat` URL scheme (`bragmat://auth-callback` — same Supabase
  redirect as Android, **no Supabase change needed**),
  `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` (Documents
  visible in Files)
- `ios/Runner/PrivacyInfo.xcprivacy` — draft manifest, wired into the
  Resources build phase
- `file_selector 1.1.0` — backup import via UIDocumentPicker (file_picker
  is ruled out: its Android plugin can't compile under the project's
  AGP 9 toolchain — the same class of issue that removed it last time)
- `BackupFileService` — iOS: Files/Documents dir + share-sheet export;
  Android SAF paths unchanged

## 4. Signing for a physical iPhone (free tier)

1. Xcode → Settings → Accounts → add Apple ID (free account works).
2. Open `ios/Runner.xcworkspace` → Runner target → Signing &amp;
   Capabilities → Team = your personal team.
3. If `com.bragmat.app` is already registered to another account, Xcode
   will offer an alternate suffix — accept it for dev builds; the final
   bundle ID gets locked in at App Store Connect time.
4. `flutter run -d <iphone> --dart-define-from-file=.env` — free
   provisioning lasts 7 days.

## 5. Validation checklist (simulator + device)

### Simulator
- [ ] App launches past AuthGate (sign-in screen, not Configuration Error)
- [ ] SQLite opens — catch list renders, add/edit/delete a catch
- [ ] Settings shows Database Version 30, no debug section, no Cloud
      Backup row
- [ ] **Backup Data** → zip appears in Files ("On My iPhone → Bragmat")
- [ ] **Restore Data** → document picker opens; pick the zip; restore
      succeeds; cancel path returns cleanly
- [ ] Sign-out/sign-in; offline (Wi-Fi off) browse works

### Physical iPhone (adds)
- [ ] Camera permission prompt text is sensible; capture attaches photo
- [ ] Photo library prompt; gallery pick attaches photo
- [ ] **EXIF reality check:** does a gallery photo with GPS surface the
      photo-details dialog? (`requestFullMetadata` is set — verify
      whether EXIF/GPS actually arrives)
- [ ] Location permission prompt; "Use Current Location" captures coords
- [ ] Email-confirmation deep link `bragmat://auth-callback` opens the
      app (sign-up flow)
- [ ] Backup export via share sheet → "Save to Files" works; file
      visible in Files app
- [ ] Restore a real Android-created backup zip end-to-end

### Known expected platform differences
- **Camera photos carry no GPS EXIF on iOS** — Apple does not stamp
  location into captures delivered to apps. Photo-GPS provenance can only
  come from *gallery* photos (and only if EXIF survives — verify above).
- No process-death gallery recovery needed (iOS pickers are
  out-of-process).

## 6. Export-compliance determination (reviewed, not yet set)

`ITSAppUsesNonExemptEncryption` is **deliberately absent** pending this
finding:

- Encryption actually used: TLS/HTTPS (Supabase, Open-Meteo,
  WorldTides, OSM tiles), iOS Keychain via flutter_secure_storage,
  and `libsodium` (via `sodium_libs`) for the cloud-backup envelope —
  Cloud Backup is gated off, but the library is still linked.
- All of it is standard, publicly-available cryptography → qualifies
  under the EAR mass-market exemption (§740.13(b)(1)).
- **Recommended:** set `ITSAppUsesNonExemptEncryption = false` in
  Info.plist before the first App Store Connect upload — the correct and
  common treatment. A self-classification note may still be required in
  App Store Connect paperwork annually depending on jurisdiction; keep
  it consistent.
- Do **not** claim `false` if any proprietary/export-restricted crypto
  is ever added.

## 7. What is still unverified from Windows

Everything under §5 — the iOS code paths compile and are unit-tested at
the Dart level, but no iOS binary has been built yet. In particular the
document-picker UX, share-sheet anchor on iPad (`sharePositionOrigin`),
Files-app visibility, EXIF retention and the deep-link return all need a
real run.
