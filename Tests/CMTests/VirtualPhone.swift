// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CMCore
import CMCoreBridge
@testable import CMTransport
import Foundation
import Synchronization

#if canImport(Darwin)
private typealias Glibc = Darwin
#endif

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// P-384 identity key for tests, using the system `openssl` (the Mac app uses the Keychain).
final class OpenSSLSigner: IdentitySigning, @unchecked Sendable {
    let directory: URL
    let publicKey: [UInt8]

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("cm-signer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = try Self.openssl(["ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", directory.appendingPathComponent("key.pem").path])
        let spki = try Self.openssl(["ec", "-in", directory.appendingPathComponent("key.pem").path, "-pubout", "-outform", "DER"])
        publicKey = Array(spki.suffix(97))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func sign(_ message: [UInt8]) throws -> [UInt8] {
        let input = directory.appendingPathComponent("msg-\(UUID().uuidString)")
        try Data(message).write(to: input)
        defer { try? FileManager.default.removeItem(at: input) }
        return try Self.openssl(["dgst", "-sha384", "-sign", directory.appendingPathComponent("key.pem").path, input.path])
    }

    static func openssl(_ args: [String]) throws -> [UInt8] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw StreamError.connectFailed }
        return [UInt8](data)
    }
}

/// Records video packets for assertions.
final class RecordingSink: VideoSink, @unchecked Sendable {
    let state = Mutex<(codec: VideoCodecID?, sizes: [String], configs: Int, frames: Int, keyFrames: Int)>((nil, [], 0, 0, 0))

    func videoStarted(codec: VideoCodecID) {
        state.withLock { $0.codec = codec }
    }

    func videoSession(width: Int, height: Int) {
        state.withLock { $0.sizes.append("\(width)x\(height)") }
    }

    func videoPacket(_ data: UnsafeRawBufferPointer, config: Bool, keyFrame: Bool, pts: UInt64) {
        state.withLock {
            if config { $0.configs += 1 } else { $0.frames += 1 }
            if keyFrame { $0.keyFrames += 1 }
        }
    }
}

/// A fake Pixel that speaks the real CarbonMirror protocol over 127.0.0.1: session setup, inner TLS 1.3
/// (Rust server side, same code as the phone), session secret, device meta, a real H.264 test stream,
/// ping/pong, battery and clipboard messages. It records every control message it receives and can
/// misbehave on purpose (attacker modes).
final class VirtualPhone: @unchecked Sendable {
    enum Attack: Sendable {
        case none
        /// Announces the pin of a different key than the one it serves.
        case wrongPin
        /// Sends a device message type the Mac does not allow (e.g. a file push).
        case unknownMessage
        /// Sends 2 MiB of clipboard text.
        case oversizedClipboard
        /// Sends clipboard bytes that are not UTF-8.
        case nonTextClipboard
        /// Sends a battery message with an out-of-range level.
        case forgedBattery
    }

    static let width = 1344
    static let height = 2992

    let attack: Attack
    /// Soak mode: loop the test stream at this frame rate until stopped (nil: send it once, fast).
    let loopFPS: Int?
    /// Frames sent (soak statistics).
    let framesSent = Mutex(0)
    private let running = Mutex(true)
    let received = Mutex<[[UInt8]]>([])
    let rejectedSecrets = Mutex(0)
    private let lineContinuation: AsyncStream<String>.Continuation
    let lines: AsyncStream<String>
    private var listener: Int32 = -1
    private var secret: [UInt8] = []
    /// The phone's stored device key (the real server keeps it in a shell-only file).
    var deviceKey: [UInt8]?
    private var identity: TLSIdentity?
    private var connections: [any ByteStream] = []
    private let lock = Mutex(())
    private let frames: [(bytes: [UInt8], config: Bool, key: Bool)]

    init(attack: Attack = .none, loopFPS: Int? = nil) {
        self.attack = attack
        self.loopFPS = loopFPS
        (lines, lineContinuation) = AsyncStream.makeStream()
        frames = Self.loadTestStream()
    }

    /// First NAL units of the synthetic Pixel test stream: SPS+PPS as one config packet, then slices.
    static func loadTestStream() -> [(bytes: [UInt8], config: Bool, key: Bool)] {
        let dir = ProcessInfo.processInfo.environment["CM_TEST_VIDEO_DIR"] ?? "\(NSHomeDirectory())/carbonmirror-deps/test-video"
        guard let handle = FileHandle(forReadingAtPath: "\(dir)/pixel10proxl-60fps.h264") else { return [] }
        let data = [UInt8](handle.readData(ofLength: 600_000))
        var starts: [Int] = []
        var i = 0
        while i + 3 < data.count {
            if data[i] == 0, data[i + 1] == 0, data[i + 2] == 1 {
                starts.append(i > 0 && data[i - 1] == 0 ? i - 1 : i)
                i += 3
            } else {
                i += 1
            }
        }
        var out: [(bytes: [UInt8], config: Bool, key: Bool)] = []
        var config: [UInt8] = []
        for (index, start) in starts.enumerated().dropLast() {
            let nal = Array(data[start..<starts[index + 1]])
            let headerIndex = nal[2] == 1 ? 3 : 4
            let type = nal[headerIndex] & 0x1F
            switch type {
            case 7, 8: config += nal
            case 1, 5:
                if !config.isEmpty {
                    out.append((config, true, false))
                    config = []
                }
                out.append((nal, false, type == 5))
            default: break
            }
        }
        return out
    }

