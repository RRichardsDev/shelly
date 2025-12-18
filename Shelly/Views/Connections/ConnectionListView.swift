//
//  ConnectionListView.swift
//  Shelly
//
//  List of Mac connections with placeholder for multi-Mac support
//

import SwiftUI
import SwiftData

struct ConnectionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @Query(sort: \HostConnection.createdAt, order: .reverse)
    private var connections: [HostConnection]

    @State private var showingAddConnection = false
    @State private var selectedConnection: HostConnection?

    var body: some View {
        NavigationStack {
            Group {
                if connections.isEmpty {
                    EmptyConnectionsView {
                        showingAddConnection = true
                    }
                } else {
                    List {
                        Section {
                            ForEach(connections) { connection in
                                ConnectionRow(
                                    connection: connection,
                                    isConnected: appState.isConnected && appState.activeHostId == connection.id
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedConnection = connection
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        deleteConnection(connection)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            Text("Your Macs")
                        } footer: {
                            Text("Tap a connection to view details. More Macs coming in a future update.")
                        }
                    }
                }
            }
            .navigationTitle("Connections")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddConnection = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddConnection) {
                AddConnectionView()
            }
            .sheet(item: $selectedConnection) { connection in
                ConnectionDetailView(connection: connection)
            }
        }
    }

    private func deleteConnection(_ connection: HostConnection) {
        modelContext.delete(connection)
    }
}

// MARK: - Connection Row

struct ConnectionRow: View {
    @Environment(AppState.self) private var appState

    let connection: HostConnection
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(isConnected ? .green : .gray)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(connection.name)
                        .font(.headline)

                    if connection.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15))
                            .foregroundStyle(.tint)
                            .clipShape(Capsule())
                    }

                    // TLS indicator (when connected)
                    if isConnected && appState.securitySettings.tlsEnabled {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                Text(connection.displayAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let lastConnected = connection.lastConnected {
                Text(lastConnected, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty State

struct EmptyConnectionsView: View {
    let onAddTapped: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Connections", systemImage: "server.rack")
        } description: {
            Text("Add your Mac to get started with remote terminal access.")
        } actions: {
            Button("Add Connection", action: onAddTapped)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    let appState = AppState()
    return ConnectionListView()
        .modelContainer(for: HostConnection.self, inMemory: true)
        .environment(appState)
}
