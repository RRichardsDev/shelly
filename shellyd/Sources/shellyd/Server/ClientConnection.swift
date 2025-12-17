//
//  ClientConnection.swift
//  shellyd
//
//  Individual client connection state and handling
//

import Foundation
import NIO
import NIOWebSocket
import Crypto

final class ClientConnection {
    private let channel: Channel
    private let configuration: ServerConfiguration

    // Authentication state
    private var isAuthenticated = false
    private var authChallenge: Data?
    private var clientPublicKey: String?
    private var sessionToken: String?

    // Pairing state
    private var pendingPairingCode: String?
    private var pendingPairingDeviceName: String?
    private var pendingPairingPublicKey: String?

    // Shell session
    private var shellSession: ShellSession?

    init(channel: Channel, configuration: ServerConfiguration) {
        self.channel = channel
        self.configuration = configuration
    }

    func cleanup() {
        shellSession?.stop()
        shellSession = nil
    }

    // MARK: - Message Handling

    func handleMessage(_ text: String, context: ChannelHandlerContext) {
        guard let data = text.data(using: .utf8) else {
            print("❌ Failed to convert text to UTF8 data")
            return
        }

        // Always log incoming messages for debugging
        print("📥 Received message (\(data.count) bytes): \(text.prefix(500))...")
        fflush(stdout)

        do {
            let message = try JSONDecoder().decode(ShellyMessage.self, from: data)
            print("📥 Parsed message type: \(message.type)")
            fflush(stdout)
            handleShellyMessage(message, context: context)
        } catch let decodingError as DecodingError {
            print("❌ DecodingError: \(decodingError)")
            switch decodingError {
            case .keyNotFound(let key, let context):
                print("   Key not found: \(key.stringValue), path: \(context.codingPath)")
            case .typeMismatch(let type, let context):
                print("   Type mismatch: expected \(type), path: \(context.codingPath)")
            case .valueNotFound(let type, let context):
                print("   Value not found: expected \(type), path: \(context.codingPath)")
            case .dataCorrupted(let context):
                print("   Data corrupted: \(context.debugDescription), path: \(context.codingPath)")
            @unknown default:
                print("   Unknown decoding error")
            }
            fflush(stdout)
            sendError(code: "PARSE_ERROR", message: "Invalid message format: \(decodingError.localizedDescription)", context: context)
        } catch {
            print("❌ Failed to parse message: \(error)")
            fflush(stdout)
            sendError(code: "PARSE_ERROR", message: "Invalid message format: \(error.localizedDescription)", context: context)
        }
    }

    func handleBinaryData(_ data: Data, context: ChannelHandlerContext) {
        // Binary data is typically terminal input
        if isAuthenticated, let session = shellSession {
            session.write(data)
        }
    }

    private func handleShellyMessage(_ message: ShellyMessage, context: ChannelHandlerContext) {
        switch message.type {
        case .pairRequest:
            handlePairRequest(message, context: context)

        case .pairVerify:
            handlePairVerify(message, context: context)

        case .hello:
            handleHello(message, context: context)

        case .authResponse:
            handleAuthResponse(message, context: context)

        case .terminalInput:
            handleTerminalInput(message, context: context)

        case .terminalResize:
            handleTerminalResize(message, context: context)

        case .sudoConfirmResponse:
            handleSudoConfirmResponse(message, context: context)

        case .sudoPassword:
            handleSudoPassword(message, context: context)

        case .ping:
            sendPong(context: context)

        case .disconnect:
            cleanup()
            context.close(promise: nil)

        default:
            if configuration.verbose {
                print("Unhandled message type: \(message.type)")
            }
        }
    }

    // MARK: - Pairing Flow

    private func handlePairRequest(_ message: ShellyMessage, context: ChannelHandlerContext) {
        print("🔐 Handling pair request...")
        do {
            let request = try JSONDecoder().decode(PairRequestPayload.self, from: message.payload)
            print("🔐 Pair request from: \(request.deviceName)")

            // Generate a 6-digit code
            let code = String(format: "%06d", Int.random(in: 0...999999))

            // Store pairing state
            pendingPairingCode = code
            pendingPairingDeviceName = request.deviceName
            pendingPairingPublicKey = request.publicKey

            // Get Mac name
            let macName = Host.current().localizedName ?? "Mac"

            // Show macOS dialog with the code
            showPairingDialog(deviceName: request.deviceName, code: code)

            // Send challenge to iPhone
            let challenge = PairChallengePayload(
                macName: macName,
                message: "Enter the code shown on \(macName)"
            )
            sendMessage(type: .pairChallenge, payload: challenge, context: context)

            print("📱 Sent pairing challenge, code: \(code)")

        } catch {
            print("❌ Failed to parse pair request: \(error)")
            sendPairResponse(success: false, message: "Invalid pairing request", context: context)
        }
    }

