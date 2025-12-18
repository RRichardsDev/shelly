//
//  HistoryListView.swift
//  Shelly
//
//  Command history with search functionality
//

import SwiftUI
import SwiftData

struct HistoryListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CommandHistory.timestamp, order: .reverse)
    private var allHistory: [CommandHistory]

    @State private var searchText = ""
    @State private var selectedHistory: CommandHistory?

    private var filteredHistory: [CommandHistory] {
        if searchText.isEmpty {
            return allHistory
        }
        return allHistory.filter { $0.command.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allHistory.isEmpty {
                    ContentUnavailableView {
                        Label("No History", systemImage: "clock")
                    } description: {
                        Text("Commands you run will appear here.")
                    }
                } else if filteredHistory.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(groupedHistory, id: \.0) { date, items in
                            Section(header: Text(formatSectionDate(date))) {
                                ForEach(items) { item in
                                    HistoryRow(item: item)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedHistory = item
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                deleteHistory(item)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                copyCommand(item.command)
                                            } label: {
                                                Label("Copy", systemImage: "doc.on.doc")
                                            }
                                            .tint(.blue)
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: "Search commands")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !allHistory.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                clearAllHistory()
                            } label: {
                                Label("Clear All History", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(item: $selectedHistory) { item in
                HistoryDetailSheet(item: item)
            }
        }
    }

    private var groupedHistory: [(Date, [CommandHistory])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredHistory) { item in
            calendar.startOfDay(for: item.timestamp)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }

    private func deleteHistory(_ item: CommandHistory) {
        modelContext.delete(item)
    }

    private func clearAllHistory() {
        for item in allHistory {
            modelContext.delete(item)
        }
    }

    private func copyCommand(_ command: String) {
        UIPasteboard.general.string = command
    }
}

// MARK: - History Row

struct HistoryRow: View {
    let item: CommandHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.command)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)

            HStack(spacing: 12) {
                Text(item.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if let exitCode = item.exitCode {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(exitCode == 0 ? .green : .red)
                            .frame(width: 6, height: 6)
                        Text("Exit \(exitCode)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let duration = item.duration {
                    Text(formatDuration(duration))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let connection = item.connection {
                    Text(connection.name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}

// MARK: - History Detail Sheet

struct HistoryDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: CommandHistory

    var body: some View {
        NavigationStack {
            List {
                Section("Command") {
                    Text(item.command)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                Section("Details") {
                    LabeledContent("Time", value: item.timestamp.formatted(date: .abbreviated, time: .standard))

                    if let exitCode = item.exitCode {
                        LabeledContent("Exit Code") {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(exitCode == 0 ? .green : .red)
                                    .frame(width: 8, height: 8)
                                Text("\(exitCode)")
                            }
                        }
                    }

                    if let duration = item.duration {
                        LabeledContent("Duration", value: String(format: "%.2f seconds", duration))
                    }

                    if let connection = item.connection {
                        LabeledContent("Connection", value: connection.name)
                    }
                }

                Section {
                    Button {
                        UIPasteboard.general.string = item.command
                    } label: {
                        Label("Copy Command", systemImage: "doc.on.doc")
                    }

                    Button {
                        // TODO: Re-run command
                    } label: {
                        Label("Run Again", systemImage: "arrow.clockwise")
                    }
                }
            }
            .navigationTitle("Command Details")
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
    HistoryListView()
        .modelContainer(for: [CommandHistory.self, HostConnection.self], inMemory: true)
}
