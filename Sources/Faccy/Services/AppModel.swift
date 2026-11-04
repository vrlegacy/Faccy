import AppKit
import AVFoundation
import Combine
import Foundation
import LocalAuthentication
import UniformTypeIdentifiers

enum AuthState: Equatable {
    case idle
    case scanning
    case failed(String)
    case success
}

enum EnrollmentPhase: Equatable {
    case idle
    case preparing
    case capturing
    case saving
    case completed
    case failed(String)
}

struct AuthRequest: Identifiable {
    enum Origin {
        /// The user pressed Open inside Faccy.
        case requested
        /// The watchdog caught the app launching somewhere else and closed it.
        case blocked
        /// The app was still running but its window was closed; reopening it
        /// requires a fresh check.
        case reopened
        /// The user is opening Faccy's own window.
        case faccyWindow
    }

    let id = UUID()
    let app: ProtectedApp?
    var origin: Origin = .requested
}

/// The app's single source of truth: settings, protected apps, profile, and auth state.
@MainActor
final class AppModel: ObservableObject {
    let persistence: PersistenceStore
    let camera = CameraController()
    let analyzer = FaceAnalyzer()
    let catalog = AppCatalog()
    let launchGuard = AppGuard()
    let authWindow = AuthWindowController()

    @Published var settings: AppSettings {
        didSet {
            persistence.saveSettings(settings)
            // If the window was usable without a check before this change
            // (lock off, or no unlock method yet), the person changing
            // settings is already inside it — don't lock them out mid-edit.
            let couldAuthenticateBefore = isEnrolled
                || (oldValue.allowTouchID && biometricsAvailable)
                || (oldValue.allowPasswordFallback && hasPassword)
            if !oldValue.lockFaccyWindow || !couldAuthenticateBefore {
                isFaccyUnlocked = true
            }
            if oldValue.cameraDeviceID != settings.cameraDeviceID {
                camera.selectDevice(id: settings.cameraDeviceID)
            }
            if oldValue.authValiditySeconds != settings.authValiditySeconds {
                scheduleSessionExpiry()
            }
            if oldValue.enforceSystemWide != settings.enforceSystemWide {
                launchGuard.isEnabled = settings.enforceSystemWide
            }
            if oldValue.enforceAtStartup != settings.enforceAtStartup {
                launchGuard.enforceExistingApps = settings.enforceAtStartup
            }
        }
    }

    @Published var protectedApps: [ProtectedApp] {
        didSet {
            persistence.saveProtectedApps(protectedApps)
            launchGuard.updateProtectedApps(protectedApps)
        }
    }

    /// Enrolled faces. Any one of them unlocks.
    @Published private(set) var faces: [FaceProfile] = []
    static let maxFaces = 5
    static let maxPasswords = 5
    @Published var authRequest: AuthRequest?
    @Published private(set) var authState: AuthState = .idle
    @Published private(set) var enrollmentPhase: EnrollmentPhase = .idle
    @Published private(set) var enrollmentCollected = 0
    @Published private(set) var lastFaceQuality: Double?
    @Published var cameraHint: String = ""
    @Published var errorMessage: String?
    /// When each protected app was last unlocked, keyed by bundle ID.
    /// Every app has its own session.
    @Published private(set) var appUnlockedAt: [String: Date] = [:]
    /// Whether Faccy's own window has been unlocked since it was last locked.
    @Published private(set) var isFaccyUnlocked = false

    // Secondary authentication
    @Published private(set) var biometricsAvailable = SecondaryAuth.biometricsAvailable
    /// Fallback passwords. Any one of them unlocks.
    @Published private(set) var passwords: [PasswordRecord] = []
    @Published private(set) var isSecondaryInProgress = false
    @Published var secondaryError: String?

    // Notch UI
    /// The compact pill hides the camera preview until recognition needs help.
    @Published private(set) var revealCamera = false
    /// Shows the inline password field inside the pill.
    @Published var showPasswordEntry = false
    /// Height the notch content wants. The window follows this instead of
    /// measuring itself, which avoids a resize feedback loop.
    @Published var notchHeight: CGFloat = 60

