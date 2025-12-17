//
//  PublicKeyStore.swift
//  shellyd
//
//  Storage for authorized public keys
//

import Foundation
import Crypto

final class PublicKeyStore {
    static let shared = PublicKeyStore()

    private init() {}

    // MARK: - Authorized Key Model

    struct AuthorizedKey {
        let publicKey: String
        let name: String
        let fingerprint: String
    }

    // MARK: - Load/Save

    func loadAuthorizedKeys() throws -> [AuthorizedKey] {
        let path = ConfigManager.shared.authorizedKeysPath

        guard FileManager.default.fileExists(atPath: path.path) else {
            return []
        }

        let content = try String(contentsOf: path, encoding: .utf8)
        var keys: [AuthorizedKey] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }

            // Parse: ssh-ed25519 AAAA... name
            let parts = trimmed.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2 else { continue }

            let keyType = String(parts[0])
            let keyData = String(parts[1])
            let name = parts.count > 2 ? String(parts[2]) : "unnamed"

            let fullKey = "\(keyType) \(keyData)"
            let fingerprint = calculateFingerprint(keyData) ?? "unknown"

            keys.append(AuthorizedKey(
                publicKey: fullKey,
                name: name,
                fingerprint: fingerprint
            ))
        }

        return keys
    }

    func addAuthorizedKey(_ key: String, name: String) throws {
        let path = ConfigManager.shared.authorizedKeysPath

        // Validate key format
        let parts = key.split(separator: " ")
        guard parts.count >= 2,
              parts[0] == "ssh-ed25519" || parts[0] == "ssh-rsa" else {
            throw KeyError.invalidFormat
        }

        // Append to file
        var content = ""
        if FileManager.default.fileExists(atPath: path.path) {
            content = try String(contentsOf: path, encoding: .utf8)
            if !content.hasSuffix("\n") {
                content += "\n"
            }
        }

        // Add key with name
        let keyLine = parts.count > 2 ? key : "\(key) \(name)"
        content += keyLine + "\n"

        try content.write(to: path, atomically: true, encoding: .utf8)

        // Ensure secure permissions
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path.path
        )
    }

    func removeAuthorizedKey(fingerprint: String) throws {
        let keys = try loadAuthorizedKeys()
        let remaining = keys.filter { $0.fingerprint != fingerprint }

        // Rewrite file
        let path = ConfigManager.shared.authorizedKeysPath
        var content = ""
        for key in remaining {
            content += "\(key.publicKey) \(key.name)\n"
        }

        try content.write(to: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Verification

    func isAuthorized(publicKey: String) -> Bool {
        guard let keys = try? loadAuthorizedKeys() else {
            return false
        }

        // Normalize the key (just type and data, no name)
        let parts = publicKey.split(separator: " ")
        guard parts.count >= 2 else { return false }
        let normalizedKey = "\(parts[0]) \(parts[1])"

        return keys.contains { storedKey in
            let storedParts = storedKey.publicKey.split(separator: " ")
            guard storedParts.count >= 2 else { return false }
            let normalizedStored = "\(storedParts[0]) \(storedParts[1])"
            return normalizedKey == normalizedStored
        }
    }

    // MARK: - Fingerprint

    private func calculateFingerprint(_ base64KeyData: String) -> String? {
        guard let data = Data(base64Encoded: base64KeyData) else {
            return nil
        }

        let hash = SHA256.hash(data: data)
        return "SHA256:" + Data(hash).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Errors

enum KeyError: LocalizedError {
    case invalidFormat
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid public key format. Expected: ssh-ed25519 AAAA..."
        case .notFound:
            return "Key not found"
        }
    }
}
