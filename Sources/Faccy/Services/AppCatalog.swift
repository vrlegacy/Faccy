import AppKit
import Foundation

/// Finds installed .app bundles so the user can choose which ones Faccy protects.
@MainActor
final class AppCatalog: ObservableObject {
    @Published private(set) var apps: [DiscoveredApp] = []
    @Published private(set) var isScanning = false

    private let fileManager = FileManager.default

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        var byBundleID: [String: DiscoveredApp] = [:]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                guard let app = makeDiscoveredApp(from: url) else { continue }
                guard app.bundleID != Bundle.main.bundleIdentifier else { continue }
                if byBundleID[app.bundleID] == nil {
                    byBundleID[app.bundleID] = app
                }
            }
        }

        apps = byBundleID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func addApp(at url: URL) -> DiscoveredApp? {
        guard url.pathExtension.lowercased() == "app",
              let app = makeDiscoveredApp(from: url)
        else { return nil }

        if let existing = apps.first(where: { $0.bundleID == app.bundleID }) {
            return existing
        }

        apps.append(app)
        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return app
    }

    private func makeDiscoveredApp(from url: URL) -> DiscoveredApp? {
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier,
              !bundleID.isEmpty
        else { return nil }

        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        let fileName = url.deletingPathExtension().lastPathComponent
        let name = [displayName, bundleName, fileName]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? fileName

        return DiscoveredApp(bundleID: bundleID, name: name, url: url)
    }
}