    private var authTimeoutTask: Task<Void, Never>?
    private var authDismissTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var sessionExpiryTask: Task<Void, Never>?
    private var successFrames = 0
    private var enrollmentEmbeddings: [[Float]] = []
    /// The face being (re-)enrolled: an existing id to replace, or nil for a new face.
    private var enrollmentTargetID: UUID?
    private var enrollmentName = ""
    private var lastEnrollmentSampleAt = Date.distantPast
    private var pendingGate: PendingGate?
    private var cancellables = Set<AnyCancellable>()

    // Touch ID runs alongside the face scan; whichever succeeds first wins.
    private var biometricContext: LAContext?

    // Automatic locking
    private var idleTimer: Timer?
    private var isIdleLocked = false
    private var lockObservers: [NSObjectProtocol] = []

    /// A protected app that needs attention once the current prompt closes.
    private struct PendingGate {
        let bundleID: String
        let origin: AuthRequest.Origin
    }

    /// Seconds of fruitless scanning before the live preview is revealed.
    private static let previewRevealDelay: TimeInterval = 5

    init() {
        let store = PersistenceStore()
        persistence = store
        settings = store.loadSettings()
        protectedApps = store.loadProtectedApps()
        faces = store.loadFaces()
        passwords = store.loadPasswords()

        launchGuard.updateProtectedApps(protectedApps)
        launchGuard.enforceExistingApps = settings.enforceAtStartup
        launchGuard.onBlockedLaunch = { [weak self] bundleID in
            self?.handleBlockedLaunch(bundleID)
        }
        launchGuard.onReopenNeedsAuth = { [weak self] bundleID in
            self?.handleReopenGate(bundleID)
        }
        launchGuard.isEnabled = settings.enforceSystemWide

        if settings.launchAtLogin, !LoginItemManager.isEnabled {
            _ = LoginItemManager.setEnabled(true)
        }

        camera.onFrame = { [weak self] buffer in
            self?.handleFrame(buffer)
        }

        camera.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        camera.$authorizationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.handleAuthorizationChange(status)
            }
            .store(in: &cancellables)