    // MARK: Listening ("adb forward" lands here)

    func listen(unixPath path: String) throws {
        guard var address = POSIXStream.unixAddress(path) else { throw StreamError.connectFailed }
        let fd = socket(AF_UNIX, POSIXStream.streamType, 0)
        let rc = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard rc == 0, Glibc.listen(fd, 8) == 0 else { throw StreamError.connectFailed }
        listener = fd
    }

    /// Handles the setup line from "stdin", then serves video and control.
    func start(setupLine: String) {
        let fields = setupLine.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
        guard fields.count == 5, fields[0] == "CM1", let s = try? Self.bytes(hex: fields[2]) else {
            lineContinuation.finish()
            return
        }
        secret = s
        if fields[1] == "tls", let der = Data(base64Encoded: fields[3]) {
            guard let id = try? TLSIdentity.server(macCA: [UInt8](der)), var pin = try? id.pin() else {
                lineContinuation.finish()
                return
            }
            identity = id
            if attack == .wrongPin { pin[0] ^= 0xFF }
            lineContinuation.yield("[server] INFO: Device: [Google] google Pixel 10 Pro XL (Android 16)")
            // Like the real server: a key in the setup line (USB) is stored; the proof uses the stored key.
            if let provisioned = try? Self.bytes(hex: fields[4]) { deviceKey = provisioned }
            let proof = deviceKey.flatMap { try? CoreCrypto.hmacSHA256(key: $0, pin) }
            lineContinuation.yield("CM-PIN " + CoreCrypto.hex(pin) + (proof.map { " " + CoreCrypto.hex($0) } ?? ""))
        }
        Thread.detachNewThread { [self] in
            Task { await self.serve() }
        }
    }

    private func accept() async -> (any ByteStream)? {
        let fd = listener
        let client: Int32 = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: Glibc.accept(fd, nil, nil)) }
        }
        guard client >= 0 else { return nil }
        let raw = POSIXStream(fd: client)
        var stream: any ByteStream = raw
        if let identity, let session = try? TLSSession(identity: identity) {
            let secure = SecureStream(inner: raw, session: session)
            guard (try? await secure.handshake()) != nil else {
                raw.close()
                return nil
            }
            stream = secure
        }
        guard let presented = try? await stream.readExactly(secret.count), presented == secret else {
            rejectedSecrets.withLock { $0 += 1 }
            stream.close()
            return nil
        }
        lock.withLock { _ in connections.append(stream) }
        return stream
    }

    private func serve() async {
        // Same order as the real server (DesktopConnection.open, then sendDeviceMeta): both sockets first, then the meta.
        guard let video = await accept() else { return }
        video.send([0])
        guard let control = await accept() else { return }
        var meta = [UInt8](repeating: 0, count: 64)
        meta.replaceSubrange(0..<15, with: Array("Pixel 10 Pro XL".utf8))
        video.send(meta)
        video.send(Array("h264".utf8))
        Task { await controlLoop(control) }
        Task { await deviceMessages(control) }
        await stream(video)
    }

    private func stream(_ video: any ByteStream) async {
        var header = [UInt8](repeating: 0, count: 12)
        header.withUnsafeMutableBytes {
            $0.storeBytes(of: UInt32(0x8000_0000).bigEndian, toByteOffset: 0, as: UInt32.self)
            $0.storeBytes(of: UInt32(Self.width).bigEndian, toByteOffset: 4, as: UInt32.self)
            $0.storeBytes(of: UInt32(Self.height).bigEndian, toByteOffset: 8, as: UInt32.self)
        }
        video.send(header)
        var pts: UInt64 = 0
        let pause: Duration = loopFPS.map { .microseconds(1_000_000 / $0) } ?? .milliseconds(2)
        repeat {
            for frame in frames where running.withLock({ $0 }) {
                var flags: UInt64 = frame.config ? 1 << 62 : pts
                if frame.key { flags |= 1 << 61 }
                var h = [UInt8](repeating: 0, count: 12)
                h.withUnsafeMutableBytes {
                    $0.storeBytes(of: flags.bigEndian, toByteOffset: 0, as: UInt64.self)
                    $0.storeBytes(of: UInt32(frame.bytes.count).bigEndian, toByteOffset: 8, as: UInt32.self)
                }
                video.send(h + frame.bytes)
                if !frame.config {
                    pts += 16_666
                    framesSent.withLock { $0 += 1 }
                }
                try? await Task.sleep(for: pause)
            }
        } while loopFPS != nil && running.withLock({ $0 })
    }

    private func deviceMessages(_ control: any ByteStream) async {
        control.send([0x40, 84, 1])
        control.send([0] + Self.be32(5) + Array("hello".utf8))
        switch attack {
        case .unknownMessage: control.send([0x50, 0, 0, 0, 4, 1, 2, 3, 4])
        case .oversizedClipboard: control.send([0] + Self.be32(2 << 20) + [UInt8](repeating: 0x41, count: 2 << 20))
        case .nonTextClipboard: control.send([0] + Self.be32(4) + [0xFF, 0xFE, 0x00, 0x01])
        case .forgedBattery: control.send([0x40, 200, 1])
        case .none, .wrongPin: break
        }
    }

    /// Records control messages; answers pings (0x41 + u64) with pongs.
    private func controlLoop(_ control: any ByteStream) async {
        while let chunk = try? await control.read(max: 4096), !chunk.isEmpty {
            received.withLock { $0.append(chunk) }
            var i = 0
            while i + 9 <= chunk.count {
                if chunk[i] == 0x41 {
                    control.send([0x41] + Array(chunk[(i + 1)..<(i + 9)]))
                    i += 9
                } else {
                    break
                }
            }
        }
    }

    func stop() {
        running.withLock { $0 = false }
        lineContinuation.finish()
        lock.withLock { _ in for c in connections { c.close() } }
        if listener >= 0 {
            shutdown(listener, Int32(SHUT_RDWR))
            sysClose(listener)
            listener = -1
        }
    }

    static func be32(_ v: Int) -> [UInt8] {
        withUnsafeBytes(of: UInt32(v).bigEndian, Array.init)
    }

    static func bytes(hex: String) throws -> [UInt8] {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { throw StreamError.connectFailed }
        return try stride(from: 0, to: chars.count, by: 2).map { i in
            guard let b = UInt8(String(decoding: chars[i..<(i + 2)], as: UTF8.self), radix: 16) else { throw StreamError.connectFailed }
            return b
        }
    }
}

