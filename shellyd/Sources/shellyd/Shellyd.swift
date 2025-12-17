//
//  Shellyd.swift
//  shellyd
//
//  Shelly daemon - Remote terminal server for macOS
//

import Foundation
import ArgumentParser
import NIO
import NIOHTTP1
import NIOWebSocket

@main
struct Shellyd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shellyd",
        abstract: "Shelly daemon - Remote terminal server for macOS",
        version: "1.0.0",
        subcommands: [Start.self, Stop.self, Status.self, AddKey.self, Pair.self],
        defaultSubcommand: Start.self
    )
}

// MARK: - Start Command

struct Start: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the Shelly daemon"
    )

    @Option(name: .shortAndLong, help: "Port to listen on")
    var port: Int = 8765

    @Option(name: .shortAndLong, help: "Host to bind to")
    var host: String = "0.0.0.0"

    @Flag(name: .shortAndLong, help: "Run in foreground (don't daemonize)")
    var foreground: Bool = false

    @Flag(name: .shortAndLong, help: "Enable verbose logging")
    var verbose: Bool = false

    @Flag(name: .long, help: "Enable pairing mode for new devices")
    var pairing: Bool = false

    func run() async throws {
        var config = ServerConfiguration(
            host: host,
            port: port,
            verbose: verbose
        )

        print("""

        ╔═══════════════════════════════════════════╗
        ║           🐚 Shelly Daemon                ║
        ╚═══════════════════════════════════════════╝

        """)

        // Initialize configuration directory
        try ConfigManager.shared.ensureConfigDirectory()

        // Load authorized keys
        let authorizedKeys = try PublicKeyStore.shared.loadAuthorizedKeys()

        // Auto-enable pairing if no keys configured
        let enablePairing = pairing || authorizedKeys.isEmpty

        if enablePairing {
            let pairingCode = PairingManager.shared.generateCode()
            config.pairingCode = pairingCode
            PairingManager.shared.saveCodeToFile(pairingCode)

            print("""
            ┌───────────────────────────────────────────┐
            │          📱 PAIRING MODE ENABLED          │
            │                                           │
            │   Enter this code in the Shelly iOS app:  │
            │                                           │
            │              🔑  \(pairingCode)                  │
            │                                           │
            │   Code expires in 10 minutes              │
            └───────────────────────────────────────────┘

            """)
        }

        print("  📡 Listening on: \(host):\(port)")
        print("  🔐 Authorized keys: \(authorizedKeys.count)")
        if verbose {
            print("  📝 Verbose logging: enabled")
        }
        print("")

        if authorizedKeys.isEmpty && !enablePairing {
            print("  ⚠️  No authorized keys. Use --pairing flag or:")
            print("     shellyd add-key <public-key>")
            print("")
        }

        print("  Press Ctrl+C to stop\n")

        // Start Bonjour advertising
        let advertiser = BonjourAdvertiser(port: port)
        try advertiser.startAdvertising()

        // Start server
        let server = WebSocketServer(configuration: config)
        try await server.start()
    }
}

// MARK: - Pair Command

struct Pair: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate a pairing code for new devices"
    )

    func run() async throws {
        let code = PairingManager.shared.generateCode()
        PairingManager.shared.saveCodeToFile(code)

        print("""

        ┌───────────────────────────────────────────┐
        │          📱 PAIRING CODE                  │
        │                                           │
        │   Enter this code in the Shelly iOS app:  │
        │                                           │
        │              🔑  \(code)                  │
        │                                           │
        │   Code expires in 10 minutes              │
        └───────────────────────────────────────────┘

        If daemon is running, restart it with --pairing flag:
          shellyd start --pairing

        """)
    }
}

// MARK: - Stop Command

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop the Shelly daemon"
    )

    func run() throws {
        let pidFile = ConfigManager.shared.pidFilePath

        guard FileManager.default.fileExists(atPath: pidFile.path) else {
            print("Daemon is not running (no PID file found)")
            return
        }

        let pidString = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(pidString) else {
            print("Invalid PID file")
            return
        }

        if kill(pid, SIGTERM) == 0 {
            print("✓ Stopped daemon (PID: \(pid))")
            try? FileManager.default.removeItem(at: pidFile)
        } else {
            print("Daemon already stopped")
            try? FileManager.default.removeItem(at: pidFile)
        }
    }
}

// MARK: - Status Command

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check daemon status"
    )

    func run() throws {
        let pidFile = ConfigManager.shared.pidFilePath

        guard FileManager.default.fileExists(atPath: pidFile.path) else {
            print("● Daemon is not running")
            return
        }

        let pidString = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(pidString) else {
            print("Invalid PID file")
            return
        }

        if kill(pid, 0) == 0 {
            print("● Daemon is running (PID: \(pid))")

            if let config = try? ConfigManager.shared.loadConfig() {
                print("  Port: \(config.port)")
            }

            let keys = (try? PublicKeyStore.shared.loadAuthorizedKeys()) ?? []
            print("  Authorized keys: \(keys.count)")
        } else {
            print("● Daemon is not running (stale PID file)")
            try? FileManager.default.removeItem(at: pidFile)
        }
    }
}

// MARK: - Add Key Command

struct AddKey: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add-key",
        abstract: "Add an authorized public key"
    )

    @Argument(help: "The public key in OpenSSH format (ssh-ed25519 AAAA...)")
    var publicKey: String

    @Option(name: .shortAndLong, help: "Comment/name for this key")
    var name: String?

    func run() throws {
        try ConfigManager.shared.ensureConfigDirectory()

        let keyName = name ?? "device-\(String(Int.random(in: 1000...9999)))"

        try PublicKeyStore.shared.addAuthorizedKey(publicKey, name: keyName)
        print("✓ Added authorized key: \(keyName)")
    }
}
