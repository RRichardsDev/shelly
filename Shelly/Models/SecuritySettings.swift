//
//  SecuritySettings.swift
//  Shelly
//
//  Security settings model synced with Mac daemon
//

import Foundation

/// Observable security settings synced from Mac daemon
@Observable
final class SecuritySettings {
    // Connection Security
    var tlsEnabled: Bool = false
    var certificatePinningEnabled: Bool = false
    var certificateFingerprint: String?

    // Session
    var sessionTimeoutEnabled: Bool = false
    var sessionTimeoutSeconds: Int = 300

    // Audit
    var auditLoggingEnabled: Bool = false
    var auditLogRetentionDays: Int = 30

    // Sync state
    var isSynced: Bool = false
    var lastSyncTime: Date?

    // Pending changes (waiting for confirmation)
    private var pendingChanges: [String: Any] = [:]

    init() {}

    /// Update from server sync payload
    func update(from payload: SecuritySettingsPayload) {
        tlsEnabled = payload.tlsEnabled
        certificatePinningEnabled = payload.certificatePinningEnabled
        certificateFingerprint = payload.certificateFingerprint
        sessionTimeoutEnabled = payload.sessionTimeoutEnabled
        sessionTimeoutSeconds = payload.sessionTimeoutSeconds
        auditLoggingEnabled = payload.auditLoggingEnabled
        auditLogRetentionDays = payload.auditLogRetentionDays
        isSynced = true
        lastSyncTime = Date()
    }

    /// Handle confirmation from server
    func handleConfirmation(_ confirmation: SettingsConfirmPayload) {
        if confirmation.success {
            // Apply the pending change to the actual property
            if let pendingValue = pendingChanges[confirmation.setting] {
                applySettingValue(setting: confirmation.setting, value: pendingValue)
            }
            pendingChanges.removeValue(forKey: confirmation.setting)
        }
        // If failed, the setting will be reverted on next sync
    }

    /// Apply a setting value to the corresponding property
    private func applySettingValue(setting: String, value: Any) {
        switch setting {
        case "tlsEnabled":
            if let boolValue = value as? Bool {
                tlsEnabled = boolValue
            }
        case "certificatePinningEnabled":
            if let boolValue = value as? Bool {
                certificatePinningEnabled = boolValue
            }
        case "sessionTimeoutEnabled":
            if let boolValue = value as? Bool {
                sessionTimeoutEnabled = boolValue
            }
        case "sessionTimeoutSeconds":
            if let intValue = value as? Int {
                sessionTimeoutSeconds = intValue
            }
        case "auditLoggingEnabled":
            if let boolValue = value as? Bool {
                auditLoggingEnabled = boolValue
            }
        case "auditLogRetentionDays":
            if let intValue = value as? Int {
                auditLogRetentionDays = intValue
            }
        default:
            print("Unknown setting: \(setting)")
        }
    }

    /// Mark a setting as pending (optimistic update)
    func markPending(_ setting: String, value: Any) {
        pendingChanges[setting] = value
    }

    /// Check if a setting has a pending change
    func isPending(_ setting: String) -> Bool {
        pendingChanges[setting] != nil
    }
}

// MARK: - Setting Keys

extension SecuritySettings {
    enum SettingKey: String {
        case tlsEnabled
        case certificatePinningEnabled
        case sessionTimeoutEnabled
        case sessionTimeoutSeconds
        case auditLoggingEnabled
        case auditLogRetentionDays
    }
}

// MARK: - Timeout Presets

extension SecuritySettings {
    static let timeoutPresets: [(label: String, seconds: Int)] = [
        ("1 minute", 60),
        ("5 minutes", 300),
        ("15 minutes", 900),
        ("30 minutes", 1800)
    ]

    static let retentionPresets: [(label: String, days: Int)] = [
        ("7 days", 7),
        ("30 days", 30),
        ("90 days", 90)
    ]

    var timeoutLabel: String {
        Self.timeoutPresets.first { $0.seconds == sessionTimeoutSeconds }?.label ?? "\(sessionTimeoutSeconds / 60) minutes"
    }

    var retentionLabel: String {
        Self.retentionPresets.first { $0.days == auditLogRetentionDays }?.label ?? "\(auditLogRetentionDays) days"
    }
}
