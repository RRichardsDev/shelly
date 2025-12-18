//
//  SSHKeyPair.swift
//  Shelly
//
//  SwiftData model for SSH key metadata (private key stored in Keychain)
//

import Foundation
import SwiftData

@Model
final class SSHKeyPair {
    @Attribute(.unique) var id: UUID
    var name: String
    var publicKey: String
    var keyType: String
    var createdAt: Date
    var keychainIdentifier: String
    var isDefault: Bool
    var fingerprint: String

    init(
        id: UUID = UUID(),
        name: String,
        publicKey: String,
        keyType: String = "ed25519",
        keychainIdentifier: String,
        isDefault: Bool = false,
        fingerprint: String
    ) {
        self.id = id
        self.name = name
        self.publicKey = publicKey
        self.keyType = keyType
        self.createdAt = Date()
        self.keychainIdentifier = keychainIdentifier
        self.isDefault = isDefault
        self.fingerprint = fingerprint
    }

    var shortFingerprint: String {
        String(fingerprint.prefix(16))
    }
}
