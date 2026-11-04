import SwiftUI

/// Verification UI styled like an iOS Dynamic Island: a compact black pill at
/// the top center of the screen. The camera preview stays hidden while
/// recognition is quick and only expands if it needs help.
struct NotchAuthView: View {
    @EnvironmentObject private var model: AppModel
    let request: AuthRequest

    @State private var password = ""
    @FocusState private var passwordFocused: Bool

    private var isExpanded: Bool {
        model.revealCamera || model.showPasswordEntry
    }

    private var cornerRadius: CGFloat {
        isExpanded ? 24 : 30
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if model.revealCamera {
                cameraPreview
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if model.showPasswordEntry {
                passwordEntry
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let error = model.secondaryError, model.showPasswordEntry {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 460)
        .background(pillBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: NotchHeightKey.self, value: proxy.size.height)
            }
        )
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: model.authState)
        .onPreferenceChange(NotchHeightKey.self) { height in
            guard height > 0 else { return }
            // Publish after layout so the window resize cannot fight SwiftUI.
            DispatchQueue.main.async {
                if abs(model.notchHeight - height) > 0.5 {
                    model.notchHeight = height
                }
            }
        }
        .onAppear {
            if model.authState == .idle {
                model.retryAuth()
            }
        }
        .onChange(of: model.showPasswordEntry) { _, showing in
            if showing {
                passwordFocused = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            appBadge

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 6)

            statusIndicator

            if model.authState != .success {
                if model.touchIDAvailable {
                    iconButton("touchid", help: "Use \(SecondaryAuth.biometryDescription)") {
                        model.authenticateWithTouchID()
                    }
                }

                if model.passwordAvailable {
                    iconButton(
                        "key.fill",
                        help: "Use password",
                        highlighted: model.showPasswordEntry
                    ) {
                        model.showPasswordEntry.toggle()
                    }
                }

                iconButton("xmark", help: "Cancel") {
                    model.cancelAuth()
                }
            }
        }
        .frame(height: 40)
    }

    @ViewBuilder
    private var appBadge: some View {
        if let app = request.app {
            AppIconView(path: app.path, size: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                Image(systemName: "faceid")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch model.authState {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(red: 0.25, green: 0.85, blue: 0.45))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
        case .scanning, .idle:
            ProgressView()
                .controlSize(.small)
        }
    }

    private func iconButton(
        _ systemImage: String,
        help: String,
        highlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(highlighted ? 1 : 0.85))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(highlighted ? 0.24 : 0.10), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(model.isSecondaryInProgress)
    }

    private var title: String {
        guard let app = request.app else { return "Face Check" }

        switch request.origin {
        case .requested:
            return "Open \(app.name)"
        case .blocked, .reopened:
            return "Reopen \(app.name)"
        }
    }

    private var statusText: String {
        switch model.authState {
        case .idle:
            return "Starting camera…"
        case .scanning:
            if !model.isEnrolled {
                return "Use \(fallbackSummary) to continue"
            }
            return model.cameraHint.isEmpty ? "Looking for your face…" : model.cameraHint
        case .failed(let message):
            return message
        case .success:
            return model.cameraHint.isEmpty ? "Verified" : model.cameraHint
        }
    }

    private var fallbackSummary: String {
        if model.touchIDAvailable, model.passwordAvailable {
            return "Touch ID or your password"
        }
        if model.touchIDAvailable {
            return SecondaryAuth.biometryDescription
        }
        return "your password"
    }

    // MARK: - Expanded content

    private var cameraPreview: some View {
        VStack(spacing: 8) {
            ZStack {
                Color.black

                if model.camera.authorizationStatus == .denied
                    || model.camera.authorizationStatus == .restricted {
                    CameraPermissionView(compact: true)
                } else if model.camera.isRunning {
                    CameraPreviewView(
                        session: model.camera.session,
                        mirror: model.settings.mirrorPreview
                    )
                    FaceGuideOverlay()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 22, weight: .light))
                        Text("Camera paused")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if case .failed = model.authState {
                HStack {
                    Spacer()

                    Button {
                        model.retryAuth()
                    } label: {
                        Text("Try Again")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            } else if model.settings.showMatchScore, let distance = model.lastMatchDistance {
                Text(matchScoreText(distance))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var passwordEntry: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                    .focused($passwordFocused)
                    .onSubmit(submitPassword)

                Button(action: submitPassword) {
                    Text("Unlock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(password.isEmpty || model.isSecondaryInProgress)
                .opacity(password.isEmpty || model.isSecondaryInProgress ? 0.5 : 1)
            }

            if model.isSecondaryInProgress {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Waiting for confirmation…")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var pillBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.96))
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.08), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
    }

    // MARK: - Actions

    private func submitPassword() {
        guard !password.isEmpty else { return }
        model.verifyPassword(password)
        password = ""
    }

    private func matchScoreText(_ distance: Float) -> String {
        let threshold = Float(model.settings.recognitionThreshold)
        let value = String(format: "%.3f", distance)
        let tolerance = String(format: "%.2f", threshold)
        return distance <= threshold
            ? "Match \(value) · tolerance \(tolerance)"
            : "Distance \(value) · tolerance \(tolerance)"
    }
}

private struct NotchHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
