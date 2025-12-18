//
//  KeyManagementView.swift
//  Shelly
//
//  SSH key management UI
//

import SwiftUI
import SwiftData

struct KeyManagementView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SSHKeyPair.createdAt, order: .reverse)
    private var keys: [SSHKeyPair]

    @State private var showingGenerateSheet = false
    @State private var selectedKey: SSHKeyPair?
    @State private var isGenerating = false

    var body: some View {
        List {
            if keys.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No SSH Keys", systemImage: "key")
                    } description: {
                        Text("Generate an SSH key to authenticate with your Mac.")
                    } actions: {
                        Button("Generate Key") {
                            showingGenerateSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Section {
                    ForEach(keys) { key in
                        KeyRow(key: key)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedKey = key
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteKey(key)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("Your Keys")
                } footer: {
                    Text("Add the public key to your Mac's shellyd authorized_keys file.")
                }
            }
        }
        .navigationTitle("SSH Keys")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingGenerateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingGenerateSheet) {
            GenerateKeySheet()
        }
        .sheet(item: $selectedKey) { key in
            KeyDetailSheet(key: key)
        }
    }

    private func deleteKey(_ key: SSHKeyPair) {
        // Delete from Keychain
        try? KeychainManager.shared.deleteSSHPrivateKey(identifier: key.keychainIdentifier)
        // Delete from SwiftData
        modelContext.delete(key)
    }
}

// MARK: - Key Row

struct KeyRow: View {
    let key: SSHKeyPair

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(key.name)
                        .font(.headline)

                    if key.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15))
                            .foregroundStyle(.tint)
                            .clipShape(Capsule())
                    }
                }

                Text(key.keyType.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(key.createdAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Generate Key Sheet

struct GenerateKeySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var existingKeys: [SSHKeyPair]

    @State private var keyName = ""
    @State private var isGenerating = false
    @State private var generatedPublicKey: String?
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                if let publicKey = generatedPublicKey {
                    // Success state
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Key Generated!", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.green)

                            Text("Copy this public key and add it to your Mac's shellyd configuration.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Public Key") {
                        Text(publicKey)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)

                        Button {
                            UIPasteboard.general.string = publicKey
                        } label: {
                            Label("Copy to Clipboard", systemImage: "doc.on.doc")
                        }
                    }

                    Section {
                        Button("Done") {
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    // Input state
                    Section {
                        TextField("Key Name", text: $keyName)
                            .textContentType(.name)
                    } header: {
                        Text("Key Name")
                    } footer: {
                        Text("A friendly name to identify this key.")
                    }

                    Section {
                        HStack {
                            Text("Algorithm")
                            Spacer()
                            Text("Ed25519")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Key Type")
                    } footer: {
                        Text("Ed25519 keys are secure and fast.")
                    }
                }
            }
            .navigationTitle(generatedPublicKey == nil ? "Generate SSH Key" : "Key Generated")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if generatedPublicKey == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Generate") {
                            generateKey()
                        }
                        .disabled(keyName.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
                    }
                }
            }
            .interactiveDismissDisabled(isGenerating)
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func generateKey() {
        isGenerating = true

        Task {
            do {
                let (keychainId, publicKey, fingerprint) = try SSHKeyGenerator.shared.generateAndSaveKeyPair(
                    name: keyName.trimmingCharacters(in: .whitespaces)
                )

                let keyPair = SSHKeyPair(
                    name: keyName.trimmingCharacters(in: .whitespaces),
                    publicKey: publicKey,
                    keyType: "ed25519",
                    keychainIdentifier: keychainId,
                    isDefault: existingKeys.isEmpty,
                    fingerprint: fingerprint
                )

                await MainActor.run {
                    modelContext.insert(keyPair)
                    generatedPublicKey = publicKey
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate key: \(error.localizedDescription)"
                    showingError = true
                    isGenerating = false
                }
            }
        }
    }
}

// MARK: - Key Detail Sheet

struct KeyDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var key: SSHKeyPair

    @Query private var allKeys: [SSHKeyPair]

    var body: some View {
        NavigationStack {
            List {
                Section("Key Info") {
                    LabeledContent("Name", value: key.name)
                    LabeledContent("Type", value: key.keyType.uppercased())
                    LabeledContent("Created", value: key.createdAt.formatted(date: .abbreviated, time: .omitted))

                    LabeledContent("Fingerprint") {
                        Text(key.shortFingerprint)
                            .font(.system(.caption, design: .monospaced))
                    }
                }

                Section("Public Key") {
                    Text(key.publicKey)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)

                    Button {
                        UIPasteboard.general.string = key.publicKey
                    } label: {
                        Label("Copy Public Key", systemImage: "doc.on.doc")
                    }
                }

                Section {
                    Toggle("Default Key", isOn: $key.isDefault)
                        .onChange(of: key.isDefault) { _, newValue in
                            if newValue {
                                for other in allKeys where other.id != key.id {
                                    other.isDefault = false
                                }
                            }
                        }
                }
            }
            .navigationTitle(key.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        KeyManagementView()
    }
    .modelContainer(for: SSHKeyPair.self, inMemory: true)
}
