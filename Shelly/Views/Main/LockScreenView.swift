//
//  LockScreenView.swift
//  Shelly
//
//  Face ID unlock screen
//

import SwiftUI

struct LockScreenView: View {
    @Environment(AppState.self) private var appState
    @State private var isAuthenticating = false
    @State private var authError: String?

    private let authManager = AuthenticationManager.shared

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // App icon/logo
            Image(systemName: "terminal.fill")
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Shelly")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Remote Terminal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Unlock button
            VStack(spacing: 16) {
                Button {
                    Task {
                        await authenticate()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: authManager.biometricType.systemImage)
                            .font(.title2)

                        Text("Unlock with \(authManager.biometricType.displayName)")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isAuthenticating)

                if let error = authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .onAppear {
            // Auto-trigger authentication on appear
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                await authenticate()
            }
        }
    }

    private func authenticate() async {
        guard !isAuthenticating else { return }

        isAuthenticating = true
        authError = nil

        let result = await authManager.authenticateToUnlock()

        await MainActor.run {
            isAuthenticating = false

            switch result {
            case .success:
                withAnimation {
                    appState.isUnlocked = true
                }
            case .failed:
                authError = "Authentication failed. Please try again."
            case .cancelled:
                break
            case .unavailable:
                authError = "Biometric authentication unavailable."
            }
        }
    }
}

#Preview {
    LockScreenView()
        .environment(AppState())
}
