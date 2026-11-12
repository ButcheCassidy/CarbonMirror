import CMCore
import CMCoreBridge
import Foundation
import Synchronization

/// Everything one session needs to know.
public struct SessionParameters: Sendable {
    public var serial: String
    public var wireless: Bool
    public var serverVersion: String
    public var codec: VideoCodec
    public var maxSize: Int
    public var maxFPS: Int
    public var bitRate: Int
    public var clipboardSync: Bool
    /// nil = plaintext (allowed only over USB with "Encrypt over USB" off).
    public var encryption: Encryption?

    public init(serial: String, wireless: Bool, serverVersion: String, codec: VideoCodec, maxSize: Int, maxFPS: Int, bitRate: Int,
                clipboardSync: Bool, encryption: Encryption?) {
        self.serial = serial
        self.wireless = wireless
        self.serverVersion = serverVersion
        self.codec = codec
        self.maxSize = maxSize
        self.maxFPS = maxFPS
        self.bitRate = bitRate
        self.clipboardSync = clipboardSync
        self.encryption = encryption
    }
}

/// Why a session ended.
public enum SessionEnd: Error, Equatable, Sendable {
    case stopped
    case deployFailed
    case serverFailed
    case connectFailed
    case connectionLost
    case identityChanged
    case tlsFailed(CoreStatus)
    case protocolViolation(CoreStatus)

    /// Failure class for the UI-state mapping (nil when the user stopped the session).
    public var failureClass: FailureClass? {
        switch self {
        case .stopped: nil
        case .deployFailed, .serverFailed, .connectFailed, .connectionLost, .protocolViolation: .connectionLost
        case .identityChanged: .pinMismatchKnownDevice
        case .tlsFailed: .tlsHandshakeFailed
        }
    }
}

/// Events for the UI.
public enum SessionEvent: Sendable {
    case connected(deviceName: String, codec: VideoCodecID, tlsSuite: UInt16?, tlsGroup: UInt16?)
    case cornerRadius(pixels: Int)
    case videoSize(width: Int, height: Int)
    case clipboard(String)
    case battery(level: Int, charging: Bool)
    case latency(milliseconds: Double)
    case throughput(fps: Double, megabitsPerSecond: Double)
    case ended(SessionEnd)
}

