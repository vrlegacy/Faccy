# Security Policy

## Threat model

Faccy is a **convenience lock** for apps on a Mac you already control. It is
designed to stop a casual person who sits down at your unlocked Mac from
opening specific apps. It is **not** a security boundary against someone who
knows how Faccy works, has your macOS user account, or has admin rights.

Everything Faccy enforces runs as an ordinary user-level process. Anything
that same user can do — quit a process, edit a file in
`~/Library/Application Support/Faccy`, run a command in Terminal — can also
undo Faccy.

## Known limitations

These are known and documented, not vulnerabilities to report:

- **Faccy's own window is not locked.** Settings, the protected-app list,
  enrollment, and the fallback password can be changed without authenticating.
- **Quitting Faccy disables protection.** It can be quit from the menu bar,
  Activity Monitor, `killall Faccy`, or by logging out and back in when
  "Launch at login" is off. Nothing relaunches it.
- **Watchdog, not a pre-launch gate.** A protected app runs for up to ~2 s
  before it is quit. Its data on disk (chats, mail, browser profiles) is never
  protected, only its UI.
- **Matching is by bundle identifier.** A re-signed copy of an app with a
  different bundle ID, a web/PWA version, or a CLI tool that reads the same
  data is not blocked.
- **No liveness detection.** A photo, video, or virtual camera feed of the
  enrolled person can pass face verification.
- **Local data is plain JSON.** The face profile, settings and password hash can
  be read, replaced or deleted by the logged-in user.
- **Any enrolled fingerprint unlocks.** Touch ID accepts every fingerprint
  enrolled on the Mac, not just the owner's.

See the "Security model and limitations" section of the README for more.

## Reporting a vulnerability

If you find a way around Faccy that is **not** in the list above, please open a
[private security advisory](https://github.com/vrlegacy/Faccy/security/advisories/new)
rather than a public issue. Include your macOS version, Mac model and steps to
reproduce.
