//
//  AuditLogger.swift
//  shellyd
//
//  Command audit logging with rotation
//

import Foundation

final class AuditLogger {
    static let shared = AuditLogger()

    private var isEnabled = false
    private var retentionDays = 30
    private let logQueue = DispatchQueue(label: "com.shelly.audit", qos: .utility)
    private let dateFormatter: ISO8601DateFormatter

    private var logPath: URL {
        ConfigManager.shared.auditLogPath
    }

    private init() {
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    // MARK: - Configuration

    func configure(enabled: Bool, retentionDays: Int) {
        self.isEnabled = enabled
        self.retentionDays = retentionDays

        if enabled {
            rotateLogIfNeeded()
        }
    }

    // MARK: - Logging

    /// Log a command input from the terminal
    func logCommand(_ command: String, clientId: String, deviceName: String) {
        guard isEnabled, !command.isEmpty else { return }

        let entry = AuditEntry(
            timestamp: dateFormatter.string(from: Date()),
            clientId: clientId,
            deviceName: deviceName,
            type: "command",
            data: command.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        appendEntry(entry)
    }

    /// Log terminal output (truncated)
    func logOutput(_ output: String, clientId: String, deviceName: String) {
        guard isEnabled else { return }

        // Only log first 500 chars of output to avoid huge logs
        let truncated = String(output.prefix(500))
        if truncated.isEmpty { return }

        let entry = AuditEntry(
            timestamp: dateFormatter.string(from: Date()),
            clientId: clientId,
            deviceName: deviceName,
            type: "output",
            data: truncated
        )

        appendEntry(entry)
    }

    /// Log a connection event
    func logConnection(clientId: String, deviceName: String, event: String) {
        guard isEnabled else { return }

        let entry = AuditEntry(
            timestamp: dateFormatter.string(from: Date()),
            clientId: clientId,
            deviceName: deviceName,
            type: "connection",
            data: event
        )

        appendEntry(entry)
    }

    // MARK: - Private

    private func appendEntry(_ entry: AuditEntry) {
        logQueue.async { [weak self] in
            guard let self else { return }

            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(entry)

                if FileManager.default.fileExists(atPath: self.logPath.path) {
                    // Append to existing file
                    let handle = try FileHandle(forWritingTo: self.logPath)
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.write("\n".data(using: .utf8)!)
                    handle.closeFile()
                } else {
                    // Create new file
                    var contents = data
                    contents.append("\n".data(using: .utf8)!)
                    try contents.write(to: self.logPath)

                    // Set secure permissions
                    try FileManager.default.setAttributes(
                        [.posixPermissions: 0o600],
                        ofItemAtPath: self.logPath.path
                    )
                }
            } catch {
                print("Failed to write audit log: \(error)")
            }
        }
    }

    private func rotateLogIfNeeded() {
        logQueue.async { [weak self] in
            guard let self else { return }

            let fm = FileManager.default
            guard fm.fileExists(atPath: self.logPath.path) else { return }

            do {
                let attrs = try fm.attributesOfItem(atPath: self.logPath.path)
                guard let modDate = attrs[.modificationDate] as? Date else { return }

                let daysSinceModified = Calendar.current.dateComponents(
                    [.day],
                    from: modDate,
                    to: Date()
                ).day ?? 0

                // If file is older than retention period, archive it
                if daysSinceModified > self.retentionDays {
                    let archivePath = self.logPath.deletingLastPathComponent()
                        .appendingPathComponent("audit-\(self.dateFormatter.string(from: modDate)).log")
                    try fm.moveItem(at: self.logPath, to: archivePath)
                }

                // Clean up old archives
                self.cleanupOldArchives()
            } catch {
                print("Failed to rotate audit log: \(error)")
            }
        }
    }

    private func cleanupOldArchives() {
        let fm = FileManager.default
        let logDir = logPath.deletingLastPathComponent()

        do {
            let files = try fm.contentsOfDirectory(atPath: logDir.path)
            let archiveFiles = files.filter { $0.hasPrefix("audit-") && $0.hasSuffix(".log") }

            for archive in archiveFiles {
                let archivePath = logDir.appendingPathComponent(archive)
                let attrs = try fm.attributesOfItem(atPath: archivePath.path)
                guard let modDate = attrs[.modificationDate] as? Date else { continue }

                let daysSinceModified = Calendar.current.dateComponents(
                    [.day],
                    from: modDate,
                    to: Date()
                ).day ?? 0

                // Delete archives older than retention period
                if daysSinceModified > retentionDays {
                    try fm.removeItem(at: archivePath)
                }
            }
        } catch {
            print("Failed to cleanup old archives: \(error)")
        }
    }
}

// MARK: - Audit Entry

struct AuditEntry: Codable {
    let timestamp: String
    let clientId: String
    let deviceName: String
    let type: String  // "command", "output", "connection"
    let data: String
}