/// Server handle backed by the virtual phone's stdout.
final class VirtualServerHandle: ServerHandle, @unchecked Sendable {
    let lines: AsyncStream<String>
    let phone: VirtualPhone

    init(phone: VirtualPhone) {
        self.phone = phone
        lines = phone.lines
    }

    func terminate() {
        phone.stop()
    }
}

/// PhoneLink that routes "adb" operations to a virtual phone on the forwarded port.
final class VirtualPhoneLink: PhoneLink, @unchecked Sendable {
    let phone: VirtualPhone
    let calls = Mutex<[String]>([])

    init(phone: VirtualPhone) {
        self.phone = phone
    }

    func prepare(serial: String) async throws { calls.withLock { $0.append("prepare") } }
    func cornerRadius(serial: String) async -> Int? { 104 }

    func forward(serial: String, scid: UInt32) async throws -> String {
        calls.withLock { $0.append("forward") }
        let path = FileManager.default.temporaryDirectory.path + "/cm-f" + CoreCrypto.hex(try CoreCrypto.randomBytes(8))
        try phone.listen(unixPath: path)
        return path
    }

    func removeForward(serial: String, socket: String) async {
        calls.withLock { $0.append("removeForward") }
        try? FileManager.default.removeItem(atPath: socket)
    }

    func startServer(serial: String, options: ServerOptions, setupLine: String) async throws -> any ServerHandle {
        calls.withLock { $0.append("startServer") }
        phone.start(setupLine: setupLine)
        return VirtualServerHandle(phone: phone)
    }

    func cleanup(serial: String) async { calls.withLock { $0.append("cleanup") } }
}

/// Records every byte that crosses a session socket, both ways, when `CM_CAPTURE_DIR` is set (Phase 11
/// Stage 3.3: the session uses Unix sockets, which tcpdump cannot see). Otherwise returns the stream as is.
final class TapStream: ByteStream, @unchecked Sendable {
    private let inner: any ByteStream
    private let sent: FileHandle
    private let received: FileHandle

    static func wrap(_ stream: any ByteStream) -> any ByteStream {
        guard let dir = ProcessInfo.processInfo.environment["CM_CAPTURE_DIR"] else { return stream }
        let id = UUID().uuidString
        let paths = ["\(dir)/\(id).sent", "\(dir)/\(id).received"]
        for path in paths { _ = FileManager.default.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        guard let sent = FileHandle(forWritingAtPath: paths[0]), let received = FileHandle(forWritingAtPath: paths[1]) else { return stream }
        return TapStream(inner: stream, sent: sent, received: received)
    }

    private init(inner: any ByteStream, sent: FileHandle, received: FileHandle) {
        self.inner = inner
        self.sent = sent
        self.received = received
    }

    func read(max: Int) async throws -> [UInt8] {
        let bytes = try await inner.read(max: max)
        received.write(Data(bytes))
        return bytes
    }

    func send(_ bytes: [UInt8]) {
        sent.write(Data(bytes))
        inner.send(bytes)
    }

    func close() {
        inner.close()
    }
}
