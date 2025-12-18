//
//  MainTabView.swift
//  Shelly
//
//  Root tab navigation after unlock
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .terminal

    enum Tab: Hashable {
        case terminal
        case connections
        case history
        case settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TerminalView()
                .tabItem {
                    Label("Terminal", systemImage: "terminal.fill")
                }
                .tag(Tab.terminal)

            ConnectionListView()
                .tabItem {
                    Label("Connections", systemImage: "server.rack")
                }
                .tag(Tab.connections)

            HistoryListView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(Tab.history)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
        .sheet(isPresented: Binding(
            get: { appState.showSudoConfirmation },
            set: { appState.showSudoConfirmation = $0 }
        )) {
            if let request = appState.pendingSudoRequest {
                SudoConfirmationSheet(request: request)
            }
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [HostConnection.self, CommandHistory.self, SSHKeyPair.self], inMemory: true)
        .environment(AppState())
}
