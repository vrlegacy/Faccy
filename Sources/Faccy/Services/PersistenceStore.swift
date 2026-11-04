import Foundation

/// Simple JSON persistence in ~/Library/Application Support/Faccy.
final class PersistenceStore {
    let directory: URL

    private let settingsURL: URL
    private let appsURL: URL
    private let profileURL: URL
    private let passwordURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

        directory = base.appendingPathComponent("Faccy", isDirectory: true)
        settingsURL = directory.appendingPathComponent("settings.json")
        appsURL = directory.appendingPathComponent("apps.json")
        profileURL = directory.appendingPathComponent("face-profile.json")
        passwordURL = directory.appendingPathComponent("password.json")

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

    // MARK: - Face profile

    func loadProfile() -> FaceProfile? {
        guard let data = try? Data(contentsOf: profileURL),
              let profile = try? decoder.decode(FaceProfile.self, from: data),
              !profile.isEmpty
        else {
            return nil
        }
        return profile
    }

    func saveProfile(_ profile: FaceProfile) throws {
        let data = try encoder.encode(profile)
        try data.write(to: profileURL, options: .atomic)
    }

    func deleteProfile() {
        try? FileManager.default.removeItem(at: profileURL)
    }

    // MARK: - Fallback password

    func loadPasswordRecord() -> PasswordRecord? {
        guard let data = try? Data(contentsOf: passwordURL),
              let record = try? decoder.decode(PasswordRecord.self, from: data)
        else {
            return nil
        }
        return record
    }

    func savePasswordRecord(_ record: PasswordRecord) throws {
        let data = try encoder.encode(record)
        try data.write(to: passwordURL, options: .atomic)
    }

    func deletePasswordRecord() {
        try? FileManager.default.removeItem(at: passwordURL)
    }
}
