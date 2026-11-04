import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating panel so verification does not steal focus.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Presents verification as a compact pill at the top center of the screen,
/// styled like the Dynamic Island. It stays small while the camera is scanning
/// and only expands (with the live preview) when recognition needs help.
@MainActor
final class AuthWindowController {
    private var panel: NotchPanel?
    private var model: AppModel?
    private var cancellables = Set<AnyCancellable>()

    private static let width: CGFloat = 460
    private static let compactHeight: CGFloat = 60
    private static let topInset: CGFloat = 6

    func present(request: AuthRequest, model: AppModel) {
        guard panel == nil else { return }

        self.model = model

        let hosting = NSHostingView(
            rootView: NotchAuthView(request: request)
                .environmentObject(model)
        )

        let panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.compactHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Native window shadow: SwiftUI's shadow would be clipped by the
        // window's own bounds because the pill fills the window edge to edge.
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = hosting

        self.panel = panel
        panel.orderFrontRegardless()

        // The view measures itself and reports the height it needs.
        model.$notchHeight
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resize()
            }
            .store(in: &cancellables)

        resize()
    }

    func dismiss() {
        guard let panel else { return }
        self.panel = nil
        model = nil
        cancellables.removeAll()
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: - Layout

    private func resize() {
        guard let panel, let model else { return }

        let height = max(Self.compactHeight, ceil(model.notchHeight))
        let screen = Self.targetScreen(for: panel)
        let size = CGSize(width: Self.width, height: height)
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - size.height - Self.topInset
        )
        let frame = NSRect(origin: origin, size: size)

        if abs(panel.frame.height - height) > 0.5 {
            panel.setFrame(frame, display: true)
        } else {
            panel.setFrameOrigin(origin)
        }

        if model.showPasswordEntry {
            panel.makeKey()
        }
    }

    private static func targetScreen(for panel: NSPanel) -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
