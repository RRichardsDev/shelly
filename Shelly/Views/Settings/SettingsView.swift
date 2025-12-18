//
//  SettingsView.swift
//  Shelly
//
//  App settings
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(Constants.UserDefaultsKeys.autoLockEnabled) private var autoLockEnabled = true

    var body: some View {
        NavigationStack {
            List {
                // Security Section
                Section {
                    NavigationLink {
                        KeyManagementView()
                    } label: {
                        Label("SSH Keys", systemImage: "key.fill")
                    }

                    Toggle(isOn: $autoLockEnabled) {
                        Label("Auto-Lock", systemImage: "lock.fill")
                    }

                    NavigationLink {
                        SecuritySettingsView()
                    } label: {
                        Label("Security", systemImage: "shield.fill")
                    }
                } header: {
                    Text("Security")
                }

                // Appearance Section
                Section {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Appearance", systemImage: "paintbrush.fill")
                    }

                    NavigationLink {
                        TerminalSettingsView()
                    } label: {
                        Label("Terminal", systemImage: "terminal.fill")
                    }
                } header: {
                    Text("Appearance")
                }

                // About Section
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About Shelly", systemImage: "info.circle.fill")
                    }

                    Link(destination: URL(string: "https://github.com/your-repo/shelly")!) {
                        Label("GitHub", systemImage: "link")
                    }
                } header: {
                    Text("About")
                }

                // Debug Section (only in debug builds)
                #if DEBUG
                Section {
                    Button {
                        // Reset all data
                    } label: {
                        Label("Reset All Data", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Debug")
                }
                #endif
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Security Settings

struct SecuritySettingsView: View {
    @AppStorage(Constants.UserDefaultsKeys.autoLockEnabled) private var autoLockEnabled = true
    @AppStorage(Constants.UserDefaultsKeys.autoLockDelay) private var autoLockDelay: Double = 300
    @Environment(AppState.self) private var appState

    private let authManager = AuthenticationManager.shared

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Biometric Type", systemImage: authManager.biometricType.systemImage)
                    Spacer()
                    Text(authManager.biometricType.displayName)
                        .foregroundStyle(.secondary)
                }

                Toggle("Require on Launch", isOn: .constant(true))
                    .disabled(true)

                Toggle("Require for Sudo", isOn: .constant(true))
                    .disabled(true)
            } header: {
                Text("Authentication")
            } footer: {
                Text("Face ID is required to unlock the app and confirm sudo commands.")
            }

            Section {
                Toggle("Auto-Lock", isOn: $autoLockEnabled)

                if autoLockEnabled {
                    Picker("Lock After", selection: $autoLockDelay) {
                        Text("1 minute").tag(60.0)
                        Text("5 minutes").tag(300.0)
                        Text("15 minutes").tag(900.0)
                        Text("30 minutes").tag(1800.0)
                    }
                }
            } header: {
                Text("Auto-Lock")
            } footer: {
                Text("Automatically lock the app after a period of inactivity.")
            }

            // Connection Security (synced from Mac)
            Section {
                Toggle("TLS Encryption", isOn: Binding(
                    get: { appState.securitySettings.tlsEnabled },
                    set: { newValue in
                        appState.securitySettings.tlsEnabled = newValue
                        appState.sendSettingsUpdate(setting: "tlsEnabled", value: newValue)
                    }
                ))
                .disabled(!appState.securitySettings.isSynced)

                if appState.securitySettings.tlsEnabled {
                    Toggle("Certificate Pinning", isOn: Binding(
                        get: { appState.securitySettings.certificatePinningEnabled },
                        set: { newValue in
                            appState.securitySettings.certificatePinningEnabled = newValue
                            appState.sendSettingsUpdate(setting: "certificatePinningEnabled", value: newValue)
                        }
                    ))
                    .disabled(!appState.securitySettings.isSynced)

                    if let fingerprint = appState.securitySettings.certificateFingerprint {
                        HStack {
                            Text("Certificate")
                            Spacer()
                            Text(fingerprint.prefix(20) + "...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Connection Security")
            } footer: {
                if !appState.securitySettings.isSynced {
                    Text("Connect to a Mac to configure these settings.")
                } else {
                    Text("TLS encrypts all traffic. Certificate pinning verifies the Mac's identity.")
                }
            }

            // Session Timeout (synced from Mac)
            Section {
                Toggle("Session Timeout", isOn: Binding(
                    get: { appState.securitySettings.sessionTimeoutEnabled },
                    set: { newValue in
                        appState.securitySettings.sessionTimeoutEnabled = newValue
                        appState.sendSettingsUpdate(setting: "sessionTimeoutEnabled", value: newValue)
                    }
                ))
                .disabled(!appState.securitySettings.isSynced)

                if appState.securitySettings.sessionTimeoutEnabled {
                    Picker("Timeout After", selection: Binding(
                        get: { appState.securitySettings.sessionTimeoutSeconds },
                        set: { newValue in
                            appState.securitySettings.sessionTimeoutSeconds = newValue
                            appState.sendSettingsUpdate(setting: "sessionTimeoutSeconds", value: newValue)
                        }
                    )) {
                        ForEach(SecuritySettings.timeoutPresets, id: \.seconds) { preset in
                            Text(preset.label).tag(preset.seconds)
                        }
                    }
                    .disabled(!appState.securitySettings.isSynced)
                }
            } header: {
                Text("Session")
            } footer: {
                Text("Require Face ID after a period of inactivity.")
            }

            // Audit Logging (synced from Mac)
            Section {
                Toggle("Audit Logging", isOn: Binding(
                    get: { appState.securitySettings.auditLoggingEnabled },
                    set: { newValue in
                        appState.securitySettings.auditLoggingEnabled = newValue
                        appState.sendSettingsUpdate(setting: "auditLoggingEnabled", value: newValue)
                    }
                ))
                .disabled(!appState.securitySettings.isSynced)

                if appState.securitySettings.auditLoggingEnabled {
                    Picker("Log Retention", selection: Binding(
                        get: { appState.securitySettings.auditLogRetentionDays },
                        set: { newValue in
                            appState.securitySettings.auditLogRetentionDays = newValue
                            appState.sendSettingsUpdate(setting: "auditLogRetentionDays", value: newValue)
                        }
                    )) {
                        ForEach(SecuritySettings.retentionPresets, id: \.days) { preset in
                            Text(preset.label).tag(preset.days)
                        }
                    }
                    .disabled(!appState.securitySettings.isSynced)
                }
            } header: {
                Text("Audit Logging")
            } footer: {
                Text("Log all terminal commands on your Mac to ~/.shellyd/audit.log")
            }
        }
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @AppStorage("fontSize") private var fontSize: Double = 14
    @AppStorage("fontName") private var fontName = "SF Mono"
    @State private var themeManager = TerminalThemeManager.shared

    private let availableFonts = ["SF Mono", "Menlo", "Monaco", "Courier New"]

    var body: some View {
        List {
            Section {
                Picker("Font", selection: $fontName) {
                    ForEach(availableFonts, id: \.self) { font in
                        Text(font)
                            .font(.custom(font, size: 16))
                            .tag(font)
                    }
                }

                VStack(alignment: .leading) {
                    Text("Font Size: \(Int(fontSize))")
                    Slider(value: $fontSize, in: 10...24, step: 1)
                }
            } header: {
                Text("Font")
            }

            Section {
                ForEach(TerminalTheme.allThemes) { theme in
                    ThemeRow(
                        theme: theme,
                        isSelected: themeManager.currentTheme.id == theme.id,
                        onSelect: {
                            themeManager.currentTheme = theme
                        }
                    )
                }
            } header: {
                Text("Theme")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Theme Row

struct ThemeRow: View {
    let theme: TerminalTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                // Theme preview
                HStack(spacing: 0) {
                    theme.background.color
                        .frame(width: 40, height: 30)
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            theme.red.color.frame(width: 10, height: 15)
                            theme.green.color.frame(width: 10, height: 15)
                            theme.blue.color.frame(width: 10, height: 15)
                            theme.yellow.color.frame(width: 10, height: 15)
                        }
                        HStack(spacing: 0) {
                            theme.cyan.color.frame(width: 10, height: 15)
                            theme.magenta.color.frame(width: 10, height: 15)
                            theme.foreground.color.frame(width: 10, height: 15)
                            theme.brightBlack.color.frame(width: 10, height: 15)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

                Text(theme.name)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Terminal Settings

struct TerminalSettingsView: View {
    @AppStorage("scrollbackLines") private var scrollbackLines: Double = 10000
    @AppStorage("cursorBlink") private var cursorBlink = true

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading) {
                    Text("Scrollback: \(Int(scrollbackLines)) lines")
                    Slider(value: $scrollbackLines, in: 1000...50000, step: 1000)
                }

                Toggle("Cursor Blink", isOn: $cursorBlink)
            } header: {
                Text("Terminal")
            }

            Section {
                HStack {
                    Text("Shell")
                    Spacer()
                    Text("zsh (from server)")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Shell")
            } footer: {
                Text("The shell is determined by the Mac daemon configuration.")
            }
        }
        .navigationTitle("Terminal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.tint)

                    VStack(spacing: 4) {
                        Text("Shelly")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("Remote Terminal for Mac")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("Version \(Constants.appVersion)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }

            Section {
                LabeledContent("Version", value: Constants.appVersion)
                LabeledContent("Build", value: "1")
            }

            Section {
                Link(destination: URL(string: "https://github.com/your-repo/shelly")!) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Link(destination: URL(string: "https://github.com/your-repo/shelly/issues")!) {
                    Label("Report an Issue", systemImage: "exclamationmark.bubble")
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
}
