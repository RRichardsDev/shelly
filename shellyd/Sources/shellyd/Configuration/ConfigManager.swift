//
//  ConfigManager.swift
//  shellyd
//
//  Configuration management for the daemon
//

import Foundation

final class ConfigManager {
    static let shared = ConfigManager()

    private init() {}

    // MARK: - Paths

    var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".shellyd")
    }

    var configFilePath: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    var authorizedKeysPath: URL {
        configDirectory.appendingPathComponent("authorized_keys")
    }

    var pidFilePath: URL {
        configDirectory.appendingPathComponent("shellyd.pid")
    }

    var logFilePath: URL {
        configDirectory.appendingPathComponent("shellyd.log")
    }

    var auditLogPath: URL {
        configDirectory.appendingPathComponent("audit.log")
    }

    var tlsCertificatePath: URL {
        configDirectory.appendingPathComponent("server.crt")
    }

    var tlsPrivateKeyPath: URL {
        configDirectory.appendingPathComponent("server.key")
    }

    // MARK: - Setup

    func ensureConfigDirectory() throws {
        let fm = FileManager.default

        if !fm.fileExists(atPath: configDirectory.path) {
            try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)

            // Set restrictive permissions (700)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: configDirectory.path)
        }

        // Create default config if needed
        if !fm.fileExists(atPath: configFilePath.path) {
            let defaultConfig = Config()
            try saveConfig(defaultConfig)
        }

        // Create authorized_keys if needed
        if !fm.fileExists(atPath: authorizedKeysPath.path) {
            fm.createFile(atPath: authorizedKeysPath.path, contents: nil)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authorizedKeysPath.path)
        }
    }

    // MARK: - Config Operations

    func loadConfig() throws -> Config {
        let data = try Data(contentsOf: configFilePath)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    func saveConfig(_ config: Config) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configFilePath)

        // Ensure secure permissions
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configFilePath.path
        )
    }

    // MARK: - PID File

    func writePIDFile() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        try String(pid).write(to: pidFilePath, atomically: true, encoding: .utf8)
    }

    func removePIDFile() throws {
        try FileManager.default.removeItem(at: pidFilePath)
    }
}

// MARK: - Config Model

struct Config: Codable {
    var port: Int
    var host: String
    var shell: String
    var enableSudoInterception: Bool
    var pushNotificationsEnabled: Bool
    var sessionTimeout: TimeInterval
    var maxConnections: Int

    // Security settings (all disabled by default)
    var tlsEnabled: Bool
    var certificatePinningEnabled: Bool
    var sessionTimeoutEnabled: Bool
    var sessionTimeoutSeconds: Int
    var auditLoggingEnabled: Bool
    var auditLogRetentionDays: Int

    init(
        port: Int = 8765,
        host: String = "0.0.0.0",
        shell: String = "/bin/zsh",
        enableSudoInterception: Bool = true,
        pushNotificationsEnabled: Bool = false,
        sessionTimeout: TimeInterval = 3600,
        maxConnections: Int = 5,
        tlsEnabled: Bool = false,
        certificatePinningEnabled: Bool = false,
        sessionTimeoutEnabled: Bool = false,
        sessionTimeoutSeconds: Int = 300,
        auditLoggingEnabled: Bool = false,
        auditLogRetentionDays: Int = 30
    ) {
        self.port = port
        self.host = host
        self.shell = shell
        self.enableSudoInterception = enableSudoInterception
        self.pushNotificationsEnabled = pushNotificationsEnabled
        self.sessionTimeout = sessionTimeout
        self.maxConnections = maxConnections
        self.tlsEnabled = tlsEnabled
        self.certificatePinningEnabled = certificatePinningEnabled
        self.sessionTimeoutEnabled = sessionTimeoutEnabled
        self.sessionTimeoutSeconds = sessionTimeoutSeconds
        self.auditLoggingEnabled = auditLoggingEnabled
        self.auditLogRetentionDays = auditLogRetentionDays
    }

    // Custom decoder with defaults for missing keys
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 8765
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? "0.0.0.0"
        shell = try container.decodeIfPresent(String.self, forKey: .shell) ?? "/bin/zsh"
        enableSudoInterception = try container.decodeIfPresent(Bool.self, forKey: .enableSudoInterception) ?? true
        pushNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .pushNotificationsEnabled) ?? false
        sessionTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .sessionTimeout) ?? 3600
        maxConnections = try container.decodeIfPresent(Int.self, forKey: .maxConnections) ?? 5
        tlsEnabled = try container.decodeIfPresent(Bool.self, forKey: .tlsEnabled) ?? false
        certificatePinningEnabled = try container.decodeIfPresent(Bool.self, forKey: .certificatePinningEnabled) ?? false
        sessionTimeoutEnabled = try container.decodeIfPresent(Bool.self, forKey: .sessionTimeoutEnabled) ?? false
        sessionTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .sessionTimeoutSeconds) ?? 300
        auditLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .auditLoggingEnabled) ?? false
        auditLogRetentionDays = try container.decodeIfPresent(Int.self, forKey: .auditLogRetentionDays) ?? 30
    }
}

// MARK: - Server Configuration

struct ServerConfiguration {
    let host: String
    let port: Int
    let verbose: Bool
    var pairingCode: String?

    init(host: String = "0.0.0.0", port: Int = 8765, verbose: Bool = false, pairingCode: String? = nil) {
        self.host = host
        self.port = port
        self.pairingCode = pairingCode
        self.verbose = verbose
    }
}
