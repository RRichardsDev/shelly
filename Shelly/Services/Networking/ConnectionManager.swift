//
//  ConnectionManager.swift
//  Shelly
//
//  Manages connection lifecycle and authentication
//

import Foundation
import SwiftData
import CryptoKit
import UIKit

@Observable
final class ConnectionManager {
    static let shared = ConnectionManager()

    // State
    var isConnected = false
    var isConnecting = false
    var isAuthenticated = false
    var connectionError: String?

    // Active connection
    private(set) var webSocketClient: WebSocketClient?
    private var currentHost: HostConnection?
    private var pendingChallenge: Data?

    // Callbacks
    var onTerminalOutput: ((Data) -> Void)?
    var onSudoConfirmRequest: ((UUID, String) -> Void)?
    var onSettingsSync: ((SecuritySettingsPayload) -> Void)?
    var onSettingsConfirm: ((SettingsConfirmPayload) -> Void)?

    private init() {}

    // MARK: - Connect

    // TLS settings (updated from AppState)
    var useTLS: Bool = false
    var pinnedCertificateFingerprint: String?

    func connect(to host: HostConnection, using keyPair: SSHKeyPair) async throws {
        guard !isConnecting else { return }

        await MainActor.run {
            isConnecting = true
            connectionError = nil
        }

        currentHost = host

        // Create WebSocket client
        webSocketClient = WebSocketClient(host: host.hostname, port: host.port)

        // Configure TLS if enabled
        // Use the stored fingerprint from the host if we don't have one from settings
        let fingerprint = pinnedCertificateFingerprint ?? host.tlsCertificateFingerprint
        webSocketClient?.configureTLS(
            enabled: useTLS,
            pinnedFingerprint: fingerprint
        )

        // Setup callbacks
        webSocketClient?.onConnect = { [weak self] in
            Task {
                await self?.handleConnected(host: host, keyPair: keyPair)
            }
        }

        webSocketClient?.onMessage = { [weak self] message in
            self?.handleMessage(message)
        }

        webSocketClient?.onDisconnect = { [weak self] error in
            self?.handleDisconnected(error: error)
        }

        webSocketClient?.onError = { [weak self] error in
            self?.handleError(error)
        }

        // Connect
        webSocketClient?.connect()
    }

    func disconnect() {
        webSocketClient?.disconnect()
        webSocketClient = nil
        currentHost = nil
        pendingChallenge = nil

        Task { @MainActor in
            isConnected = false
            isConnecting = false
            isAuthenticated = false
        }
    }

    // MARK: - Send

    func sendInput(_ text: String) {
        webSocketClient?.sendInput(text)
    }

    func sendInput(_ data: Data) {
        webSocketClient?.sendInput(data)
    }

    func sendResize(rows: Int, cols: Int) {
        webSocketClient?.sendResize(rows: rows, cols: cols)
    }

    func sendSudoConfirmation(requestId: UUID, approved: Bool) {
        do {
            let message = try ShellyMessage.sudoConfirmResponse(requestId: requestId, approved: approved)
            webSocketClient?.send(message)
        } catch {
            handleError(error)
        }
    }

    func sendSudoPassword(_ password: String) {
        do {
            let message = try ShellyMessage.sudoPassword(password)
            webSocketClient?.send(message)
        } catch {
            handleError(error)
        }
    }

    // MARK: - Message Handling

    private func handleConnected(host: HostConnection, keyPair: SSHKeyPair) async {
        // Send hello message with public key
        let deviceName = await UIDevice.current.name

        do {
            let message = try ShellyMessage.hello(
                publicKey: keyPair.publicKey,
                deviceName: deviceName
            )
            webSocketClient?.send(message)
        } catch {
            handleError(error)
        }
    }

    private func handleMessage(_ message: ShellyMessage) {
        switch message.type {
        case .authChallenge:
            handleAuthChallenge(message)

        case .authResult:
            handleAuthResult(message)

        case .terminalOutput:
            handleTerminalOutput(message)

        case .sudoConfirmRequest:
            handleSudoConfirmRequest(message)

        case .error:
            handleErrorMessage(message)

        case .settingsSync:
            handleSettingsSync(message)

        case .settingsConfirm:
            handleSettingsConfirm(message)

        case .pong:
            // Ignore pong
            break

        default:
            print("Unhandled message type: \(message.type)")
        }
    }

    private func handleAuthChallenge(_ message: ShellyMessage) {
        do {
            let challenge = try message.decodePayload(AuthChallengePayload.self)
            pendingChallenge = challenge.challenge

            // Sign the challenge
            guard let keyPair = try? loadDefaultKeyPair() else {
                throw ConnectionError.noKeyPair
            }

            let privateKey = try SSHKeyGenerator.shared.loadPrivateKey(identifier: keyPair.keychainIdentifier)
            let signature = SSHKeyGenerator.shared.sign(challenge.challenge, with: privateKey)

            // Send response
            let response = try ShellyMessage.authResponse(signature: signature)
            webSocketClient?.send(response)

        } catch {
            handleError(error)
        }
    }

    private func handleAuthResult(_ message: ShellyMessage) {
        do {
            let result = try message.decodePayload(AuthResultPayload.self)

            Task { @MainActor in
                if result.success {
                    isAuthenticated = true
                    isConnected = true
                    isConnecting = false

                    // Update last connected time
                    currentHost?.lastConnected = Date()
                } else {
                    connectionError = result.message ?? "Authentication failed"
                    disconnect()
                }
            }
        } catch {
            handleError(error)
        }
    }

    private func handleTerminalOutput(_ message: ShellyMessage) {
        do {
            let output = try message.decodePayload(TerminalOutputPayload.self)
            onTerminalOutput?(output.data)
        } catch {
            handleError(error)
        }
    }

    private func handleSudoConfirmRequest(_ message: ShellyMessage) {
        do {
            let request = try message.decodePayload(SudoConfirmRequestPayload.self)
            onSudoConfirmRequest?(request.requestId, request.command)
        } catch {
            handleError(error)
        }
    }

    private func handleErrorMessage(_ message: ShellyMessage) {
        do {
            let error = try message.decodePayload(ErrorPayload.self)
            Task { @MainActor in
                connectionError = error.message
            }
        } catch {
            handleError(error)
        }
    }

    private func handleSettingsSync(_ message: ShellyMessage) {
        do {
            let settings = try message.decodePayload(SecuritySettingsPayload.self)
            onSettingsSync?(settings)
        } catch {
            handleError(error)
        }
    }

    private func handleSettingsConfirm(_ message: ShellyMessage) {
        do {
            let confirm = try message.decodePayload(SettingsConfirmPayload.self)
            onSettingsConfirm?(confirm)
        } catch {
            handleError(error)
        }
    }

    private func handleDisconnected(error: Error?) {
        Task { @MainActor in
            isConnected = false
            isConnecting = false
            isAuthenticated = false

            if let error = error {
                connectionError = error.localizedDescription
            }
        }
    }

    private func handleError(_ error: Error) {
        Task { @MainActor in
            connectionError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func loadDefaultKeyPair() throws -> SSHKeyPair {
        // This would need access to ModelContext
        // For now, throw an error - this needs to be passed in from the UI layer
        throw ConnectionError.noKeyPair
    }
}

// MARK: - Errors

enum ConnectionError: LocalizedError {
    case noKeyPair
    case authenticationFailed
    case notConnected

    var errorDescription: String? {
        switch self {
        case .noKeyPair:
            return "No SSH key pair available"
        case .authenticationFailed:
            return "Authentication failed"
        case .notConnected:
            return "Not connected to server"
        }
    }
}
