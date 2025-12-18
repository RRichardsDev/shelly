//
//  AppState.swift
//  Shelly
//
//  Global application state management
//

import SwiftUI

@Observable
final class AppState {
    // Authentication state
    var isUnlocked: Bool = false
    var requiresAuthentication: Bool = true

    // Connection state
    var isConnected: Bool = false
    var isConnecting: Bool = false
    var connectionError: String?

    // Active connection
    var activeHostId: UUID?

    // Terminal state
    var terminalOutput: String = ""

    // Sudo confirmation
    var pendingSudoRequest: SudoConfirmRequest?
    var showSudoConfirmation: Bool = false

    // Security settings (synced from Mac)
    var securitySettings = SecuritySettings()

    // Reconnect required flag (when TLS settings change)
    var reconnectRequired: Bool = false
    var reconnectMessage: String?

    // Connection manager reference (set by TerminalView)
    weak var terminalConnectionManager: TerminalConnectionManager?

    // Session timeout manager
    let sessionTimeoutManager = SessionTimeoutManager.shared

    init() {
        setupSessionTimeout()
    }

    func reset() {
        isConnected = false
        isConnecting = false
        connectionError = nil
        terminalOutput = ""
        reconnectRequired = false
        reconnectMessage = nil
    }

    // MARK: - Settings Sync

    /// Send a settings update to the Mac daemon
    func sendSettingsUpdate(setting: String, value: Bool) {
        guard let manager = terminalConnectionManager, manager.isConnected else { return }
        manager.sendSettingsUpdate(setting: setting, value: value)
        securitySettings.markPending(setting, value: value)
    }

    /// Send a settings update to the Mac daemon (Int value)
    func sendSettingsUpdate(setting: String, value: Int) {
        guard let manager = terminalConnectionManager, manager.isConnected else { return }
        manager.sendSettingsUpdate(setting: setting, value: value)
        securitySettings.markPending(setting, value: value)
    }

    /// Handle settings sync from Mac
    func handleSettingsSync(_ payload: SecuritySettingsPayload) {
        securitySettings.update(from: payload)

        // Update session timeout manager
        sessionTimeoutManager.configure(
            enabled: payload.sessionTimeoutEnabled,
            timeoutSeconds: payload.sessionTimeoutSeconds
        )

        // Update ConnectionManager TLS settings for next connection
        ConnectionManager.shared.useTLS = payload.tlsEnabled
        if payload.certificatePinningEnabled {
            ConnectionManager.shared.pinnedCertificateFingerprint = payload.certificateFingerprint
        } else {
            ConnectionManager.shared.pinnedCertificateFingerprint = nil
        }
    }

    /// Handle settings confirmation from Mac
    func handleSettingsConfirm(_ payload: SettingsConfirmPayload) {
        securitySettings.handleConfirmation(payload)

        // Update session timeout if that setting changed
        if payload.setting == "sessionTimeoutEnabled" || payload.setting == "sessionTimeoutSeconds" {
            sessionTimeoutManager.configure(
                enabled: securitySettings.sessionTimeoutEnabled,
                timeoutSeconds: securitySettings.sessionTimeoutSeconds
            )
        }

        // Handle TLS setting change - update immediately and reconnect
        if payload.setting == "tlsEnabled" && payload.success {
            ConnectionManager.shared.useTLS = securitySettings.tlsEnabled
            if payload.reconnectRequired {
                performAutoReconnect()
            }
        }

        // Handle certificate pinning change
        if payload.setting == "certificatePinningEnabled" && payload.success {
            if securitySettings.certificatePinningEnabled {
                ConnectionManager.shared.pinnedCertificateFingerprint = securitySettings.certificateFingerprint
            } else {
                ConnectionManager.shared.pinnedCertificateFingerprint = nil
            }
            if payload.reconnectRequired {
                performAutoReconnect()
            }
        }
    }

    /// Auto-reconnect with new settings
    private func performAutoReconnect() {
        guard let manager = terminalConnectionManager, manager.isConnected else { return }

        // Store current connection info before disconnecting
        // The reconnect will happen automatically via TerminalConnectionManager's reconnect logic
        Task {
            // Brief disconnect to trigger reconnect with new TLS settings
            manager.disconnect()

            // Small delay to ensure clean disconnect
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

            // Reconnection will be handled by the view that owns the connection
            // Post notification so views can reconnect
            await MainActor.run {
                reconnectRequired = true
                reconnectMessage = nil // Clear message since we're auto-handling
                NotificationCenter.default.post(name: .shellySettingsChangedReconnect, object: nil)
            }
        }
    }

    // MARK: - Session Timeout

    private func setupSessionTimeout() {
        sessionTimeoutManager.onSessionTimeout = { [weak self] in
            self?.handleSessionTimeout()
        }
    }

    private func handleSessionTimeout() {
        // Lock the app - require Face ID again
        isUnlocked = false

        // Disconnect from Mac
        terminalConnectionManager?.disconnect()
        isConnected = false
        isConnecting = false
    }

    /// Record activity to reset timeout timer
    func recordActivity() {
        sessionTimeoutManager.recordActivity()
    }
}

// Sudo confirmation request model
struct SudoConfirmRequest: Identifiable {
    let id: UUID
    let command: String
    let timestamp: Date
}
