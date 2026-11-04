import Foundation

/// Simple JSON persistence in ~/Library/Application Support/Faccy.
final class PersistenceStore {
    let directory: URL

    private let settingsURL: URL
    private let appsURL: URL
    private let facesURL: URL
    private let passwordsURL: URL
    /// Single-face / single-password files from earlier versions, migrated on load.
    private let legacyProfileURL: URL
    private let legacyPasswordURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

        directory = base.appendingPathComponent("Faccy", isDirectory: true)
        settingsURL = directory.appendingPathComponent("settings.json")
        appsURL = directory.appendingPathComponent("apps.json")
        facesURL = directory.appendingPathComponent("faces.json")
        passwordsURL = directory.appendingPathComponent("passwords.json")
        legacyProfileURL = directory.appendingPathComponent("face-profile.json")
        legacyPasswordURL = directory.appendingPathComponent("password.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Settings

    func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? decoder.decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return settings
    }

    func saveSettings(_ settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    // MARK: - Protected apps

    func loadProtectedApps() -> [ProtectedApp] {
        guard let data = try? Data(contentsOf: appsURL),
              let apps = try? decoder.decode([ProtectedApp].self, from: data)
        else {
            return []
        }
        return apps
    }

    func saveProtectedApps(_ apps: [ProtectedApp]) {
        guard let data = try? encoder.encode(apps) else { return }
        try? data.write(to: appsURL, options: .atomic)
    }

    // MARK: - Faces

    func loadFaces() -> [FaceProfile] {
        if let data = try? Data(contentsOf: facesURL),
           let faces = try? decoder.decode([FaceProfile].self, from: data) {
            return faces.filter { !$0.isEmpty }
        }

        // Migrate a single face saved by an earlier version.
        guard let data = try? Data(contentsOf: legacyProfileURL),
              let legacy = try? decoder.decode(FaceProfile.self, from: data),
              !legacy.isEmpty
        else { return [] }

        let faces = [legacy]
        if (try? saveFaces(faces)) != nil {
            try? FileManager.default.removeItem(at: legacyProfileURL)
        }
        return faces
    }

    func saveFaces(_ faces: [FaceProfile]) throws {
        let data = try encoder.encode(faces)
        try data.write(to: facesURL, options: .atomic)
    }

    // MARK: - Fallback passwords

    func loadPasswords() -> [PasswordRecord] {
        if let data = try? Data(contentsOf: passwordsURL),
           let records = try? decoder.decode([PasswordRecord].self, from: data) {
            return records
        }

        // Migrate a single password saved by an earlier version.
        guard let data = try? Data(contentsOf: legacyPasswordURL),
              let legacy = try? decoder.decode(PasswordRecord.self, from: data)
        else { return [] }

        let records = [legacy]
        if (try? savePasswords(records)) != nil {
            try? FileManager.default.removeItem(at: legacyPasswordURL)
        }
        return records
    }

    func savePasswords(_ records: [PasswordRecord]) throws {
        let data = try encoder.encode(records)
        try data.write(to: passwordsURL, options: .atomic)
    }
}
