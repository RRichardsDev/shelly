//
//  PairingManager.swift
//  shellyd
//
//  Manages device pairing with 6-digit codes
//

import Foundation

final class PairingManager {
    static let shared = PairingManager()

    private var currentCode: String?
    private var codeExpiry: Date?
    private let codeValidityDuration: TimeInterval = 600 // 10 minutes

    private init() {}

    // Generate a new 6-digit pairing code
    func generateCode() -> String {
        let code = String(format: "%06d", Int.random(in: 0...999999))
        currentCode = code
        codeExpiry = Date().addingTimeInterval(codeValidityDuration)
        return code
    }

    // Validate a pairing code
    func validateCode(_ code: String) -> Bool {
        guard let currentCode = currentCode,
              let expiry = codeExpiry,
              Date() < expiry else {
            return false
        }
        return code == currentCode
    }

    // Invalidate current code (after successful pairing)
    func invalidateCode() {
        currentCode = nil
        codeExpiry = nil
    }

    // Check if pairing mode is active
    var isPairingActive: Bool {
        guard let expiry = codeExpiry else { return false }
        return Date() < expiry
    }

    // Save code to file for reference
    func saveCodeToFile(_ code: String) {
        let path = ConfigManager.shared.configDirectory.appendingPathComponent("pairing_code")
        try? code.write(to: path, atomically: true, encoding: .utf8)
    }

    // Load code from file
    func loadCodeFromFile() -> String? {
        let path = ConfigManager.shared.configDirectory.appendingPathComponent("pairing_code")
        return try? String(contentsOf: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
