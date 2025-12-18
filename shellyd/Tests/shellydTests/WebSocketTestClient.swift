//
//  WebSocketTestClient.swift
//  shellydTests
//
//  WebSocket client for testing server connections
//

import Foundation
import NIO
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import NIOSSL
import Crypto

final class WebSocketTestClient: @unchecked Sendable {
    private let group: EventLoopGroup
    private var channel: Channel?
    private let handler: ClientHandler
    private let lock = NSLock()

    var receivedMessages: [ShellyMessage] {
        lock.lock()
        defer { lock.unlock() }
        return handler.receivedMessages
    }

    var isConnected: Bool {
        channel?.isActive ?? false
    }

    var lastError: Error? {
        handler.lastError
    }

    init() {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.handler = ClientHandler()
    }

    deinit {
        try? group.syncShutdownGracefully()
    }

    // MARK: - Connection

    func connect(host: String, port: Int, useTLS: Bool = false) async throws {
        let handlerRef = handler

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        if useTLS {
            var tlsConfig = TLSConfiguration.makeClientConfiguration()
            tlsConfig.certificateVerification = .none
            let sslContext = try NIOSSLContext(configuration: tlsConfig)

            channel = try await bootstrap.channelInitializer { channel in
                let sslHandler = try! NIOSSLClientHandler(context: sslContext, serverHostname: host)
                return channel.pipeline.addHandler(sslHandler).flatMap {
                    channel.pipeline.addHTTPClientHandlers().flatMap {
                        channel.pipeline.addHandler(HTTPUpgradeHandler(host: host, handler: handlerRef))
                    }
                }
            }.connect(host: host, port: port).get()
        } else {
            channel = try await bootstrap.channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(HTTPUpgradeHandler(host: host, handler: handlerRef))
                }
            }.connect(host: host, port: port).get()
        }
    }

    func disconnect() async throws {
        try await channel?.close()
        channel = nil
    }

    // MARK: - Messaging

    func send(_ message: ShellyMessage) throws {
        guard let channel = channel else {
            throw TestError.notConnected
        }

        let data = try JSONEncoder().encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TestError.encodingFailed
        }

        var buffer = channel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)

        let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
        channel.writeAndFlush(frame, promise: nil)
    }

    func sendHello(publicKey: String, deviceName: String) throws {
        let payload = HelloPayload(
            clientVersion: "1.0.0-test",
            publicKey: publicKey,
            deviceName: deviceName
        )
        let message = try ShellyMessage(type: .hello, payload: payload)
        try send(message)
    }

    func sendAuthResponse(signature: Data) throws {
        let payload = AuthResponsePayload(signature: signature)
        let message = try ShellyMessage(type: .authResponse, payload: payload)
        try send(message)
    }

    func sendTerminalInput(_ text: String) throws {
        let payload = TerminalInputPayload(string: text)
        let message = try ShellyMessage(type: .terminalInput, payload: payload)
        try send(message)
    }

    func sendResize(rows: Int, cols: Int) throws {
        let payload = TerminalResizePayload(rows: rows, cols: cols)
        let message = try ShellyMessage(type: .terminalResize, payload: payload)
        try send(message)
    }

    func sendPairRequest(publicKey: String, deviceName: String) throws {
        let payload = PairRequestPayload(publicKey: publicKey, deviceName: deviceName)
        let message = try ShellyMessage(type: .pairRequest, payload: payload)
        try send(message)
    }

    func sendPairVerify(code: String) throws {
        let payload = PairVerifyPayload(code: code)
        let message = try ShellyMessage(type: .pairVerify, payload: payload)
        try send(message)
    }

    // MARK: - Helpers

    func waitForMessage(of type: ShellyMessageType, timeout: TimeInterval = 5) async throws -> ShellyMessage {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            lock.lock()
            let found = handler.receivedMessages.first(where: { $0.type == type })
            lock.unlock()
            if let message = found {
                return message
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw TestError.timeout("Waiting for \(type) message")
    }

    func clearMessages() {
        lock.lock()
        handler.receivedMessages.removeAll()
        lock.unlock()
    }
}

// MARK: - WebSocket Frame Handler

final class ClientHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    var receivedMessages: [ShellyMessage] = []
    var lastError: Error?

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        switch frame.opcode {
        case .text:
            var data = frame.data
            if let text = data.readString(length: data.readableBytes),
               let jsonData = text.data(using: .utf8),
               let message = try? JSONDecoder().decode(ShellyMessage.self, from: jsonData) {
                receivedMessages.append(message)
            }

        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: frame.data)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)

        default:
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        lastError = error
        context.close(promise: nil)
    }
}

// MARK: - HTTP Upgrade Handler

final class HTTPUpgradeHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private let host: String
    private let handler: ClientHandler
    private var upgradeCompleted = false

    init(host: String, handler: ClientHandler) {
        self.host = host
        self.handler = handler
    }

    func channelActive(context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        headers.add(name: "Host", value: host)
        headers.add(name: "Upgrade", value: "websocket")
        headers.add(name: "Connection", value: "Upgrade")
        headers.add(name: "Sec-WebSocket-Key", value: generateWebSocketKey())
        headers.add(name: "Sec-WebSocket-Version", value: "13")

        let requestHead = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/", headers: headers)
        context.write(wrapOutboundOut(.head(requestHead)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !upgradeCompleted else { return }

        let response = unwrapInboundIn(data)

        switch response {
        case .head(let head):
            if head.status == .switchingProtocols {
                upgradeCompleted = true
                upgradeToWebSocket(context: context)
            }
        default:
            break
        }
    }

    private func upgradeToWebSocket(context: ChannelHandlerContext) {
        let pipeline = context.pipeline

        _ = pipeline.context(handlerType: ByteToMessageHandler<HTTPResponseDecoder>.self).flatMap { httpContext in
            pipeline.removeHandler(context: httpContext)
        }.flatMap {
            pipeline.context(handlerType: HTTPRequestEncoder.self).flatMap { encoderContext in
                pipeline.removeHandler(context: encoderContext)
            }
        }.flatMap {
            pipeline.removeHandler(self)
        }.flatMap {
            pipeline.addHandler(ByteToMessageHandler(WebSocketFrameDecoder()))
        }.flatMap {
            pipeline.addHandler(WebSocketFrameEncoder())
        }.flatMap {
            pipeline.addHandler(self.handler)
        }
    }

    private func generateWebSocketKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
}

// MARK: - Test Errors

enum TestError: LocalizedError {
    case notConnected
    case encodingFailed
    case timeout(String)
    case serverNotRunning
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .notConnected: return "WebSocket not connected"
        case .encodingFailed: return "Message encoding failed"
        case .timeout(let what): return "Timeout: \(what)"
        case .serverNotRunning: return "Server is not running"
        case .authenticationFailed: return "Authentication failed"
        }
    }
}
