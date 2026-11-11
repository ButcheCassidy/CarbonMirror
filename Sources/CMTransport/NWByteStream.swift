#if canImport(Network)
import Foundation
import Network
import Synchronization

/// Network.framework stream to 127.0.0.1 (the `adb forward` port), pinned to the loopback interface.
public final class NWByteStream: ByteStream, @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.nomadicrebel.carbonmirror.nwstream")
    private let closed = Mutex(false)

    private init(connection: NWConnection) {
        self.connection = connection
    }

    /// Connects to 127.0.0.1:`port` over loopback only; fails after `timeout`.
    public static func connect(port: UInt16, timeout: TimeInterval = 5) async throws -> NWByteStream {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw StreamError.connectFailed }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.prohibitExpensivePaths = false
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }
        let connection = NWConnection(host: .ipv4(.loopback), port: nwPort, using: parameters)
        let stream = NWByteStream(connection: connection)
        let resumed = Mutex(false)
        return try await withCheckedThrowingContinuation { continuation in
            let finish: @Sendable (Result<NWByteStream, Error>) -> Void = { result in
                let first = resumed.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(with: result) }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.success(stream))
                case .failed, .cancelled: finish(.failure(StreamError.connectFailed))
                default: break
                }
            }
            connection.start(queue: stream.queue)
            stream.queue.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(StreamError.timedOut))
            }
        }
    }

    public func read(max: Int) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: max) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    continuation.resume(returning: [UInt8](data))
                } else if isComplete || error == nil {
                    continuation.resume(returning: [])
                } else {
                    continuation.resume(throwing: StreamError.closed)
                }
            }
        }
    }

    public func send(_ bytes: [UInt8]) {
        connection.send(content: Data(bytes), completion: .contentProcessed { [weak self] error in
            if error != nil { self?.close() }
        })
    }

    public func close() {
        let first = closed.withLock { wasClosed -> Bool in
            defer { wasClosed = true }
            return !wasClosed
        }
        if first { connection.cancel() }
    }
}
#endif
