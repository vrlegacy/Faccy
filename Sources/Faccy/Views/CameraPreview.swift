import AppKit
import AVFoundation
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    var mirror: Bool = true

    func makeNSView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.mirror = mirror
        return view
    }

    func updateNSView(_ nsView: PreviewContainerView, context: Context) {
        nsView.previewLayer.session = session
        nsView.mirror = mirror
        nsView.applyMirroring()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            nsView.applyMirroring()
        }
    }
}

final class PreviewContainerView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    var mirror: Bool = true {
        didSet { applyMirroring() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = previewLayer
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = previewLayer
        previewLayer.videoGravity = .resizeAspectFill
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        applyMirroring()
    }

    func applyMirroring() {
        guard let connection = previewLayer.connection,
              connection.isVideoMirroringSupported
        else { return }

        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirror
    }
}