    private func handlePairVerify(_ message: ShellyMessage, context: ChannelHandlerContext) {
        print("🔐 Handling pair verify...")
        do {
            let verify = try JSONDecoder().decode(PairVerifyPayload.self, from: message.payload)

            guard let expectedCode = pendingPairingCode,
                  let deviceName = pendingPairingDeviceName,
                  let publicKey = pendingPairingPublicKey else {
                sendPairResponse(success: false, message: "No pending pairing request", context: context)
                return
            }

            // Verify the code
            guard verify.code == expectedCode else {
                print("❌ Pairing failed: invalid code")
                sendPairResponse(success: false, message: "Invalid code. Please try again.", context: context)
                // Clear state
                clearPairingState()
                return
            }

            // Add the public key to authorized keys
            do {
                try PublicKeyStore.shared.addAuthorizedKey(publicKey, name: deviceName)
                print("✅ Paired successfully with: \(deviceName)")
                print("   Key added to authorized_keys")

                sendPairResponse(success: true, message: "Paired successfully! You can now connect.", context: context)

                // Close the pairing UI window
                let killTask = Process()
                killTask.launchPath = "/usr/bin/pkill"
                killTask.arguments = ["-9", "ShellyPairingUI"]
                try? killTask.run()

                // Clear state
                clearPairingState()
            } catch {
                print("❌ Failed to save key: \(error)")
                sendPairResponse(success: false, message: "Failed to save key: \(error.localizedDescription)", context: context)
                clearPairingState()
            }

        } catch {
            sendPairResponse(success: false, message: "Invalid verify request", context: context)
        }
    }

    private func clearPairingState() {
        pendingPairingCode = nil
        pendingPairingDeviceName = nil
        pendingPairingPublicKey = nil
    }

