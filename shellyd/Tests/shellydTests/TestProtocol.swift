//
//  TestProtocol.swift
//  shellydTests
//
//  Protocol definitions for testing (mirrors main code)
//

import Foundation

// MARK: - Message Types

enum ShellyMessageType: String, Codable {
    case hello
    case authChallenge
    case authResponse
    case authResult
    case disconnect
    case pairRequest
    case pairChallenge
    case pairVerify
    case pairResponse
    case terminalOutput
    case terminalInput
    case terminalResize
    case settingsSync
    case settingsUpdate
    case settingsConfirm
    case ping
    case pong
    case error
}

// MARK: - Base Message

struct ShellyMessage: Codable {
    let type: ShellyMessageType
    let payload: Data
    let timestamp: Date
    let messageId: UUID

    init(type: ShellyMessageType, payload: Data, messageId: UUID = UUID()) {
        self.type = type
        self.payload = payload
        self.timestamp = Date()
        self.messageId = messageId
    }

    init<T: Encodable>(type: ShellyMessageType, payload: T, messageId: UUID = UUID()) throws {
        self.type = type
        self.payload = try JSONEncoder().encode(payload)
        self.timestamp = Date()
        self.messageId = messageId
    }

    func decodePayload<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: payload)
    }
}

// MARK: - Payloads

struct HelloPayload: Codable {
    let clientVersion: String
    let publicKey: String
    let deviceName: String
}

struct AuthChallengePayload: Codable {
    let challenge: Data
    let serverVersion: String
    let serverPublicKey: String
}

struct AuthResponsePayload: Codable {
    let signature: Data
}

struct AuthResultPayload: Codable {
    let success: Bool
    let message: String?
    let sessionToken: String?
}

struct PairRequestPayload: Codable {
    let publicKey: String
    let deviceName: String
}

struct PairChallengePayload: Codable {
    let macName: String
    let message: String
}

struct PairVerifyPayload: Codable {
    let code: String
}

struct PairResponsePayload: Codable {
    let success: Bool
    let message: String?
    let certificateFingerprint: String?
}

struct TerminalOutputPayload: Codable {
    let data: Data
}

struct TerminalInputPayload: Codable {
    let data: Data

    init(string: String) {
        self.data = string.data(using: .utf8) ?? Data()
    }
}

struct TerminalResizePayload: Codable {
    let rows: Int
    let cols: Int
}

struct ErrorPayload: Codable {
    let code: String
    let message: String
    let recoverable: Bool
}

struct SettingsValue: Codable {
    let value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(Bool.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct SettingsUpdatePayload: Codable {
    let setting: String
    let value: Bool
}
