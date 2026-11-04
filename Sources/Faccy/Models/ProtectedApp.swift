import Foundation

/// An application the user has chosen to protect with face authentication.
struct ProtectedApp: Identifiable, Codable, Hashable {
    var id: String { bundleID }

    let bundleID: String
    var name: String
    var path: String
    var lastOpenedAt: Date?
    var launchCount: Int

    init(
        bundleID: String,
        name: String,
        path: String,
        lastOpenedAt: Date? = nil,
        launchCount: Int = 0
    ) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
        self.lastOpenedAt = lastOpenedAt
        self.launchCount = launchCount
    }
}

/// An app discovered on disk that can be added to the protected list.
struct DiscoveredApp: Identifiable, Hashable {
    var id: String { bundleID }

    let bundleID: String
    let name: String
    let url: URL

    var path: String { url.path }
}