    private func showPairingDialog(deviceName: String, code: String) {
        DispatchQueue.global().async {
            // Try to use the pairing UI app bundle first
            let appPaths = [
                "/Applications/ShellyPairingUI.app",
                FileManager.default.homeDirectoryForCurrentUser.path + "/.shellyd/ShellyPairingUI.app"
            ]

            var appPath: String?
            for path in appPaths {
                if FileManager.default.fileExists(atPath: path) {
                    appPath = path
                    break
                }
            }

            if let path = appPath {
                // Kill any existing pairing UI first
                let killTask = Process()
                killTask.launchPath = "/usr/bin/pkill"
                killTask.arguments = ["-9", "ShellyPairingUI"]
                try? killTask.run()
                killTask.waitUntilExit()

                // Use 'open -n' to launch a NEW instance of the app bundle
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = ["-n", path, "--args", deviceName, code]
                try? task.run()

                // Use AppleScript to force the app to front after a short delay
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    let script = """
                    tell application "ShellyPairingUI" to activate
                    tell application "System Events"
                        set frontmost of process "ShellyPairingUI" to true
                        tell process "ShellyPairingUI"
                            set frontmost to true
                            perform action "AXRaise" of window 1
                        end tell
                    end tell
                    """
                    let appleScript = Process()
                    appleScript.launchPath = "/usr/bin/osascript"
                    appleScript.arguments = ["-e", script]
                    try? appleScript.run()
                }
            } else {
                // Fallback to AppleScript dialog
                let formattedCode = code.prefix(3) + " " + code.suffix(3)
                let script = "display dialog \"\(deviceName) wants to pair with this Mac.\n\nEnter this code on your iPhone:\n\n\(formattedCode)\" with title \"Shelly Pairing Request\" buttons {\"OK\"} default button \"OK\" with icon note"

                let task = Process()
                task.launchPath = "/usr/bin/osascript"
                task.arguments = ["-e", script]
                try? task.run()
            }
        }
    }

    private func sendPairResponse(success: Bool, message: String?, context: ChannelHandlerContext) {
        let payload = PairResponsePayload(success: success, message: message)
        sendMessage(type: .pairResponse, payload: payload, context: context)
    }

    // MARK: - Authentication Flow

    private func handleHello(_ message: ShellyMessage, context: ChannelHandlerContext) {
        do {
            let hello = try JSONDecoder().decode(HelloPayload.self, from: message.payload)

            // Check if public key is authorized
            guard PublicKeyStore.shared.isAuthorized(publicKey: hello.publicKey) else {
                if configuration.verbose {
                    print("Client rejected: public key not authorized")
                    print("  Device: \(hello.deviceName)")
                    print("  Key: \(hello.publicKey.prefix(50))...")
                }
                sendAuthResult(success: false, message: "Public key not authorized", context: context)
                return
            }

            // Store client public key
            clientPublicKey = hello.publicKey

            // Generate challenge
            var challengeBytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, challengeBytes.count, &challengeBytes)
            authChallenge = Data(challengeBytes)

            // Send challenge
            let challengePayload = AuthChallengePayload(
                challenge: authChallenge!,
                serverVersion: "1.0.0",
                serverPublicKey: "" // TODO: Server public key for mutual auth
            )

            sendMessage(type: .authChallenge, payload: challengePayload, context: context)

            if configuration.verbose {
                print("Sent auth challenge to client: \(hello.deviceName)")
            }

        } catch {
            sendError(code: "HELLO_ERROR", message: "Invalid hello payload", context: context)
        }
    }

    private func handleAuthResponse(_ message: ShellyMessage, context: ChannelHandlerContext) {
        do {
            let response = try JSONDecoder().decode(AuthResponsePayload.self, from: message.payload)

            guard let challenge = authChallenge,
                  let publicKeyString = clientPublicKey else {
                sendAuthResult(success: false, message: "No pending challenge", context: context)
                return
            }

            // Verify signature
            let isValid = verifySignature(
                signature: response.signature,
                challenge: challenge,
                publicKey: publicKeyString
            )

            if isValid {
                isAuthenticated = true
                sessionToken = UUID().uuidString

                sendAuthResult(success: true, message: "Authentication successful", sessionToken: sessionToken, context: context)

                // Start shell session
                startShellSession(context: context)

                if configuration.verbose {
                    print("Client authenticated successfully")
                }
            } else {
                sendAuthResult(success: false, message: "Invalid signature", context: context)

                if configuration.verbose {
                    print("Client authentication failed: invalid signature")
                }
            }

        } catch {
            sendAuthResult(success: false, message: "Invalid auth response", context: context)
        }
    }

    private func verifySignature(signature: Data, challenge: Data, publicKey: String) -> Bool {
        // Parse the public key
        let parts = publicKey.split(separator: " ")
        guard parts.count >= 2,
              parts[0] == "ssh-ed25519",
              let keyBlob = Data(base64Encoded: String(parts[1])) else {
            return false
        }

        // Extract raw public key from SSH format
        // SSH format: [4-byte length][key-type][4-byte length][raw-key]
        let bytes = [UInt8](keyBlob)
        var offset = 0

        // Helper to read big-endian UInt32 safely
        func readUInt32() -> Int? {
            guard offset + 4 <= bytes.count else { return nil }
            let value = (UInt32(bytes[offset]) << 24) |
                        (UInt32(bytes[offset + 1]) << 16) |
                        (UInt32(bytes[offset + 2]) << 8) |
                        UInt32(bytes[offset + 3])
            offset += 4
            return Int(value)
        }

        // Skip key type
        guard let keyTypeLen = readUInt32() else { return false }
        offset += keyTypeLen

        // Get raw key length
        guard let rawKeyLen = readUInt32() else { return false }

        guard offset + rawKeyLen <= bytes.count else { return false }
        let rawKeyData = Data(bytes[offset..<(offset + rawKeyLen)])

        // Verify using CryptoKit
        do {
            let pubKey = try Curve25519.Signing.PublicKey(rawRepresentation: rawKeyData)
            return pubKey.isValidSignature(signature, for: challenge)
        } catch {
            if configuration.verbose {
                print("Signature verification error: \(error)")
            }
            return false
        }
    }

    // MARK: - Terminal Operations

    private func startShellSession(context: ChannelHandlerContext) {
        do {
            let config = try ConfigManager.shared.loadConfig()
            let eventLoop = context.eventLoop

            shellSession = ShellSession(
                shell: config.shell,
                onOutput: { [weak self] data in
                    // Must dispatch to event loop since shell output comes from different queue
                    eventLoop.execute {
                        self?.sendTerminalOutput(data, context: context)
                    }
                },
                onSudoPrompt: { [weak self] command in
                    eventLoop.execute {
                        self?.sendSudoConfirmRequest(command: command, context: context)
                    }
                }
            )

            try shellSession?.start()

            if configuration.verbose {
                print("Shell session started")
            }

        } catch {
            sendError(code: "SHELL_ERROR", message: "Failed to start shell: \(error)", context: context)
        }
    }

    private func handleTerminalInput(_ message: ShellyMessage, context: ChannelHandlerContext) {
        guard isAuthenticated else {
            sendError(code: "NOT_AUTHENTICATED", message: "Not authenticated", context: context)
            return
        }

        do {
            let input = try JSONDecoder().decode(TerminalInputPayload.self, from: message.payload)
            shellSession?.write(input.data)
        } catch {
            // Try raw data
            shellSession?.write(message.payload)
        }
    }

    private func handleTerminalResize(_ message: ShellyMessage, context: ChannelHandlerContext) {
        guard isAuthenticated else { return }

        do {
            let resize = try JSONDecoder().decode(TerminalResizePayload.self, from: message.payload)
            shellSession?.resize(rows: resize.rows, cols: resize.cols)
        } catch {
            if configuration.verbose {
                print("Failed to parse resize: \(error)")
            }
        }
    }

    // MARK: - Sudo Handling

    private func handleSudoConfirmResponse(_ message: ShellyMessage, context: ChannelHandlerContext) {
        guard isAuthenticated else { return }

        do {
            let response = try JSONDecoder().decode(SudoConfirmResponsePayload.self, from: message.payload)

            if response.approved {
                // Wait for password
                if configuration.verbose {
                    print("Sudo approved, waiting for password")
                }
            } else {
                // Send ctrl+c to cancel sudo
                shellSession?.write(Data([0x03])) // Ctrl+C
            }
        } catch {
            if configuration.verbose {
                print("Failed to parse sudo response: \(error)")
            }
        }
    }

    private func handleSudoPassword(_ message: ShellyMessage, context: ChannelHandlerContext) {
        guard isAuthenticated else { return }

        do {
            let passwordPayload = try JSONDecoder().decode(SudoPasswordPayload.self, from: message.payload)

            // Send password to shell followed by newline
            if let passwordData = (passwordPayload.password + "\n").data(using: .utf8) {
                shellSession?.write(passwordData)
            }

            if configuration.verbose {
                print("Sudo password sent to shell")
            }
        } catch {
            if configuration.verbose {
                print("Failed to parse sudo password: \(error)")
            }
        }
    }

    // MARK: - Send Messages

    private func sendMessage<T: Encodable>(type: ShellyMessageType, payload: T, context: ChannelHandlerContext) {
        do {
            let payloadData = try JSONEncoder().encode(payload)
            let message = ShellyMessage(type: type, payload: payloadData)
            let messageData = try JSONEncoder().encode(message)

            if let text = String(data: messageData, encoding: .utf8) {
                var buffer = context.channel.allocator.buffer(capacity: text.utf8.count)
                buffer.writeString(text)

                let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
                context.writeAndFlush(NIOAny(frame), promise: nil)
            }
        } catch {
            if configuration.verbose {
                print("Failed to send message: \(error)")
            }
        }
    }

    private func sendTerminalOutput(_ data: Data, context: ChannelHandlerContext) {
        print("📤 Sending terminal output (\(data.count) bytes)")
        if let text = String(data: data, encoding: .utf8) {
            print("   Content: \(text.prefix(100))")
        }
        fflush(stdout)
        let payload = TerminalOutputPayload(data: data)
        sendMessage(type: .terminalOutput, payload: payload, context: context)
    }

    private func sendAuthResult(success: Bool, message: String, sessionToken: String? = nil, context: ChannelHandlerContext) {
        let payload = AuthResultPayload(success: success, message: message, sessionToken: sessionToken)
        sendMessage(type: .authResult, payload: payload, context: context)
    }

    private func sendSudoConfirmRequest(command: String, context: ChannelHandlerContext) {
        let payload = SudoConfirmRequestPayload(requestId: UUID(), command: command)
        sendMessage(type: .sudoConfirmRequest, payload: payload, context: context)
    }

    private func sendPong(context: ChannelHandlerContext) {
        sendMessage(type: .pong, payload: EmptyPayload(), context: context)
    }

    private func sendError(code: String, message: String, context: ChannelHandlerContext) {
        let payload = ErrorPayload(code: code, message: message, recoverable: true)
        sendMessage(type: .error, payload: payload, context: context)
    }
}
