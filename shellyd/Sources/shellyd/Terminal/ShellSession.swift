//
//  ShellSession.swift
//  shellyd
//
//  Shell session management with PTY
//

import Foundation

final class ShellSession {
    private let shell: String
    private let onOutput: (Data) -> Void
    private let onSudoPrompt: (String) -> Void

    // Audit logging
    private let clientId: String
    private let deviceName: String
    private let auditLogger = AuditLogger.shared

    private var masterFd: Int32 = -1
    private var slaveFd: Int32 = -1
    private var childPid: pid_t = 0
    private var readSource: DispatchSourceRead?

    private var isRunning = false

    // Sudo detection and command tracking
    private var outputBuffer = Data()
    private var lastCommand = ""
    private var inputBuffer = ""  // Buffer for tracking typed commands

    init(
        shell: String,
        clientId: String,
        deviceName: String,
        onOutput: @escaping (Data) -> Void,
        onSudoPrompt: @escaping (String) -> Void
    ) {
        self.shell = shell
        self.clientId = clientId
        self.deviceName = deviceName
        self.onOutput = onOutput
        self.onSudoPrompt = onSudoPrompt
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    func start() throws {
        guard !isRunning else { return }

        // Create PTY
        var winSize = winsize(
            ws_row: UInt16(24),
            ws_col: UInt16(80),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        childPid = forkpty(&masterFd, nil, nil, &winSize)

        if childPid < 0 {
            throw ShellError.forkFailed
        }

        if childPid == 0 {
            // Child process
            setupChildEnvironment()

            // Execute shell
            let shellArgs = [shell, "-l"]
            let cArgs = shellArgs.map { strdup($0) } + [nil]
            execv(shell, cArgs)

            // If exec fails
            _exit(1)
        }

        // Parent process
        isRunning = true
        startReadingOutput()
    }

    func stop() {
        guard isRunning else { return }

        isRunning = false
        readSource?.cancel()
        readSource = nil

        if masterFd >= 0 {
            close(masterFd)
            masterFd = -1
        }

        if childPid > 0 {
            kill(childPid, SIGTERM)

            // Wait briefly, then force kill
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [childPid] in
                var status: Int32 = 0
                let result = waitpid(childPid, &status, WNOHANG)
                if result == 0 {
                    kill(childPid, SIGKILL)
                    waitpid(childPid, &status, 0)
                }
            }

            childPid = 0
        }
    }

    // MARK: - I/O

    func write(_ data: Data) {
        guard isRunning, masterFd >= 0 else { return }

        // Track commands for sudo detection and audit logging
        if let text = String(data: data, encoding: .utf8) {
            if text.contains("\r") || text.contains("\n") {
                // Command submitted - log it
                let command = inputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !command.isEmpty {
                    auditLogger.logCommand(command, clientId: clientId, deviceName: deviceName)
                }
                lastCommand = command
                inputBuffer = ""
            } else if text == "\u{7F}" || text == "\u{08}" {
                // Backspace - remove last character from buffer
                if !inputBuffer.isEmpty {
                    inputBuffer.removeLast()
                }
            } else if text == "\u{03}" {
                // Ctrl+C - clear buffer
                inputBuffer = ""
            } else {
                // Regular character - add to buffer
                inputBuffer += text
            }
        }

        data.withUnsafeBytes { ptr in
            if let baseAddress = ptr.baseAddress {
                _ = Darwin.write(masterFd, baseAddress, data.count)
            }
        }
    }

    func resize(rows: Int, cols: Int) {
        guard isRunning, masterFd >= 0 else { return }

        var winSize = winsize(
            ws_row: UInt16(rows),
            ws_col: UInt16(cols),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        _ = ioctl(masterFd, TIOCSWINSZ, &winSize)
    }

    // MARK: - Private

    private func setupChildEnvironment() {
        // Set up environment variables
        setenv("TERM", "xterm-256color", 1)
        setenv("COLORTERM", "truecolor", 1)
        setenv("LANG", "en_US.UTF-8", 1)
        setenv("LC_ALL", "en_US.UTF-8", 1)

        // Change to home directory
        if let home = getenv("HOME") {
            chdir(home)
        }
    }

    private func startReadingOutput() {
        readSource = DispatchSource.makeReadSource(fileDescriptor: masterFd, queue: .global())

        readSource?.setEventHandler { [weak self] in
            self?.readOutput()
        }

        readSource?.setCancelHandler { [weak self] in
            self?.isRunning = false
        }

        readSource?.resume()
    }

    private func readOutput() {
        guard isRunning, masterFd >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(masterFd, &buffer, buffer.count)

        if bytesRead > 0 {
            let data = Data(buffer[0..<bytesRead])

            // Check for sudo prompt
            if detectSudoPrompt(in: data) {
                // Request confirmation from iOS
                onSudoPrompt(lastCommand)
            }

            // Forward output
            onOutput(data)

        } else if bytesRead == 0 {
            // EOF - shell exited
            stop()
        } else if errno != EAGAIN && errno != EINTR {
            // Error
            stop()
        }
    }

    private func detectSudoPrompt(in data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else {
            return false
        }

        // Common sudo prompt patterns
        let sudoPatterns = [
            "Password:",
            "[sudo] password for",
            "Password for",
        ]

        for pattern in sudoPatterns {
            if text.localizedCaseInsensitiveContains(pattern) {
                return true
            }
        }

        return false
    }
}

// MARK: - Errors

enum ShellError: LocalizedError {
    case forkFailed
    case ptyFailed

    var errorDescription: String? {
        switch self {
        case .forkFailed:
            return "Failed to fork process"
        case .ptyFailed:
            return "Failed to create PTY"
        }
    }
}
