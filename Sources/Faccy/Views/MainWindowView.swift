import AppKit
import SwiftUI

private enum SidebarItem: Hashable {
    case apps
    case face
    case settings
}

struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showMenuBarIcon: Bool
    @State private var selection: SidebarItem = .apps

    var body: some View {
        // A ZStack (not a Group) so onAppear/onDisappear belong to the window,
        // not to whichever child is showing.
        ZStack {
            if model.isFaccyLocked {
                FaccyLockedView()
            } else {
                content
            }
        }
        .alert("Faccy", isPresented: errorBinding) {
            Button("OK") {
                model.clearError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            model.refreshSecondaryAvailability()
            showMenuBarIcon = model.settings.showMenuBarIcon
        }
        .onDisappear {
            // Closing the window locks it again.
            model.relockFaccyWindow()
        }
        .onChange(of: model.settings.showMenuBarIcon) { _, newValue in
            showMenuBarIcon = newValue
        }
    }

    private var content: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Protected Apps", systemImage: "lock.shield")
                    .tag(SidebarItem.apps)
                Label("Face Setup", systemImage: "faceid")
                    .tag(SidebarItem.face)
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarItem.settings)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 250)
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
        } detail: {
            Group {
                switch selection {
                case .apps:
                    ProtectedAppsView(openFaceSetup: { selection = .face })
                case .face:
                    EnrollmentView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(minWidth: 700, minHeight: 560)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.clearError()
                }
            }
        )
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack(spacing: 8) {
                Circle()
                    .fill(model.isEnrolled ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(model.isEnrolled ? "Face profile active" : "No face profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.hasActiveSessions {
                Button {
                    model.lockNow()
                } label: {
                    Label("Lock Now", systemImage: "lock.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
}

/// Shown instead of Faccy's window until the user authenticates.
private struct FaccyLockedView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)

            Text("Faccy is locked")
                .font(.title2.weight(.semibold))

            Text("Verify it's you to change protected apps, face setup, or settings.")
                .foregroundStyle(.secondary)

            Button {
                model.requestFaccyUnlock()
            } label: {
                Label("Unlock", systemImage: "faceid")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.authRequest != nil)
        }
        .padding(40)
        .frame(minWidth: 700, minHeight: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
