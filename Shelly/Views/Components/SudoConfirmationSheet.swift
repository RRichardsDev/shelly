//
//  SudoConfirmationSheet.swift
//  Shelly
//
//  Face ID confirmation sheet for sudo commands
//

import SwiftUI

struct SudoConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let request: SudoConfirmRequest

    @State private var isAuthenticating = false
    @State private var authError: String?

    private let authManager = AuthenticationManager.shared

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.orange)

                Text("Sudo Confirmation")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding(.top, 20)

            // Command info
            VStack(spacing: 8) {
                Text("A command requires elevated privileges:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(request.command)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal)

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                Button {
                    Task {
                        await authenticate()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: authManager.biometricType.systemImage)
                        Text("Approve with \(authManager.biometricType.displayName)")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isAuthenticating)

                Button {
                    deny()
                } label: {
                    Text("Deny")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(.red)
                .disabled(isAuthenticating)

                if let error = authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isAuthenticating)
    }

    private func authenticate() async {
        isAuthenticating = true
        authError = nil

        let result = await authManager.authenticateForSudo(command: request.command)

        await MainActor.run {
            isAuthenticating = false

            switch result {
            case .success:
                // TODO: Send approval to daemon
                appState.showSudoConfirmation = false
                appState.pendingSudoRequest = nil
            case .failed:
                authError = "Authentication failed. Please try again."
            case .cancelled:
                break
            case .unavailable:
                authError = "Biometric authentication unavailable."
            }
        }
    }

    private func deny() {
        // TODO: Send denial to daemon
        appState.showSudoConfirmation = false
        appState.pendingSudoRequest = nil
        dismiss()
    }
}

#Preview {
    let appState = AppState()
    appState.pendingSudoRequest = SudoConfirmRequest(
        id: UUID(),
        command: "sudo rm -rf /tmp/test",
        timestamp: Date()
    )

    return Color.clear
        .sheet(isPresented: .constant(true)) {
            SudoConfirmationSheet(request: appState.pendingSudoRequest!)
                .environment(appState)
        }
}
