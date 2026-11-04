import AppKit
import AVFoundation
import Combine
import Foundation

struct CameraDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Owns the AVCaptureSession used by both enrollment and verification.
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var authorizationStatus: AVAuthorizationStatus
    @Published private(set) var isRunning = false
    @Published private(set) var availableDevices: [CameraDevice] = []
    @Published private(set) var activeDeviceID: String?
    @Published private(set) var errorMessage: String?

    /// Called on the main queue at roughly 16 fps while the session is running.
    /// The higher rate is needed to see a blink, which lasts only ~150-300 ms.
    var onFrame: ((CVPixelBuffer) -> Void)?

    private let sessionQueue = DispatchQueue(label: "io.github.vrlegacy.faccy.camera.session")
    private let videoQueue = DispatchQueue(label: "io.github.vrlegacy.faccy.camera.video", qos: .userInitiated)
    private var videoOutput: AVCaptureVideoDataOutput?
    private var currentInput: AVCaptureDeviceInput?
    private var configuredDeviceID: String?
    private var lastFrameTime: CFAbsoluteTime = 0
    private var wantsToRun = false
    private var preferredDeviceID: String?

    override init() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        super.init()
        refreshDevices()
    }

    func refreshDevices() {
        availableDevices = videoDevices()
            .map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Only the Mac's own camera is allowed. External, Continuity (iPhone) and
    /// virtual cameras (OBS and similar) are ignored so a recorded video cannot
    /// be fed in as the camera.
    private func videoDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.filter { $0.deviceType == .builtInWideAngleCamera }
    }

    private var hasCameraUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil
    }

    func start(preferredDeviceID: String?) {
        self.preferredDeviceID = preferredDeviceID
        wantsToRun = true

        guard hasCameraUsageDescription else {
            errorMessage = "Camera access requires the Faccy.app bundle. Build and open it with ./scripts/build.sh --open instead of using swift run."
            wantsToRun = false
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationStatus = .authorized
            startOnQueue(deviceID: preferredDeviceID)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.authorizationStatus = granted ? .authorized : .denied
                    if granted {
                        self.refreshDevices()
                        self.startOnQueue(deviceID: self.preferredDeviceID)
                    } else {
                        self.errorMessage = "Camera access was denied. Enable it in System Settings › Privacy & Security › Camera."
                        self.wantsToRun = false
                    }
                }
            }
        case .denied, .restricted:
            authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
            errorMessage = "Camera access is off. Enable Faccy in System Settings › Privacy & Security › Camera."
            wantsToRun = false
        @unknown default:
            errorMessage = "Camera access is unavailable."
            wantsToRun = false
        }
    }

    func stop() {
        wantsToRun = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    /// Requests camera permission without starting a capture session.
    func requestAccess() {
        guard hasCameraUsageDescription else {
            errorMessage = "Camera access requires the Faccy.app bundle. Build and open it with ./scripts/build.sh --open instead of using swift run."
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.authorizationStatus = granted ? .authorized : .denied
                    if granted {
                        self.refreshDevices()
                    } else {
                        self.errorMessage = "Camera access was denied. Enable it in System Settings › Privacy & Security › Camera."
                    }
                }
            }
        case .denied, .restricted:
            openCameraPrivacySettings()
        case .authorized:
            authorizationStatus = .authorized
            refreshDevices()
        @unknown default:
            break
        }
    }

    func selectDevice(id: String?) {
        preferredDeviceID = id
        guard wantsToRun else { return }
        startOnQueue(deviceID: id)
    }

    func openCameraPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func startOnQueue(deviceID: String?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureIfNeeded(deviceID: deviceID)

            guard self.currentInput != nil else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }

            DispatchQueue.main.async {
                self.activeDeviceID = self.currentInput?.device.uniqueID
                self.isRunning = self.session.isRunning
                self.errorMessage = nil
            }
        }
    }

    private func configureIfNeeded(deviceID: String?) {
        let device = resolveDevice(deviceID: deviceID)
        guard let device else {
            DispatchQueue.main.async {
                self.errorMessage = "No built-in camera found. Faccy only uses the Mac's own camera — use Touch ID or your password instead."
            }
            return
        }

        if configuredDeviceID == device.uniqueID, currentInput != nil, videoOutput != nil {
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        if let currentInput {
            session.removeInput(currentInput)
            self.currentInput = nil
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Could not use \(device.localizedName)."
                }
                return
            }
            session.addInput(input)
            currentInput = input
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Could not open the camera: \(error.localizedDescription)"
            }
            return
        }

        if videoOutput == nil {
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(output) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Could not configure the camera output."
                }
                return
            }
            session.addOutput(output)
            videoOutput = output
        }

        configuredDeviceID = device.uniqueID
    }

    private func resolveDevice(deviceID: String?) -> AVCaptureDevice? {
        let devices = videoDevices()

        if let deviceID,
           let match = devices.first(where: { $0.uniqueID == deviceID }) {
            return match
        }
        if let preferredDeviceID,
           let match = devices.first(where: { $0.uniqueID == preferredDeviceID }) {
            return match
        }
        return devices.first
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrameTime >= 0.06 else { return }
        lastFrameTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(pixelBuffer)
        }
    }
}
