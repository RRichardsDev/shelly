//
//  ConnectionDetailView.swift
//  Shelly
//
//  Connection detail and editing view
//

import SwiftUI
import SwiftData

struct ConnectionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let connection: HostConnection

    @State private var name: String = ""
    @State private var hostname: String = ""
    @State private var port: Int = 8765
    @State private var isDefault: Bool = false
    @State private var showingDeleteConfirmation = false
    @State private var hasSudoPassword = false

    @Query(filter: #Predicate<HostConnection> { _ in true })
    private var allConnections: [HostConnection]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, height: 60)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(connection.name)
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text(connection.displayAddress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    LabeledContent("Name", value: connection.name)
                    LabeledContent("Hostname", value: connection.hostname)
                    LabeledContent("Port", value: "\(connection.port)")

                    if let lastConnected = connection.lastConnected {
                        LabeledContent("Last Connected") {
                            Text(lastConnected, style: .relative)
                        }
                    }

                    LabeledContent("Added") {
                        Text(connection.createdAt, style: .date)
                    }
                } header: {
                    Text("Connection Details")
                }

                Section {
                    Toggle("Default Connection", isOn: $isDefault)
                        .onChange(of: isDefault) { _, newValue in
                            if newValue {
                                makeDefault()
                            }
                        }
                } footer: {
                    Text("The default connection is used automatically when opening the terminal.")
                }

                Section {
                    if hasSudoPassword {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Password saved in Keychain")
                                .foregroundStyle(.secondary)
                        }

                        Button("Remove Saved Password", role: .destructive) {
                            removeSudoPassword()
                        }
                    } else {
                        HStack {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                            Text("No password saved")
                                .foregroundStyle(.secondary)
                        }

                        Button("Set Sudo Password") {
                            // Will be set on first sudo use
                        }
                        .disabled(true)
                    }
                } header: {
                    Text("Sudo Password")
                } footer: {
                    Text("Your sudo password is stored securely and only sent after Face ID confirmation.")
                }

                Section {
                    Button("Connect", systemImage: "play.circle") {
                        // TODO: Switch to this connection
                        dismiss()
                    }
                    .disabled(connection.isDefault) // Already connected if default
                }

                Section {
                    Button("Delete Connection", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Delete Connection?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteConnection()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove \(connection.name) from your saved connections.")
            }
            .onAppear {
                loadState()
            }
        }
    }

    private func loadState() {
        name = connection.name
        hostname = connection.hostname
        port = connection.port
        isDefault = connection.isDefault
        hasSudoPassword = KeychainManager.shared.hasSudoPassword(forHost: connection.id)
    }

    private func makeDefault() {
        // Clear other defaults
        for conn in allConnections where conn.id != connection.id {
            conn.isDefault = false
        }
        connection.isDefault = true
    }

    private func removeSudoPassword() {
        try? KeychainManager.shared.deleteSudoPassword(forHost: connection.id)
        hasSudoPassword = false
    }

    private func deleteConnection() {
        // Remove sudo password from keychain
        try? KeychainManager.shared.deleteSudoPassword(forHost: connection.id)
        modelContext.delete(connection)
        dismiss()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: HostConnection.self, configurations: config)

    let connection = HostConnection(name: "Test Mac", hostname: "192.168.1.100", port: 8765)
    container.mainContext.insert(connection)

    return ConnectionDetailView(connection: connection)
        .modelContainer(container)
}
