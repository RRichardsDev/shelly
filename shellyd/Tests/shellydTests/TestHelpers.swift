//
//  TestHelpers.swift
//  shellydTests
//
//  Test utilities, key generation, and helpers
//

import Foundation
import Crypto

// MARK: - Test Key Pair

struct TestKeyPair {
    let privateKey: Curve25519.Signing.PrivateKey
    let publicKey: Curve25519.Signing.PublicKey
    let sshPublicKey: String

    init() {
        self.privateKey = Curve25519.Signing.PrivateKey()
        self.publicKey = privateKey.publicKey
        self.sshPublicKey = Self.formatAsSSHKey(publicKey: publicKey)
    }

    func sign(_ data: Data) -> Data {
        try! privateKey.signature(for: data)
    }

    private static func formatAsSSHKey(publicKey: Curve25519.Signing.PublicKey) -> String {
        // Build SSH key blob: [4-byte length][key-type][4-byte length][raw-key]
        var blob = Data()

        let keyType = "ssh-ed25519"
        let keyTypeData = keyType.data(using: .utf8)!

        // Key type length (big endian)
        var keyTypeLength = UInt32(keyTypeData.count).bigEndian
        blob.append(Data(bytes: &keyTypeLength, count: 4))
        blob.append(keyTypeData)

        // Raw public key length
        let rawKey = publicKey.rawRepresentation
        var rawKeyLength = UInt32(rawKey.count).bigEndian
        blob.append(Data(bytes: &rawKeyLength, count: 4))
        blob.append(rawKey)

        return "ssh-ed25519 \(blob.base64EncodedString())"
    }
}

// MARK: - Server Process Manager

class TestServerManager {
    static let shared = TestServerManager()

    private var serverProcess: Process?
    private var outputPipe: Pipe?

    private init() {}

    var isRunning: Bool {
        serverProcess?.isRunning ?? false
    }

    func startServer(port: Int = 9876, verbose: Bool = false) throws {
        guard !isRunning else { return }

        let shellydPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/shellyd")

        guard FileManager.default.fileExists(atPath: shellydPath.path) else {
            throw TestError.serverNotRunning
        }

        let process = Process()
        process.executableURL = shellydPath
        process.arguments = ["start", "--port", "\(port)"]
        if verbose {
            process.arguments?.append("--verbose")
        }

        outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        serverProcess = process

        // Wait for server to start
        Thread.sleep(forTimeInterval: 1.5)
    }

    func stopServer() {
        serverProcess?.terminate()
        serverProcess?.waitUntilExit()
        serverProcess = nil
    }

    func getServerOutput() -> String? {
        guard let pipe = outputPipe else { return nil }
        let data = pipe.fileHandleForReading.availableData
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Test Config Helper

struct TestConfig {
    static let testPort = 9876
    static let testTLSPort = 9877
    static let host = "127.0.0.1"

    static var testConfigDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("shellyd-test-\(UUID().uuidString)")
    }

    static func createTestConfigDirectory() throws -> URL {
        let dir = testConfigDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cleanup(directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}

// MARK: - Async Helpers

extension XCTestCase {
    func waitAsync(timeout: TimeInterval = 5, _ operation: @escaping () async throws -> Void) {
        let expectation = XCTestExpectation(description: "Async operation")
        Task {
            do {
                try await operation()
                expectation.fulfill()
            } catch {
                XCTFail("Async operation failed: \(error)")
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: timeout)
    }
}

import XCTest
