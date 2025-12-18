//
//  WebSocketClient.swift
//  Shelly
//
//  WebSocket client for communicating with Mac daemon
//

import Foundation
import CommonCrypto

@Observable
final class WebSocketClient: NSObject {
    // Connection state
    var isConnected = false
    var isConnecting = false

    // Callbacks
    var onMessage: ((ShellyMessage) -> Void)?
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onError: ((Error) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var pingTimer: Timer?

    private let host: String
    private let port: Int

    // TLS configuration
    private var useTLS: Bool = false
    private var pinnedCertificateFingerprint: String?
    private var allowSelfSignedCertificates: Bool = true  // For development

    init(host: String, port: Int) {
        self.host = host
        self.port = port
        super.init()
    }

    /// Configure TLS settings before connecting
    func configureTLS(enabled: Bool, pinnedFingerprint: String? = nil) {
        self.useTLS = enabled
        self.pinnedCertificateFingerprint = pinnedFingerprint
    }

    // MARK: - Connection

    func connect() {
        guard !isConnected, !isConnecting else { return }

        isConnecting = true

        let scheme = useTLS ? "wss" : "ws"
        let urlString = "\(scheme)://\(host):\(port)/ws"
        guard let url = URL(string: urlString) else {
            isConnecting = false
            onError?(WebSocketError.invalidURL)
            return
        }

        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true

        // Use delegate for TLS certificate handling
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: url)

        webSocketTask?.resume()

        // Start receiving messages
        receiveMessage()

        // Consider connected after starting receive
        DispatchQueue.main.async {
            self.isConnecting = false
            self.isConnected = true
            self.onConnect?()
            self.startPingTimer()
        }
    }

    func disconnect() {
        stopPingTimer()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil

        DispatchQueue.main.async {
            self.isConnected = false
            self.isConnecting = false
            self.onDisconnect?(nil)
        }
    }

    // MARK: - Send

    func send(_ message: ShellyMessage) {
        guard isConnected else { return }

        do {
            let data = try JSONEncoder().encode(message)
            guard let text = String(data: data, encoding: .utf8) else {
                throw WebSocketError.encodingFailed
            }

            let wsMessage = URLSessionWebSocketTask.Message.string(text)
            webSocketTask?.send(wsMessage) { [weak self] error in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.onError?(error)
                    }
                }
            }
        } catch {
            onError?(error)
        }
    }

    func sendInput(_ data: Data) {
        do {
            let message = try ShellyMessage.terminalInput(data)
            send(message)
        } catch {
            onError?(error)
        }
    }

    func sendInput(_ text: String) {
        do {
            let message = try ShellyMessage.terminalInput(text)
            send(message)
        } catch {
            onError?(error)
        }
    }

    func sendResize(rows: Int, cols: Int) {
        do {
            let message = try ShellyMessage.terminalResize(rows: rows, cols: cols)
            send(message)
        } catch {
            onError?(error)
        }
    }

    // MARK: - Receive

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleReceivedMessage(message)
                // Continue receiving
                self?.receiveMessage()

            case .failure(let error):
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.onDisconnect?(error)
                }
            }
        }
    }

    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8) else { return }
            parseMessage(data)

        case .data(let data):
            parseMessage(data)

        @unknown default:
            break
        }
    }

    private func parseMessage(_ data: Data) {
        do {
            let message = try JSONDecoder().decode(ShellyMessage.self, from: data)
            DispatchQueue.main.async {
                self.onMessage?(message)
            }
        } catch {
            DispatchQueue.main.async {
                self.onError?(error)
            }
        }
    }

    // MARK: - Ping/Pong

    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: Constants.pingInterval, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func sendPing() {
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.onError?(error)
                }
            }
        }
    }
}

// MARK: - Errors

enum WebSocketError: LocalizedError {
    case invalidURL
    case encodingFailed
    case notConnected
    case certificateMismatch
    case certificateValidationFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid WebSocket URL"
        case .encodingFailed:
            return "Failed to encode message"
        case .notConnected:
            return "Not connected to server"
        case .certificateMismatch:
            return "Server certificate does not match pinned certificate"
        case .certificateValidationFailed:
            return "Failed to validate server certificate"
        }
    }
}

// MARK: - URLSessionDelegate for TLS

extension WebSocketClient: URLSessionDelegate {
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

        // If we have a pinned fingerprint, validate it
        if let pinnedFingerprint = pinnedCertificateFingerprint {
            // Get the server certificate
            if let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
               let serverCertificate = certificateChain.first {
                let serverFingerprint = computeFingerprint(for: serverCertificate)

                if serverFingerprint == pinnedFingerprint {
                    // Certificate matches - trust it
                    let credential = URLCredential(trust: serverTrust)
                    completionHandler(.useCredential, credential)
                    return
                } else {
                    // Certificate doesn't match - reject
                    print("⚠️ Certificate fingerprint mismatch!")
                    print("   Expected: \(pinnedFingerprint)")
                    print("   Got: \(serverFingerprint)")
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    DispatchQueue.main.async {
                        self.onError?(WebSocketError.certificateMismatch)
                    }
                    return
                }
            }
        }

        // If no pinned fingerprint but TLS is enabled, accept self-signed certs (for now)
        if useTLS && allowSelfSignedCertificates {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
            return
        }

        // Default handling
        completionHandler(.performDefaultHandling, nil)
    }

    /// Compute SHA-256 fingerprint of a certificate
    private func computeFingerprint(for certificate: SecCertificate) -> String {
        let data = SecCertificateCopyData(certificate) as Data
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }

        // Format as colon-separated hex string
        return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
