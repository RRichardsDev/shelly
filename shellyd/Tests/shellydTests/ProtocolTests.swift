//
//  ProtocolTests.swift
//  shellydTests
//
//  Unit tests for message encoding/decoding
//  Includes both positive (should work) and negative (should fail) tests
//

import XCTest
import Foundation

final class ProtocolTests: XCTestCase {

    // MARK: - Message Type Tests (Positive)

    func testAllMessageTypesRoundTrip() throws {
        let types: [ShellyMessageType] = [
            .hello, .authChallenge, .authResponse, .authResult,
            .disconnect, .pairRequest, .pairChallenge, .pairVerify,
            .pairResponse, .terminalOutput, .terminalInput, .terminalResize,
            .ping, .pong, .error
        ]

        for type in types {
            let message = ShellyMessage(type: type, payload: Data())
            let encoded = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(ShellyMessage.self, from: encoded)
            XCTAssertEqual(decoded.type, type, "Failed roundtrip for \(type)")
        }
    }

    // MARK: - Hello Payload Tests

    func testHelloPayloadEncoding() throws {
        let payload = HelloPayload(
            clientVersion: "1.0.0",
            publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...",
            deviceName: "Test iPhone"
        )

        let message = try ShellyMessage(type: .hello, payload: payload)
        let encoded = try JSONEncoder().encode(message)

        XCTAssertNotNil(encoded)
        XCTAssertGreaterThan(encoded.count, 0)

        // Decode and verify
        let decoded = try JSONDecoder().decode(ShellyMessage.self, from: encoded)
        XCTAssertEqual(decoded.type, .hello)

        let decodedPayload = try decoded.decodePayload(HelloPayload.self)
        XCTAssertEqual(decodedPayload.clientVersion, "1.0.0")
        XCTAssertEqual(decodedPayload.deviceName, "Test iPhone")
    }

    // MARK: - Auth Payload Tests

