import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var showPasswordSetup = false
    @State private var showRemovePasswordConfirm = false

    var body: some View {
        Form {
            Section {
                Picker("Camera", selection: cameraBinding) {
                    Text("Automatic").tag("")
                    ForEach(model.camera.availableDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }

                HStack {
                    Text("Status")
                    Spacer()
                    Text(cameraStatusText)
                        .foregroundStyle(.secondary)
                }

                Toggle("Mirror camera preview", isOn: $model.settings.mirrorPreview)

                HStack {
                    Button("Refresh Cameras") {
                        model.camera.refreshDevices()
                    }

                    if model.camera.authorizationStatus == .denied || model.camera.authorizationStatus == .restricted {
                        Button("Open Camera Settings") {
                            model.openCameraPrivacySettings()
                        }
                    }
                }
            } header: {
                Text("Camera")
            } footer: {
                Text("Faccy only uses the Mac's built-in camera, and only while enrolling or verifying a face. External, iPhone and virtual cameras are ignored.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Match tolerance")
                        Spacer()
                        Text(String(format: "%.2f", model.settings.recognitionThreshold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $model.settings.recognitionThreshold,
                        in: 0.15...0.90,
                        step: 0.01
                    )

                    Text("Lower values are stricter. If your face is often rejected, raise it slightly. If someone else gets in, lower it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Stepper(
                    "Enrollment samples: \(model.settings.enrollmentSampleCount)",
                    value: $model.settings.enrollmentSampleCount,
                    in: 3...10
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Minimum capture quality")
                        Spacer()
                        Text("\(Int(model.settings.minimumFaceQuality * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $model.settings.minimumFaceQuality,
                        in: 0.10...0.80,
                        step: 0.05
                    )
                }

                Stepper(
                    "Verification timeout: \(Int(model.settings.maxVerifySeconds)) sec",
                    value: Binding(
                        get: { Int(model.settings.maxVerifySeconds) },
                        set: { model.settings.maxVerifySeconds = Double($0) }
                    ),
                    in: 5...30
                )
            } header: {
                Text("Recognition")
            } footer: {
                Text("To unlock, your face has to match and then blink once, so a still photo can't get in.")
            }

            Section {
                Toggle("Block protected apps launched outside Faccy", isOn: $model.settings.enforceSystemWide)

                if model.settings.enforceSystemWide {
                    Toggle("Lock protected apps already running when Faccy starts", isOn: $model.settings.enforceAtStartup)

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                        Text("Watchdog active — \(model.protectedApps.count) protected app\(model.protectedApps.count == 1 ? "" : "s")")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Enforcement")
            } footer: {
                Text("When on, Faccy watches for protected apps opened from the Dock, Spotlight, Finder, or anywhere else. It quits them and asks you to authenticate before reopening. Apps that are already open, or that open on their own at login, are hidden instead and ask for a check when you switch to them. This is a watchdog, not a kernel-level block: an app may appear briefly before it is closed, and Faccy must be running.")
            }

            Section {
                Toggle(isOn: $model.settings.allowTouchID) {
                    HStack(spacing: 6) {
                        Text("Allow \(SecondaryAuth.biometryDescription)")
                        if !model.biometricsAvailable {
                            Text("(not available on this Mac)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!model.biometricsAvailable)

                Toggle("Allow a custom password", isOn: $model.settings.allowPasswordFallback)

                HStack {
                    Text("Password")
                    Spacer()
                    Text(model.hasPassword ? "Set" : "Not set")
                        .foregroundStyle(.secondary)

                    Button(model.hasPassword ? "Change…" : "Set…") {
                        showPasswordSetup = true
                    }

                    if model.hasPassword {
                        Button("Remove", role: .destructive) {
                            showRemovePasswordConfirm = true
                        }
                    }
                }
            } header: {
                Text("Fallback Unlock")
            } footer: {
                Text("Fallbacks let you open protected apps when Face Auth fails or the camera is unavailable. The password is stored as a salted, iterated SHA-256 hash — never in plain text.")
            }

            Section {
                Toggle("Require unlock to open Faccy", isOn: $model.settings.lockFaccyWindow)

                Picker("Remember each app's unlock for", selection: $model.settings.authValiditySeconds) {
                    Text("Every launch").tag(0)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("30 minutes").tag(1800)
                }

                Picker("Lock after idle", selection: $model.settings.idleLockSeconds) {
                    Text("Never").tag(0)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("30 minutes").tag(1800)
                }

                HStack {
                    Toggle(
                        "Launch Faccy at login",
                        isOn: Binding(
                            get: { model.settings.launchAtLogin },
                            set: { model.setLaunchAtLogin($0) }
                        )
                    )

                    Spacer()

                    if model.hasActiveSessions {
                        Button("Lock Now") {
                            model.lockNow()
                        }
                    }
                }
            } header: {
                Text("Session")
            } footer: {
                Text("Each app keeps its own unlock. Faccy locks every protected app and its own window when the screen locks, the Mac sleeps, or you are idle for the time above. If Faccy is not installed in /Applications, macOS may not allow it to register as a login item.")
            }

            Section {
                Toggle("Show Faccy in the menu bar", isOn: $model.settings.showMenuBarIcon)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Turn this off for a completely hidden background app. You can still open Faccy from Spotlight or by launching Faccy.app again.")
            }

            Section {
                HStack {
                    Text("Data folder")
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.open(model.persistence.directory)
                    }
                }

                HStack {
                    Text("Storage")
                    Spacer()
                    Text(model.isEnrolled ? "Face profile + settings" : "Settings only")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Data")
            } footer: {
                Text(model.persistence.directory.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Section {
                Label {
                    Text("Faccy is a convenience layer, not a system security boundary. It cannot unlock your Mac or replace FileVault. System-wide enforcement is a watchdog: a protected app can start and draw briefly before Faccy quits it. Anyone who can quit Faccy or edit its data folder can bypass it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.shield")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Security Notes")
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .navigationTitle("Settings")
        .onAppear {
            model.refreshSecondaryAvailability()
        }
        .sheet(isPresented: $showPasswordSetup) {
            PasswordSetupView()
                .environmentObject(model)
        }
        .alert("Remove fallback password?", isPresented: $showRemovePasswordConfirm) {
            Button("Remove", role: .destructive) {
                model.removePassword()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will only be able to unlock protected apps with Face Auth or Touch ID.")
        }
    }

    private var cameraBinding: Binding<String> {
        Binding(
            get: { model.settings.cameraDeviceID ?? "" },
            set: { newValue in
                model.settings.cameraDeviceID = newValue.isEmpty ? nil : newValue
            }
        )
    }

    private var cameraStatusText: String {
        switch model.camera.authorizationStatus {
        case .authorized:
            return model.camera.isRunning ? "Authorized · live" : "Authorized · idle"
        case .notDetermined:
            return "Permission not requested"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        @unknown default:
            return "Unknown"
        }
    }
}
