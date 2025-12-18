//
//  SSHKeyGenerator.swift
//  Shelly
//
//  Ed25519 SSH key generation and management
//

import Foundation
import CryptoKit

final class SSHKeyGenerator {
    static let shared = SSHKeyGenerator()

    private init() {}

    // Generate a new Ed25519 keypair
    func generateKeyPair() -> (privateKey: Curve25519.Signing.PrivateKey, publicKey: String) {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = formatPublicKeyOpenSSH(privateKey.publicKey)
        return (privateKey, publicKey)
    }

    // Format public key in OpenSSH format
    func formatPublicKeyOpenSSH(_ publicKey: Curve25519.Signing.PublicKey) -> String {
        let keyType = "ssh-ed25519"
        let keyTypeData = keyType.data(using: .utf8)!
        let publicKeyRaw = publicKey.rawRepresentation

        var blob = Data()
        // Length-prefixed key type
        var keyTypeLength = UInt32(keyTypeData.count).bigEndian
        blob.append(Data(bytes: &keyTypeLength, count: 4))
        blob.append(keyTypeData)

        // Length-prefixed public key
        var pubKeyLength = UInt32(publicKeyRaw.count).bigEndian
        blob.append(Data(bytes: &pubKeyLength, count: 4))
        blob.append(publicKeyRaw)

        return "\(keyType) \(blob.base64EncodedString())"
    }

    // Calculate fingerprint of public key (SHA256)
    func fingerprint(_ publicKey: Curve25519.Signing.PublicKey) -> String {
        let hash = SHA256.hash(data: publicKey.rawRepresentation)
        return "SHA256:" + Data(hash).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
    }

    func fingerprint(fromPublicKeyString publicKeyString: String) -> String? {
        guard let publicKey = parsePublicKey(publicKeyString) else { return nil }
        return fingerprint(publicKey)
    }

    // Parse OpenSSH public key string
    func parsePublicKey(_ opensshKey: String) -> Curve25519.Signing.PublicKey? {
        let parts = opensshKey.split(separator: " ")
        guard parts.count >= 2,
              parts[0] == "ssh-ed25519",
              let blob = Data(base64Encoded: String(parts[1])) else {
            return nil
        }

        // Parse blob: skip key type, get public key data
        var offset = 0

        // Read key type length and skip
        guard blob.count > 4 else { return nil }
        let keyTypeLength = Int(blob.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).bigEndian })
        offset += 4 + keyTypeLength

        // Read public key length
        guard blob.count > offset + 4 else { return nil }
        let pubKeyLength = Int(blob.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).bigEndian })
        offset += 4

        // Extract public key data
        guard blob.count >= offset + pubKeyLength else { return nil }
        let pubKeyData = blob.subdata(in: offset..<(offset + pubKeyLength))

        return try? Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData)
    }

    // Sign data with private key
    func sign(_ data: Data, with privateKey: Curve25519.Signing.PrivateKey) -> Data {
        try! privateKey.signature(for: data)
    }

    // Verify signature
    func verify(_ signature: Data, for data: Data, with publicKey: Curve25519.Signing.PublicKey) -> Bool {
        publicKey.isValidSignature(signature, for: data)
    }

    // Serialize private key for Keychain storage
    func serializePrivateKey(_ privateKey: Curve25519.Signing.PrivateKey) -> Data {
        privateKey.rawRepresentation
    }

    // Deserialize private key from Keychain
    func deserializePrivateKey(_ data: Data) throws -> Curve25519.Signing.PrivateKey {
        try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    // Generate and save a new key pair
    func generateAndSaveKeyPair(name: String) throws -> (keychainId: String, publicKey: String, fingerprint: String) {
        let (privateKey, publicKey) = generateKeyPair()
        let keychainId = UUID().uuidString
        let fp = fingerprint(privateKey.publicKey)

        // Save private key to Keychain
        try KeychainManager.shared.saveSSHPrivateKey(
            serializePrivateKey(privateKey),
            identifier: keychainId
        )

        return (keychainId, publicKey, fp)
    }

    // Load private key from Keychain
    func loadPrivateKey(identifier: String) throws -> Curve25519.Signing.PrivateKey {
        let data = try KeychainManager.shared.loadSSHPrivateKey(identifier: identifier)
        return try deserializePrivateKey(data)
    }
}
