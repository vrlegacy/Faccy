<p align="center"><img src="Support/logo.png" width="160" alt="Faccy icon"></p>

# Faccy

[![Build](https://github.com/vrlegacy/Faccy/actions/workflows/build.yml/badge.svg)](https://github.com/vrlegacy/Faccy/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)

A macOS menu bar app that asks for your face — or Touch ID, or a password — before opening the apps you choose.

Faccy is a local-first prototype for Apple silicon Macs (including M5): the camera feed is processed on-device with Apple's Vision framework, and only face feature prints (no photos) are stored in `~/Library/Application Support/Faccy`.

> **Important:** Macs do not have Face ID. Faccy implements its own camera-based face verification, with Touch ID and a local password as fallbacks. It is a convenience layer, not a system security boundary, and it does not unlock your Mac or replace FileVault.

## What works

- **Up to 5 faces** — enroll, name, re-enroll or delete up to five faces (you, family, a colleague). Any enrolled face unlocks.
- **Face verification with a blink** — your face must match your enrolled profile and then blink once, so a still photo can't unlock anything. Only the Mac's built-in camera is used; external, iPhone (Continuity) and virtual cameras are ignored.
- **Faccy locks itself** — the main window (protected apps, face setup, settings) needs a check before you can use it, and locks again when you close it.
- **System-wide interception** — a watchdog kills protected apps launched from the Dock, Spotlight, Finder, or anywhere else the moment they appear, then asks you to authenticate before reopening them.
- **Automatic locking** — every protected app and Faccy's own window lock again when the screen locks, the Mac or its display sleeps, you switch users, or you're idle (5 minutes by default).
- **Dynamic Island-style prompt** — verification appears as a compact black pill at the top center of the screen, sized like the notch. It stays out of the way and never steals focus from what you are doing.
- **Camera preview only when needed** — the live preview stays hidden while recognition is quick. If no match is found within a few seconds, or recognition fails, the pill expands to show the camera and a retry button.
- **Reopen requires a fresh scan** — if you close a protected app's window while the app keeps running, bringing it back later hides the app and asks for face verification again, even inside a "remember unlock" session.
- **Protected app list** — choose installed apps that require authentication.
- **Secondary unlock** — Touch ID and up to 5 labeled fallback passwords (any one unlocks), for when the camera fails or Face Auth isn't set up.
- **Quick launch** — open protected apps from the main window or the menu bar.
- **Per-app sessions** — "Remember unlock" applies to each app separately: unlocking one app does not unlock the others.
- **Settings** — match tolerance, enrollment samples, capture quality, per-app unlock duration, idle lock, Faccy window lock, enforcement toggle, fallback unlock, launch at login (on by default), menu bar visibility, and data folder access.
- **Menu bar app** — no Dock icon; runs as an accessory app. The menu bar icon is optional: turn off **Show Faccy in the menu bar** in Settings for a completely hidden background app. You can still open Faccy from Spotlight or by launching `Faccy.app` again.
- **Local persistence** — settings, protected apps, feature prints, and the password hash are stored on disk.

### Authentication methods

Faccy tries face verification first, and offers these alternatives in the same prompt:

| Method | Notes |
| --- | --- |
| Face Auth | Built-in camera + Vision feature prints compared to every enrolled face (up to 5), followed by one blink. |
| Touch ID | Uses `LocalAuthentication` with `deviceOwnerAuthenticationWithBiometrics`. Only shown when a fingerprint is enrolled. |
| Custom passwords | Up to 5, each a salted, 60,000-round iterated SHA-256 hash stored in `passwords.json`. Minimum 4 characters. |

A successful fallback unlock uses the same session rules as a face match, so "Remember each app's unlock for" applies to all three. The one exception is reopening a protected app whose window was closed: that always requires a fresh check.

## Download

Grab the latest `Faccy-x.y.z.dmg` from [Releases](https://github.com/vrlegacy/Faccy/releases), open it and drag Faccy to Applications.

Faccy is ad-hoc signed, not notarized, so the first time macOS will say it can't verify the developer. Right-click Faccy in Applications and choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Faccy.app
```

## One-click build

Double-click **`build.command`** in Finder. It builds Faccy, makes `dist/Faccy-<version>.dmg`, quits any running copy, installs the app to `/Applications` (keeping only that one copy), and opens it.

## Publishing a release

Bump `CFBundleShortVersionString` if you like, then push a tag. GitHub Actions builds the app and attaches the DMG to a new release:

```bash
git tag v0.2.0
git push origin v0.2.0
```

## Build and run

Requirements: macOS 14 or newer, Swift 6 toolchain (Command Line Tools is enough).

```bash
git clone https://github.com/vrlegacy/Faccy.git
cd Faccy
./scripts/build.sh
open dist/Faccy.app
```

Or build and open in one step:

```bash
./scripts/build.sh --open
```

To install, move the built app into Applications so there is only one copy (macOS treats every copy with the same bundle ID as the same app, and two running copies means two watchdogs fighting each other):

```bash
rm -rf /Applications/Faccy.app && cp -R dist/Faccy.app /Applications/
open /Applications/Faccy.app
```

On first use macOS will ask for camera permission. If you denied it, enable Faccy in **System Settings › Privacy & Security › Camera**.

The build script creates an ad-hoc signed `.app` bundle in `dist/`. This is required for a stable bundle identifier and the `NSCameraUsageDescription` permission prompt. Do not use `swift run` for camera testing — the raw executable has no `Info.plist` and will refuse to start the camera.

## How it works

1. `AppModel` owns settings, the protected app list, the face profile, and the current auth/enrollment state.
2. `CameraController` manages `AVCaptureSession` and delivers throttled frames to the main queue.
3. `FaceAnalyzer` runs Vision off the main thread:
   - `VNDetectFaceRectanglesRequest` finds the largest face.
   - `VNDetectFaceCaptureQualityRequest` scores enrollment frames.
   - The face region is cropped with padding and passed to `VNGenerateImageFeaturePrintRequest`.
   - The resulting feature vector is compared with enrolled samples using L2 distance.
4. A launch request opens the notch panel. On success, `NSWorkspace` opens the app.
5. `AppGuard` listens for `NSWorkspace.didLaunchApplicationNotification` and polls running apps. When a protected app appears without Faccy's approval, it is terminated (force-terminated after one second if it ignores the quit), and the notch panel is shown. Approvals are tracked per process ID and expire after ten seconds, so a stale approval can't unlock a later manual launch.
6. After approval, `AppGuard` watches the app's visible windows. If the app is frontmost with no on-screen window for five seconds, it is marked closed. Bringing it back (Dock, `open`, Cmd-Tab, or a new window while already active) hides it and asks for a fresh verification. Detection is frontmost-only, so a minimized window or a window on another Space does not trigger a prompt.
7. Settings and profiles are persisted by `PersistenceStore` as JSON.

### Project layout

```
Sources/Faccy/
  FaccyApp.swift              App entry, main window, menu bar item
  Models/                     ProtectedApp, AppSettings, FaceProfile
  Services/
    AppModel.swift            Single source of truth / state machine
    AppGuard.swift            System-wide launch + reopen watchdog
    AuthWindowController.swift  Notch (Dynamic Island) verification panel
    SecondaryAuth.swift       Touch ID + password hashing
    CameraController.swift    AVFoundation capture session
    FaceAnalyzer.swift        Vision detection + feature prints
    AppCatalog.swift          Scans installed .app bundles
    AppLauncher.swift         NSWorkspace launch + login item helpers
    PersistenceStore.swift    JSON storage in Application Support
  Views/                      SwiftUI screens and components
    NotchAuthView.swift       Compact/expanding pill, preview, password entry
Support/Info.plist            Bundle metadata + camera usage description
Support/AppIcon.icns          App icon (source: Support/icon.svg)
scripts/build.sh              Builds dist/Faccy.app
scripts/make-dmg.sh           Packages the app into dist/Faccy-<version>.dmg
build.command                 Double-click: build, DMG, install, open
.github/workflows/            CI build + tag-triggered release with DMG
```

## Security model and limitations

This prototype is intentionally honest about its boundaries:

- **System-wide enforcement is a watchdog, not a kernel gate.** Faccy notices a new process as soon as it registers with the window server, hides it and kills it immediately (an app that was just launched has no unsaved work), so it is usually gone within a fraction of a second. It can still flash briefly. True pre-launch blocking needs an Apple-granted Endpoint Security entitlement, which a normal app cannot obtain. Faccy must be running for interception to work; quitting Faccy disables protection.
- **Apps already running when Faccy starts are locked, not closed.** When Faccy starts (usually at login), protected apps that are already open, or that open on their own in the next 30 seconds, are hidden and ask for a check when you switch to them. Nothing is quit or reopened. Turn off **Lock protected apps already running when Faccy starts** in Settings to leave them unlocked.
- **Protected apps are quit, not paused.** Faccy asks the app to quit, then force-quits after one second. Unsaved work in a protected app can be lost. This is a real tradeoff of watchdog-style enforcement.
- **Reopen detection is a heuristic.** Faccy decides a window was closed when the app is frontmost and reports no on-screen window for five seconds. An app that keeps an invisible layer-0 window, or that takes longer than five seconds to create its first window, may not be gated as expected. This is a watchdog, not a window-level lock.
- **Liveness is a single blink.** A printed photo cannot blink, and virtual cameras are refused, but a video of the enrolled person blinking, held up to the built-in camera, can still pass. Macs without a built-in camera (Mac mini, Mac Studio, Mac Pro) can only use Touch ID or the password.
- **Fallback passwords are local only.** It is stored as a salted, iterated hash (not plain text), but anyone who can read or replace the file in Application Support can tamper with Faccy's data. It protects against someone using your Mac, not against an attacker with your user account.
- **Touch ID is a fallback, not a second factor.** Any one method unlocks the app; they are alternatives, not a chain.
- **Vision feature prints are not a dedicated face-recognition model.** They are a practical baseline for a prototype. A production app should use a Core ML face-embedding model trained for recognition, with a calibrated threshold and liveness checks.
- **No encryption at rest yet.** Feature prints are stored as plain JSON in Application Support. For production, encrypt the profile with a Keychain-backed key.
- **Not notarized.** The generated app is ad-hoc signed for local development.
- **Tune the tolerance for your camera and lighting.** The default match tolerance is `0.45`. The match score is never shown, so use **Test Face** to check that you are recognized, then adjust the tolerance in Settings. Lower is stricter.
- **Re-enroll after a major macOS update** if recognition starts behaving differently; Apple can change Vision feature-print revisions between releases.

## Roadmap ideas

- Replace the feature-print baseline with a Core ML face-embedding model.
- Add a head-turn challenge on top of the blink check.
- Encrypt the face profile with a Keychain key.
- Add Apple Watch unlock as another fallback.
- Add per-app timeout rules and audit history.
- Investigate Endpoint Security for real pre-launch blocking (requires Apple entitlement).
- Add a proper app icon, onboarding, and notarized distribution.

## Security

Read [SECURITY.md](SECURITY.md) for the threat model, known bypasses, and how to report a vulnerability.

## License

[MIT](LICENSE) © vrlegacy
