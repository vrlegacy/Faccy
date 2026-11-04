import CryptoKit
import Foundation
import LocalAuthentication

/// A salted, iterated SHA-256 record of the user's fallback password.
/// The password itself is never stored.
struct PasswordRecord: Codable, Equatable, Sendable {
    var salt: Data
    var hash: Data
    var iterations: Int

    static let defaultIterations = 60_000
    static let minimumLength = 4

    static func make(password: String, iterations: Int = defaultIterations) -> PasswordRecord {
        var saltBytes = [UInt8](repeating: 0, count: 16)
        for index in saltBytes.indices {
            saltBytes[index] = UInt8.random(in: 0...255)
        }
        let salt = Data(saltBytes)

        return PasswordRecord(
            salt: salt,
            hash: derive(password: password, salt: salt, iterations: iterations),
            iterations: iterations
        )
    }

    func matches(_ password: String) -> Bool {
        let candidate = Self.derive(password: password, salt: salt, iterations: iterations)
        return Self.constantTimeEquals(candidate, hash)
    }

    static func derive(password: String, salt: Data, iterations: Int) -> Data {
        var block = Data(salt)
        block.append(Data(password.utf8))

        var digest = Data(SHA256.hash(data: block))
        guard iterations > 1 else { return digest }

        for _ in 1..<iterations {
            var input = Data()
            input.append(digest)
            input.append(salt)
            digest = Data(SHA256.hash(data: input))
        }
        return digest
    }

    private static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }
}

enum SecondaryAuth {
    /// True when this Mac has an enrolled fingerprint sensor.
    static var biometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    static var biometryDescription: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID:
            return "Touch ID"
        case .faceID:
            return "Face ID"
        case .opticID:
            return "Optic ID"
        default:
            return "Biometrics"
        }
    }

    static func evaluateBiometrics(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Use Face Auth"
        try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )
    }
}
