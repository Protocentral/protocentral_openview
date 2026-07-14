# Mobile deployment — current state and what's missing

Written 2026-07-14, alongside the v3.0.0 desktop release. Desktop (Linux /
Windows / macOS) now builds and publishes from `.github/workflows/release.yml`.
**Mobile does not ship from CI at all.** This is the working notes for that.

OpenView is already live on both stores, so nothing here is greenfield:

- App Store (iPhone / iPad / Apple Silicon Mac) — `id1667747246`, `com.protocentral.openview`
- Google Play — `com.protocentral.openview`

## Where mobile deployment actually stands

**iOS — manual, from a developer Mac.** `ios.sh` runs `flutter build ios
--release --no-codesign` then `fastlane ios beta`, and `ios/fastlane/Fastfile`
does `build_app` → `upload_to_testflight`. That works, but:

- It is not wired into any workflow. Every release is somebody's laptop.
- `ios/fastlane/Appfile` authenticates as a personal Apple ID
  (`ashwinkw@ieee.org`). CI needs an **App Store Connect API key** (issuer ID,
  key ID, `.p8`) instead — an Apple ID login with 2FA cannot run unattended.
- There is no `match`/certificate management, so signing assets live only on
  that one Mac.

**Android — nothing.** No fastlane, no Play publishing, no signed build.
`distribution/whatsnew/whatsnew-en-US` is a leftover from a
`r0adkll/upload-google-play` setup that no longer exists in this repo — nothing
reads it today.

## Fixed already (found while getting v3.0.0 out)

- **A Java keystore was committed** — `android/akw-newkey`, in the initial
  commit, in a public repo. Removed from HEAD and `*.jks`/`key.properties`/`*.p12`
  are now gitignored. **The key is still public in git history and in the 14
  forks — it must be rotated.** See "Key rotation" below.
- **`flutter build apk --release` was broken in CI**: an undefined GitHub
  Actions secret is exported as an *empty string*, so
  `System.getenv("KEYSTORE_BASE64") != null` was true with no secret set, and
  Gradle wrote a zero-byte keystore. Now tests for blank.
- **`flutter build apk --release` OOM'd** — `JetifyTransform` ran out of heap at
  `-Xmx1536M`. Now `-Xmx4g`, and `android.enableJetifier=false` (every plugin
  here is AndroidX already). *Unverified — no Android build has run since.*

## Key rotation (do this first)

The exposed keystore is almost certainly your Play **upload** key, not the app
signing key — if Play App Signing is on, Google holds the signing key and the
upload key is resettable.

1. Play Console → Test and release → Setup → **App integrity** → App signing.
2. If Play App Signing is enabled: **Request upload key reset**, upload a new
   upload certificate. Old key stops working; users are unaffected.
3. If it is *not* enabled, the leaked key signs your published app — that is the
   bad case, and it needs an app signing key upgrade (new installs only).

A backup of the removed keystore is at `~/.protocentral-keys/akw-newkey.jks` on
Ashwin's machine. Treat it as burned.

## To deploy Android from CI

1. New release keystore, kept out of the repo. Secrets: `KEYSTORE_BASE64`,
   `KEY_ALIAS`, `KEY_PASSWORD`, `STORE_PASSWORD`. (The `key.properties` plumbing
   in `android/app/build.gradle.kts` already reads these.)
2. `flutter build appbundle --release` for Play; `flutter build apk --release`
   only if you also want a sideload asset on the GitHub release.
3. Play service account JSON → `PLAY_SERVICE_ACCOUNT_JSON` secret →
   `r0adkll/upload-google-play` with `track: internal`, promoting manually.
   `distribution/whatsnew/` becomes the `whatsNewDirectory` again.

Note: a GitHub-released APK can never upgrade a Play-installed app in place —
Play delivers APKs signed with Google's app signing key. That is expected, not a
bug, and it is independent of which keystore we choose.

## To deploy iOS from CI

