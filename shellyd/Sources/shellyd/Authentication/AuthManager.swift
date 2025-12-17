//
//  AuthManager.swift
//  shellyd
//
//  Authentication state machine and challenge generation
//

import Foundation
import Crypto

final class AuthManager {
    static let shared = AuthManager()

    private init() {}

    // MARK: - Challenge Generation

    func generateChallenge() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    // MARK: - Signature Verification

    func verifySignature(
        signature: Data,
        challenge: Data,
        publicKeyString: String
    ) -> Bool {
        // Parse SSH public key format
        guard let rawPublicKey = parseSSHPublicKey(publicKeyString) else {
            return false
        }

        // Verify using CryptoKit
        do {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: rawPublicKey)
            return publicKey.isValidSignature(signature, for: challenge)
        } catch {
            print("Signature verification error: \(error)")
            return false
        }
    }

    // MARK: - Key Parsing

    private func parseSSHPublicKey(_ keyString: String) -> Data? {
        let parts = keyString.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let keyType = String(parts[0])
        let keyData = String(parts[1])

        // Only support Ed25519 for now
        guard keyType == "ssh-ed25519" else {
            print("Unsupported key type: \(keyType)")
            return nil
        }

        guard let blob = Data(base64Encoded: keyData) else {
            return nil
        }

        // Parse SSH key blob format
        // Format: [4-byte length][key-type-string][4-byte length][raw-key-data]
        return extractRawPublicKey(from: blob)
    }

    private func extractRawPublicKey(from blob: Data) -> Data? {
        var offset = 0

        // Read key type length
        guard blob.count > 4 else { return nil }
        let keyTypeLength = blob.withUnsafeBytes { ptr -> Int in
            Int(ptr.load(fromByteOffset: offset, as: UInt32.self).bigEndian)
        }
        offset += 4

        // Skip key type string
        offset += keyTypeLength

        // Read raw key length
        guard blob.count > offset + 4 else { return nil }
        let rawKeyLength = blob.withUnsafeBytes { ptr -> Int in
            Int(ptr.load(fromByteOffset: offset, as: UInt32.self).bigEndian)
        }
        offset += 4

        // Extract raw key data
        guard blob.count >= offset + rawKeyLength else { return nil }
        return blob.subdata(in: offset..<(offset + rawKeyLength))
    }

    // MARK: - Session Management

    func generateSessionToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
}
