import AppKit
import SwiftUI

struct AppIconView: View {
    let path: String
    var size: CGFloat = 40

    var body: some View {
        Image(nsImage: AppLauncher.icon(for: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

struct StatusPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.13), in: Capsule())
            .foregroundStyle(tint)
    }
}

struct FaceGuideOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, proxy.size.height) * 0.46
            let height = width * 1.35

            ZStack {
                Ellipse()
                    .stroke(
                        Color.white.opacity(0.7),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 7])
                    )
                    .frame(width: width, height: height)
                    .shadow(color: .black.opacity(0.25), radius: 3)

                Ellipse()
                    .stroke(Color.black.opacity(0.18), lineWidth: 5)
                    .frame(width: width, height: height)
                    .blur(radius: 2)
                    .zIndex(-1)
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}

struct CameraPermissionView: View {
    @EnvironmentObject private var model: AppModel
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            Image(systemName: "video.slash")
                .font(.system(size: compact ? 24 : 34, weight: .light))
                .foregroundStyle(.secondary)

            Text("Camera access is needed")
                .font(compact ? .callout.weight(.semibold) : .headline)

            if !compact {
                Text("Faccy only uses the camera while you enroll or verify your face. Nothing is uploaded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            if let error = model.camera.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            if model.camera.authorizationStatus == .denied || model.camera.authorizationStatus == .restricted {
                Button("Open System Settings") {
                    model.openCameraPrivacySettings()
                }
            } else {
                Button("Allow Camera") {
                    model.requestCameraAccess()
                }
            }
        }
        .padding(compact ? 12 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
        .foregroundStyle(.white)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    var subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
