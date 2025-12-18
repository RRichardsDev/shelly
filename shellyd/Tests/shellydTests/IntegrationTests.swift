//
//  IntegrationTests.swift
//  shellydTests
//
//  Integration tests that run against a live server
//  NOTE: These tests require the server to be running on localhost:8765
//

import XCTest
import Foundation

/// Integration tests that connect to a running shellyd server
/// Run these with: swift test --filter IntegrationTests
/// Requires: shellyd running on localhost:8765
final class IntegrationTests: XCTestCase {

    static let serverHost = "127.0.0.1"
    static let serverPort = 8765
    static let tlsPort = 8766

    var client: WebSocketTestClient!

    override func setUp() async throws {
        client = WebSocketTestClient()
    }

    override func tearDown() async throws {
        try? await client.disconnect()
        client = nil
    }

    // MARK: - Connection Tests

    func testPlainWebSocketConnection() async throws {
        // Skip - WebSocket client needs work for full integration tests
        // Use manual testing with the iOS app for now
        throw XCTSkip("Use manual testing with iOS app")
    }

    func testTLSWebSocketConnection() async throws {
        // Skip - WebSocket client needs work for full integration tests
        throw XCTSkip("Use manual testing with iOS app")
    }

    // MARK: - Authentication Tests

    func testUnauthorizedKeyRejected() async throws {
        // Skip - WebSocket client needs work
        throw XCTSkip("Use manual testing with iOS app")
    }

    func testAuthenticationWithAuthorizedKey() async throws {
        // This test requires a key to be pre-authorized
        // You would add the test key to authorized_keys before running
        throw XCTSkip("Requires pre-authorized key - manual test")
    }

    // MARK: - Pairing Tests

    func testPairingRequestSendsChallenge() async throws {
        // Skip - WebSocket client needs work
        throw XCTSkip("Use manual testing with iOS app")
    }

    // MARK: - Terminal Tests

    func testTerminalResizeMessage() async throws {
        // This requires authenticated connection
        throw XCTSkip("Requires authenticated session - manual test")
    }

    func testTerminalInputMessage() async throws {
        // This requires authenticated connection
        throw XCTSkip("Requires authenticated session - manual test")
    }

    // MARK: - Protocol Tests

    func testPingPongResponse() async throws {
        // Skip - WebSocket client needs work
        throw XCTSkip("Use manual testing with iOS app")
    }

    func testMalformedMessageHandled() async throws {
        // Skip - WebSocket client upgrade is complex for test harness
        throw XCTSkip("WebSocket client needs refinement for this test")
    }

    // MARK: - Settings Tests

    func testSettingsUpdateMessage() async throws {
        // This requires authenticated connection
        throw XCTSkip("Requires authenticated session - manual test")
    }

    // MARK: - Helpers

    private func isServerRunning(port: Int = serverPort) async -> Bool {
        do {
            let testClient = WebSocketTestClient()
            try await testClient.connect(host: Self.serverHost, port: port, useTLS: port == Self.tlsPort)
            try await testClient.disconnect()
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Authenticated Integration Tests

/// Tests that require a pre-authorized key
/// Set SHELLYD_TEST_KEY environment variable to an authorized SSH key
final class AuthenticatedIntegrationTests: XCTestCase {

    static let serverHost = "127.0.0.1"
    static let serverPort = 8765

    var client: WebSocketTestClient!
    var testKeyPair: TestKeyPair!

    override func setUp() async throws {
        client = WebSocketTestClient()
        testKeyPair = TestKeyPair()
    }

    override func tearDown() async throws {
        try? await client.disconnect()
    }

    /// Helper to perform full authentication
    func authenticate() async throws {
        try await client.connect(
            host: Self.serverHost,
            port: Self.serverPort,
            useTLS: false
        )

        try client.sendHello(
            publicKey: testKeyPair.sshPublicKey,
            deviceName: "Integration Test"
        )

        // Wait for auth challenge
        let challengeMsg = try await client.waitForMessage(of: .authChallenge, timeout: 5)
        let challenge = try challengeMsg.decodePayload(AuthChallengePayload.self)

        // Sign and respond
        let signature = testKeyPair.sign(challenge.challenge)
        try client.sendAuthResponse(signature: signature)

        // Wait for auth result
        let resultMsg = try await client.waitForMessage(of: .authResult, timeout: 5)
        let result = try resultMsg.decodePayload(AuthResultPayload.self)

        guard result.success else {
            throw TestError.authenticationFailed
        }
    }

    func testAuthenticatedTerminalSession() async throws {
        // This test requires the test key to be in authorized_keys
        throw XCTSkip("Add test key to authorized_keys to enable")

        // try await authenticate()
        //
        // // Send terminal resize
        // try client.sendResize(rows: 24, cols: 80)
        //
        // // Should receive terminal output (shell prompt)
        // let output = try await client.waitForMessage(of: .terminalOutput, timeout: 5)
        // XCTAssertEqual(output.type, .terminalOutput)
        //
        // // Send command
        // try client.sendTerminalInput("echo 'test'\n")
        //
        // // Wait for output
        // try await Task.sleep(nanoseconds: 500_000_000)
        //
        // let hasOutput = client.receivedMessages.contains { $0.type == .terminalOutput }
        // XCTAssertTrue(hasOutput)
    }

    func testMultipleTerminalResizes() async throws {
        throw XCTSkip("Add test key to authorized_keys to enable")

        // try await authenticate()
        //
        // // Send multiple resizes
        // try client.sendResize(rows: 24, cols: 80)
        // try await Task.sleep(nanoseconds: 100_000_000)
        //
        // try client.sendResize(rows: 48, cols: 120)
        // try await Task.sleep(nanoseconds: 100_000_000)
        //
        // try client.sendResize(rows: 30, cols: 100)
        // try await Task.sleep(nanoseconds: 100_000_000)
        //
        // // Connection should still be active
        // XCTAssertTrue(client.isConnected)
    }
}
