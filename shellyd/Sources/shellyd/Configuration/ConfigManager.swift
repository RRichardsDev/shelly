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

    init(
        port: Int = 8765,
        host: String = "0.0.0.0",
        shell: String = "/bin/zsh",
        enableSudoInterception: Bool = true,
        pushNotificationsEnabled: Bool = false,
        sessionTimeout: TimeInterval = 3600,
        maxConnections: Int = 5
    ) {
        self.port = port
        self.host = host
        self.shell = shell
        self.enableSudoInterception = enableSudoInterception
        self.pushNotificationsEnabled = pushNotificationsEnabled
        self.sessionTimeout = sessionTimeout
        self.maxConnections = maxConnections
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
