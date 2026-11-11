import CMCore
import CMCoreBridge
import Foundation

/// App-private adb environment: its own HOME/ANDROID_USER_HOME (0700 dir, 0600 files), never `~/.android`,
/// and an adb server on a random non-default port bound to 127.0.0.1 only.
public struct AdbEnvironment: Sendable {
    public enum Failure: Error, Equatable {
        case cannotCreateDirectory
        case cannotSecure
    }

    /// Range the per-launch adb server port is drawn from (never 5037, adb's default).
    public static let portRange: ClosedRange<UInt32> = 20_000...59_999
    static let portFileName = "adb-server.port"

    public let directory: URL
    public let serverPort: UInt16

    /// `~/Library/Application Support/CarbonMirror/adb/` (inside the sandbox container on macOS).
    public static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("CarbonMirror", isDirectory: true).appendingPathComponent("adb", isDirectory: true)
    }

    /// Creates the private directory with owner-only permissions, tightens any files in it, and picks a port.
    public static func prepare(directory: URL = defaultDirectory()) throws -> AdbEnvironment {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw Failure.cannotCreateDirectory
        }
        do {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            for name in try fm.contentsOfDirectory(atPath: directory.path) {
                let path = directory.appendingPathComponent(name).path
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDir) {
                    try fm.setAttributes([.posixPermissions: isDir.boolValue ? 0o700 : 0o600], ofItemAtPath: path)
                }
            }
        } catch {
            throw Failure.cannotSecure
        }
        let port = UInt16(try CoreCrypto.randomInt(in: portRange))
        return AdbEnvironment(directory: directory, serverPort: port)
    }

    public init(directory: URL, serverPort: UInt16) {
        self.directory = directory
        self.serverPort = serverPort
    }

    /// The complete environment for adb child processes — nothing is inherited from the app's environment.
    public var variables: [String: String] {
        [
            "HOME": directory.path,
            "ANDROID_USER_HOME": directory.path,
            "TMPDIR": directory.path,
            "PATH": "/usr/bin:/bin",
            "ADB_SERVER_SOCKET": "tcp:127.0.0.1:\(serverPort)",
            "ADB_MDNS_OPENSCREEN": "1",
        ]
    }

    /// Same directory, another port (used when the chosen port turns out to be taken).
    public func withPort(_ port: UInt16) -> AdbEnvironment {
        AdbEnvironment(directory: directory, serverPort: port)
    }

    var portFile: URL { directory.appendingPathComponent(Self.portFileName) }

    /// Port of the adb server a previous run started (for launch-time stale-process cleanup).
    func previousPort() -> UInt16? {
        guard let text = try? String(contentsOf: portFile, encoding: .utf8) else { return nil }
        return UInt16(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Records the running server's port, owner-only.
    func recordPort() throws {
        let fm = FileManager.default
        guard fm.createFile(atPath: portFile.path, contents: Data("\(serverPort)\n".utf8), attributes: [.posixPermissions: 0o600]) else {
            throw Failure.cannotSecure
        }
    }

    func forgetPort() {
        try? FileManager.default.removeItem(at: portFile)
    }
}