    func testAuthChallengePayloadEncoding() throws {
        let challenge = Data([0x01, 0x02, 0x03, 0x04])
        let payload = AuthChallengePayload(
            challenge: challenge,
            serverVersion: "1.0.0",
            serverPublicKey: "ssh-ed25519 AAAAC3..."
        )

        let message = try ShellyMessage(type: .authChallenge, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(AuthChallengePayload.self)
        XCTAssertEqual(decodedPayload.challenge, challenge)
        XCTAssertEqual(decodedPayload.serverVersion, "1.0.0")
    }

    func testAuthResponsePayloadEncoding() throws {
        let signature = Data(repeating: 0xAB, count: 64)
        let payload = AuthResponsePayload(signature: signature)

        let message = try ShellyMessage(type: .authResponse, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(AuthResponsePayload.self)
        XCTAssertEqual(decodedPayload.signature, signature)
    }

    func testAuthResultPayloadSuccess() throws {
        let payload = AuthResultPayload(
            success: true,
            message: "Authenticated",
            sessionToken: "token123"
        )

        let message = try ShellyMessage(type: .authResult, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(AuthResultPayload.self)
        XCTAssertTrue(decodedPayload.success)
        XCTAssertEqual(decodedPayload.sessionToken, "token123")
    }

    func testAuthResultPayloadFailure() throws {
        let payload = AuthResultPayload(
            success: false,
            message: "Invalid signature",
            sessionToken: nil
        )

        let message = try ShellyMessage(type: .authResult, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(AuthResultPayload.self)
        XCTAssertFalse(decodedPayload.success)
        XCTAssertNil(decodedPayload.sessionToken)
    }

    // MARK: - Pairing Payload Tests

    func testPairRequestPayloadEncoding() throws {
        let payload = PairRequestPayload(
            publicKey: "ssh-ed25519 AAAAC3...",
            deviceName: "New iPhone"
        )

        let message = try ShellyMessage(type: .pairRequest, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(PairRequestPayload.self)
        XCTAssertEqual(decodedPayload.deviceName, "New iPhone")
    }

    func testPairVerifyPayloadEncoding() throws {
        let payload = PairVerifyPayload(code: "123456")

        let message = try ShellyMessage(type: .pairVerify, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(PairVerifyPayload.self)
        XCTAssertEqual(decodedPayload.code, "123456")
    }

    func testPairResponsePayloadSuccess() throws {
        let payload = PairResponsePayload(
            success: true,
            message: "Paired successfully",
            certificateFingerprint: "SHA256:abc123"
        )

        let message = try ShellyMessage(type: .pairResponse, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(PairResponsePayload.self)
        XCTAssertTrue(decodedPayload.success)
        XCTAssertEqual(decodedPayload.certificateFingerprint, "SHA256:abc123")
    }

    // MARK: - Terminal Payload Tests

    func testTerminalOutputPayloadEncoding() throws {
        let data = "Hello, World!\n".data(using: .utf8)!
        let payload = TerminalOutputPayload(data: data)

        let message = try ShellyMessage(type: .terminalOutput, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(TerminalOutputPayload.self)
        XCTAssertEqual(decodedPayload.data, data)
    }

    func testTerminalInputPayloadEncoding() throws {
        let payload = TerminalInputPayload(string: "ls -la\n")

        let message = try ShellyMessage(type: .terminalInput, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(TerminalInputPayload.self)
        XCTAssertEqual(String(data: decodedPayload.data, encoding: .utf8), "ls -la\n")
    }

    func testTerminalResizePayloadEncoding() throws {
        let payload = TerminalResizePayload(rows: 24, cols: 80)

        let message = try ShellyMessage(type: .terminalResize, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(TerminalResizePayload.self)
        XCTAssertEqual(decodedPayload.rows, 24)
        XCTAssertEqual(decodedPayload.cols, 80)
    }

    // MARK: - Error Payload Tests

    func testErrorPayloadEncoding() throws {
        let payload = ErrorPayload(
            code: "AUTH_FAILED",
            message: "Invalid credentials",
            recoverable: false
        )

        let message = try ShellyMessage(type: .error, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(ErrorPayload.self)
        XCTAssertEqual(decodedPayload.code, "AUTH_FAILED")
        XCTAssertFalse(decodedPayload.recoverable)
    }

    // MARK: - Message ID Tests

    func testMessageIdUniqueness() throws {
        let message1 = ShellyMessage(type: .ping, payload: Data())
        let message2 = ShellyMessage(type: .ping, payload: Data())

        XCTAssertNotEqual(message1.messageId, message2.messageId)
    }

    func testCustomMessageId() throws {
        let customId = UUID()
        let message = ShellyMessage(type: .ping, payload: Data(), messageId: customId)

        XCTAssertEqual(message.messageId, customId)
    }

    // MARK: - Timestamp Tests

    func testTimestampIsRecent() throws {
        let before = Date()
        let message = ShellyMessage(type: .ping, payload: Data())
        let after = Date()

        XCTAssertGreaterThanOrEqual(message.timestamp, before)
        XCTAssertLessThanOrEqual(message.timestamp, after)
    }

    // MARK: - Negative Tests (Should Fail)

    func testInvalidMessageTypeDecoding() {
        // Invalid message type should fail to decode
        let invalidJSON = """
        {"type":"invalid_type","payload":"","timestamp":0,"messageId":"00000000-0000-0000-0000-000000000000"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(ShellyMessage.self, from: invalidJSON)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testMalformedJSONDecoding() {
        // Malformed JSON should fail
        let malformedJSON = "{ not valid json }".data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(ShellyMessage.self, from: malformedJSON))
    }

    func testEmptyJSONDecoding() {
        // Empty JSON should fail
        let emptyJSON = "{}".data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(ShellyMessage.self, from: emptyJSON))
    }

    func testMissingRequiredFieldsDecoding() {
        // Missing required fields should fail
        let missingType = """
        {"payload":"","timestamp":0,"messageId":"00000000-0000-0000-0000-000000000000"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(ShellyMessage.self, from: missingType))

        let missingPayload = """
        {"type":"hello","timestamp":0,"messageId":"00000000-0000-0000-0000-000000000000"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(ShellyMessage.self, from: missingPayload))
    }

    func testWrongPayloadTypeDecoding() throws {
        // Create message with hello payload, try to decode as auth
        let helloPayload = HelloPayload(
            clientVersion: "1.0.0",
            publicKey: "ssh-ed25519 AAAA...",
            deviceName: "Test"
        )
        let message = try ShellyMessage(type: .hello, payload: helloPayload)

        // Trying to decode as wrong payload type should fail
        XCTAssertThrowsError(try message.decodePayload(AuthChallengePayload.self))
    }

    func testInvalidBase64InPayload() {
        // Invalid base64 in payload field should fail
        let invalidBase64 = """
        {"type":"hello","payload":"!!!not-base64!!!","timestamp":0,"messageId":"00000000-0000-0000-0000-000000000000"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(ShellyMessage.self, from: invalidBase64))
    }

    func testInvalidUUIDInMessageId() {
        // Invalid UUID should fail
        let invalidUUID = """
        {"type":"hello","payload":"e30=","timestamp":0,"messageId":"not-a-uuid"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(ShellyMessage.self, from: invalidUUID))
    }

    func testNullPayloadDecoding() {
        // Null payload should fail
        let nullPayload = """
        {"type":"hello","payload":null,"timestamp":0,"messageId":"00000000-0000-0000-0000-000000000000"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(ShellyMessage.self, from: nullPayload))
    }

    // MARK: - Edge Case Tests

    func testEmptyPayload() throws {
        // Empty payload should work for some message types
        let message = ShellyMessage(type: .ping, payload: Data())
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ShellyMessage.self, from: encoded)

        XCTAssertEqual(decoded.type, .ping)
        XCTAssertTrue(decoded.payload.isEmpty)
    }

    func testLargePayload() throws {
        // Large payload should work
        let largeData = Data(repeating: 0x41, count: 100_000) // 100KB
        let message = ShellyMessage(type: .terminalOutput, payload: largeData)
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ShellyMessage.self, from: encoded)

        XCTAssertEqual(decoded.payload.count, 100_000)
    }

    func testUnicodeInPayload() throws {
        // Unicode characters should work
        let payload = HelloPayload(
            clientVersion: "1.0.0",
            publicKey: "ssh-ed25519 AAAA...",
            deviceName: "Test 📱 Device 中文 العربية"
        )
        let message = try ShellyMessage(type: .hello, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(HelloPayload.self)
        XCTAssertEqual(decodedPayload.deviceName, "Test 📱 Device 中文 العربية")
    }

    func testSpecialCharactersInPayload() throws {
        // Special characters that need escaping
        let payload = HelloPayload(
            clientVersion: "1.0.0",
            publicKey: "ssh-ed25519 AAAA...",
            deviceName: "Test \"Device\" with \\ and\nnewline"
        )
        let message = try ShellyMessage(type: .hello, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(HelloPayload.self)
        XCTAssertTrue(decodedPayload.deviceName.contains("\""))
        XCTAssertTrue(decodedPayload.deviceName.contains("\\"))
        XCTAssertTrue(decodedPayload.deviceName.contains("\n"))
    }

    func testZeroTerminalSize() throws {
        // Zero dimensions should encode/decode (server should validate)
        let payload = TerminalResizePayload(rows: 0, cols: 0)
        let message = try ShellyMessage(type: .terminalResize, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(TerminalResizePayload.self)
        XCTAssertEqual(decodedPayload.rows, 0)
        XCTAssertEqual(decodedPayload.cols, 0)
    }

    func testNegativeTerminalSize() throws {
        // Negative dimensions should encode/decode (server should validate)
        let payload = TerminalResizePayload(rows: -1, cols: -1)
        let message = try ShellyMessage(type: .terminalResize, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(TerminalResizePayload.self)
        XCTAssertEqual(decodedPayload.rows, -1)
        XCTAssertEqual(decodedPayload.cols, -1)
    }

    func testVeryLongDeviceName() throws {
        // Very long device name should work
        let longName = String(repeating: "A", count: 10_000)
        let payload = HelloPayload(
            clientVersion: "1.0.0",
            publicKey: "ssh-ed25519 AAAA...",
            deviceName: longName
        )
        let message = try ShellyMessage(type: .hello, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(HelloPayload.self)
        XCTAssertEqual(decodedPayload.deviceName.count, 10_000)
    }

    func testEmptyDeviceName() throws {
        // Empty device name should encode/decode
        let payload = HelloPayload(
            clientVersion: "1.0.0",
            publicKey: "ssh-ed25519 AAAA...",
            deviceName: ""
        )
        let message = try ShellyMessage(type: .hello, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(HelloPayload.self)
        XCTAssertTrue(decodedPayload.deviceName.isEmpty)
    }

    func testEmptyPublicKey() throws {
        // Empty public key should encode/decode (server should validate)
        let payload = HelloPayload(
            clientVersion: "1.0.0",
            publicKey: "",
            deviceName: "Test"
        )
        let message = try ShellyMessage(type: .hello, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(HelloPayload.self)
        XCTAssertTrue(decodedPayload.publicKey.isEmpty)
    }

    func testPairCodeFormats() throws {
        // Various code formats should encode/decode
        let codes = ["123456", "000000", "999999", "12345", "1234567", "", "abc123"]

        for code in codes {
            let payload = PairVerifyPayload(code: code)
            let message = try ShellyMessage(type: .pairVerify, payload: payload)
            let decoded = try JSONDecoder().decode(
                ShellyMessage.self,
                from: JSONEncoder().encode(message)
            )

            let decodedPayload = try decoded.decodePayload(PairVerifyPayload.self)
            XCTAssertEqual(decodedPayload.code, code)
        }
    }

    func testBinaryDataInTerminalOutput() throws {
        // Binary data (non-UTF8) should work
        let binaryData = Data([0x00, 0x01, 0xFF, 0xFE, 0x80, 0x90])
        let payload = TerminalOutputPayload(data: binaryData)
        let message = try ShellyMessage(type: .terminalOutput, payload: payload)
        let decoded = try JSONDecoder().decode(
            ShellyMessage.self,
            from: JSONEncoder().encode(message)
        )

        let decodedPayload = try decoded.decodePayload(TerminalOutputPayload.self)
        XCTAssertEqual(decodedPayload.data, binaryData)
    }
}
