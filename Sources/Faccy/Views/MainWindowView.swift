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
        .onChange(of: model.settings.showMenuBarIcon) { _, newValue in
            showMenuBarIcon = newValue
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

            if model.isSessionValid {
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
