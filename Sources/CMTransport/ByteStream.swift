import Foundation
import Synchronization

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// A bidirectional byte stream to the phone (always 127.0.0.1 through `adb forward`).
/// `send` is ordered and non-blocking, so callers can encrypt and enqueue atomically.
public protocol ByteStream: AnyObject, Sendable {
    /// Up to `max` bytes; an empty array means the peer closed the stream.
    func read(max: Int) async throws -> [UInt8]
    /// Queues bytes for sending, in call order. A failed send closes the stream.
    func send(_ bytes: [UInt8])
    func close()
}

/// Opens a stream to a local port.
/// Connects to a forwarded Unix-socket path.
public typealias StreamConnector = @Sendable (String) async throws -> any ByteStream

public enum StreamError: Error, Equatable {
    case connectFailed
    case closed
    case timedOut
}

extension ByteStream {
    /// Reads exactly `count` bytes; throws `closed` if the stream ends first.
    public func readExactly(_ count: Int) async throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(count)
        while out.count < count {
            let chunk = try await read(max: count - out.count)
            if chunk.isEmpty { throw StreamError.closed }
            out.append(contentsOf: chunk)
        }
        return out
    }
}

/// BSD-socket stream: the session's private Unix sockets (Mac and Linux) and the tests' loopback TCP.
public final class POSIXStream: ByteStream, @unchecked Sendable {
    private let fd: Int32
    private let readQueue = DispatchQueue(label: "com.nomadicrebel.carbonmirror.stream.read")
    private let writeQueue = DispatchQueue(label: "com.nomadicrebel.carbonmirror.stream.write")
    private let closed = Mutex(false)

    /// Wraps an already-connected socket (used by the virtual phone's accept loop).
    public init(fd: Int32) {
        self.fd = fd
        var on: Int32 = 1
        setsockopt(fd, Int32(IPPROTO_TCP), TCP_NODELAY, &on, socklen_t(MemoryLayout<Int32>.size))
        #if canImport(Darwin)
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    deinit {
        sysClose(fd)
    }

    /// Connects to the Unix-domain socket at `path` (the private `adb forward` socket).
    public static func connect(unixPath path: String) async throws -> POSIXStream {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard var address = unixAddress(path) else { return continuation.resume(throwing: StreamError.connectFailed) }
                let fd = socket(AF_UNIX, Self.streamType, 0)
                guard fd >= 0 else { return continuation.resume(throwing: StreamError.connectFailed) }
                let rc = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sysConnect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
                }
                guard rc == 0 else {
                    sysClose(fd)
                    return continuation.resume(throwing: StreamError.connectFailed)
                }
                continuation.resume(returning: POSIXStream(fd: fd))
            }
        }
    }

    /// `sockaddr_un` for `path`; nil when it does not fit `sun_path`.
    static func unixAddress(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty, bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        #if canImport(Darwin)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        return address
    }

    static var streamType: Int32 {
        #if canImport(Glibc)
        Int32(SOCK_STREAM.rawValue)
        #else
        SOCK_STREAM
        #endif
    }

    static func loopback(port: UInt16) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        a.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        return a
    }

    public func read(max: Int) async throws -> [UInt8] {
        let fd = self.fd
        return try await withCheckedThrowingContinuation { continuation in
            readQueue.async {
                var buffer = [UInt8](repeating: 0, count: max)
                let n = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, max, 0) }
                if n < 0 {
                    continuation.resume(throwing: StreamError.closed)
                } else {
                    buffer.removeSubrange(n...)
                    continuation.resume(returning: buffer)
                }
            }
        }
    }

    public func send(_ bytes: [UInt8]) {
        let fd = self.fd
        writeQueue.async { [weak self] in
            var offset = 0
            while offset < bytes.count {
                let n = bytes.withUnsafeBytes { sysSend(fd, $0.baseAddress! + offset, bytes.count - offset) }
                if n <= 0 {
                    self?.close()
                    return
                }
                offset += n
            }
        }
    }

    public func close() {
        let first = closed.withLock { wasClosed -> Bool in
            defer { wasClosed = true }
            return !wasClosed
        }
        if first { shutdown(fd, Int32(SHUT_RDWR)) }
    }
}

/// Platform shims (Glibc and Darwin spell a few calls differently).
@inline(__always) func sysClose(_ fd: Int32) {
    #if canImport(Glibc)
    _ = Glibc.close(fd)
    #else
    _ = Darwin.close(fd)
    #endif
}

@inline(__always) func sysConnect(_ fd: Int32, _ addr: UnsafePointer<sockaddr>, _ len: socklen_t) -> Int32 {
    #if canImport(Glibc)
    Glibc.connect(fd, addr, len)
    #else
    Darwin.connect(fd, addr, len)
    #endif
}

@inline(__always) func sysSend(_ fd: Int32, _ ptr: UnsafeRawPointer, _ len: Int) -> Int {
    #if canImport(Glibc)
    Glibc.send(fd, ptr, len, Int32(MSG_NOSIGNAL))
    #else
    Darwin.send(fd, ptr, len, 0)
    #endif
}
