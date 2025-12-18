//
//  TerminalView.swift
//  Shelly
//
//  Main terminal view container
//

import SwiftUI
import SwiftData

struct TerminalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    @Query(filter: #Predicate<HostConnection> { $0.isDefault })
    private var defaultConnections: [HostConnection]

    @Query(filter: #Predicate<SSHKeyPair> { $0.isDefault })
    private var defaultKeys: [SSHKeyPair]

    @State private var connectionManager = TerminalConnectionManager()
    @State private var terminalState = TerminalState()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Connection status bar
                ConnectionStatusBar(
                    isConnected: connectionManager.isConnected,
                    isConnecting: connectionManager.isConnecting,
                    hostName: defaultConnections.first?.name,
                    error: connectionManager.connectionError,
                    isTLSEnabled: appState.securitySettings.tlsEnabled
                )

                // Terminal canvas with size detection
                GeometryReader { geometry in
                    TerminalCanvas(state: terminalState, colorScheme: colorScheme)
                        .onChange(of: geometry.size) { _, newSize in
                            updateTerminalSize(newSize)
                        }
                        .onAppear {
                            updateTerminalSize(geometry.size)
                        }
                }

                // Quick actions bar
                QuickActionsBar { command in
                    connectionManager.sendInput(command)
                }

                // Input bar
                TerminalInputBar(
                    text: $inputText,
                    isFocused: $isInputFocused,
                    onSubmit: sendCommand
                )
            }
            .navigationTitle("Terminal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Clear Screen", systemImage: "trash") {
                            terminalState.clear()
                        }
                        Button("Reconnect", systemImage: "arrow.clockwise") {
                            reconnect()
                        }
                        Divider()
                        Button("Disconnect", systemImage: "xmark.circle", role: .destructive) {
                            disconnect()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            setupCallbacks()
            connectIfNeeded()
        }
        .onDisappear {
            // Don't disconnect on disappear - keep connection alive
        }
        .onReceive(NotificationCenter.default.publisher(for: .shellySettingsChangedReconnect)) { _ in
            // Auto-reconnect when security settings change
            handleSettingsReconnect()
        }
        .sheet(isPresented: $connectionManager.showingSudoConfirmation) {
            if let request = connectionManager.pendingSudoRequest,
               let hostId = defaultConnections.first?.id {
                SudoConfirmationView(
                    command: request.command,
                    hostId: hostId,
                    onApprove: { password in
                        connectionManager.approveSudo(password: password)
                    },
                    onDeny: {
                        connectionManager.denySudo()
                    }
                )
                .presentationDetents([.medium])
            }
        }
    }

    private func setupCallbacks() {
        // Set connection manager reference in AppState for settings updates
        appState.terminalConnectionManager = connectionManager

        connectionManager.onTerminalOutput = { data in
            if let text = String(data: data, encoding: .utf8) {
                terminalState.append(text)
            }
        }

        connectionManager.onDisconnected = { error in
            if let error = error {
                terminalState.appendLine("\n[Disconnected: \(error.localizedDescription)]")
            } else {
                terminalState.appendLine("\n[Disconnected]")
            }
        }

        connectionManager.onSettingsSync = { settings in
            appState.handleSettingsSync(settings)
        }

        connectionManager.onSettingsConfirm = { confirm in
            appState.handleSettingsConfirm(confirm)
        }
    }

    private func sendCommand() {
        guard !inputText.isEmpty else { return }

        let command = inputText
        inputText = ""

        // Save to history
        if let connection = defaultConnections.first {
            let history = CommandHistory(command: command, connection: connection)
            modelContext.insert(history)
        }

        // Send via WebSocket (with newline to execute)
        connectionManager.sendInput(command + "\n")
    }

    private func connectIfNeeded() {
        guard !connectionManager.isConnected,
              !connectionManager.isConnecting,
              let host = defaultConnections.first,
              let keyPair = defaultKeys.first else {
            if defaultConnections.isEmpty {
                terminalState.appendLine("[No connection configured. Add a Mac in Settings.]")
            } else if defaultKeys.isEmpty {
                terminalState.appendLine("[No SSH key found. This shouldn't happen!]")
            }
            return
        }

        terminalState.appendLine("Connecting to \(host.name)...")

        Task {
            do {
                try await connectionManager.connect(to: host, using: keyPair)
                await MainActor.run {
                    terminalState.appendLine("Connected!\n")
                }
            } catch {
                await MainActor.run {
                    terminalState.appendLine("Connection failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func reconnect() {
        disconnect()
        terminalState.clear()
        connectIfNeeded()
    }

    private func disconnect() {
        connectionManager.disconnect()
        terminalState.appendLine("[Disconnected]")
    }

    private func handleSettingsReconnect() {
        let tlsStatus = ConnectionManager.shared.useTLS ? "TLS enabled" : "TLS disabled"
        terminalState.appendLine("\n[Security settings changed: \(tlsStatus)]")
        terminalState.appendLine("[Reconnecting...]")

        // Brief delay then reconnect
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            await MainActor.run {
                connectIfNeeded()
                // Clear the reconnect required flag
                appState.reconnectRequired = false
            }
        }
    }

    private func updateTerminalSize(_ size: CGSize) {
        // Calculate rows and cols based on monospace font size
        let charWidth: CGFloat = 8.4  // Approximate width of monospace char at size 14
        let charHeight: CGFloat = 17  // Approximate height including line spacing

        let cols = max(20, Int((size.width - 16) / charWidth))  // 16 for padding
        let rows = max(5, Int(size.height / charHeight))

        // Only send if changed
        if cols != terminalState.cols || rows != terminalState.rows {
            terminalState.cols = cols
            terminalState.rows = rows
            connectionManager.sendResize(rows: rows, cols: cols)
        }
    }
}

// MARK: - Connection Status Bar

struct ConnectionStatusBar: View {
    let isConnected: Bool
    let isConnecting: Bool
    let hostName: String?
    let error: String?
    var isTLSEnabled: Bool = false

    var body: some View {
        HStack {
            if isConnecting {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
            } else {
                Circle()
                    .fill(isConnected ? .green : .red)
                    .frame(width: 8, height: 8)
            }

            if let name = hostName {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.caption)
                        .fontWeight(.medium)
                    if isConnected && isTLSEnabled {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            } else {
                Text("No connection configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let error = error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var statusText: String {
        if isConnecting {
            return "Connecting..."
        } else if isConnected {
            return "Connected"
        } else {
            return "Disconnected"
        }
    }
}

// MARK: - Terminal State

@Observable
class TerminalState {
    var lines: [TerminalLine] = []
    var cursorRow: Int = 0
    var cursorCol: Int = 0
    var rows: Int = 24
    var cols: Int = 80

    func appendLine(_ text: String) {
        // Split by newlines and add each line
        let newLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for line in newLines {
            lines.append(TerminalLine(text: String(line)))
        }
        cursorRow = lines.count
        cursorCol = 0
    }

    func append(_ text: String) {
        // Handle text that may contain newlines and carriage returns
        var remaining = text

        while !remaining.isEmpty {
            if let controlIndex = remaining.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
                let beforeControl = String(remaining[..<controlIndex])

                if lines.isEmpty {
                    lines.append(TerminalLine(text: ""))
                }
                lines[lines.count - 1].text += beforeControl

                let char = remaining[controlIndex]
                remaining = String(remaining[remaining.index(after: controlIndex)...])

                if char == "\n" {
                    // Newline - move to new line
                    lines.append(TerminalLine(text: ""))
                } else if char == "\r" {
                    // Carriage return - go to start of current line
                    if remaining.first == "\n" {
                        // \r\n sequence - treat as newline
                        remaining = String(remaining.dropFirst())
                        lines.append(TerminalLine(text: ""))
                    } else {
                        // Standalone \r - clear current line (will be overwritten)
                        if !lines.isEmpty {
                            lines[lines.count - 1].text = ""
                        }
                    }
                }
            } else {
                // No more control characters
                if lines.isEmpty {
                    lines.append(TerminalLine(text: ""))
                }
                lines[lines.count - 1].text += remaining
                remaining = ""
            }
        }

        cursorRow = lines.count
        cursorCol = lines.last?.text.count ?? 0
    }

    func clear() {
        lines.removeAll()
        cursorRow = 0
        cursorCol = 0
    }
}

struct TerminalLine: Identifiable {
    let id = UUID()
    var text: String
    var attributes: [TerminalAttribute] = []
}

struct TerminalAttribute {
    let range: Range<String.Index>
    let foregroundColor: Color?
    let backgroundColor: Color?
    let isBold: Bool
    let isUnderline: Bool
}

#Preview {
    TerminalView()
        .modelContainer(for: [HostConnection.self, CommandHistory.self, SSHKeyPair.self], inMemory: true)
}
