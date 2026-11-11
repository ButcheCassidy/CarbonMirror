import Foundation
import Synchronization

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Every child process CarbonMirror starts is registered here so all of them can be killed on quit,
/// on SIGTERM/SIGINT/SIGHUP, or before a restart.
public final class ChildProcesses: Sendable {
    public static let shared = ChildProcesses()

    private let pids = Mutex<Set<Int32>>([])
    private let signalSources = Mutex<[DispatchSourceSignal]>([])

    init() {}

    func add(_ pid: Int32) {
        _ = pids.withLock { $0.insert(pid) }
    }

    func remove(_ pid: Int32) {
        _ = pids.withLock { $0.remove(pid) }
    }

    /// Number of children still registered.
    public var count: Int { pids.withLock { $0.count } }

    /// SIGTERM to every child, then SIGKILL to any still alive after `grace`.
    public func terminateAll(grace: TimeInterval = 0.5) {
        let live = pids.withLock { set -> Set<Int32> in
            let copy = set
            set.removeAll()
            return copy
        }
        guard !live.isEmpty else { return }
        for pid in live { kill(pid, SIGTERM) }
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline, live.contains(where: { kill($0, 0) == 0 }) {
            usleep(20_000)
        }
        for pid in live where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    /// Kills all children and exits when the app receives SIGTERM, SIGINT or SIGHUP.
    public func installSignalHandlers() {
        signalSources.withLock { sources in
            guard sources.isEmpty else { return }
            for sig in [SIGTERM, SIGINT, SIGHUP] {
                signal(sig, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: sig, queue: .global(qos: .userInitiated))
                source.setEventHandler { [weak self] in
                    self?.terminateAll()
                    exit(128 + sig)
                }
                source.resume()
                sources.append(source)
            }
        }
    }
}
