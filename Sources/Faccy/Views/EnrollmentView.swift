import SwiftUI

struct EnrollmentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                HStack(alignment: .top, spacing: 20) {
                    previewCard
                        .frame(maxWidth: .infinity)

                    controlPanel
                        .frame(width: 340)
                }

                privacyNote
            }
            .padding(28)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .confirmationDialog(
            "Delete your face profile?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete Profile", role: .destructive) {
                model.deleteProfile()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Protected apps will stay in your list, but face authentication will stop working until you enroll again.")
        }
        .onDisappear {
            if model.isEnrolling {
                model.cancelEnrollment()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Face Setup")
                .font(.system(size: 30, weight: .bold))
            Text("Enroll once, then verify before protected apps open.")
                .foregroundStyle(.secondary)
        }
    }

    private var previewCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black)

            if model.camera.authorizationStatus == .denied || model.camera.authorizationStatus == .restricted {
                CameraPermissionView()
            } else if model.camera.isRunning || model.isEnrolling {
                CameraPreviewView(
                    session: model.camera.session,
                    mirror: model.settings.mirrorPreview
                )
                .overlay(FaceGuideOverlay())
            } else {
                idlePlaceholder
            }

            VStack {
                HStack {
                    StatusPill(
                        text: model.camera.isRunning ? "Camera live" : "Camera off",
                        systemImage: model.camera.isRunning ? "video.fill" : "video.slash",
                        tint: model.camera.isRunning ? .green : .secondary
                    )
                    .padding(14)

                    Spacer()
                }

                Spacer()

                if !model.cameraHint.isEmpty {
                    Text(model.cameraHint)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(14)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var idlePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text("Camera is off")
                .font(.headline)
                .foregroundStyle(.white)
            Text("It starts only while enrolling or verifying.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var controlPanel: some View {
        VStack(spacing: 16) {
            profileCard

            if model.isEnrolling {
                enrollmentCard
            } else if case .failed(let message) = model.enrollmentPhase {
                failureCard(message)
            } else if model.enrollmentPhase == .completed {
                completedCard
            }

            instructionsCard
        }
    }

    private var profileCard: some View {
        SectionCard(
            title: "Face Profile",
            subtitle: model.isEnrolled ? "Stored locally on this Mac" : "Not enrolled yet"
        ) {
            if let profile = model.profile {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Profile active")
                            .font(.headline)
                        Text("Enrolled \(profile.createdAt, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                Divider()

                HStack {
                    Text("Samples")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(profile.sampleCount)")
                        .monospacedDigit()
                }
                .font(.callout)

                HStack {
                    Button {
                        model.requestTest()
                    } label: {
                        Label("Test Face", systemImage: "faceid")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        model.startEnrollment()
                    } label: {
                        Label("Re-enroll", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isEnrolling)

                    Spacer()
                }

                Button("Delete Profile", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.red)
                .disabled(model.isEnrolling)
            } else {
                Text("No face profile has been created yet.")
                    .foregroundStyle(.secondary)

                Button {
                    model.startEnrollment()
                } label: {
                    Label("Enroll My Face", systemImage: "faceid")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isEnrolling)
            }
        }
    }

    private var enrollmentCard: some View {
        SectionCard(
            title: "Enrolling",
            subtitle: "Sample \(model.enrollmentCollected) of \(model.requiredEnrollmentSamples)"
        ) {
            ProgressView(
                value: Double(model.enrollmentCollected),
                total: Double(model.requiredEnrollmentSamples)
            )

            if let quality = model.lastFaceQuality {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Capture quality")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(quality * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(max(quality, 0), 1))
                        .tint(quality >= model.settings.minimumFaceQuality ? .green : .orange)
                }
            }

            Text(model.cameraHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Cancel Enrollment") {
                model.cancelEnrollment()
            }
            .buttonStyle(.bordered)
        }
    }

    private func failureCard(_ message: String) -> some View {
        SectionCard(title: "Enrollment Failed") {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("Try Again") {
                    model.startEnrollment()
                }
                .buttonStyle(.borderedProminent)

                Button("Dismiss") {
                    model.cancelEnrollment()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var completedCard: some View {
        SectionCard(title: "Profile Saved") {
            Text("Your face profile is ready. You can now protect apps and verify with a quick scan.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                model.requestTest()
            } label: {
                Label("Test Recognition", systemImage: "faceid")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var instructionsCard: some View {
        SectionCard(title: "Tips for a good scan") {
            VStack(alignment: .leading, spacing: 9) {
                tip("sun.max", "Face a light source — avoid strong backlight.")
                tip("person.crop.circle", "Keep your whole face inside the oval.")
                tip("arrow.triangle.2.circlepath", "During enrollment, slowly turn your head a little.")
                tip("lock.shield", "Feature prints never leave this Mac.")
            }
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.secondary)

            Text("Faccy stores face feature prints, not photos, in ~/Library/Application Support/Faccy. Recognition runs entirely on this Mac. Face authentication is convenient, but it is not a replacement for FileVault, Touch ID, or a strong login password.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
