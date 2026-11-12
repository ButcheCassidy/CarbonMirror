#if canImport(Network)
import Foundation
import Network
import Synchronization

/// Network.framework stream for the Wireless-debugging probe: LAN only, on a physical interface (never a VPN tunnel).
public final class NWByteStream: ByteStream, @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.nomadicrebel.carbonmirror.nwstream")
    private let closed = Mutex(false)

    private init(connection: NWConnection) {
        self.connection = connection
    }

    /// Connects to `endpoint` with `parameters` (TCP_NODELAY on); fails after `timeout`.
    static func connect(endpoint: NWEndpoint, parameters: NWParameters, timeout: TimeInterval) async throws -> NWByteStream {
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        let stream = NWByteStream(connection: connection)
        let resumed = Mutex(false)
        return try await withCheckedThrowingContinuation { continuation in
            let finish: @Sendable (Result<NWByteStream, Error>) -> Void = { result in
                let first = resumed.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                guard first else { return }
                if case .failure = result { connection.cancel() }
                continuation.resume(with: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.success(stream))
                case .failed, .cancelled: finish(.failure(StreamError.connectFailed))
                case .waiting: finish(.failure(StreamError.connectFailed))
                default: break
                }
            }
            connection.start(queue: stream.queue)
            stream.queue.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(StreamError.timedOut))
            }
        }
    }

    /// Name of the interface the connection's route uses (e.g. `en0`, or `utun4` behind a VPN).
    var interfaceName: String? {
        connection.currentPath?.availableInterfaces.first?.name
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
