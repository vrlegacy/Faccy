import SwiftUI

struct PasswordSetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?

    private var isValid: Bool {
        password.count >= PasswordRecord.minimumLength && password == confirmation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.hasPassword ? "Change Fallback Password" : "Set Fallback Password")
                    .font(.title2.weight(.semibold))
                Text("Use this to unlock protected apps when Face Auth or Touch ID isn't available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                SecureField("New password", text: $password)
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirm password", text: $confirmation)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !password.isEmpty, password.count < PasswordRecord.minimumLength {
                Text("Use at least \(PasswordRecord.minimumLength) characters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !confirmation.isEmpty, password != confirmation {
                Text("Passwords don't match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Stored locally as a salted, iterated SHA-256 hash.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func save() {
        guard isValid else { return }
        do {
            try model.setPassword(password)
            dismiss()
        } catch {
            errorMessage = "Could not save the password: \(error.localizedDescription)"
        }
    }
}
