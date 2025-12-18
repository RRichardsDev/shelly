//
//  ShellyApp.swift
//  Shelly
//
//  Created by Rhodri Richards on 16/12/2025.
//

import SwiftUI
import SwiftData

@main
struct ShellyApp: App {
    @State private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            HostConnection.self,
            CommandHistory.self,
            SSHKeyPair.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isUnlocked || !appState.requiresAuthentication {
                    MainTabView()
                } else {
                    LockScreenView()
                }
            }
            .environment(appState)
        }
        .modelContainer(sharedModelContainer)
    }
}
