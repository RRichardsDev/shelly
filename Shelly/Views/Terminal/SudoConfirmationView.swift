//
//  SudoConfirmationView.swift
//  Shelly
//
//  Face ID confirmation for sudo commands
//

import SwiftUI
import LocalAuthentication

struct SudoConfirmationView: View {
    let command: String
    let hostId: UUID
    let onApprove: (String) -> Void
    let onDeny: () -> Void

    @State private var isAuthenticating = false
    @State private var showPasswordEntry = false
    @State private var password = ""
    @State private var savePassword = true
    @State private var authError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)

                // Title
                Text("Sudo Authentication Required")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Command being run
                VStack(alignment: .leading, spacing: 8) {
                    Text("Command:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(command.isEmpty ? "sudo ..." : command)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .padding(.horizontal)

                if showPasswordEntry {
                    // Password entry
                    VStack(spacing: 16) {
                        SecureField("Sudo Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)

                        Toggle("Save password securely", isOn: $savePassword)
                            .padding(.horizontal)
                            .font(.callout)
                    }
                }

                if let error = authError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    if showPasswordEntry {
                        Button {
                            submitPassword()
                        } label: {
                            Text("Authorize")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.blue)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                        }
                        .disabled(password.isEmpty)
                    } else {
                        Button {
                            authenticateWithFaceID()
                        } label: {
                            HStack {
                                Image(systemName: "faceid")
                                Text("Authenticate with Face ID")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isAuthenticating)
                    }

                    Button {
                        onDeny()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .padding(.top, 32)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
        .onAppear {
            // Auto-trigger Face ID
            authenticateWithFaceID()
        }
    }

    private func authenticateWithFaceID() {
        isAuthenticating = true
        authError = nil

        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // No biometrics available, fall back to password entry
            showPasswordEntry = true
            isAuthenticating = false
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Authorize sudo command"
        ) { success, error in
            DispatchQueue.main.async {
                isAuthenticating = false

                if success {
                    // Check if we have a stored password
                    if let storedPassword = try? KeychainManager.shared.loadSudoPassword(forHost: hostId) {
                        onApprove(storedPassword)
                    } else {
                        // Need password
                        showPasswordEntry = true
                    }
                } else {
                    if let error = error as? LAError {
                        switch error.code {
                        case .userCancel, .appCancel:
                            onDeny()
                        case .userFallback:
                            showPasswordEntry = true
                        default:
                            authError = error.localizedDescription
                            showPasswordEntry = true
                        }
                    } else {
                        showPasswordEntry = true
                    }
                }
            }
        }
    }

    private func submitPassword() {
        guard !password.isEmpty else { return }

        // Save password if requested
        if savePassword {
            try? KeychainManager.shared.saveSudoPassword(password, forHost: hostId)
        }

        onApprove(password)
    }
}

#Preview {
    SudoConfirmationView(
        command: "sudo apt update",
        hostId: UUID(),
        onApprove: { _ in },
        onDeny: { }
    )
}
