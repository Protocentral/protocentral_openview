# Auto-update — phase 1 (check and notify)

Written 2026-09-10. Implements the desktop update check; **phase 2 (true
one-click update) is not built** — see the bottom of this file for what it
needs.

## The shape of the problem

| Platform | How it updates | What OpenView does |
| --- | --- | --- |
| iOS / Android | App Store, Google Play | Nothing. The store updates it. |
| Desktop (GitHub Release zips) | Nothing — the user must notice a new release | Checks daily, shows a banner, opens the download in a browser |

Desktop is the whole problem: `.github/workflows/release.yml` publishes raw
zips, so somebody who downloaded v3.0.0 has no way to learn that v3.2.0 exists.

## What phase 1 does

1. Two seconds after first frame, [`UpdateController.checkAtStartup`](../lib/controllers/update_controller.dart)
   GETs `/repos/Protocentral/protocentral_openview/releases/latest`.
2. If the tag parses to a version newer than `package_info_plus` reports, the
   [`UpdateBanner`](../lib/ui/widgets/update_banner.dart) appears above the page
   body with **What's new** / **Download** / dismiss.
3. **Download** opens the matching release asset in the user's browser. Nothing
   is downloaded, verified, or installed by the app.

The same check runs on demand from Settings → About → **Check for updates**.

It never blocks startup, never throws out of the check, and stays silent when
offline or rate-limited.

## The distribution-channel gate

`UpdateChannel.isSelfDistributed` is the master switch, and it is
`String.fromEnvironment('OV_CHANNEL')` — **`store` by default**, so a build that
forgets the flag stays quiet rather than nagging App Store or Play users with a
GitHub zip. Only the desktop jobs in `release.yml` pass
`--dart-define=OV_CHANNEL=github`.

When it is off, the whole feature is absent: no check, no banner, and no
Updates card in Settings. Future distro packages (Flathub, AUR) should stay on
the default so the package manager keeps ownership of updating.

To exercise the flow locally:

```sh
flutter run -d macos --dart-define=OV_CHANNEL=github
```

Because the tag will match your own version, Settings → About will say "You are
running the latest release" rather than showing a banner. To see the banner,
temporarily lower `version:` in `pubspec.yaml`.

## Things that are easy to break

- **Asset names are duplicated.** `UpdateController.assetNameForCurrentPlatform`
  hard-codes the four zip names produced by the `Package` steps in
  `release.yml`. Rename one there without renaming it here and the dialog
  quietly degrades to the release page instead of a direct download.
  `test/update_controller_test.dart` pins the names but cannot see the workflow.
- **Rate limit.** Unauthenticated GitHub API is 60 requests/hour *per IP*. One
  check per day per user is nowhere near it, but a shared lab NAT plus a tight
  loop would be — hence `lastUpdateCheck` in `openview_settings.json` and the
  24 h `_checkInterval`.
- **`/releases/latest` excludes prereleases**, which is what we want: a
  `v3.3.0-rc1` tag must not nag stable users. Do not switch to `/releases`
  without re-adding that filter.
- **Release notes are Markdown**, and OpenView has no Markdown renderer.
  `_ReleaseNotes` flattens headings, bullets and emphasis by hand and collapses
  PR URLs to `#123`. It is deliberately dumb — if the notes ever need real
  rendering, add `flutter_markdown` rather than growing that function.

## User controls

**Settings → About → Check for updates** is the manual check, sitting next to
the version it is about — the familiar desktop "About → Check for Updates…"
idiom. It ignores both the daily cadence and any skipped version (the user
asked), and reports the same way: the release-notes dialog when there is
something, a snackbar when there isn't. The line beside the button carries the
standing state — last checked, up to date, or the error from the last attempt.

**Settings → Updates** carries the preferences only, so there is exactly one
check button on the screen:

- **Check for updates automatically** — persisted as `autoCheckUpdates`.
- **What's new in x.y.z** — reopens the dialog after a check has found
  something.
- **Un-skip x.y.z** — clears `skippedUpdateVersion`.

Both are absent on store builds. Dismissing the banner with the × hides it for
the session; **Skip this version** in the dialog suppresses it for good.

## Phase 2 — what real one-click updates need

The standard answer for desktop Flutter is
[`auto_updater`](https://pub.dev/packages/auto_updater), which wraps **Sparkle**
(macOS) and **WinSparkle** (Windows) and consumes an `appcast.xml` published
alongside the release. Some prerequisites are still missing:

1. **macOS signing and notarization are in place.** The release workflow signs
   with Developer ID, submits the app to Apple's notary service, and staples the
   ticket before packaging. Sparkle's remaining prerequisite is a signed
   installer/update feed; this step alone does not add auto-updates.
   The workflow requires `AC_CERTIFICATE` (base64-encoded Developer ID `.p12`),
   `AC_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_ID`, and
   `APPLE_APP_SPECIFIC_PASSWORD` repository secrets.
2. **Windows needs an installer** (MSIX or Inno Setup), not a zip — WinSparkle
   updates by running one. Without an OV/EV code-signing cert, SmartScreen will
   flag every build.
3. **Linux is not supported by `auto_updater` at all.** Linux stays on the
   phase-1 notify path, or moves to Flathub and lets the package manager own it.

Do the signing and notarization first — it fixes the Gatekeeper warning on its
own merits, and everything else is blocked behind it.

Deliberately **not** on the roadmap: downloading and swapping the app bundle
ourselves. macOS quarantine and Gatekeeper, Windows file locks on the running
`.exe`, and hand-rolled signature verification are exactly what Sparkle and
WinSparkle exist to handle.
