import AppKit
import Foundation
import ServiceManagement

enum AppLauncher {
    static func open(_ app: ProtectedApp, completion: @escaping (Error?) -> Void) {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
            ?? URL(fileURLWithPath: app.path)

        guard FileManager.default.fileExists(atPath: url.path) else {
            completion(NSError(
                domain: "Faccy",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "\(app.name) could not be found on disk."]
            ))
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                completion(error)
            }
        }
    }

    static func icon(for path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }
}

enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
