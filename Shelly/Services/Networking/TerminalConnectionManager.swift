//
//  TerminalConnectionManager.swift
//  Shelly
//
//  Manages terminal connections with authentication
//

import Foundation
import SwiftData
import CryptoKit
import UIKit

@Observable
final class TerminalConnectionManager {
    // Connection state
    var isConnected = false
    var isConnecting = false
    var connectionError: String?

    // Sudo confirmation state
    var pendingSudoRequest: SudoConfirmRequestPayload?
    var showingSudoConfirmation = false

    // Terminal output callback
    var onTerminalOutput: ((Data) -> Void)?
    var onDisconnected: ((Error?) -> Void)?
    var onSudoRequest: ((SudoConfirmRequestPayload) -> Void)?
    var onSettingsSync: ((SecuritySettingsPayload) -> Void)?
    var onSettingsConfirm: ((SettingsConfirmPayload) -> Void)?

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var currentConnection: HostConnection?
    private var currentKeyPair: SSHKeyPair?
    private var sessionToken: String?

    // Reconnection
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var reconnectTask: Task<Void, Never>?

    // MARK: - Connect

    func connect(to connection: HostConnection, using keyPair: SSHKeyPair) async throws {
        guard !isConnecting else { return }

        isConnecting = true
        connectionError = nil
        currentConnection = connection
        currentKeyPair = keyPair

        defer {
            if !isConnected {
                isConnecting = false
            }
        }

        // Determine protocol and port based on TLS setting
        let useTLS = ConnectionManager.shared.useTLS
        let scheme = useTLS ? "wss" : "ws"
        let port = useTLS ? connection.port + 1 : connection.port

        // Create WebSocket connection
        let urlString = "\(scheme)://\(connection.hostname):\(port)/ws"
        guard let url = URL(string: urlString) else {
            throw TerminalConnectionError.invalidURL
        }

        // Create session with optional certificate pinning
        let sessionConfig = URLSessionConfiguration.default
        if useTLS, let pinnedFingerprint = ConnectionManager.shared.pinnedCertificateFingerprint {
            urlSession = URLSession(
                configuration: sessionConfig,
                delegate: CertificatePinningDelegate(expectedFingerprint: pinnedFingerprint),
                delegateQueue: nil
            )
        } else {
            urlSession = URLSession(configuration: sessionConfig)
        }

        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()

        // Start receiving messages
        startReceiving()

        // Send hello message
        try await sendHello(publicKey: keyPair.publicKey, deviceName: UIDevice.current.name)
    }

    // MARK: - Disconnect

    func disconnect() {
        cancelReconnection()

        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession = nil
        sessionToken = nil

        isConnected = false
        isConnecting = false
    }

    // MARK: - Send Input

    func sendInput(_ text: String) {
        guard isConnected else { return }

        Task {
            do {
                let message = try ShellyMessage.terminalInput(text)
                try await send(message)
            } catch {
                print("Failed to send input: \(error)")
            }
        }
    }

    func sendInput(_ data: Data) {
        guard isConnected else { return }

        Task {
            do {
                let message = try ShellyMessage.terminalInput(data)
                try await send(message)
            } catch {
                print("Failed to send input: \(error)")
            }
        }
    }

    func sendResize(rows: Int, cols: Int) {
        guard isConnected else { return }

        Task {
            do {
                let message = try ShellyMessage.terminalResize(rows: rows, cols: cols)
                try await send(message)
            } catch {
                print("Failed to send resize: \(error)")
            }
        }
    }

    // MARK: - Sudo Handling

    func approveSudo(password: String) {
        guard isConnected, let request = pendingSudoRequest else { return }

        Task {
            do {
                // Send confirmation
                let confirmMessage = try ShellyMessage.sudoConfirmResponse(requestId: request.requestId, approved: true)
                try await send(confirmMessage)

                // Send password
                let passwordMessage = try ShellyMessage.sudoPassword(password)
                try await send(passwordMessage)

                await MainActor.run {
                    pendingSudoRequest = nil
                    showingSudoConfirmation = false
                }
            } catch {
                print("Failed to send sudo approval: \(error)")
            }
        }
    }

    func denySudo() {
        guard isConnected, let request = pendingSudoRequest else { return }

        Task {
            do {
                let message = try ShellyMessage.sudoConfirmResponse(requestId: request.requestId, approved: false)
                try await send(message)

                await MainActor.run {
                    pendingSudoRequest = nil
                    showingSudoConfirmation = false
                }
            } catch {
                print("Failed to send sudo denial: \(error)")
            }
        }
    }

    // MARK: - Authentication Flow

    private func sendHello(publicKey: String, deviceName: String) async throws {
        let message = try ShellyMessage.hello(publicKey: publicKey, deviceName: deviceName)
        try await send(message)
    }

    private func handleAuthChallenge(_ challenge: AuthChallengePayload) async throws {
        guard let keyPair = currentKeyPair else {
            throw TerminalConnectionError.noKeyPair
        }

        // Load private key from keychain
        let privateKey = try SSHKeyGenerator.shared.loadPrivateKey(identifier: keyPair.keychainIdentifier)

        // Sign the challenge
        let signature = SSHKeyGenerator.shared.sign(challenge.challenge, with: privateKey)

        // Send auth response
        let message = try ShellyMessage.authResponse(signature: signature)
        try await send(message)
    }

