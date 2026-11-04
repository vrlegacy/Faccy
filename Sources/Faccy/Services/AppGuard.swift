import AppKit
import Foundation

/// Watches protected apps across the whole system.
///
/// Two things are enforced:
/// 1. An app launched from anywhere other than Faccy is quit and must be
///    authenticated before it is relaunched.
/// 2. An app Faccy approved is "closed" again once it is frontmost with no
///    on-screen windows for a few seconds (its window was closed while the app
///    kept running). Reopening that window hides the app and asks for a fresh
///    authentication.
///
/// "Closed" is only judged while the app is active: a window that is minimized
/// or on another Space is not treated as closed.
///
/// This is a watchdog, not a kernel-level gate: an app can appear briefly
/// before it is hidden or quit.
@MainActor
final class AppGuard {
    /// Called once per blocked process with the protected app's bundle identifier.
    var onBlockedLaunch: ((String) -> Void)?
    /// Called when a running protected app is reopened after being closed or
    /// hidden. The app has already been hidden by the time this fires.
    var onReopenNeedsAuth: ((String) -> Void)?

    /// When false, protected apps that are already running when the watchdog
    /// starts are adopted instead of being quit.
    var enforceExistingApps = true

    /// Turn interception on or off. Turning it off leaves running apps alone.
    var isEnabled = false {
        didSet {
            guard oldValue != isEnabled else { return }
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }

    private var protectedBundleIDs: Set<String> = []
    /// Bundle ID -> time the approval was granted. Consumed by the next launch.
    private var pendingAuthorizations: [String: Date] = [:]
    private var authorizedPIDs: [pid_t: String] = [:]
    private var authorizedAt: [pid_t: Date] = [:]
    private var blockedPIDs: Set<pid_t> = []
    /// Approved processes that lost all visible windows. Sticky until reopened.
    private var closedPIDs: Set<pid_t> = []

    private var launchObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    private var readyAt = Date.distantPast

    /// Give the app a moment to finish launching before we start acting.
    private static let startupGrace: TimeInterval = 1.5
    private static let forceTerminateDelay: TimeInterval = 1.0
    private static let pollInterval: TimeInterval = 0.7
    /// Time after approval before "no windows" counts as closed. Long enough
    /// that an app still creating its window is not mistaken for a closed one.
    private static let windowGrace: TimeInterval = 5.0

    // MARK: - Configuration

    func updateProtectedApps(_ apps: [ProtectedApp]) {
        protectedBundleIDs = Set(apps.map(\.bundleID))
    }

    /// Marks the next launch of `bundleID` as Faccy-approved so it is not blocked.
    func authorizeNextLaunch(of bundleID: String) {
        pendingAuthorizations[bundleID] = Date()
    }

    /// Approves any instance of `bundleID` that is currently running.
    func authorizeRunningInstances(of bundleID: String) {
        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier == bundleID && !app.isTerminated {
            let pid = app.processIdentifier
            authorizedPIDs[pid] = bundleID
            authorizedAt[pid] = Date()
            closedPIDs.remove(pid)
        }
    }

    /// Unhides and activates an app after the user authenticated.
    func reopen(bundleID: String) {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && !$0.isTerminated
        }

        for app in apps {
            let pid = app.processIdentifier
            authorizedPIDs[pid] = bundleID
            authorizedAt[pid] = Date()
            closedPIDs.remove(pid)
            app.unhide()
        }

        apps.first?.activate(options: [.activateAllWindows])
    }

