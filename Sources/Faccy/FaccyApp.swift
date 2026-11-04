import AppKit
import SwiftUI

@main
struct FaccyApp: App {
    @StateObject private var model = AppModel()

    /// Mirrors `settings.showMenuBarIcon`. A plain `@State` keeps MenuBarExtra's
    /// `isInserted` binding stable and stops it from writing back to settings
    /// on every scene update.
    @State private var showMenuBarIcon = PersistenceStore().loadSettings().showMenuBarIcon

    var body: some Scene {
        Window("Faccy", id: "main") {
            MainWindowView(showMenuBarIcon: $showMenuBarIcon)
                .environmentObject(model)
        }
        .defaultSize(width: 980, height: 680)
        .windowToolbarStyle(.unified)

        MenuBarExtra(
            "Faccy",
            systemImage: "faceid",
            isInserted: $showMenuBarIcon
        ) {
            MenuBarView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.menu)
    }
}
