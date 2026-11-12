import CMCore
import CMCoreBridge
import Foundation

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Owns the app-private adb server: cleans up a stale one from a previous run, starts it on 127.0.0.1,
/// watches the device list (`track-devices`, so USB attach/detach arrive as events), restarts it after a
/// crash with backoff, and kills everything on stop.
public actor AdbSupervisor {
    public enum State: Equatable, Sendable {
        case stopped
        case starting
        case running
        case restarting(attempt: Int)
    }

    public enum Failure: Error, Equatable {
        case serverWouldNotStart
    }

    /// Delay before each restart attempt; the last value repeats.
    public static let restartBackoff: [TimeInterval] = [0.5, 1, 2, 4, 8]
    /// A watch that lasted this long counts as healthy and resets the backoff.
    static let healthyRunSeconds: TimeInterval = 10

    public private(set) var state: State = .stopped
    public private(set) var devices: [AdbListedDevice] = []
    /// Latest device list after every change (newest value only).
    public nonisolated let deviceUpdates: AsyncStream<[AdbListedDevice]>

    private let runner: AdbRunner
    private let updates: AsyncStream<[AdbListedDevice]>.Continuation
    private var watchTask: Task<Void, Never>?
    private var watchPID: Int32?

    public init(runner: AdbRunner) {
        self.runner = runner
        (deviceUpdates, updates) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Starts the server and the device watch.
    public func start() async throws {
        guard state == .stopped else { return }
        state = .starting
        await killStaleServer()
        guard let result = try? await runner.run(.startServer, timeout: 15), result.succeeded else {
            state = .stopped
            throw Failure.serverWouldNotStart
        }
        state = .running
        Log.info(.adb, "adb server running on a private socket")
        watchTask = Task { await self.watchLoop() }
    }

    /// Stops the watch, kills the server and every child process.
    public func stop() async {
        watchTask?.cancel()
        if let pid = watchPID { ChildProcesses.shared.stop(pid) }
        await watchTask?.value
        watchTask = nil
        _ = try? await runner.run(.killServer, timeout: 5)
        runner.environment.removeSocket(runner.environment.serverSocket)
        ChildProcesses.shared.terminateAll()
        devices = []
        updates.yield([])
        state = .stopped
        Log.info(.adb, "adb server stopped")
    }

    private func killStaleServer() async {
        guard runner.environment.hasStaleServerSocket else { return }
        _ = try? await runner.run(.killServer, timeout: 5)
        runner.environment.removeSocket(runner.environment.serverSocket)
        Log.info(.adb, "stale adb server cleaned up")
    }

    private func watchLoop() async {
        var attempt = 0
        while !Task.isCancelled {
            let began = Date()
            await watchOnce()
            if Task.isCancelled { break }
            if Date().timeIntervalSince(began) >= Self.healthyRunSeconds { attempt = 0 }
            state = .restarting(attempt: attempt)
            Log.error(.adb, "device watch ended; restarting", ["attempt": "\(attempt)"])
            let delay = Self.restartBackoff[min(attempt, Self.restartBackoff.count - 1)]
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { break }
            _ = try? await runner.run(.startServer, timeout: 15)
            attempt += 1
            state = .running
        }
    }

    /// One `track-devices` session: reads frames until the process ends or sends something malformed.
    private func watchOnce() async {
        guard let argv = try? runner.validatedArgv(.trackDevices, usb: false, confirmed: false) else { return }
        let (process, pipe) = runner.makeProcess(argv)
        do {
            try process.run()
        } catch {
            return
        }
        let pid = process.processIdentifier
        watchPID = pid
        ChildProcesses.shared.add(pid)
        let chunks = Self.chunks(of: pipe.fileHandleForReading)
        var buffer: [UInt8] = []
        reading: for await chunk in chunks {
            buffer.append(contentsOf: chunk)
            while true {
                let frame: Range<Int>?
                do {
                    frame = try AdbDeviceList.trackFrame(buffer)
                } catch {
                    Log.error(.adb, "malformed device-list frame", ["code": error.name])
                    break reading
                }
                guard let frame else { break }
                if let list = try? AdbDeviceList.parse(Array(buffer[frame])) {
                    publish(list)
                }
                buffer.removeFirst(frame.upperBound)
            }
        }
        ChildProcesses.shared.stop(pid)
        process.waitUntilExit()
        watchPID = nil
    }

    private func publish(_ list: [AdbListedDevice]) {
        guard list != devices else { return }
        devices = list
        updates.yield(list)
        Log.info(.adb, "device list changed", ["count": "\(list.count)", "online": "\(list.filter(\.isOnline).count)"])
    }

    /// Reads a pipe on its own thread and delivers chunks until EOF.
    private static func chunks(of handle: FileHandle) -> AsyncStream<[UInt8]> {
        AsyncStream { continuation in
            Thread.detachNewThread {
                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    continuation.yield(Array(data))
                }
                continuation.finish()
            }
        }
    }
}
