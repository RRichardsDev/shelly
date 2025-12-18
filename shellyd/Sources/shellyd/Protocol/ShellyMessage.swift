//
//  ShellyMessage.swift
//  shellyd
//
//  Protocol message definitions (mirrors iOS app)
//

import Foundation

// MARK: - Message Types

enum ShellyMessageType: String, Codable {
    // Connection lifecycle
    case hello
    case authChallenge
    case authResponse
    case authResult
    case disconnect

    // Pairing
    case pairRequest      // iPhone -> Mac: "I want to pair"
    case pairChallenge    // Mac -> iPhone: "Enter this code"
    case pairVerify       // iPhone -> Mac: "Here's the code I entered"
    case pairResponse     // Mac -> iPhone: "Success/Failure"

    // Terminal I/O
    case terminalOutput
    case terminalInput
    case terminalResize

    // Sudo flow
    case sudoPrompt
    case sudoConfirmRequest
    case sudoConfirmResponse
    case sudoPassword

    // Notifications
    case registerPushToken
    case longRunningCommand
    case commandComplete

    // Settings sync
    case settingsSync       // Mac -> iPhone: Full settings on connect
    case settingsUpdate     // iPhone -> Mac: Request setting change
    case settingsConfirm    // Mac -> iPhone: Confirm change applied

    // System
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

// MARK: - Connection Payloads

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

// MARK: - Pairing Payloads

struct PairRequestPayload: Codable {
    let publicKey: String
    let deviceName: String
}

struct PairChallengePayload: Codable {
    let macName: String
    let message: String  // "Enter the code shown on your Mac"
}

struct PairVerifyPayload: Codable {
    let code: String
}

struct PairResponsePayload: Codable {
    let success: Bool
    let message: String?
    let certificateFingerprint: String?  // TLS certificate fingerprint for pinning
}

// MARK: - Terminal Payloads

struct TerminalOutputPayload: Codable {
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(string: String) {
        self.data = string.data(using: .utf8) ?? Data()
    }

    var string: String? {
        String(data: data, encoding: .utf8)
    }
}

struct TerminalInputPayload: Codable {
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(string: String) {
        self.data = string.data(using: .utf8) ?? Data()
    }
}

struct TerminalResizePayload: Codable {
    let rows: Int
    let cols: Int
}

// MARK: - Sudo Payloads

struct SudoPromptPayload: Codable {
    let prompt: String
}

struct SudoConfirmRequestPayload: Codable {
    let requestId: UUID
    let command: String
}

struct SudoConfirmResponsePayload: Codable {
    let requestId: UUID
    let approved: Bool
}

struct SudoPasswordPayload: Codable {
    let password: String
}

// MARK: - Notification Payloads

struct RegisterPushTokenPayload: Codable {
    let token: String
    let deviceId: String
}

struct CommandCompletePayload: Codable {
    let command: String
    let exitCode: Int
    let duration: TimeInterval
}

// MARK: - System Payloads

struct ErrorPayload: Codable {
    let code: String
    let message: String
    let recoverable: Bool
}

struct EmptyPayload: Codable {}

// MARK: - Settings Sync Payloads

struct SecuritySettingsPayload: Codable {
    var tlsEnabled: Bool
    var certificatePinningEnabled: Bool
    var sessionTimeoutEnabled: Bool
    var sessionTimeoutSeconds: Int
    var auditLoggingEnabled: Bool
    var auditLogRetentionDays: Int
    var certificateFingerprint: String?  // Sent when TLS is enabled

    init(from config: Config, certificateFingerprint: String? = nil) {
        self.tlsEnabled = config.tlsEnabled
        self.certificatePinningEnabled = config.certificatePinningEnabled
        self.sessionTimeoutEnabled = config.sessionTimeoutEnabled
        self.sessionTimeoutSeconds = config.sessionTimeoutSeconds
        self.auditLoggingEnabled = config.auditLoggingEnabled
        self.auditLogRetentionDays = config.auditLogRetentionDays
        self.certificateFingerprint = certificateFingerprint
    }
}

struct SettingsUpdatePayload: Codable {
    let setting: String
    let value: SettingsValue
}

struct SettingsConfirmPayload: Codable {
    let setting: String
    let success: Bool
    let message: String?
    let reconnectRequired: Bool  // True when TLS setting changes
}

// Type-safe settings value wrapper
enum SettingsValue: Codable {
    case bool(Bool)
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                SettingsValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported value type")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}
