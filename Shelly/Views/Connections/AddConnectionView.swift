//
//  AddConnectionView.swift
//  Shelly
//
//  Add a new Mac connection with auto-discovery and pairing support
//

import SwiftUI
import SwiftData

struct AddConnectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var existingConnections: [HostConnection]
    @Query private var sshKeys: [SSHKeyPair]

    // Bonjour browser
    @ObservedObject private var browser = BonjourBrowser.shared

    // Selected discovered host
    @State private var selectedHost: DiscoveredHost?

    // Manual entry fields
    @State private var name = ""
    @State private var hostname = ""
    @State private var port = String(Constants.defaultPort)
    @State private var pairingCode = ""
    @State private var setAsDefault = true

    // UI state
    @State private var showManualEntry = false
    @State private var isPairing = false
    @State private var pairingStatus: PairingStatus = .idle

    // New pairing flow state
    @State private var showCodeEntry = false
    @State private var macName = ""
    @State private var webSocket: URLSessionWebSocketTask?

    enum PairingStatus: Equatable {
        case idle
        case connecting
        case waitingForCode
        case verifying
        case generatingKey
        case success
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Auto-discovered Macs
                Section {
                    if browser.discoveredHosts.isEmpty {
                        if browser.isScanning {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Searching for Macs...")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("No Macs found on network")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(browser.discoveredHosts) { host in
                            DiscoveredHostRow(
                                host: host,
                                isSelected: selectedHost?.id == host.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectHost(host)
                            }
                        }
                    }

                    Button {
                        browser.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("Available Macs")
                } footer: {
                    Text("Macs running shellyd will appear automatically.")
                }

                // Manual entry toggle
                Section {
                    Toggle("Enter Details Manually", isOn: $showManualEntry)
                }

                // Manual Connection Details
                if showManualEntry {
                    Section {
                        TextField("Display Name", text: $name)
                            .textContentType(.name)

                        TextField("Hostname or IP", text: $hostname)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("Port", text: $port)
                            .keyboardType(.numberPad)
                    } header: {
                        Text("Connection Details")
                    } footer: {
                        Text("Enter your Mac's hostname (e.g., my-mac.local) or IP address.")
                    }
                }

                // Pairing Code (shown after Mac displays code)
                if showCodeEntry {
                    Section {
                        VStack(spacing: 12) {
                            Text("Enter the code shown on")
                                .foregroundStyle(.secondary)
                            Text(macName)
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                        TextField("000000", text: $pairingCode)
                            .keyboardType(.numberPad)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .onChange(of: pairingCode) { _, newValue in
                                // Limit to 6 digits
                                let filtered = newValue.filter { $0.isNumber }
                                if filtered.count > 6 {
                                    pairingCode = String(filtered.prefix(6))
                                } else if filtered != newValue {
                                    pairingCode = filtered
                                }
                                // Auto-submit when 6 digits entered
                                if pairingCode.count == 6 {
                                    Task {
                                        await verifyCode()
                                    }
                                }
                            }
                    } header: {
                        Text("Pairing Code")
                    }
                }

                // Status
                if pairingStatus != .idle {
                    Section {
                        HStack {
                            statusIcon
                            Text(statusMessage)
                                .foregroundStyle(statusColor)
                        }
                    }
                }

                // Options
                Section {
                    Toggle("Set as Default", isOn: $setAsDefault)
                } footer: {
                    Text("The default connection will be used automatically when opening the terminal.")
                }
            }
            .navigationTitle("Add Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Pair") {
                        Task {
                            await startPairing()
                        }
                    }
                    .disabled(!isValid || isPairing)
                }
            }
            .onAppear {
                browser.startScanning()
            }
            .onDisappear {
                browser.stopScanning()
            }
            .interactiveDismissDisabled(isPairing)
        }
    }

    // MARK: - Host Selection

    private func selectHost(_ host: DiscoveredHost) {
        selectedHost = host
        name = host.name
        hostname = host.host
        port = String(host.port)
        showManualEntry = false
    }

    // MARK: - Validation

    private var isValid: Bool {
        let hasHost: Bool
        if let selected = selectedHost {
            // Selected host must be resolved to connect
            hasHost = selected.isResolved && !selected.host.isEmpty
        } else {
            hasHost = !hostname.trimmingCharacters(in: .whitespaces).isEmpty &&
                (Int(port) ?? 0) > 0 && (Int(port) ?? 0) <= 65535
        }
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty

        return hasHost && hasName
    }

    // MARK: - Status UI

    private var statusIcon: some View {
        Group {
            switch pairingStatus {
            case .idle:
                EmptyView()
            case .connecting, .waitingForCode, .verifying, .generatingKey:
                ProgressView()
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var statusMessage: String {
        switch pairingStatus {
        case .idle:
            return ""
        case .connecting:
            return "Connecting to Mac..."
        case .generatingKey:
            return "Generating SSH key..."
        case .waitingForCode:
            return "Check your Mac for the pairing code..."
        case .verifying:
            return "Verifying code..."
        case .success:
            return "Paired successfully!"
        case .failed(let message):
            return message
        }
    }

    private var statusColor: Color {
        switch pairingStatus {
        case .success:
            return .green
        case .failed:
            return .red
        default:
            return .secondary
        }
    }

    // MARK: - Pairing Logic

    private var targetHost: String {
        if let selected = selectedHost {
            return selected.host
        }
        return hostname.trimmingCharacters(in: .whitespaces)
    }

    private var targetPort: Int {
        if let selected = selectedHost {
            return selected.port
        }
        return Int(port) ?? Int(Constants.defaultPort)
    }

    private var displayName: String {
        if let selected = selectedHost {
            return name.isEmpty ? selected.name : name
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    private func startPairing() async {
        isPairing = true
        pairingStatus = .connecting
        pairingCode = ""
        showCodeEntry = false

        do {
            // Step 1: Ensure we have an SSH key
            pairingStatus = .generatingKey
            let keyPair = try await getOrCreateSSHKey()

            // Step 2: Connect to Mac
            pairingStatus = .connecting
            let urlString = "ws://\(targetHost):\(targetPort)/ws"
            guard let url = URL(string: urlString) else {
                throw PairingError.invalidURL
            }

            let session = URLSession(configuration: .default)
            webSocket = session.webSocketTask(with: url)
            webSocket?.resume()

            // Step 3: Send pairing request (without code)
            let payload = PairRequestPayload(
                publicKey: keyPair.publicKey,
                deviceName: UIDevice.current.name
            )

            let message = try ShellyMessage(type: .pairRequest, payload: payload)
            let messageData = try JSONEncoder().encode(message)
            guard let messageString = String(data: messageData, encoding: .utf8) else {
                throw PairingError.encodingFailed
            }

            try await webSocket?.send(.string(messageString))

            // Step 4: Wait for pairChallenge
            pairingStatus = .waitingForCode
            guard let ws = webSocket else {
                throw PairingError.invalidResponse
            }

            let response = try await withTimeout(seconds: 30) {
                try await ws.receive()
            }

            guard case .string(let text) = response,
                  let data = text.data(using: .utf8) else {
                throw PairingError.invalidResponse
            }

            let shellyMessage = try JSONDecoder().decode(ShellyMessage.self, from: data)

            if shellyMessage.type == ShellyMessageType.pairChallenge {
                let challenge = try shellyMessage.decodePayload(PairChallengePayload.self)
                await MainActor.run {
                    macName = challenge.macName
                    showCodeEntry = true
                    pairingStatus = .waitingForCode
                }
            } else if shellyMessage.type == ShellyMessageType.pairResponse {
                let pairResponse = try shellyMessage.decodePayload(PairResponsePayload.self)
                if !pairResponse.success {
                    throw PairingError.pairingFailed(pairResponse.message ?? "Unknown error")
                }
            } else {
                throw PairingError.unexpectedResponse
            }

        } catch {
            await MainActor.run {
                pairingStatus = .failed(error.localizedDescription)
                isPairing = false
                showCodeEntry = false
            }
        }
    }

    private func verifyCode() async {
        guard let ws = webSocket, pairingCode.count == 6 else { return }

        await MainActor.run {
            pairingStatus = .verifying
        }

        do {
            // Send the code
            let verifyPayload = PairVerifyPayload(code: pairingCode)
            let message = try ShellyMessage(type: .pairVerify, payload: verifyPayload)
            let messageData = try JSONEncoder().encode(message)
            guard let messageString = String(data: messageData, encoding: .utf8) else {
                throw PairingError.encodingFailed
            }

            try await ws.send(.string(messageString))

            // Wait for response
            let response = try await withTimeout(seconds: 10) {
                try await ws.receive()
            }

            guard case .string(let text) = response,
                  let data = text.data(using: .utf8) else {
                throw PairingError.invalidResponse
            }

            let shellyMessage = try JSONDecoder().decode(ShellyMessage.self, from: data)

            guard shellyMessage.type == .pairResponse else {
                throw PairingError.unexpectedResponse
            }

            let pairResponse = try shellyMessage.decodePayload(PairResponsePayload.self)

            guard pairResponse.success else {
                throw PairingError.pairingFailed(pairResponse.message ?? "Invalid code")
            }

            // Success! Save the connection with certificate fingerprint
            let certFingerprint = pairResponse.certificateFingerprint

            await MainActor.run {
                pairingStatus = .success

                // Update defaults
                if setAsDefault {
                    for connection in existingConnections {
                        connection.isDefault = false
                    }
                }

                let connection = HostConnection(
                    name: displayName,
                    hostname: targetHost,
                    port: targetPort,
                    isDefault: setAsDefault || existingConnections.isEmpty,
                    tlsCertificateFingerprint: certFingerprint
                )

                modelContext.insert(connection)
            }

            ws.cancel(with: .normalClosure, reason: nil)

            // Wait a moment to show success, then dismiss
            try await Task.sleep(for: .seconds(1))
            await MainActor.run {
                dismiss()
            }

        } catch {
            await MainActor.run {
                pairingStatus = .failed(error.localizedDescription)
                pairingCode = ""
            }
        }
    }

    private func getOrCreateSSHKey() async throws -> SSHKeyPair {
        // Use existing default key if available
        if let existingKey = sshKeys.first(where: { $0.isDefault }) ?? sshKeys.first {
            return existingKey
        }

        // Generate new key
        let (keychainId, publicKey, fingerprint) = try SSHKeyGenerator.shared.generateAndSaveKeyPair(
            name: "Shelly Key"
        )

        let keyPair = SSHKeyPair(
            name: "Shelly Key",
            publicKey: publicKey,
            keyType: "ed25519",
            keychainIdentifier: keychainId,
            isDefault: true,
            fingerprint: fingerprint
        )

        modelContext.insert(keyPair)
        return keyPair
    }
}

// MARK: - Discovered Host Row

struct DiscoveredHostRow: View {
    let host: DiscoveredHost
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading) {
                Text(host.name)
                    .font(.headline)
                if host.isResolved {
                    Text("\(host.host):\(String(host.port))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Resolving...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}

// MARK: - Timeout Helper

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw PairingError.timeout
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - Errors

enum PairingError: LocalizedError {
    case invalidURL
    case encodingFailed
    case invalidResponse
    case unexpectedResponse
    case pairingFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server address"
        case .encodingFailed:
            return "Failed to encode request"
        case .invalidResponse:
            return "Invalid response from server"
        case .unexpectedResponse:
            return "Unexpected response from server"
        case .pairingFailed(let message):
            return message
        case .timeout:
            return "Connection timed out"
        }
    }
}

#Preview {
    AddConnectionView()
        .modelContainer(for: [HostConnection.self, SSHKeyPair.self], inMemory: true)
}
