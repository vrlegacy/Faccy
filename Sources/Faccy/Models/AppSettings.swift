import Foundation

/// User-editable configuration for Faccy.
struct AppSettings: Codable, Equatable {
    /// Maximum feature-print distance that still counts as a match.
    /// Lower is stricter.
    var recognitionThreshold: Double = 0.45

    /// How many face samples to capture during enrollment.
    var enrollmentSampleCount: Int = 5

    /// Minimum Vision face-capture quality accepted while enrolling.
    var minimumFaceQuality: Double = 0.35

    /// The camera the user picked, by AVCaptureDevice.uniqueID.
    var cameraDeviceID: String?

    /// Mirror the preview (the usual front-camera look).
    var mirrorPreview: Bool = true

    /// Keep a successful verification valid for this many seconds.
    /// 0 means every protected app launch requires a fresh scan.
    var authValiditySeconds: Int = 0

    /// How long to look for a matching face before giving up.
    var maxVerifySeconds: Double = 12

    /// Whether the user wants Faccy to start at login.
    var launchAtLogin: Bool = true

    /// Require authentication before Faccy's own window (settings, app list,
    /// face setup) can be used.
    var lockFaccyWindow: Bool = true

    /// Lock everything after this many seconds without keyboard or mouse
    /// input. 0 turns idle locking off.
    var idleLockSeconds: Int = 300

    /// Bumped when a new default has to be applied to existing installs.
    var settingsRevision: Int = AppSettings.currentRevision
    static let currentRevision = 2

    /// Intercept protected apps launched from anywhere (Dock, Spotlight, Finder)
    /// and quit them until the user authenticates.
    var enforceSystemWide: Bool = true

    /// Also close protected apps that were already running when Faccy started.
    /// Turning this off leaves pre-existing instances alone.
    var enforceAtStartup: Bool = true

    /// Offer Touch ID as a fallback to face verification.
    var allowTouchID: Bool = true

    /// Offer a custom password as a fallback to face verification.
    var allowPasswordFallback: Bool = true

    /// Show the Faccy icon in the menu bar. When off, open the app from
    /// Spotlight or by launching Faccy.app again.
    var showMenuBarIcon: Bool = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case recognitionThreshold
        case enrollmentSampleCount
        case minimumFaceQuality
        case cameraDeviceID
        case mirrorPreview
        case authValiditySeconds
        case maxVerifySeconds
        case launchAtLogin
        case lockFaccyWindow
        case idleLockSeconds
        case settingsRevision
        case enforceSystemWide
        case enforceAtStartup
        case allowTouchID
        case allowPasswordFallback
        case showMenuBarIcon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()

        recognitionThreshold = try container.decodeIfPresent(Double.self, forKey: .recognitionThreshold) ?? defaults.recognitionThreshold
        enrollmentSampleCount = try container.decodeIfPresent(Int.self, forKey: .enrollmentSampleCount) ?? defaults.enrollmentSampleCount
        minimumFaceQuality = try container.decodeIfPresent(Double.self, forKey: .minimumFaceQuality) ?? defaults.minimumFaceQuality
        cameraDeviceID = try container.decodeIfPresent(String.self, forKey: .cameraDeviceID)
        mirrorPreview = try container.decodeIfPresent(Bool.self, forKey: .mirrorPreview) ?? defaults.mirrorPreview
        authValiditySeconds = try container.decodeIfPresent(Int.self, forKey: .authValiditySeconds) ?? defaults.authValiditySeconds
        maxVerifySeconds = try container.decodeIfPresent(Double.self, forKey: .maxVerifySeconds) ?? defaults.maxVerifySeconds
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        lockFaccyWindow = try container.decodeIfPresent(Bool.self, forKey: .lockFaccyWindow) ?? defaults.lockFaccyWindow
        idleLockSeconds = try container.decodeIfPresent(Int.self, forKey: .idleLockSeconds) ?? defaults.idleLockSeconds
        enforceSystemWide = try container.decodeIfPresent(Bool.self, forKey: .enforceSystemWide) ?? defaults.enforceSystemWide
        enforceAtStartup = try container.decodeIfPresent(Bool.self, forKey: .enforceAtStartup) ?? defaults.enforceAtStartup
        allowTouchID = try container.decodeIfPresent(Bool.self, forKey: .allowTouchID) ?? defaults.allowTouchID
        allowPasswordFallback = try container.decodeIfPresent(Bool.self, forKey: .allowPasswordFallback) ?? defaults.allowPasswordFallback
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? defaults.showMenuBarIcon

        // Revision 2 turns on launch at login and the Faccy window lock for
        // installs that saved settings before those defaults existed.
        let revision = try container.decodeIfPresent(Int.self, forKey: .settingsRevision) ?? 1
        if revision < 2 {
            launchAtLogin = true
            lockFaccyWindow = true
        }
        settingsRevision = Self.currentRevision
    }
}
