import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openAndUnlock()
        } label: {
            Label("Open Faccy", systemImage: "macwindow")
        }

        Divider()

        if model.protectedApps.isEmpty {
            Text("No protected apps")
        } else {
            ForEach(model.protectedApps.prefix(8)) { app in
                Button {
                    showMainWindow()
                    model.requestLaunch(app)
                } label: {
                    Label(app.name, systemImage: "lock")
                }
            }

            if model.protectedApps.count > 8 {
                Text("\(model.protectedApps.count - 8) more in Faccy…")
            }
        }

        if !model.isEnrolled {
            Divider()
            Button {
                showMainWindow()
            } label: {
                Label("Set Up Face…", systemImage: "faceid")
            }
        }

        Divider()

        if model.hasActiveSessions {
            Button {
                model.lockNow()
            } label: {
                Label("Lock Now", systemImage: "lock.fill")
            }
        }

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit Faccy", systemImage: "power")
        }
        .keyboardShortcut("q")
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openAndUnlock() {
        showMainWindow()
        model.requestFaccyUnlock()
    }
}
