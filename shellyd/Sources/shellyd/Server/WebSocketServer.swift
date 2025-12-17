//
//  WebSocketServer.swift
//  shellyd
//
//  WebSocket server using SwiftNIO
//

import Foundation
import NIO
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket

final class WebSocketServer {
    private let configuration: ServerConfiguration
    private var channel: Channel?
    private let group: MultiThreadedEventLoopGroup

    init(configuration: ServerConfiguration) {
        self.configuration = configuration
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }

    func start() async throws {
        // Write PID file
        try ConfigManager.shared.writePIDFile()

        // Setup signal handling
        setupSignalHandlers()

        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { channel, head in
                channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { channel, head in
                channel.pipeline.addHandler(WebSocketFrameHandler(configuration: self.configuration))
            }
        )

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let httpHandler = HTTPHandler(configuration: self.configuration)
                let config: NIOHTTPServerUpgradeConfiguration = (
                    upgraders: [upgrader],
                    completionHandler: { _ in
                        channel.pipeline.removeHandler(httpHandler, promise: nil)
                    }
                )
                return channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: config).flatMap {
                    channel.pipeline.addHandler(httpHandler)
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)

        do {
            channel = try await bootstrap.bind(host: configuration.host, port: configuration.port).get()

            // Keep running until channel is closed
            try await channel?.closeFuture.get()
        } catch {
            print("Failed to start server: \(error)")
            throw error
        }
    }

    func stop() {
        print("\nShutting down...")

        channel?.close(promise: nil)

        do {
            try group.syncShutdownGracefully()
            try ConfigManager.shared.removePIDFile()
        } catch {
            print("Error during shutdown: \(error)")
        }
    }

    private func setupSignalHandlers() {
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        signalSource.setEventHandler { [weak self] in
            self?.stop()
            exit(0)
        }
        signalSource.resume()

        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signal(SIGTERM, SIG_IGN)
        termSource.setEventHandler { [weak self] in
            self?.stop()
            exit(0)
        }
        termSource.resume()
    }
}

// MARK: - HTTP Handler (for non-WebSocket requests)

final class HTTPHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let configuration: ServerConfiguration

    init(configuration: ServerConfiguration) {
        self.configuration = configuration
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = unwrapInboundIn(data)

        switch reqPart {
        case .head(let head):
            // Return simple status page for non-WebSocket requests
            handleHTTPRequest(context: context, head: head)
        case .body:
            break
        case .end:
            break
        }
    }

    private func handleHTTPRequest(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let body = """
        <!DOCTYPE html>
        <html>
        <head><title>Shelly Daemon</title></head>
        <body>
        <h1>Shelly Daemon</h1>
        <p>WebSocket server is running.</p>
        <p>Connect using the Shelly iOS app.</p>
        </body>
        </html>
        """

        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/html")
        headers.add(name: "Content-Length", value: String(body.utf8.count))

        let response = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(response)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: body.utf8.count)
        buffer.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)

        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}

// MARK: - WebSocket Frame Handler

final class WebSocketFrameHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let configuration: ServerConfiguration
    private var clientConnection: ClientConnection?

    init(configuration: ServerConfiguration) {
        self.configuration = configuration
    }

    func handlerAdded(context: ChannelHandlerContext) {
        clientConnection = ClientConnection(channel: context.channel, configuration: configuration)

        if configuration.verbose {
            print("Client connected: \(context.channel.remoteAddress?.description ?? "unknown")")
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        clientConnection?.cleanup()
        clientConnection = nil

        if configuration.verbose {
            print("Client disconnected")
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        switch frame.opcode {
        case .text:
            handleTextFrame(context: context, frame: frame)

        case .binary:
            handleBinaryFrame(context: context, frame: frame)

        case .ping:
            // Respond with pong
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: frame.data)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)

        case .pong:
            // Ignore pong responses
            break

        case .connectionClose:
            handleClose(context: context, frame: frame)

        default:
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("WebSocket error: \(error)")
        context.close(promise: nil)
    }

    private func handleTextFrame(context: ChannelHandlerContext, frame: WebSocketFrame) {
        if configuration.verbose {
            print("Frame info: fin=\(frame.fin), opcode=\(frame.opcode), maskKey=\(String(describing: frame.maskKey)), dataLength=\(frame.data.readableBytes)")
            fflush(stdout)
        }

        // NIOWebSocket should auto-unmask, but let's handle it explicitly if needed
        var frameData = frame.unmaskedData
        guard let text = frameData.readString(length: frameData.readableBytes) else {
            print("Failed to read string from frame data")
            fflush(stdout)
            return
        }

        if configuration.verbose {
            print("Received: \(text.prefix(100))...")
            fflush(stdout)
        }

        // Parse and handle message
        clientConnection?.handleMessage(text, context: context)
    }

    private func handleBinaryFrame(context: ChannelHandlerContext, frame: WebSocketFrame) {
        var data = frame.data
        guard let bytes = data.readBytes(length: data.readableBytes) else {
            return
        }

        clientConnection?.handleBinaryData(Data(bytes), context: context)
    }

    private func handleClose(context: ChannelHandlerContext, frame: WebSocketFrame) {
        // Echo back close frame and close connection
        let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: frame.data)
        context.writeAndFlush(wrapOutboundOut(closeFrame)).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}
