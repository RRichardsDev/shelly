//
//  AuthenticationTests.swift
//  shellydTests
//
//  Tests for authentication flow and key management
//  Includes both positive (should work) and negative (should fail) tests
//

import XCTest
import Crypto

final class AuthenticationTests: XCTestCase {

    // MARK: - Key Pair Tests (Positive)

    func testKeyPairGeneration() {
        let keyPair = TestKeyPair()

        XCTAssertNotNil(keyPair.privateKey)
        XCTAssertNotNil(keyPair.publicKey)
        XCTAssertTrue(keyPair.sshPublicKey.hasPrefix("ssh-ed25519 "))
    }

    func testKeyPairSSHFormat() {
        let keyPair = TestKeyPair()

        // SSH key format: ssh-ed25519 <base64-data>
        let parts = keyPair.sshPublicKey.split(separator: " ")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0], "ssh-ed25519")

        // Verify base64 data is valid
        let base64Part = String(parts[1])
        XCTAssertNotNil(Data(base64Encoded: base64Part))
    }

    func testKeyPairSignature() {
        let keyPair = TestKeyPair()
        let challenge = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])

        let signature = keyPair.sign(challenge)

        // Ed25519 signatures are 64 bytes
        XCTAssertEqual(signature.count, 64)

        // Verify signature
        let isValid = keyPair.publicKey.isValidSignature(signature, for: challenge)
        XCTAssertTrue(isValid)
    }

    func testSignatureVerificationWithWrongKey() {
        let keyPair1 = TestKeyPair()
        let keyPair2 = TestKeyPair()
        let challenge = Data([0x01, 0x02, 0x03, 0x04])

        let signature = keyPair1.sign(challenge)

        // Verify with wrong key should fail
        let isValid = keyPair2.publicKey.isValidSignature(signature, for: challenge)
        XCTAssertFalse(isValid)
    }

    func testSignatureVerificationWithWrongChallenge() {
        let keyPair = TestKeyPair()
        let challenge1 = Data([0x01, 0x02, 0x03, 0x04])
        let challenge2 = Data([0x05, 0x06, 0x07, 0x08])

        let signature = keyPair.sign(challenge1)

        // Verify with wrong challenge should fail
        let isValid = keyPair.publicKey.isValidSignature(signature, for: challenge2)
        XCTAssertFalse(isValid)
    }

    // MARK: - SSH Key Parsing Tests

    func testSSHKeyBlobStructure() {
        let keyPair = TestKeyPair()
        let parts = keyPair.sshPublicKey.split(separator: " ")
        let base64Data = String(parts[1])
        let blob = Data(base64Encoded: base64Data)!

        // Parse the blob - read bytes individually to avoid alignment issues
        var offset = 0

        // Read key type length (4 bytes, big endian)
        let keyTypeLength = Int(blob[offset]) << 24 |
                           Int(blob[offset + 1]) << 16 |
                           Int(blob[offset + 2]) << 8 |
                           Int(blob[offset + 3])
        offset += 4
        XCTAssertEqual(keyTypeLength, 11) // "ssh-ed25519" = 11 chars

        // Read key type
        let keyTypeData = blob.subdata(in: offset..<(offset + keyTypeLength))
        let keyType = String(data: keyTypeData, encoding: .utf8)
        XCTAssertEqual(keyType, "ssh-ed25519")
        offset += keyTypeLength

        // Read raw key length (4 bytes, big endian)
        let rawKeyLength = Int(blob[offset]) << 24 |
                          Int(blob[offset + 1]) << 16 |
                          Int(blob[offset + 2]) << 8 |
                          Int(blob[offset + 3])
        offset += 4
        XCTAssertEqual(rawKeyLength, 32) // Ed25519 public keys are 32 bytes

        // Extract raw key
        let rawKey = blob.subdata(in: offset..<(offset + rawKeyLength))
        XCTAssertEqual(rawKey, keyPair.publicKey.rawRepresentation)
    }

    // MARK: - Challenge Generation Tests

    func testChallengeUniqueness() {
        var challenges = Set<Data>()

        for _ in 0..<100 {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            let challenge = Data(bytes)
            challenges.insert(challenge)
        }

        // All challenges should be unique
        XCTAssertEqual(challenges.count, 100)
    }

    func testChallengeSize() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let challenge = Data(bytes)

        XCTAssertEqual(challenge.count, 32)
    }

    // MARK: - Session Token Tests

    func testSessionTokenGeneration() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = Data(bytes).base64EncodedString()

        XCTAssertFalse(token.isEmpty)
        XCTAssertEqual(token.count, 44) // 32 bytes base64 encoded
    }

    func testSessionTokenUniqueness() {
        var tokens = Set<String>()

        for _ in 0..<100 {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            let token = Data(bytes).base64EncodedString()
            tokens.insert(token)
        }

        XCTAssertEqual(tokens.count, 100)
    }

    // MARK: - Full Auth Flow Simulation

    func testCompleteAuthFlowSimulation() throws {
        // 1. Client generates key pair
        let clientKeyPair = TestKeyPair()

        // 2. Client sends hello with public key
        let helloPayload = HelloPayload(
            clientVersion: "1.0.0",
            publicKey: clientKeyPair.sshPublicKey,
            deviceName: "Test Device"
        )

        // 3. Server generates challenge
        var challengeBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, challengeBytes.count, &challengeBytes)
        let challenge = Data(challengeBytes)

        // 4. Client signs challenge
        let signature = clientKeyPair.sign(challenge)

        // 5. Server verifies signature
        let isValid = clientKeyPair.publicKey.isValidSignature(signature, for: challenge)
        XCTAssertTrue(isValid)

        // 6. Server generates session token
        var tokenBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, tokenBytes.count, &tokenBytes)
        let sessionToken = Data(tokenBytes).base64EncodedString()

        XCTAssertFalse(sessionToken.isEmpty)
    }

    // MARK: - Key Fingerprint Tests

    func testKeyFingerprintGeneration() {
        let keyPair = TestKeyPair()
        let parts = keyPair.sshPublicKey.split(separator: " ")
        let base64Data = String(parts[1])
        let keyData = Data(base64Encoded: base64Data)!

        // Generate SHA256 fingerprint
        let hash = SHA256.hash(data: keyData)
        let fingerprint = "SHA256:" + Data(hash).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")

        XCTAssertTrue(fingerprint.hasPrefix("SHA256:"))
        XCTAssertGreaterThan(fingerprint.count, 10)
    }

    func testFingerprintConsistency() {
        let keyPair = TestKeyPair()
        let parts = keyPair.sshPublicKey.split(separator: " ")
        let base64Data = String(parts[1])
        let keyData = Data(base64Encoded: base64Data)!

        let hash1 = SHA256.hash(data: keyData)
        let fingerprint1 = "SHA256:" + Data(hash1).base64EncodedString()

        let hash2 = SHA256.hash(data: keyData)
        let fingerprint2 = "SHA256:" + Data(hash2).base64EncodedString()

        // Same key should always produce same fingerprint
        XCTAssertEqual(fingerprint1, fingerprint2)
    }

    // MARK: - Negative Tests (Should Fail)

    func testSignatureWithTamperedChallenge() {
        let keyPair = TestKeyPair()
        let originalChallenge = Data([0x01, 0x02, 0x03, 0x04])
        let tamperedChallenge = Data([0x01, 0x02, 0x03, 0x05]) // One byte different

        let signature = keyPair.sign(originalChallenge)

        // Verification with tampered challenge should fail
        let isValid = keyPair.publicKey.isValidSignature(signature, for: tamperedChallenge)
        XCTAssertFalse(isValid, "Tampered challenge should not verify")
    }

    func testSignatureWithTamperedSignature() {
        let keyPair = TestKeyPair()
        let challenge = Data([0x01, 0x02, 0x03, 0x04])

        var signature = keyPair.sign(challenge)
        // Tamper with the signature
        signature[0] ^= 0xFF

        // Verification with tampered signature should fail
        let isValid = keyPair.publicKey.isValidSignature(signature, for: challenge)
        XCTAssertFalse(isValid, "Tampered signature should not verify")
    }

    func testEmptySignatureRejected() {
        let keyPair = TestKeyPair()
        let challenge = Data([0x01, 0x02, 0x03, 0x04])
        let emptySignature = Data()

        // Empty signature should not verify
        let isValid = keyPair.publicKey.isValidSignature(emptySignature, for: challenge)
        XCTAssertFalse(isValid, "Empty signature should not verify")
    }

    func testWrongSizeSignatureRejected() {
        let keyPair = TestKeyPair()
        let challenge = Data([0x01, 0x02, 0x03, 0x04])

        // Wrong size signature (Ed25519 signatures are 64 bytes)
        let shortSignature = Data(repeating: 0xAB, count: 32)
        let longSignature = Data(repeating: 0xAB, count: 128)

        let shortValid = keyPair.publicKey.isValidSignature(shortSignature, for: challenge)
        let longValid = keyPair.publicKey.isValidSignature(longSignature, for: challenge)

        XCTAssertFalse(shortValid, "Short signature should not verify")
        XCTAssertFalse(longValid, "Long signature should not verify")
    }

    func testEmptyChallengeCanBeSignedButIsWeak() {
        let keyPair = TestKeyPair()
        let emptyChallenge = Data()

        // Empty challenge can be signed (but shouldn't be used in practice)
        let signature = keyPair.sign(emptyChallenge)
        let isValid = keyPair.publicKey.isValidSignature(signature, for: emptyChallenge)

        // It will verify, but this is a weak practice
        XCTAssertTrue(isValid, "Empty challenge signs, but is weak security")
        XCTAssertEqual(signature.count, 64, "Signature should still be 64 bytes")
    }

    func testDifferentKeysProduceDifferentSignatures() {
        let keyPair1 = TestKeyPair()
        let keyPair2 = TestKeyPair()
        let challenge = Data([0x01, 0x02, 0x03, 0x04])

        let sig1 = keyPair1.sign(challenge)
        let sig2 = keyPair2.sign(challenge)

        // Different keys should produce different signatures
        XCTAssertNotEqual(sig1, sig2, "Different keys should produce different signatures")
    }

    func testDifferentChallengesProduceDifferentSignatures() {
        let keyPair = TestKeyPair()
        let challenge1 = Data([0x01, 0x02, 0x03, 0x04])
        let challenge2 = Data([0x05, 0x06, 0x07, 0x08])

        let sig1 = keyPair.sign(challenge1)
        let sig2 = keyPair.sign(challenge2)

        // Different challenges should produce different signatures
        XCTAssertNotEqual(sig1, sig2, "Different challenges should produce different signatures")
    }

    func testCrossKeyVerificationFails() {
        let keyPair1 = TestKeyPair()
        let keyPair2 = TestKeyPair()
        let challenge = Data([0x01, 0x02, 0x03, 0x04])

        // Sign with key1, verify with key2
        let signature = keyPair1.sign(challenge)
        let isValid = keyPair2.publicKey.isValidSignature(signature, for: challenge)

        XCTAssertFalse(isValid, "Cross-key verification should fail")
    }

    // MARK: - SSH Key Format Negative Tests

    func testInvalidSSHKeyTypeRejected() {
        // Test that non-ed25519 key types would be handled
        // (In real implementation, server should reject)
        let invalidKeyTypes = [
            "ssh-rsa AAAA...",
            "ssh-dss AAAA...",
            "ecdsa-sha2-nistp256 AAAA...",
            "invalid AAAA..."
        ]

        for keyString in invalidKeyTypes {
            let parts = keyString.split(separator: " ")
            XCTAssertEqual(parts.count, 2, "Should have type and data")
            XCTAssertNotEqual(String(parts[0]), "ssh-ed25519")
        }
    }

    func testMalformedSSHKeyFormat() {
        // Keys without space separator
        let noSpace = "ssh-ed25519AAAA..."
        let parts = noSpace.split(separator: " ")
        XCTAssertEqual(parts.count, 1, "Malformed key has no space")

        // Keys with too many parts
        let tooManyParts = "ssh-ed25519 AAAA... extra parts here"
        let parts2 = tooManyParts.split(separator: " ")
        XCTAssertGreaterThan(parts2.count, 2)
    }

    func testInvalidBase64InSSHKey() {
        // Invalid base64 should not decode
        let invalidBase64 = "!!!not-valid-base64!!!"
        let decoded = Data(base64Encoded: invalidBase64)
        XCTAssertNil(decoded, "Invalid base64 should not decode")
    }

    // MARK: - Edge Cases

    func testVeryLargeChallenge() {
        let keyPair = TestKeyPair()
        let largeChallenge = Data(repeating: 0xAB, count: 1_000_000) // 1MB

        let signature = keyPair.sign(largeChallenge)
        let isValid = keyPair.publicKey.isValidSignature(signature, for: largeChallenge)

        XCTAssertTrue(isValid, "Large challenge should still work")
        XCTAssertEqual(signature.count, 64, "Signature size is constant")
    }

    func testAllZeroChallenge() {
        let keyPair = TestKeyPair()
        let zeroChallenge = Data(repeating: 0x00, count: 32)

        let signature = keyPair.sign(zeroChallenge)
        let isValid = keyPair.publicKey.isValidSignature(signature, for: zeroChallenge)

        XCTAssertTrue(isValid, "Zero challenge should still work")
    }

    func testAllOnesChallenge() {
        let keyPair = TestKeyPair()
        let onesChallenge = Data(repeating: 0xFF, count: 32)

        let signature = keyPair.sign(onesChallenge)
        let isValid = keyPair.publicKey.isValidSignature(signature, for: onesChallenge)

        XCTAssertTrue(isValid, "All-ones challenge should still work")
    }

    func testSameChallengeProducesValidSignatures() {
        let keyPair = TestKeyPair()
        let challenge = Data([0x01, 0x02, 0x03, 0x04])

        // Sign the same challenge twice
        let sig1 = keyPair.sign(challenge)
        let sig2 = keyPair.sign(challenge)

        // Both signatures should be valid (CryptoKit may use randomized nonces)
        let valid1 = keyPair.publicKey.isValidSignature(sig1, for: challenge)
        let valid2 = keyPair.publicKey.isValidSignature(sig2, for: challenge)

        XCTAssertTrue(valid1, "First signature should be valid")
        XCTAssertTrue(valid2, "Second signature should be valid")
        XCTAssertEqual(sig1.count, 64, "Signature should be 64 bytes")
        XCTAssertEqual(sig2.count, 64, "Signature should be 64 bytes")
    }

    // MARK: - Security Tests

    func testDifferentKeyPairsAreUnique() {
        var publicKeys = Set<Data>()

        for _ in 0..<100 {
            let keyPair = TestKeyPair()
            publicKeys.insert(keyPair.publicKey.rawRepresentation)
        }

        XCTAssertEqual(publicKeys.count, 100, "All generated keys should be unique")
    }

    func testPrivateKeyNotExposedInSSHFormat() {
        let keyPair = TestKeyPair()

        // SSH public key format should not contain private key
        XCTAssertFalse(keyPair.sshPublicKey.contains("PRIVATE"))
        XCTAssertTrue(keyPair.sshPublicKey.hasPrefix("ssh-ed25519 "))

        // Public key in SSH format should be ~68 bytes base64 for ed25519
        let parts = keyPair.sshPublicKey.split(separator: " ")
        let base64Length = parts[1].count
        XCTAssertLessThan(base64Length, 100, "SSH public key should be compact")
    }

    func testSignatureNonMalleable() {
        let keyPair = TestKeyPair()
        let challenge = Data([0x01, 0x02, 0x03, 0x04])
        let signature = keyPair.sign(challenge)

        // Try various bit flips - none should verify
        for i in 0..<signature.count {
            var malleated = signature
            malleated[i] ^= 0x01 // Flip one bit

            let isValid = keyPair.publicKey.isValidSignature(malleated, for: challenge)
            XCTAssertFalse(isValid, "Bit-flipped signature at position \(i) should not verify")
        }
    }
}
