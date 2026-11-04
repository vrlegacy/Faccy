import SwiftUI

struct ProtectedAppsView: View {
    @EnvironmentObject private var model: AppModel
    var openFaceSetup: () -> Void = {}

    @State private var showAddApps = false
    @State private var appToRemove: ProtectedApp?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !model.canAuthenticate {
                    setupBanner
                }

                if model.hasActiveSessions {
                    unlockedBanner
                }

                if model.protectedApps.isEmpty {
                    emptyState
                } else {
                    appList
                }

                enforcementNote
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .sheet(isPresented: $showAddApps) {
            AddAppsView()
                .environmentObject(model)
        }
        .alert(
            "Remove \(appToRemove?.name ?? "app")?",
            isPresented: Binding(
                get: { appToRemove != nil },
                set: { isPresented in
                    if !isPresented { appToRemove = nil }
                }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let app = appToRemove {
                    model.removeApp(app)
                }
                appToRemove = nil
            }
            Button("Cancel", role: .cancel) {
                appToRemove = nil
            }
        } message: {
            Text("It will no longer require face authentication when opened through Faccy.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Protected Apps")
                    .font(.system(size: 30, weight: .bold))
                Text("Face verification is required before any app below opens.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isEnrolled {
                Button {
                    model.requestTest()
                } label: {
                    Label("Test Face", systemImage: "faceid")
                }
            }

            if model.settings.enforceSystemWide {
                StatusPill(text: "System-wide", systemImage: "checkmark.shield.fill", tint: .green)
            }

            Button {
                showAddApps = true
            } label: {
                Label("Add Apps", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var setupBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "faceid")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text("Set up an unlock method")
                    .font(.headline)
                Text("Faccy needs Face Auth, Touch ID, or a fallback password before it can unlock protected apps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Set Up Face") {
                openFaceSetup()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
    }

    private var unlockedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.open.fill")
                .foregroundStyle(.green)
            Text("Unlocked apps open without a new scan for \(model.authValidityDescription). Each app has its own unlock.")
                .font(.callout)
            Spacer()
            Button("Lock Now") {
                model.lockNow()
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)

            Text("No protected apps yet")
                .font(.title3.weight(.semibold))

            Text("Pick the apps that should ask for your face before they open.")
                .foregroundStyle(.secondary)

            Button {
                showAddApps = true
            } label: {
                Label("Choose Apps", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                .foregroundStyle(Color.secondary.opacity(0.28))
        )
    }

    private var appList: some View {
        LazyVStack(spacing: 10) {
            ForEach(model.protectedApps) { app in
                appRow(app)
            }
        }
    }

    private func appRow(_ app: ProtectedApp) -> some View {
        HStack(spacing: 14) {
            AppIconView(path: app.path, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(app.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let lastOpenedAt = app.lastOpenedAt {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("Opened \(lastOpenedAt, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if model.isSessionValid(for: app.bundleID) {
                StatusPill(text: "Unlocked", systemImage: "lock.open", tint: .green)
            } else {
                StatusPill(text: "Face required", systemImage: "lock", tint: .secondary)
            }

            Button {
                model.requestLaunch(app)
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderedProminent)

            Menu {
                Button(role: .destructive) {
                    appToRemove = app
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var enforcementNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)

            Text(model.settings.enforceSystemWide
                 ? "System-wide protection is on. Protected apps opened from the Dock, Spotlight, or Finder are quit immediately and must be unlocked through Faccy. An app may appear briefly before it closes."
                 : "System-wide protection is off. Only launches started from Faccy are gated. Turn on Enforcement in Settings to block launches from the Dock, Spotlight, and Finder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}
