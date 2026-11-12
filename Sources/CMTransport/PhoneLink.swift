// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CMCore
import CMCoreBridge
import Foundation
import Synchronization

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// A running mirror server on the phone: its stdout lines (the `CM-PIN` / `CM-ERROR` channel) and a kill switch.
public protocol ServerHandle: AnyObject, Sendable {
    /// stdout lines; the stream finishes when the server exits.
    var lines: AsyncStream<String> { get }
    func terminate()
}

/// Everything a session needs from adb (the virtual phone in tests implements the same protocol).
public protocol PhoneLink: Sendable {
    /// Verifies and pushes the server and core library.
    func prepare(serial: String) async throws
    /// Rounded-corner radius in pixels, nil when the phone does not report one.
    func cornerRadius(serial: String) async -> Int?
    /// Forwards a new private Unix socket to the server's abstract socket; returns the socket path.
    func forward(serial: String, scid: UInt32) async throws -> String
    func removeForward(serial: String, socket: String) async
    /// Starts the server and writes the session-setup line to its stdin.
    func startServer(serial: String, options: ServerOptions, setupLine: String) async throws -> any ServerHandle
    /// Removes the server's files from the phone.
    func cleanup(serial: String) async
}

/// The long-running `adb shell … app_process` that hosts the server.
final class AdbServerProcess: ServerHandle, @unchecked Sendable {
    static let maxLineBytes = 4096

    let lines: AsyncStream<String>
    private let process: Process
    private let stdin: Pipe

    init(process: Process, stdin: Pipe, stdout: Pipe) {
        self.process = process
        self.stdin = stdin
        let handle = stdout.fileHandleForReading
        lines = AsyncStream { continuation in
            Thread.detachNewThread {
                var line: [UInt8] = []
                reading: while true {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    for byte in data {
                        if byte == UInt8(ascii: "\n") {
                            continuation.yield(String(decoding: line, as: UTF8.self))
                            line.removeAll(keepingCapacity: true)
                        } else if line.count < Self.maxLineBytes {
                            line.append(byte)
                        } else {
                            break reading
                        }
                    }
                }
                continuation.finish()
            }
        }
    }

    func write(_ text: String) {
        stdin.fileHandleForWriting.write(Data(text.utf8))
    }

    func terminate() {
        try? stdin.fileHandleForWriting.close()
        if process.isRunning { ChildProcesses.shared.stop(process.processIdentifier) }
    }
}

extension AdbRunner {
    /// Starts an allowlisted long-running command with stdin/stdout pipes (stderr is discarded).
    func launch(_ command: AdbCommand) throws -> AdbServerProcess {
        let argv = try validatedArgv(command, usb: false, confirmed: false)
        let (process, stdout) = makeProcess(argv)
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw AdbRunError.launchFailed
        }
        ChildProcesses.shared.add(process.processIdentifier)
        return AdbServerProcess(process: process, stdin: stdin, stdout: stdout)
    }
}

/// Production link: the bundled adb through the allowlisted runner.
public struct AdbPhoneLink: PhoneLink {
    public let runner: AdbRunner
    public let deployer: ServerDeployer

    public init(runner: AdbRunner, deployer: ServerDeployer) {
        self.runner = runner
        self.deployer = deployer
    }

    public func prepare(serial: String) async throws {
        try await deployer.deploy(to: serial)
    }

    public func cornerRadius(serial: String) async -> Int? {
        guard let result = try? await runner.run(.readDisplayInfo(serial: serial), timeout: 10), result.succeeded else { return nil }
        return try? ScrcpyProtocol.cornerRadius(dumpsys: result.output)
    }

    public func forward(serial: String, scid: UInt32) async throws -> String {
        let socket = try runner.environment.newForwardSocket()
        try await runner.runChecked(.forward(serial: serial, localSocket: socket, scid: scid), timeout: 10)
        return socket
    }

    public func removeForward(serial: String, socket: String) async {
        _ = try? await runner.run(.removeForward(serial: serial, localSocket: socket), timeout: 5)
        runner.environment.removeSocket(socket)
    }

    public func startServer(serial: String, options: ServerOptions, setupLine: String) async throws -> any ServerHandle {
        let process = try runner.launch(.startMirrorServer(serial: serial, options: options))
        process.write(setupLine)
        return process
    }

    public func cleanup(serial: String) async {
        await deployer.cleanup(on: serial)
    }
}
