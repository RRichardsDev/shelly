//
//  Constants.swift
//  Shelly
//
//  App-wide constants
//

import Foundation

enum Constants {
    // App Info
    static let appName = "Shelly"
    static let appVersion = "1.0.0"

    // Network
    static let defaultPort: UInt16 = 8765
    static let connectionTimeout: TimeInterval = 10.0
    static let pingInterval: TimeInterval = 30.0

    // Terminal
    static let defaultTerminalRows = 24
    static let defaultTerminalCols = 80
    static let scrollbackLimit = 10000

    // Security
    static let keychainService = "com.shelly.keychain"
    static let keychainAccessGroup: String? = nil

    // Keychain Keys
    enum KeychainKeys {
        static let sshPrivateKey = "ssh_private_key"
        static let sudoPassword = "sudo_password"
        static let authToken = "auth_token"
    }

    // UserDefaults Keys
    enum UserDefaultsKeys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let defaultHostId = "defaultHostId"
        static let autoLockEnabled = "autoLockEnabled"
        static let autoLockDelay = "autoLockDelay"
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when security settings change and require reconnection
    static let shellySettingsChangedReconnect = Notification.Name("shellySettingsChangedReconnect")
}
