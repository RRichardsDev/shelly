//
//  CertificatePinningDelegate.swift
//  Shelly
//
//  URLSession delegate for certificate pinning validation
//

import Foundation
import CryptoKit

final class CertificatePinningDelegate: NSObject, URLSessionDelegate {
    private let expectedFingerprint: String

    init(expectedFingerprint: String) {
        self.expectedFingerprint = expectedFingerprint
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Get the server certificate
        guard let certificate = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let serverCert = certificate.first else {
            print("⚠️ Certificate pinning: No server certificate found")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Get certificate data and compute SHA-256 fingerprint
        let certData = SecCertificateCopyData(serverCert) as Data
        let fingerprint = computeFingerprint(certData)

        // Compare fingerprints (case-insensitive)
        if fingerprint.lowercased() == expectedFingerprint.lowercased() {
            print("✅ Certificate pinning: Fingerprint matched")
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            print("❌ Certificate pinning: Fingerprint mismatch")
            print("   Expected: \(expectedFingerprint)")
            print("   Got: \(fingerprint)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func computeFingerprint(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
