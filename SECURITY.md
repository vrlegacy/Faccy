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

- **Quitting Faccy disables protection.** It can be quit from the menu bar,
  Activity Monitor or `killall Faccy`, and nothing relaunches it. (Faccy's own
  window is locked, and "Launch at login" is on by default.)
- **Watchdog, not a pre-launch gate.** A newly launched protected app is
  killed as soon as Faccy sees it, but it can still flash on screen for a
  fraction of a second. True pre-launch blocking needs Apple's Endpoint
  Security entitlement. The app's data on disk (chats, mail, browser
  profiles) is never protected, only its UI.
- **Matching is by bundle identifier.** A re-signed copy of an app with a
  different bundle ID, a web/PWA version, or a CLI tool that reads the same
  data is not blocked.
- **No liveness check.** Only the built-in camera is used, but a photo or
  video of an enrolled person held up to it can pass.
- **Local data is plain JSON.** The face profile, settings and password hash can
  be read, replaced or deleted by the logged-in user.
- **The fallback password can be short.** Four characters are accepted and
  there is no limit on attempts.
- **Any enrolled fingerprint unlocks.** Touch ID accepts every fingerprint
  enrolled on the Mac, not just the owner's.

See the "Security model and limitations" section of the README for more.

## Reporting a vulnerability

If you find a way around Faccy that is **not** in the list above, please open a
[private security advisory](https://github.com/vrlegacy/Faccy/security/advisories/new)
rather than a public issue. Include your macOS version, Mac model and steps to
reproduce.