    /// True when the app is running with a process Faccy already approved.
    func isAuthorizedRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == bundleID
                && !app.isTerminated
                && authorizedPIDs[app.processIdentifier] == bundleID
        }
    }

    /// Stops treating an app's current process as protected.
    func forgetAuthorizations() {
        authorizedPIDs.removeAll()
        authorizedAt.removeAll()
        pendingAuthorizations.removeAll()
        closedPIDs.removeAll()
    }

    // MARK: - Lifecycle

    func start() {
        guard launchObserver == nil else { return }
        readyAt = Date().addingTimeInterval(Self.startupGrace)

        if !enforceExistingApps {
            for app in NSWorkspace.shared.runningApplications {
                guard let bundleID = app.bundleIdentifier,
                      protectedBundleIDs.contains(bundleID)
                else { continue }
                authorizedPIDs[app.processIdentifier] = bundleID
                authorizedAt[app.processIdentifier] = Date()
            }
        }

        let center = NSWorkspace.shared.notificationCenter

        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.evaluate(app)
            }
        }

        activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.handleActivation(app)
            }
        }

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        if let launchObserver {
            center.removeObserver(launchObserver)
            self.launchObserver = nil
        }
        if let activationObserver {
            center.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        pollTimer?.invalidate()
        pollTimer = nil
        pendingAuthorizations.removeAll()
        blockedPIDs.removeAll()
    }

    // MARK: - Evaluation

    private func poll() {
        guard isEnabled else { return }
        pruneDeadPIDs()

        let snapshot = Self.windowSnapshot()
        updateClosedState(snapshot: snapshot)
        gateReopenedWindows(snapshot: snapshot)

        for app in NSWorkspace.shared.runningApplications {
            evaluate(app)
        }
    }

    private func evaluate(_ app: NSRunningApplication) {
        guard isEnabled, Date() >= readyAt else { return }
        guard let bundleID = app.bundleIdentifier,
              protectedBundleIDs.contains(bundleID),
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return
        }

        let pid = app.processIdentifier
        if authorizedPIDs[pid] == bundleID { return }
        if app.isTerminated { return }

        // This launch came from Faccy itself — let it through. Approvals are
        // short-lived so a stale one cannot authorize a later manual launch.
        if let approvedAt = pendingAuthorizations[bundleID] {
            pendingAuthorizations.removeValue(forKey: bundleID)
            if Date().timeIntervalSince(approvedAt) < 10 {
                authorizedPIDs[pid] = bundleID
                authorizedAt[pid] = Date()
                return
            }
        }

        guard !blockedPIDs.contains(pid) else { return }
        blockedPIDs.insert(pid)

        app.terminate()
        scheduleForceTerminate(pid: pid, bundleID: bundleID)
        onBlockedLaunch?(bundleID)
    }

    private func handleActivation(_ app: NSRunningApplication) {
        guard isEnabled, Date() >= readyAt else { return }
        guard let bundleID = app.bundleIdentifier,
              protectedBundleIDs.contains(bundleID),
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return
        }

        let pid = app.processIdentifier
        // Only apps Faccy already approved are reopened this way. Unauthorized
        // launches are handled by `evaluate`.
        guard authorizedPIDs[pid] == bundleID, closedPIDs.contains(pid) else { return }

        app.hide()
        onReopenNeedsAuth?(bundleID)
    }

    private func updateClosedState(snapshot: WindowSnapshot) {
        let now = Date()

        for (pid, bundleID) in authorizedPIDs where protectedBundleIDs.contains(bundleID) {
            guard let grantedAt = authorizedAt[pid],
                  now.timeIntervalSince(grantedAt) > Self.windowGrace,
                  let app = NSRunningApplication(processIdentifier: pid),
                  !app.isTerminated
            else { continue }

            // Only judge "closed" while the app is frontmost. When it is not
            // active its window may simply be on another Space or minimized,
            // which is not the same as the user closing it.
            guard app.isActive else { continue }

            if (snapshot.onscreenIDs[pid] ?? []).isEmpty, closedPIDs.insert(pid).inserted {
            }
        }
    }

    /// A closed app that reopens its window while it is already the frontmost
    /// app does not post an activation notification, so catch that here too.
    private func gateReopenedWindows(snapshot: WindowSnapshot) {
        for pid in closedPIDs {
            guard let bundleID = authorizedPIDs[pid],
                  protectedBundleIDs.contains(bundleID),
                  let app = NSRunningApplication(processIdentifier: pid),
                  !app.isTerminated,
                  !app.isHidden,
                  app.isActive,
                  !(snapshot.onscreenIDs[pid] ?? []).isEmpty
            else { continue }

            app.hide()
            onReopenNeedsAuth?(bundleID)
        }
    }

    private func scheduleForceTerminate(pid: pid_t, bundleID: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.forceTerminateDelay * 1_000_000_000))
            guard let self else { return }
            defer { self.blockedPIDs.remove(pid) }

            guard let current = NSRunningApplication(processIdentifier: pid), !current.isTerminated else {
                return
            }
            if self.authorizedPIDs[pid] == bundleID { return }
            current.forceTerminate()
        }
    }

    private func pruneDeadPIDs() {
        authorizedPIDs = authorizedPIDs.filter { pid, _ in
            guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
            return !app.isTerminated
        }

        let alive = Set(authorizedPIDs.keys)
        authorizedAt = authorizedAt.filter { alive.contains($0.key) }
        closedPIDs = closedPIDs.filter { alive.contains($0) }

        pendingAuthorizations = pendingAuthorizations.filter { _, grantedAt in
            Date().timeIntervalSince(grantedAt) < 10
        }
    }

    /// Layer-0 windows belonging to each process, split into "exists" and
    /// "currently on screen".
    ///
    /// Window IDs are stable for the lifetime of a window, so we can remember
    /// which windows were real and visible. `.optionAll` keeps minimized
    /// windows and windows on other Spaces in `allIDs`, which means switching
    /// Spaces or minimizing does not look like closing the window.
    private struct WindowSnapshot {
        var allIDs: [pid_t: Set<CGWindowID>] = [:]
        var onscreenIDs: [pid_t: Set<CGWindowID>] = [:]
    }

    private static func windowSnapshot() -> WindowSnapshot {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return WindowSnapshot()
        }

        var snapshot = WindowSnapshot()
        for window in info {
            guard let owner = window[kCGWindowOwnerPID as String] as? Int,
                  let number = window[kCGWindowNumber as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue,
                  width >= 100, height >= 100
            else { continue }

            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
            guard layer == 0, alpha > 0 else { continue }

            let pid = pid_t(owner)
            let id = CGWindowID(number)
            snapshot.allIDs[pid, default: []].insert(id)
            if (window[kCGWindowIsOnscreen as String] as? Bool) == true {
                snapshot.onscreenIDs[pid, default: []].insert(id)
            }
        }
        return snapshot
    }
}
