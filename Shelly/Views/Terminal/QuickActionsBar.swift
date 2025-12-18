//
//  QuickActionsBar.swift
//  Shelly
//
//  Placeholder for quick action buttons (future feature)
//

import SwiftUI

struct QuickActionsBar: View {
    var onExecuteCommand: ((String) -> Void)?
    @State private var showingAddAction = false

    // Placeholder quick actions
    private let placeholderActions: [QuickAction] = [
        QuickAction(name: "Clear", icon: "trash", command: "clear"),
        QuickAction(name: "List", icon: "list.bullet", command: "ls -la"),
        QuickAction(name: "Status", icon: "info.circle", command: "git status"),
        QuickAction(name: "Disk", icon: "internaldrive", command: "df -h"),
        QuickAction(name: "Top", icon: "chart.bar", command: "top -l 1 | head -20"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(placeholderActions) { action in
                    QuickActionButton(action: action) {
                        onExecuteCommand?(action.command + "\n")
                    }
                }

                // Add new action button (placeholder)
                Button {
                    showingAddAction = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground).opacity(0.5))
        .alert("Coming Soon", isPresented: $showingAddAction) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Custom quick actions will be available in a future update.")
        }
    }
}

struct QuickAction: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let command: String
}

struct QuickActionButton: View {
    let action: QuickAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: action.icon)
                    .font(.caption)
                Text(action.name)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.tint.opacity(0.15))
            .foregroundStyle(.tint)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack {
        Spacer()
        QuickActionsBar()
    }
}
