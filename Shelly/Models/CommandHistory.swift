//
//  CommandHistory.swift
//  Shelly
//
//  SwiftData model for command history entries
//

import Foundation
import SwiftData

@Model
final class CommandHistory {
    @Attribute(.unique) var id: UUID
    var command: String
    var timestamp: Date
    var exitCode: Int?
    var duration: TimeInterval?
    var connection: HostConnection?

    init(
        id: UUID = UUID(),
        command: String,
        exitCode: Int? = nil,
        duration: TimeInterval? = nil,
        connection: HostConnection? = nil
    ) {
        self.id = id
        self.command = command
        self.timestamp = Date()
        self.exitCode = exitCode
        self.duration = duration
        self.connection = connection
    }
}