1. App Store Connect API key → secrets (`ASC_KEY_ID`, `ASC_ISSUER_ID`,
   `ASC_KEY_P8`). Replace the `apple_id` auth in `Appfile`.
2. Signing assets into CI — `fastlane match` (private certs repo) is the usual
   answer; otherwise import a distribution `.p12` + provisioning profile from
   secrets, like the macOS job does.
3. `macos-latest` runner, `flutter build ipa` (or fastlane `build_app`), then
   `upload_to_testflight`.

## Bugs to fix before the next mobile release

- **`NSLocalNetworkUsageDescription` is missing from `ios/Runner/Info.plist`.**
  `lib/transport/wifi_service.dart` is a raw TCP client to a LAN `host:port`. On
  iOS 14+ that requires the local-network permission, and without the usage
  string iOS never prompts and refuses the connection — **Wi-Fi mode is probably
  broken on iOS today**. Worth reproducing on a device first.
- `NSAppTransportSecurity.NSAllowsArbitraryLoads = true` is a blanket ATS
  exemption and invites App Store review questions. If it is only there for the
  LAN TCP transport, `NSAllowsLocalNetworking` is the narrower answer.
- `ITSEncryptionExportComplianceCode` is set to the string `"Yes"`, which is not
  a compliance code. With `ITSAppUsesNonExemptEncryption = false` it should just
  be removed.
- iOS deployment target is inconsistent: `Podfile` says 13.1, the Runner target
  says 15.3, `Info.plist` `LSMinimumSystemVersion` says 13.0.
- `AndroidManifest.xml` declares `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`
  *and* removes the `-sdk-23` variants, while `BLUETOOTH_SCAN` is already
  `neverForLocation`. If location is not actually needed, dropping it simplifies
  the Play data-safety declaration.
- `WRITE_EXTERNAL_STORAGE` / `READ_EXTERNAL_STORAGE` are declared with no
  `maxSdkVersion` — Play flags this on modern targets.
- Cosmetic: `MainActivity.kt` declares `package com.protocentral.openview` but
  lives in `.../kotlin/com/protocentral/healthypiconnect/`. Stale
  `MARKETING_VERSION = 2.0.15` / `CURRENT_PROJECT_VERSION = 85` in
  `ios/Runner.xcodeproj` are harmless (Info.plist uses `$(FLUTTER_BUILD_NAME)` /
  `$(FLUTTER_BUILD_NUMBER)`, so Flutter's pubspec version wins).

## F-Droid

Customers have asked for it. It is feasible, and the licence is not the problem
— the repo is MIT, there is no telemetry, no ads, no Firebase.

**The one blocker is `geolocator`.** It is declared in `pubspec.yaml` but
**imported nowhere in `lib/`**, and `geolocator_android` pulls in
`com.google.android.gms:play-services-location` — a proprietary dependency
F-Droid will not build against. Deleting the dependency removes the blocker,
shrinks the APK, and drops Play Services entirely. That is a one-line change
plus a `flutter pub get`, and it is worth doing regardless of F-Droid.

After that, F-Droid inclusion is a metadata exercise, not an engineering one:

1. Verify `flutter build apk --release` works from a clean checkout (needs the
   Gradle heap fix above to be confirmed).
2. Submit a metadata YAML merge request to
   [fdroiddata](https://gitlab.com/fdroid/fdroiddata) with a build recipe using
   the Flutter srclib, pinned to our Flutter version, plus
   `UpdateCheckMode: Tags` and `AutoUpdateMode: Version` so new git tags are
   picked up automatically.
3. Expect review round-trips on the first MR.

Effort: roughly a day for the first submission, then near-zero per release
(F-Droid builds from tags). Two things to tell users up front: F-Droid signs
with **its own key**, so the F-Droid build and the Play build cannot upgrade each
other — switching stores means uninstall/reinstall — and F-Droid builds land
days after the Play release, because they build and sign on their own
infrastructure.
