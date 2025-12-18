//
//  HostConnection.swift
//  Shelly
//
//  SwiftData model for Mac connection details
//

import Foundation
import SwiftData

@Model
final class HostConnection {
    @Attribute(.unique) var id: UUID
    var name: String
    var hostname: String
    var port: Int
    var lastConnected: Date?
    var isDefault: Bool
    var publicKeyFingerprint: String?
    var tlsCertificateFingerprint: String?  // TLS certificate fingerprint for cert pinning
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \CommandHistory.connection)
    var commandHistory: [CommandHistory] = []

    init(
        id: UUID = UUID(),
        name: String,
        hostname: String,
        port: Int = Int(Constants.defaultPort),
        isDefault: Bool = false,
        publicKeyFingerprint: String? = nil,
        tlsCertificateFingerprint: String? = nil
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.isDefault = isDefault
        self.publicKeyFingerprint = publicKeyFingerprint
        self.tlsCertificateFingerprint = tlsCertificateFingerprint
        self.createdAt = Date()
    }

    var displayAddress: String {
        "\(hostname):\(port)"
    }
}