        camera.$errorMessage
            .receive(on: RunLoop.main)
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.handleCameraError(message)
            }
            .store(in: &cancellables)

        DispatchQueue.main.async { [weak self] in
            self?.catalog.refresh()
        }

        startLockMonitoring()
    }

    // MARK: - Derived state

    var isEnrolled: Bool {
        faces.contains { !$0.isEmpty }
    }

    var hasPassword: Bool {
        !passwords.isEmpty
    }

    var canAddFace: Bool {
        faces.count < Self.maxFaces
    }

    var canAddPassword: Bool {
        passwords.count < Self.maxPasswords
    }

    var isEnrolling: Bool {
        enrollmentPhase == .preparing || enrollmentPhase == .capturing
    }

    /// True while this app is inside its own "remember unlock" window.
    func isSessionValid(for bundleID: String) -> Bool {
        guard settings.authValiditySeconds > 0, let unlockedAt = appUnlockedAt[bundleID] else { return false }
        return Date().timeIntervalSince(unlockedAt) < Double(settings.authValiditySeconds)
    }

    /// True when at least one protected app is currently unlocked.
    var hasActiveSessions: Bool {
        appUnlockedAt.keys.contains { isSessionValid(for: $0) }
    }

    /// Faccy's own window needs a check before it can be used. Until some
    /// unlock method exists there is nothing to check with, so the window
    /// stays open for first-time setup.
    var isFaccyLocked: Bool {
        settings.lockFaccyWindow && canAuthenticate && !isFaccyUnlocked
    }

    var touchIDAvailable: Bool {
        settings.allowTouchID && biometricsAvailable
    }

    var passwordAvailable: Bool {
        settings.allowPasswordFallback && hasPassword
    }

    var secondaryAuthAvailable: Bool {
        touchIDAvailable || passwordAvailable
    }

    /// Whether any authentication method can be used to open protected apps.
    var canAuthenticate: Bool {
        isEnrolled || secondaryAuthAvailable
    }

    var requiredEnrollmentSamples: Int {
        max(3, settings.enrollmentSampleCount)
    }

    var authValidityDescription: String {
        switch settings.authValiditySeconds {
        case 0:
            return "Every launch"
        case 1...59:
            return "\(settings.authValiditySeconds) sec"
        case 60..<3600:
            return "\(settings.authValiditySeconds / 60) min"
        default:
            return "\(settings.authValiditySeconds / 3600) hr"
        }
    }

    func isProtected(_ app: DiscoveredApp) -> Bool {
        protectedApps.contains { $0.bundleID == app.bundleID }
    }

    // MARK: - App list

    func addApp(_ app: DiscoveredApp) {
        guard !protectedApps.contains(where: { $0.bundleID == app.bundleID }) else { return }

        var updated = protectedApps
        updated.append(ProtectedApp(bundleID: app.bundleID, name: app.name, path: app.path))
        updated.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        protectedApps = updated
    }

    func removeApp(_ app: ProtectedApp) {
        protectedApps.removeAll { $0.bundleID == app.bundleID }
    }

    func addAppFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Choose an application to protect"
        panel.prompt = "Protect"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let discovered = catalog.addApp(at: url) else {
            errorMessage = "That item is not a launchable application."
            return
        }
        addApp(discovered)
    }

    // MARK: - Launch / authentication

    func requestLaunch(_ app: ProtectedApp) {
        guard canAuthenticate else {
            errorMessage = "Set up Face Auth, Touch ID, or a fallback password before opening protected apps."
            return
        }

        // Already open and unlocked: just bring it forward, no new check.
        if isSessionValid(for: app.bundleID) || launchGuard.isUnlockedRunning(bundleID: app.bundleID) {
            relaunch(app)
            return
        }

        presentAuth(for: app)
    }

    func requestTest() {
        guard isEnrolled else {
            errorMessage = "Enroll your face before testing recognition."
            return
        }

        presentAuth(for: nil)
    }

    /// Asks the user to authenticate before Faccy's own window is shown.
    func requestFaccyUnlock() {
        guard isFaccyLocked, authRequest == nil else { return }
        presentAuth(for: nil, origin: .faccyWindow)
    }

    /// Locks Faccy's window again, for example when it is closed.
    func relockFaccyWindow() {
        isFaccyUnlocked = false
    }

    /// Shows the verification pill for an app (or a bare recognition test).
    private func presentAuth(for app: ProtectedApp?, origin: AuthRequest.Origin = .requested) {
        authDismissTask?.cancel()
        authDismissTask = nil

        let request = AuthRequest(app: app, origin: origin)
        notchHeight = 60
        authRequest = request
        beginAuth()
        authWindow.present(request: request, model: self)
    }

    // MARK: - System-wide interception

    private func handleBlockedLaunch(_ bundleID: String) {
        guard let app = protectedApps.first(where: { $0.bundleID == bundleID }) else { return }

        if isSessionValid(for: app.bundleID) {
            relaunch(app)
            return
        }

        // Another verification is already on screen; handle this once it closes.
        if authRequest != nil {
            pendingGate = PendingGate(bundleID: bundleID, origin: .blocked)
            return
        }

        presentAuth(for: app, origin: .blocked)
    }

    /// A protected app is still running but its window was closed, and the user
    /// just brought it back. The watchdog has hidden it; always re-verify.
    private func handleReopenGate(_ bundleID: String) {
        guard let app = protectedApps.first(where: { $0.bundleID == bundleID }) else { return }

        if authRequest != nil {
            pendingGate = PendingGate(bundleID: bundleID, origin: .reopened)
            return
        }

        presentAuth(for: app, origin: .reopened)
    }

    private func relaunch(_ app: ProtectedApp) {
        // If the watchdog is mid-quit, wait for the old process to disappear so
        // the new launch is a real launch instead of an activation of a dying app.
        guard launchGuard.isEnabled,
              Self.isRunning(app.bundleID),
              !launchGuard.isAuthorizedRunning(bundleID: app.bundleID)
        else {
            launch(app)
            return
        }

        Task { @MainActor [weak self] in
            for _ in 0..<30 {
                if !Self.isRunning(app.bundleID) { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            guard let self else { return }
            // The user has authenticated, so if the old instance refused to
            // quit, approve it rather than fighting it forever.
            if Self.isRunning(app.bundleID) {
                self.launchGuard.authorizeRunningInstances(of: app.bundleID)
            }
            self.launch(app)
        }
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == bundleID && !app.isTerminated
        }
    }

    private func processPendingGate() {
        guard let gate = pendingGate else { return }
        pendingGate = nil

        guard let app = protectedApps.first(where: { $0.bundleID == gate.bundleID }) else { return }
        // A reopened window always needs a fresh scan, even inside an otherwise
        // valid session: closing and reopening is what the user wants gated.
        if gate.origin == .reopened {
            presentAuth(for: app, origin: .reopened)
        } else if isSessionValid(for: app.bundleID) {
            relaunch(app)
        } else {
            presentAuth(for: app, origin: gate.origin)
        }
    }

    func retryAuth() {
        guard authRequest != nil else { return }
        beginAuth()
    }

    func cancelAuth() {
        // Once the face has matched, let the short success transition finish
        // so closing the sheet cannot swallow the app launch.
        guard authState != .success else { return }

        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        authDismissTask?.cancel()
        authDismissTask = nil
        revealTask?.cancel()
        revealTask = nil
        cancelBiometrics()
        authWindow.dismiss()
        authRequest = nil
        authState = .idle
        secondaryError = nil
        isSecondaryInProgress = false
        revealCamera = false
        showPasswordEntry = false
        cameraHint = ""
        if !isEnrolling {
            camera.stop()
        }
        processPendingGate()
    }

    private func beginAuth() {
        guard let request = authRequest else { return }

        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        authDismissTask?.cancel()
        revealTask?.cancel()
        revealTask = nil
        successFrames = 0
        lastFaceQuality = nil
        secondaryError = nil
        isSecondaryInProgress = false
        revealCamera = false
        showPasswordEntry = false
        authState = .scanning

        let appName = request.app?.name
        switch (request.origin, appName) {
        case (.faccyWindow, _):
            cameraHint = "Center your face to unlock Faccy."
        case (.reopened, let name?):
            cameraHint = "Center your face to reopen \(name)."
        case (.blocked, let name?):
            cameraHint = "Center your face to reopen \(name)."
        case (_, let name?):
            cameraHint = "Center your face to open \(name)."
        case (_, nil):
            cameraHint = "Center your face to verify."
        }

        // Offer Touch ID at the same time as the face scan for real unlocks
        // (not for a bare "Test Face"). Whichever succeeds first is used.
        let isRealUnlock = request.app != nil || request.origin == .faccyWindow
        if isRealUnlock, touchIDAvailable {
            authenticateWithTouchID()
        }

        guard isEnrolled else {
            cameraHint = touchIDAvailable
                ? "Touch the sensor, or use your password."
                : "Use your password to continue."
            return
        }

        camera.start(preferredDeviceID: settings.cameraDeviceID)

        if camera.authorizationStatus != .notDetermined {
            startAuthTimeout()
        }

        startRevealTimer()
    }

    /// The pill stays compact while recognition is quick. If it takes a while,
    /// reveal the live preview so the user can see what the camera sees.
    private func startRevealTimer() {
        revealTask?.cancel()
        revealTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.previewRevealDelay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.authState == .scanning else { return }
            self.revealCamera = true
            self.cameraHint = "Still looking for your face. Make sure it's well lit and centered."
        }
    }

    private func revealPreview() {
        revealTask?.cancel()
        revealTask = nil
        revealCamera = true
    }

    private func startAuthTimeout() {
        guard authState == .scanning, authTimeoutTask == nil else { return }

        let timeout = max(3, settings.maxVerifySeconds)
        authTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled, let self, self.authState == .scanning else { return }
            self.failAuth("No match found. Adjust your position and try again.")
        }
    }

    private func completeAuth(name: String?) {
        guard authState == .scanning else { return }
        finishAuthSuccess(message: name.map { "Verified — \($0)." } ?? "Face verified.")
    }

    /// Shared success path for face, Touch ID, and password authentication.
    private func finishAuthSuccess(message: String) {
        cancelBiometrics()
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        revealTask?.cancel()
        revealTask = nil
        if let bundleID = authRequest?.app?.bundleID {
            appUnlockedAt[bundleID] = Date()
            scheduleSessionExpiry()
        }
        if authRequest?.origin == .faccyWindow {
            isFaccyUnlocked = true
        }
        authState = .success
        cameraHint = message
        secondaryError = nil
        isSecondaryInProgress = false
        camera.stop()

        if let app = authRequest?.app {
            if authRequest?.origin == .reopened {
                // The process never quit — just unhide and bring it forward.
                launchGuard.reopen(bundleID: app.bundleID)
            } else {
                // If an approved copy is already running but locked (hidden
                // at startup, screen lock, idle), this check unlocks it too,
                // so bringing it forward doesn't ask a second time.
                launchGuard.unlockApprovedInstances(of: app.bundleID)
                relaunch(app)
            }
        }

        authDismissTask?.cancel()
        authDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard let self, !Task.isCancelled else { return }

            self.authWindow.dismiss()
            self.authRequest = nil
            self.authState = .idle
            self.revealCamera = false
            self.showPasswordEntry = false
            self.processPendingGate()
        }
    }

    // MARK: - Secondary authentication

    /// Starts a Touch ID check. It runs alongside the face scan; if the face
    /// matches first the Touch ID prompt is withdrawn, and vice versa.
    func authenticateWithTouchID() {
        guard let request = authRequest,
              touchIDAvailable,
              biometricContext == nil,
              authState != .success
        else { return }

        let context = LAContext()
        context.localizedCancelTitle = isEnrolled ? "Use Face" : "Cancel"
        context.localizedFallbackTitle = ""
        biometricContext = context
        secondaryError = nil

        let reason: String
        if let app = request.app {
            reason = "unlock \(app.name)"
        } else {
            reason = "unlock Faccy"
        }
        let requestID = request.id

        Task { @MainActor [weak self] in
            do {
                _ = try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: reason
                )
                guard let self, self.biometricContext === context else { return }
                self.biometricContext = nil
                guard self.authRequest?.id == requestID, self.authState != .success else { return }
                self.finishAuthSuccess(message: "Verified with \(SecondaryAuth.biometryDescription).")
            } catch {
                guard let self, self.biometricContext === context else { return }
                self.biometricContext = nil
                // Dismissing the Touch ID prompt just leaves the face scan running.
                if let laError = error as? LAError,
                   [.userCancel, .appCancel, .systemCancel].contains(laError.code) {
                    return
                }
                self.secondaryError = Self.describeBiometricError(error)
            }
        }
    }

    /// Withdraws a pending Touch ID prompt.
    private func cancelBiometrics() {
        guard let context = biometricContext else { return }
        biometricContext = nil
        context.invalidate()
    }

    func verifyPassword(_ password: String) {
        guard authRequest != nil, passwordAvailable, !isSecondaryInProgress else { return }
        let records = persistence.loadPasswords()
        guard !records.isEmpty else {
            secondaryError = "No fallback password is set."
            return
        }

        isSecondaryInProgress = true
        secondaryError = nil
        let candidate = password

        Task { @MainActor [weak self] in
            let matchedLabel = await Task.detached(priority: .userInitiated) { () -> String? in
                records.first { $0.matches(candidate) }?.label
            }.value

            guard let self else { return }
            self.isSecondaryInProgress = false

            if let matchedLabel {
                self.finishAuthSuccess(message: "Verified with \(matchedLabel).")
            } else {
                self.secondaryError = "Incorrect password. Try again."
            }
        }
    }

    func refreshSecondaryAvailability() {
        biometricsAvailable = SecondaryAuth.biometricsAvailable
        passwords = persistence.loadPasswords()
    }

    private static func describeBiometricError(_ error: Error) -> String {
        guard let laError = error as? LAError else {
            return error.localizedDescription
        }

        switch laError.code {
        case .userCancel, .appCancel, .systemCancel:
            return "Touch ID was cancelled."
        case .authenticationFailed:
            return "Touch ID didn't recognize you. Try again or use your password."
        case .biometryNotAvailable:
            return "Touch ID isn't available right now."
        case .biometryNotEnrolled:
            return "No fingerprint is enrolled. Add one in System Settings › Touch ID & Password."
        case .biometryLockout:
            return "Touch ID is locked. Use your password or Face Auth."
        default:
            return laError.localizedDescription
        }
    }

    // MARK: - Password management

    /// Adds another fallback password, up to `maxPasswords`.
    func addPassword(label: String, password: String) throws {
        guard canAddPassword else {
            throw NSError(
                domain: "Faccy",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "You can save up to \(Self.maxPasswords) passwords."]
            )
        }

        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Password \(passwords.count + 1)" : trimmed
        var updated = passwords
        updated.append(PasswordRecord.make(label: name, password: password))
        try persistence.savePasswords(updated)
        passwords = updated
        // The person adding a password is the owner; don't lock them out
        // of the window they are using.
        isFaccyUnlocked = true
        secondaryError = nil
    }

    func removePassword(_ id: UUID) {
        let updated = passwords.filter { $0.id != id }
        do {
            try persistence.savePasswords(updated)
            passwords = updated
        } catch {
            errorMessage = "Could not remove the password: \(error.localizedDescription)"
        }
    }

    private func failAuth(_ message: String) {
        guard authState == .scanning else { return }
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        authState = .failed(message)
        cameraHint = message
        camera.stop()
        // Something went wrong — show what the camera sees so the user can fix it.
        revealPreview()
    }

    private func launch(_ app: ProtectedApp) {
        // Let the watchdog know this particular launch is approved. If the app
        // is already running we are just activating it, so no approval is needed.
        if !Self.isRunning(app.bundleID) {
            launchGuard.authorizeNextLaunch(of: app.bundleID)
        }

        AppLauncher.open(app) { [weak self] error in
            guard let self else { return }
            if let error {
                self.errorMessage = "Could not open \(app.name): \(error.localizedDescription)"
            } else if let index = self.protectedApps.firstIndex(where: { $0.bundleID == app.bundleID }) {
                self.protectedApps[index].lastOpenedAt = Date()
                self.protectedApps[index].launchCount += 1
            }
        }
    }

    /// Ends every app's unlock session.
    func lockNow() {
        sessionExpiryTask?.cancel()
        sessionExpiryTask = nil
        appUnlockedAt.removeAll()
    }

    /// Locks everything: every app session, Faccy's own window, and every
    /// protected app that is running right now (they are hidden and need a
    /// fresh check to come back).
    func lockAll() {
        lockNow()
        isFaccyUnlocked = false
        pendingGate = nil
        if authRequest != nil, authState != .success {
            cancelAuth()
        }
        launchGuard.lockRunningApps()
    }

    /// Drops expired app sessions and wakes up again at the next expiry.
    private func scheduleSessionExpiry() {
        sessionExpiryTask?.cancel()
        sessionExpiryTask = nil

        guard settings.authValiditySeconds > 0 else {
            if !appUnlockedAt.isEmpty {
                appUnlockedAt.removeAll()
            }
            return
        }

        let validity = Double(settings.authValiditySeconds)
        let now = Date()
        let active = appUnlockedAt.filter { now.timeIntervalSince($0.value) < validity }
        if active.count != appUnlockedAt.count {
            appUnlockedAt = active
        }

        guard let earliest = active.values.min() else { return }
        let remaining = max(0.5, validity - now.timeIntervalSince(earliest))

        sessionExpiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.sessionExpiryTask = nil
            self.scheduleSessionExpiry()
        }
    }

    // MARK: - Automatic locking

    /// Locks everything when the screen locks, the Mac or its displays go to
    /// sleep, the user switches away from this login session, or there has
    /// been no input for `idleLockSeconds`.
    private func startLockMonitoring() {
        let workspace = NSWorkspace.shared.notificationCenter
        let workspaceEvents: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ]
        for name in workspaceEvents {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.lockAll()
                }
            }
            lockObservers.append(token)
        }

        let distributed = DistributedNotificationCenter.default()
        let screenLockToken = distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lockAll()
            }
        }
        lockObservers.append(screenLockToken)

        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdle()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func checkIdle() {
        guard settings.idleLockSeconds > 0 else {
            isIdleLocked = false
            return
        }

        // kCGAnyInputEventType: any keyboard, mouse or trackpad input.
        guard let anyInput = CGEventType(rawValue: ~0) else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)

        if idle >= Double(settings.idleLockSeconds) {
            if !isIdleLocked {
                isIdleLocked = true
                lockAll()
            }
        } else {
            isIdleLocked = false
        }
    }

    // MARK: - Enrollment

    /// Enrolls a new face (`replacing: nil`) or re-enrolls an existing one.
    func startEnrollment(name: String, replacing id: UUID? = nil) {
        guard !isEnrolling else { return }
        guard id != nil || canAddFace else {
            errorMessage = "You can enroll up to \(Self.maxFaces) faces. Delete one to add another."
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        enrollmentTargetID = id
        enrollmentName = trimmed.isEmpty ? "Face \(faces.count + 1)" : trimmed

        authTimeoutTask?.cancel()
        authDismissTask?.cancel()
        cancelBiometrics()
        authWindow.dismiss()
        authRequest = nil
        authState = .idle

        enrollmentEmbeddings = []
        enrollmentCollected = 0
        lastEnrollmentSampleAt = .distantPast
        lastFaceQuality = nil
        enrollmentPhase = .preparing
        cameraHint = "Look straight at the camera, then slowly turn your head a little."

        camera.start(preferredDeviceID: settings.cameraDeviceID)
    }

    /// Tries the last enrollment again after a failure.
    func retryEnrollment() {
        startEnrollment(name: enrollmentName, replacing: enrollmentTargetID)
    }

    func renameFace(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = faces.firstIndex(where: { $0.id == id }) else { return }
        var updated = faces
        updated[index].name = trimmed
        if (try? persistence.saveFaces(updated)) != nil {
            faces = updated
        }
    }

    func cancelEnrollment() {
        enrollmentPhase = .idle
        enrollmentEmbeddings = []
        enrollmentCollected = 0
        lastFaceQuality = nil
        cameraHint = ""
        camera.stop()
    }

    func deleteFace(_ id: UUID) {
        let updated = faces.filter { $0.id != id }
        do {
            try persistence.saveFaces(updated)
        } catch {
            errorMessage = "Could not delete the face: \(error.localizedDescription)"
            return
        }
        faces = updated
        if faces.isEmpty {
            resetAfterLastFaceRemoved()
        }
    }

    /// With no faces left, stop anything that depended on face recognition.
    private func resetAfterLastFaceRemoved() {
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        authDismissTask?.cancel()
        authDismissTask = nil
        revealTask?.cancel()
        revealTask = nil
        sessionExpiryTask?.cancel()
        sessionExpiryTask = nil
        authWindow.dismiss()
        appUnlockedAt.removeAll()
        pendingGate = nil
        authRequest = nil
        authState = .idle
        revealCamera = false
        showPasswordEntry = false
        enrollmentPhase = .idle
        enrollmentEmbeddings = []
        enrollmentCollected = 0
        lastFaceQuality = nil
        cameraHint = ""
        camera.stop()
    }

    private func consumeEnrollment(_ analysis: FaceAnalysis) {
        guard isEnrolling else { return }

        if enrollmentPhase == .preparing {
            enrollmentPhase = .capturing
        }

        let now = Date()
        guard now.timeIntervalSince(lastEnrollmentSampleAt) >= 0.45 else { return }
        lastEnrollmentSampleAt = now

        enrollmentEmbeddings.append(analysis.embedding)
        enrollmentCollected = enrollmentEmbeddings.count
        cameraHint = "Sample \(enrollmentCollected) of \(requiredEnrollmentSamples). Slowly turn your head a little."

        if enrollmentCollected >= requiredEnrollmentSamples {
            finishEnrollment()
        }
    }

    private func finishEnrollment() {
        enrollmentPhase = .saving

        var updated = faces
        if let id = enrollmentTargetID, let index = updated.firstIndex(where: { $0.id == id }) {
            updated[index] = FaceProfile(
                id: id,
                name: updated[index].name,
                embeddings: enrollmentEmbeddings
            )
        } else {
            updated.append(FaceProfile(name: enrollmentName, embeddings: enrollmentEmbeddings))
        }

        do {
            try persistence.saveFaces(updated)
            faces = updated
            isFaccyUnlocked = true
            enrollmentPhase = .completed
            cameraHint = "\(enrollmentName) saved. You can now protect apps."
            camera.stop()
        } catch {
            enrollmentPhase = .failed("Could not save the face profile: \(error.localizedDescription)")
            camera.stop()
        }
    }

    // MARK: - Camera frames

    private func handleFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isEnrolling || authState == .scanning else { return }

        analyzer.analyze(
            pixelBuffer: pixelBuffer,
            requireQuality: isEnrolling,
            minimumQuality: settings.minimumFaceQuality
        ) { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                self.handleAnalysis(result)
            }
        }
    }

    private func handleAnalysis(_ result: Result<FaceAnalysis, FaceAnalysisError>) {
        guard isEnrolling || authState == .scanning else { return }

        switch result {
        case .success(let analysis):
            lastFaceQuality = analysis.quality
            if isEnrolling {
                consumeEnrollment(analysis)
            } else {
                consumeAuth(analysis)
            }

        case .failure(let error):
            if case .busy = error { return }
            cameraHint = error.userMessage
        }
    }

    private func consumeAuth(_ analysis: FaceAnalysis) {
        guard authState == .scanning, isEnrolled else { return }

        // Closest sample across every enrolled face.
        var bestDistance = Float.infinity
        var bestFace: FaceProfile?
        for face in faces {
            for embedding in face.embeddings {
                let distance = FaceAnalyzer.distance(embedding, analysis.embedding)
                if distance < bestDistance {
                    bestDistance = distance
                    bestFace = face
                }
            }
        }

        guard bestDistance <= Float(settings.recognitionThreshold) else {
            successFrames = 0
            cameraHint = "Face not recognized. Move closer and look at the camera."
            return
        }

        // Two matching frames in a row avoids a one-off false match.
        successFrames += 1
        if successFrames >= 2 {
            completeAuth(name: bestFace?.name)
        } else {
            cameraHint = "Match found — hold still."
        }
    }

    // MARK: - Camera permission

    func handleAuthorizationChange(_ status: AVAuthorizationStatus) {
        if status == .authorized, authState == .scanning {
            startAuthTimeout()
        }

        if status == .denied || status == .restricted {
            if authState == .scanning {
                failAuth("Camera access is off. Enable Faccy in System Settings › Privacy & Security › Camera.")
            }
            if isEnrolling {
                enrollmentPhase = .failed("Camera access is off. Enable Faccy in System Settings › Privacy & Security › Camera.")
            }
        }
    }

    private func handleCameraError(_ message: String) {
        if authState == .scanning {
            failAuth(message)
        }
        if isEnrolling {
            enrollmentPhase = .failed(message)
            camera.stop()
        }
    }

    func requestCameraAccess() {
        camera.requestAccess()
    }

    func openCameraPrivacySettings() {
        camera.openCameraPrivacySettings()
    }

    // MARK: - Login item

    func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != settings.launchAtLogin else { return }

        if let error = LoginItemManager.setEnabled(enabled) {
            errorMessage = "Could not update the login item: \(error)"
            return
        }
        settings.launchAtLogin = enabled
    }

    func clearError() {
        errorMessage = nil
    }
}
