//
//  AuthenticationManager.swift
//  Shelly
//
//  Face ID / Touch ID authentication management
//

import Foundation
import LocalAuthentication

final class AuthenticationManager {
    static let shared = AuthenticationManager()

    private init() {}

    // Check if biometric authentication is available
    var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    // Get the type of biometric available
    var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .opticID
        @unknown default:
            return .none
        }
    }

    // Authenticate to unlock the app
    func authenticateToUnlock() async -> AuthenticationResult {
        await authenticate(reason: "Unlock Shelly to access your terminal")
    }

    // Authenticate to confirm sudo command
    func authenticateForSudo(command: String) async -> AuthenticationResult {
        let reason = "Confirm sudo command: \(command.prefix(50))\(command.count > 50 ? "..." : "")"
        return await authenticate(reason: reason)
    }

    // Generic authentication
    func authenticate(reason: String) async -> AuthenticationResult {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Fall back to device passcode
            return await authenticateWithPasscode(reason: reason)
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success ? .success : .failed
        } catch let authError as LAError {
            switch authError.code {
            case .userCancel:
                return .cancelled
            case .userFallback:
                return await authenticateWithPasscode(reason: reason)
            case .biometryLockout:
                return await authenticateWithPasscode(reason: reason)
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    // Fallback to device passcode
    private func authenticateWithPasscode(reason: String) async -> AuthenticationResult {
        let context = LAContext()

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            return success ? .success : .failed
        } catch {
            return .failed
        }
    }
}

// MARK: - Types

enum BiometricType {
    case none
    case faceID
    case touchID
    case opticID

    var displayName: String {
        switch self {
        case .none: return "Passcode"
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "lock.fill"
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        }
    }
}

enum AuthenticationResult {
    case success
    case failed
    case cancelled
    case unavailable

    var isSuccess: Bool {
        self == .success
    }
}
