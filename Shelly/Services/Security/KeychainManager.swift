//
//  KeychainManager.swift
//  Shelly
//
//  Secure storage for SSH keys, passwords, and tokens
//

import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()

    private let service = Constants.keychainService

    private init() {}

    // MARK: - Generic Operations

    func save(_ data: Data, forKey key: String) throws {
        // Delete existing item first
        try? delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func load(forKey key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }

        return data
    }

    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    func exists(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - String Convenience

    func saveString(_ string: String, forKey key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(data, forKey: key)
    }

    func loadString(forKey key: String) throws -> String {
        let data = try load(forKey: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return string
    }

    // MARK: - SSH Key Operations

    func saveSSHPrivateKey(_ privateKey: Data, identifier: String) throws {
        try save(privateKey, forKey: "ssh_key_\(identifier)")
    }

    func loadSSHPrivateKey(identifier: String) throws -> Data {
        try load(forKey: "ssh_key_\(identifier)")
    }

    func deleteSSHPrivateKey(identifier: String) throws {
        try delete(forKey: "ssh_key_\(identifier)")
    }

    // MARK: - Sudo Password Operations

    func saveSudoPassword(_ password: String, forHost hostId: UUID) throws {
        try saveString(password, forKey: "sudo_\(hostId.uuidString)")
    }

    func loadSudoPassword(forHost hostId: UUID) throws -> String {
        try loadString(forKey: "sudo_\(hostId.uuidString)")
    }

    func deleteSudoPassword(forHost hostId: UUID) throws {
        try delete(forKey: "sudo_\(hostId.uuidString)")
    }

    func hasSudoPassword(forHost hostId: UUID) -> Bool {
        exists(forKey: "sudo_\(hostId.uuidString)")
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to Keychain: \(status)"
        case .loadFailed(let status):
            return "Failed to load from Keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain: \(status)"
        case .encodingFailed:
            return "Failed to encode data for Keychain"
        case .decodingFailed:
            return "Failed to decode data from Keychain"
        }
    }
}
