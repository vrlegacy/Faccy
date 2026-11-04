import SwiftUI

struct AddAppsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    private var filteredApps: [DiscoveredApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.catalog.apps }
        return model.catalog.apps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleID.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            Divider()
            appList
            Divider()
            footer
        }
        .frame(width: 640, height: 600)
        .onAppear {
            if model.catalog.apps.isEmpty {
                model.catalog.refresh()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose Apps")
                    .font(.title2.weight(.bold))
                Text("Selected apps will require face verification when opened through Faccy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.catalog.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Rescan installed apps")

            Button {
                model.addAppFromDisk()
            } label: {
                Label("Add from Disk…", systemImage: "folder.badge.plus")
            }
        }
        .padding(20)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search apps", text: $searchText)
                .textFieldStyle(.plain)

            if model.catalog.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var appList: some View {
        if filteredApps.isEmpty {
            VStack(spacing: 10) {
                if model.catalog.isScanning {
                    ProgressView()
                    Text("Scanning installed apps…")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "No apps found" : "No apps match “\(searchText)”")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredApps) { app in
                        appRow(app)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
        }
    }

    private func appRow(_ app: DiscoveredApp) -> some View {
        let isProtected = model.isProtected(app)

        return HStack(spacing: 12) {
            AppIconView(path: app.path, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body.weight(.medium))
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isProtected {
                Label("Protected", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button("Protect") {
                    model.addApp(app)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isProtected ? Color.green.opacity(0.06) : Color.clear)
        )
    }

    private var footer: some View {
        HStack {
            Text("\(model.protectedApps.count) app\(model.protectedApps.count == 1 ? "" : "s") protected")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }
}
