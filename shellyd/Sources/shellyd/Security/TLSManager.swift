//
//  TLSManager.swift
//  shellyd
//
//  TLS certificate management and SSL context creation
//

import Foundation
import NIOSSL
import NIO

final class TLSManager {
    static let shared = TLSManager()

    private var sslContext: NIOSSLContext?
    private var certificateFingerprint: String?

    private var certificatePath: URL {
        ConfigManager.shared.tlsCertificatePath
    }

    private var privateKeyPath: URL {
        ConfigManager.shared.tlsPrivateKeyPath
    }

    private init() {}

    // MARK: - Certificate Management

    /// Generate a self-signed certificate if one doesn't exist
    func ensureCertificateExists() throws {
        let fm = FileManager.default

        if fm.fileExists(atPath: certificatePath.path) && fm.fileExists(atPath: privateKeyPath.path) {
            // Certificates already exist
            return
        }

        print("🔐 Generating TLS certificate...")

        // Use openssl to generate a self-signed certificate
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = [
            "req", "-x509",
            "-newkey", "ec",
            "-pkeyopt", "ec_paramgen_curve:P-256",
            "-keyout", privateKeyPath.path,
            "-out", certificatePath.path,
            "-days", "365",
            "-nodes",
            "-subj", "/CN=Shelly Daemon"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TLSError.certificateGenerationFailed(output)
        }

        // Set secure permissions on private key
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateKeyPath.path)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: certificatePath.path)

        print("✅ TLS certificate generated successfully")
    }

    /// Load the SSL context for the server
    func loadSSLContext() throws -> NIOSSLContext {
        if let context = sslContext {
            return context
        }

        // Ensure certificate exists
        try ensureCertificateExists()

        print("🔐 Loading TLS certificate from: \(certificatePath.path)")
        fflush(stdout)
        print("🔐 Loading TLS private key from: \(privateKeyPath.path)")
        fflush(stdout)

        // Load certificate chain
        let certificates: [NIOSSLCertificate]
        do {
            certificates = try NIOSSLCertificate.fromPEMFile(certificatePath.path)
            print("🔐 Loaded \(certificates.count) certificate(s)")
        } catch {
            print("❌ Failed to load certificate: \(error)")
            throw error
        }

        let privateKey: NIOSSLPrivateKey
        do {
            privateKey = try NIOSSLPrivateKey(file: privateKeyPath.path, format: .pem)
            print("🔐 Loaded private key")
        } catch {
            print("❌ Failed to load private key: \(error)")
            throw error
        }

        // Create SSL configuration
        var configuration = TLSConfiguration.makeServerConfiguration(
            certificateChain: certificates.map { .certificate($0) },
            privateKey: .privateKey(privateKey)
        )

        // Allow TLS 1.2 and 1.3
        configuration.minimumTLSVersion = .tlsv12

        // Create context
        let context: NIOSSLContext
        do {
            context = try NIOSSLContext(configuration: configuration)
            print("🔐 SSL context created successfully")
        } catch {
            print("❌ Failed to create SSL context: \(error)")
            throw error
        }
        sslContext = context

        // Compute certificate fingerprint
        certificateFingerprint = try computeFingerprint()

        return context
    }

    /// Get the certificate fingerprint (SHA-256)
    func getFingerprint() throws -> String {
        if let fingerprint = certificateFingerprint {
            return fingerprint
        }

        return try computeFingerprint()
    }

    /// Check if TLS is properly configured
    func isTLSConfigured() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: certificatePath.path) && fm.fileExists(atPath: privateKeyPath.path)
    }

    // MARK: - Private

    private func computeFingerprint() throws -> String {
        // Use openssl to get the certificate fingerprint
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = [
            "x509",
            "-in", certificatePath.path,
            "-noout",
            "-fingerprint",
            "-sha256"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw TLSError.fingerprintComputationFailed
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        // Parse output: "SHA256 Fingerprint=AB:CD:EF:..."
        if let range = output.range(of: "=") {
            let fingerprint = String(output[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            certificateFingerprint = fingerprint
            return fingerprint
        }

        throw TLSError.fingerprintComputationFailed
    }

    /// Reset the SSL context (e.g., after regenerating certificates)
    func resetContext() {
        sslContext = nil
        certificateFingerprint = nil
    }
}

// MARK: - Errors

enum TLSError: LocalizedError {
    case certificateGenerationFailed(String)
    case certificateNotFound
    case fingerprintComputationFailed
    case contextCreationFailed

    var errorDescription: String? {
        switch self {
        case .certificateGenerationFailed(let output):
            return "Failed to generate TLS certificate: \(output)"
        case .certificateNotFound:
            return "TLS certificate not found"
        case .fingerprintComputationFailed:
            return "Failed to compute certificate fingerprint"
        case .contextCreationFailed:
            return "Failed to create SSL context"
        }
    }
}
