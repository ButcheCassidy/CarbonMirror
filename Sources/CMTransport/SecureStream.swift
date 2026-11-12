// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CMCoreBridge
import Foundation
import Synchronization

/// Inner TLS over a byte stream (spec 7.3). The TLS state machine runs in the Rust core; this class moves
/// bytes. All TLS calls happen under one lock, and ciphertext is enqueued on the inner stream while still
/// holding it, so records always leave in order.
public final class SecureStream: ByteStream, @unchecked Sendable {
    public static let readChunk = 64 * 1024

    private let inner: any ByteStream
    private let lock = Mutex(())
    private let tls: TLSSession
    /// Decrypted bytes not yet handed out (guarded by `lock`).
    private var leftover: [UInt8] = []

    public init(inner: any ByteStream, session: TLSSession) {
        self.inner = inner
        self.tls = session
    }

    /// Runs the handshake; throws the core's status on failure (pin mismatch, policy, timeout) or
    /// `StreamError.closed` when the peer hung up before answering.
    public func handshake() async throws {
        try flush()
        while try lock.withLock({ _ throws(CoreStatus) in tls.isHandshaking }) {
            let chunk = try await inner.read(max: Self.readChunk)
            if chunk.isEmpty { throw StreamError.closed }
            try lock.withLock { _ throws(CoreStatus) in
                try tls.receive(chunk)
            }
            try flush()
        }
    }

    /// Negotiated suite and group, for the debug HUD and logs.
    public func negotiated() throws -> (suite: UInt16, group: UInt16) {
        try lock.withLock { _ throws(CoreStatus) in try tls.negotiated() }
    }

    private func flush() throws {
        try lock.withLock { _ throws(CoreStatus) in
            let out = try tls.takeOutgoing()
            if !out.isEmpty { inner.send(out) }
        }
    }

    public func read(max: Int) async throws -> [UInt8] {
        while true {
            let ready: [UInt8]? = try lock.withLock { _ throws(CoreStatus) -> [UInt8]? in
                if leftover.isEmpty {
                    switch Result(catching: { () throws(CoreStatus) in try tls.takePlaintext() }) {
                    case let .success(bytes): leftover = bytes
                    case .failure(.tlsClosed): return []
                    case let .failure(status): throw status
                    }
                }
                if leftover.isEmpty { return nil }
                let n = min(max, leftover.count)
                defer { leftover.removeFirst(n) }
                return Array(leftover[0..<n])
            }
            if let ready { return ready }
            let chunk = try await inner.read(max: Self.readChunk)
            if chunk.isEmpty { return [] }
            try lock.withLock { _ throws(CoreStatus) in
                try tls.receive(chunk)
            }
            try flush()
        }
    }

    public func send(_ bytes: [UInt8]) {
        do {
            try lock.withLock { _ throws(CoreStatus) in
                try tls.send(bytes)
                let out = try tls.takeOutgoing()
                if !out.isEmpty { inner.send(out) }
            }
        } catch {
            close()
        }
    }

    public func close() {
        try? lock.withLock { _ throws(CoreStatus) in
            tls.close()
            let out = try tls.takeOutgoing()
            if !out.isEmpty { inner.send(out) }
        }
        inner.close()
    }
}