/// One mirroring session (spec 4/5/7): deploys the verified server, tunnels through `adb forward`, runs the
/// inner TLS (wireless always, USB optionally), checks the session secret, then streams video to the sink
/// and carries control messages both ways. Only allowlisted device messages are accepted; anything else
/// ends the session.
public actor MirrorSession {
    static let pinTimeout: Duration = .seconds(15)
    static let connectAttempts = 60
    static let connectRetryDelay: Duration = .milliseconds(100)
    static let videoReadChunk = 256 * 1024
    static let pingInterval: Duration = .seconds(2)
    static let secretLength = 32

    public nonisolated let events: AsyncStream<SessionEvent>
    private let eventSink: AsyncStream<SessionEvent>.Continuation
    private let parameters: SessionParameters
    private let link: any PhoneLink
    private let connector: StreamConnector
    private let video: any VideoSink
    private let control = Mutex<(any ByteStream)?>(nil)
    private var videoStream: (any ByteStream)?
    private var server: (any ServerHandle)?
    private var socket: String?
    private var tasks: [Task<Void, Never>] = []
    private var ended = false
    private let started = ContinuousClock.now

    public init(parameters: SessionParameters, link: any PhoneLink, connector: @escaping StreamConnector, video: any VideoSink) {
        self.parameters = parameters
        self.link = link
        self.connector = connector
        self.video = video
        (events, eventSink) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))
    }

    /// Sends one encoded control message (thread-safe, ordered, non-blocking).
    public nonisolated func send(_ message: [UInt8]) {
        control.withLock { $0?.send(message) }
    }

    // MARK: Lifecycle

    public func start() async throws(SessionEnd) {
        do throws(SessionEnd) {
            if parameters.wireless && parameters.encryption == nil {
                throw SessionEnd.tlsFailed(.tlsPolicyViolation)
            }
            do {
                try await link.prepare(serial: parameters.serial)
            } catch {
                throw SessionEnd.deployFailed
            }
            if let radius = await link.cornerRadius(serial: parameters.serial) {
                eventSink.yield(.cornerRadius(pixels: radius))
            }
            try await connect()
        } catch {
            ended = true
            await teardown()
            eventSink.finish()
            throw error
        }
        Log.info(.transport, "session started", ["wireless": parameters.wireless ? "yes" : "no", "tls": parameters.encryption != nil ? "yes" : "no"])
    }

    private func connect() async throws(SessionEnd) {
        let secret: [UInt8]
        let scid: UInt32
        do {
            secret = try CoreCrypto.randomBytes(Self.secretLength)
            scid = UInt32(try CoreCrypto.randomInt(in: 0...0x7FFF_FFFF))
        } catch {
            throw .connectFailed
        }
        do {
            socket = try await link.forward(serial: parameters.serial, scid: scid)
        } catch {
            throw .connectFailed
        }
        let options = ServerOptions(version: parameters.serverVersion, scid: scid, codec: parameters.codec, maxSize: parameters.maxSize,
                                    maxFPS: parameters.maxFPS, bitRate: parameters.bitRate, clipboardAutosync: parameters.clipboardSync,
                                    stayAwake: true)
        let mode = parameters.encryption == nil ? "plain" : "tls"
        let ca = parameters.encryption.map { Data($0.macCA).base64EncodedString() } ?? "-"
        let setup = "CM1 \(mode) \(CoreCrypto.hex(secret)) \(ca)\n"
        let handle: any ServerHandle
        do {
            handle = try await link.startServer(serial: parameters.serial, options: options, setupLine: setup)
        } catch {
            throw .serverFailed
        }
        server = handle
        let (pins, pinSink) = AsyncStream.makeStream(of: Result<[UInt8], SessionEnd>.self, bufferingPolicy: .bufferingNewest(1))
        tasks.append(Task { [weak self] in await self?.watchServer(handle, pins: pinSink) })

        var identity: TLSIdentity?
        if let encryption = parameters.encryption {
            let pin = try await Self.awaitPin(pins)
            Log.info(.security, "phone session key received")
            do {
                identity = try TLSIdentity.client(signer: encryption.signer, phonePin: pin)
            } catch {
                throw .tlsFailed(error)
            }
        }
        let videoStream = try await open(identity: identity, secret: secret, expectDummyByte: true)
        self.videoStream = videoStream
        Log.info(.transport, "video socket authenticated")
        let deviceName: String
        let codec: VideoCodecID
        do {
            let meta = try await videoStream.readExactly(ScrcpyProtocol.deviceNameLength + 4)
            (deviceName, codec) = try ScrcpyProtocol.preamble(meta)
        } catch let status as CoreStatus {
            throw .protocolViolation(status)
        } catch {
            throw .connectionLost
        }
        let controlStream = try await open(identity: identity, secret: secret, expectDummyByte: false)
        control.withLock { $0 = controlStream }
        Log.info(.transport, "control socket authenticated")
        let negotiated = (videoStream as? SecureStream).flatMap { try? $0.negotiated() }
        eventSink.yield(.connected(deviceName: deviceName, codec: codec, tlsSuite: negotiated?.suite, tlsGroup: negotiated?.group))
        video.videoStarted(codec: codec)

        tasks += [
            Task { [weak self] in await self?.videoLoop(videoStream) },
            Task { [weak self] in await self?.controlLoop(controlStream) },
            Task { [weak self] in await self?.pingLoop() },
        ]
    }

    /// Waits for `CM-PIN <hex>` (or `CM-ERROR identity-changed`) from the server's stdout watcher.
    private static func awaitPin(_ pins: AsyncStream<Result<[UInt8], SessionEnd>>) async throws(SessionEnd) -> [UInt8] {
        let result: Result<[UInt8], SessionEnd>? = await withTaskGroup(of: Result<[UInt8], SessionEnd>?.self) { group in
            group.addTask {
                var iterator = pins.makeAsyncIterator()
                return await iterator.next() ?? .failure(.serverFailed)
            }
            group.addTask {
                try? await Task.sleep(for: pinTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return try (result ?? .failure(.serverFailed)).get()
    }

    /// Reads the server's stdout until it exits: forwards the pin line, then ends the session on exit.
    private func watchServer(_ handle: any ServerHandle, pins: AsyncStream<Result<[UInt8], SessionEnd>>.Continuation) async {
        for await line in handle.lines {
            if line.hasPrefix("CM-ERROR identity-changed") {
                pins.yield(.failure(.identityChanged))
            } else if line.hasPrefix("CM-PIN "), let pin = try? CoreCrypto.bytes(fromHex: String(line.dropFirst(7))) {
                pins.yield(.success(pin))
            }
        }
        pins.yield(.failure(.serverFailed))
        pins.finish()
        finish(.serverFailed)
    }

    /// Connects to the forwarded port (retrying while the server starts), runs TLS, presents the secret.
    private func open(identity: TLSIdentity?, secret: [UInt8], expectDummyByte: Bool) async throws(SessionEnd) -> any ByteStream {
        for _ in 0..<Self.connectAttempts {
            guard let socket, let raw = try? await connector(socket) else {
                try? await Task.sleep(for: Self.connectRetryDelay)
                continue
            }
            do {
                var stream: any ByteStream = raw
                if let identity {
                    let secure = SecureStream(inner: raw, session: try TLSSession(identity: identity))
                    try await secure.handshake()
                    stream = secure
                }
                stream.send(secret)
                if expectDummyByte { _ = try await stream.readExactly(1) }
                return stream
            } catch StreamError.closed {
                raw.close()
                try? await Task.sleep(for: Self.connectRetryDelay)
            } catch let status as CoreStatus {
                raw.close()
                throw status == .tlsPinMismatch ? .identityChanged : .tlsFailed(status)
            } catch {
                raw.close()
                throw .connectFailed
            }
        }
        throw .connectFailed
    }

    // MARK: Loops

    private func videoLoop(_ stream: any ByteStream) async {
        var buffer: [UInt8] = []
        buffer.reserveCapacity(1 << 20)
        var start = 0
        var frames = 0
        var bytes = 0
        var windowStart = ContinuousClock.now

        do {
            while !Task.isCancelled {
                while buffer.count - start < ScrcpyProtocol.videoHeaderLength {
                    let chunk = try await stream.read(max: Self.videoReadChunk)
                    if chunk.isEmpty { throw StreamError.closed }
                    buffer.append(contentsOf: chunk)
                }
                let header = try ScrcpyProtocol.videoHeader(in: buffer, at: start)
                start += ScrcpyProtocol.videoHeaderLength
                switch header {
                case let .session(width, height):
                    video.videoSession(width: width, height: height)
                    eventSink.yield(.videoSize(width: width, height: height))
                case let .config(size), let .frame(_, _, size):
                    while buffer.count - start < size {
                        let chunk = try await stream.read(max: Self.videoReadChunk)
                        if chunk.isEmpty { throw StreamError.closed }
                        buffer.append(contentsOf: chunk)
                    }
                    let (config, key, pts): (Bool, Bool, UInt64) = switch header {
                    case let .frame(pts, keyFrame, _): (false, keyFrame, pts)
                    default: (true, false, 0)
                    }
                    buffer.withUnsafeBytes { video.videoPacket(UnsafeRawBufferPointer(rebasing: $0[start..<(start + size)]), config: config, keyFrame: key, pts: pts) }
                    start += size
                    if !config {
                        frames += 1
                        bytes += size
                    }
                }
                if start > (1 << 20) {
                    buffer.removeFirst(start)
                    start = 0
                }
                let elapsed = ContinuousClock.now - windowStart
                if elapsed >= .seconds(1) {
                    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    eventSink.yield(.throughput(fps: Double(frames) / seconds, megabitsPerSecond: Double(bytes * 8) / seconds / 1e6))
                    frames = 0
                    bytes = 0
                    windowStart = .now
                }
            }
        } catch let status as CoreStatus {
            Log.error(.media, "video stream rejected", ["code": status.name])
            finish(.protocolViolation(status))
        } catch {
            finish(.connectionLost)
        }
    }

    private func controlLoop(_ stream: any ByteStream) async {
        var buffer: [UInt8] = []
        do {
            while !Task.isCancelled {
                let chunk = try await stream.read(max: 64 * 1024)
                if chunk.isEmpty { throw StreamError.closed }
                buffer.append(contentsOf: chunk)
                while !buffer.isEmpty {
                    let parsed: (DeviceMessage, Int)
                    do {
                        parsed = try ScrcpyProtocol.deviceMessage(in: buffer)
                    } catch .needMoreData {
                        break
                    }
                    handle(parsed.0, in: buffer)
                    buffer.removeFirst(parsed.1)
                }
            }
        } catch let status as CoreStatus {
            Log.error(.transport, "device message rejected", ["code": status.name])
            finish(.protocolViolation(status))
        } catch {
            finish(.connectionLost)
        }
    }

    private func handle(_ message: DeviceMessage, in buffer: [UInt8]) {
        switch message {
        case let .clipboard(range):
            guard parameters.clipboardSync else { return }
            eventSink.yield(.clipboard(String(decoding: buffer[range], as: UTF8.self)))
        case let .battery(level, charging):
            eventSink.yield(.battery(level: level, charging: charging))
        case let .pong(value):
            let now = elapsedNanoseconds()
            if now >= value { eventSink.yield(.latency(milliseconds: Double(now - value) / 1e6)) }
        case .ackClipboard, .uhidOutput:
            break
        }
    }

    /// Monotonic time since the session object was created; the ping payload.
    private func elapsedNanoseconds() -> UInt64 {
        let elapsed = ContinuousClock.now - started
        return UInt64(elapsed.components.seconds) * 1_000_000_000 + UInt64(elapsed.components.attoseconds / 1_000_000_000)
    }

    private func pingLoop() async {
        while !Task.isCancelled {
            if let ping = try? ControlMessage.ping(elapsedNanoseconds()) { send(ping) }
            try? await Task.sleep(for: Self.pingInterval)
        }
    }

    // MARK: Ending

    /// Ends the session from inside (stream errors, server exit).
    private func finish(_ reason: SessionEnd) {
        guard !ended else { return }
        Task { await self.end(reason) }
    }

    /// Stops the session at the user's request (or before a handover).
    public func stop() async {
        await end(.stopped)
    }

    private func end(_ reason: SessionEnd) async {
        guard !ended else { return }
        ended = true
        await teardown()
        Log.info(.transport, "session ended")
        eventSink.yield(.ended(reason))
        eventSink.finish()
    }

    private func teardown() async {
        for task in tasks { task.cancel() }
        tasks = []
        control.withLock { stream in
            stream?.close()
            stream = nil
        }
        videoStream?.close()
        videoStream = nil
        server?.terminate()
        server = nil
        if let socket { await link.removeForward(serial: parameters.serial, socket: socket) }
        await link.cleanup(serial: parameters.serial)
    }
}