    private func handleAuthResult(_ result: AuthResultPayload) {
        if result.success {
            sessionToken = result.sessionToken
            isConnected = true
            isConnecting = false
            print("Authentication successful!")
        } else {
            connectionError = result.message ?? "Authentication failed"
            isConnecting = false
            disconnect()
        }
    }

    // MARK: - Message Handling

    private func send(_ message: ShellyMessage) async throws {
        guard let webSocket = webSocket else {
            throw TerminalConnectionError.notConnected
        }

        let data = try JSONEncoder().encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TerminalConnectionError.encodingFailed
        }

        try await webSocket.send(.string(text))
    }

    private func startReceiving() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.reconnectAttempts = 0 // Reset on successful message
                self?.handleReceivedMessage(message)
                self?.startReceiving() // Continue receiving

            case .failure(let error):
                DispatchQueue.main.async {
                    self?.handleDisconnection(error: error)
                }
            }
        }
    }

    private func handleDisconnection(error: Error?) {
        let wasConnected = isConnected
        isConnected = false
        isConnecting = false

        // Clean up current connection
        webSocket?.cancel()
        webSocket = nil

        // Notify listener
        onDisconnected?(error)

        // Attempt reconnection if we were previously connected
        if wasConnected, let connection = currentConnection, let keyPair = currentKeyPair {
            attemptReconnection(to: connection, using: keyPair)
        }
    }

    private func attemptReconnection(to connection: HostConnection, using keyPair: SSHKeyPair) {
        guard reconnectAttempts < maxReconnectAttempts else {
            connectionError = "Failed to reconnect after \(maxReconnectAttempts) attempts"
            return
        }

        reconnectAttempts += 1
        let delay = Double(min(reconnectAttempts * 2, 10)) // Exponential backoff, max 10 seconds

        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !Task.isCancelled else { return }

            do {
                try await connect(to: connection, using: keyPair)
            } catch {
                // Will retry via handleDisconnection if connect fails
            }
        }
    }

    func cancelReconnection() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
    }

    // MARK: - Settings Update

    func sendSettingsUpdate(setting: String, value: Bool) {
        guard isConnected else { return }

        Task {
            do {
                let message = try ShellyMessage.settingsUpdate(setting: setting, value: value)
                try await send(message)
            } catch {
                print("Failed to send settings update: \(error)")
            }
        }
    }

    func sendSettingsUpdate(setting: String, value: Int) {
        guard isConnected else { return }

        Task {
            do {
                let message = try ShellyMessage.settingsUpdate(setting: setting, value: value)
                try await send(message)
            } catch {
                print("Failed to send settings update: \(error)")
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
                self.handleShellyMessage(message)
            }
        } catch {
            print("Failed to parse message: \(error)")
        }
    }

    private func handleShellyMessage(_ message: ShellyMessage) {
        switch message.type {
        case .authChallenge:
            do {
                let challenge = try message.decodePayload(AuthChallengePayload.self)
                Task {
                    try await handleAuthChallenge(challenge)
                }
            } catch {
                connectionError = "Failed to parse auth challenge"
            }

        case .authResult:
            do {
                let result = try message.decodePayload(AuthResultPayload.self)
                handleAuthResult(result)
            } catch {
                connectionError = "Failed to parse auth result"
            }

        case .terminalOutput:
            do {
                let output = try message.decodePayload(TerminalOutputPayload.self)
                onTerminalOutput?(output.data)
            } catch {
                print("Failed to parse terminal output: \(error)")
            }

        case .error:
            do {
                let error = try message.decodePayload(ErrorPayload.self)
                connectionError = error.message
                if !error.recoverable {
                    disconnect()
                }
            } catch {
                print("Failed to parse error: \(error)")
            }

        case .sudoConfirmRequest:
            do {
                let request = try message.decodePayload(SudoConfirmRequestPayload.self)
                pendingSudoRequest = request
                showingSudoConfirmation = true
                onSudoRequest?(request)
            } catch {
                print("Failed to parse sudo request: \(error)")
            }

        case .pong:
            // Keep-alive response
            break

        case .settingsSync:
            do {
                let settings = try message.decodePayload(SecuritySettingsPayload.self)
                onSettingsSync?(settings)
            } catch {
                print("Failed to parse settings sync: \(error)")
            }

        case .settingsConfirm:
            do {
                let confirm = try message.decodePayload(SettingsConfirmPayload.self)
                onSettingsConfirm?(confirm)
            } catch {
                print("Failed to parse settings confirm: \(error)")
            }

        default:
            print("Unhandled message type: \(message.type)")
        }
    }
}

// MARK: - Errors

enum TerminalConnectionError: LocalizedError {
    case invalidURL
    case notConnected
    case encodingFailed
    case noKeyPair
    case authenticationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server address"
        case .notConnected:
            return "Not connected to server"
        case .encodingFailed:
            return "Failed to encode message"
        case .noKeyPair:
            return "No SSH key available"
        case .authenticationFailed(let message):
            return message
        }
    }
}
