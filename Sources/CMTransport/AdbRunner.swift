import CMCore
import CMCoreBridge
import Foundation
import Synchronization

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Output of one finished adb command (stdout and stderr merged; adb reports most errors on stderr).
public struct AdbResult: Sendable, Equatable {
    public let exitCode: Int32
    public let output: [UInt8]

    public var succeeded: Bool { exitCode == 0 }
    public var text: String { String(decoding: output, as: UTF8.self) }
}

/// Why an adb command did not produce a result.
public enum AdbRunError: Error, Equatable {
    case refused(CoreStatus)
    case launchFailed
    case timedOut
    case outputTooLarge
    case failed(exitCode: Int32)
}

/// Runs the bundled adb. Every argv goes through the Rust allowlist first; refused commands never start.
public struct AdbRunner: Sendable {
    /// Largest output accepted from one command.
    public static let maxOutputBytes = 1 << 20

    public let executable: URL
    public let environment: AdbEnvironment

    public init(executable: URL, environment: AdbEnvironment) {
        self.executable = executable
        self.environment = environment
    }

    /// Same adb, another environment (used after picking a new server port).
    public func with(environment: AdbEnvironment) -> AdbRunner {
        AdbRunner(executable: executable, environment: environment)
    }

    /// Checks `command` against the allowlist and returns its argv.
    func validatedArgv(_ command: AdbCommand, usb: Bool, confirmed: Bool) throws(AdbRunError) -> [String] {
        let argv = command.argv
        do {
            try AdbPolicy.validate(argv, usb: usb, confirmed: confirmed)
        } catch {
            Log.error(.adb, "adb command refused by allowlist", ["code": error.name])
            throw .refused(error)
        }
        return argv
    }

    /// Runs `command` to completion off the caller's thread.
    public func run(_ command: AdbCommand, usb: Bool = false, confirmed: Bool = false, timeout: TimeInterval = 30) async throws(AdbRunError) -> AdbResult {
        let argv = try validatedArgv(command, usb: usb, confirmed: confirmed)
        let result: Result<AdbResult, AdbRunError> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.runBlocking(argv, timeout: timeout))
            }
        }
        return try result.get()
    }

    /// Like ``run(_:usb:confirmed:timeout:)`` but also fails on a non-zero exit code.
    @discardableResult
    public func runChecked(_ command: AdbCommand, usb: Bool = false, confirmed: Bool = false, timeout: TimeInterval = 30) async throws(AdbRunError) -> AdbResult {
        let result = try await run(command, usb: usb, confirmed: confirmed, timeout: timeout)
        guard result.succeeded else { throw .failed(exitCode: result.exitCode) }
        return result
    }

    /// Configured process for `argv` with a merged output pipe; the environment is exactly ``AdbEnvironment/variables``.
    func makeProcess(_ argv: [String]) -> (Process, Pipe) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = argv
        process.environment = environment.variables
        process.currentDirectoryURL = environment.directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        return (process, pipe)
    }

    private func runBlocking(_ argv: [String], timeout: TimeInterval) -> Result<AdbResult, AdbRunError> {
        let (process, pipe) = makeProcess(argv)
        do {
            try process.run()
        } catch {
            Log.error(.adb, "adb launch failed")
            return .failure(.launchFailed)
        }
        let pid = process.processIdentifier
        ChildProcesses.shared.add(pid)
        defer { ChildProcesses.shared.remove(pid) }

        let timedOut = Mutex(false)
        let timer = DispatchWorkItem {
            timedOut.withLock { $0 = true }
            kill(pid, SIGKILL)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

        var output: [UInt8] = []
        var tooLarge = false
        let reader = pipe.fileHandleForReading
        while true {
            let chunk = reader.availableData
            if chunk.isEmpty { break }
            output.append(contentsOf: chunk)
            if output.count > Self.maxOutputBytes {
                tooLarge = true
                kill(pid, SIGKILL)
                break
            }
        }
        process.waitUntilExit()
        timer.cancel()
        if tooLarge { return .failure(.outputTooLarge) }
        if timedOut.withLock({ $0 }) { return .failure(.timedOut) }
        return .success(AdbResult(exitCode: process.terminationStatus, output: output))
    }
}
