import CMCore
import CMCoreBridge
import Foundation

/// App-private adb environment: its own HOME/ANDROID_USER_HOME (0700 dir, 0600 files), never `~/.android`.
/// The adb server and every `adb forward` listen on **Unix-domain sockets** in a 0700 folder inside the app's
/// sandbox container — never on TCP — so no other user, no sandboxed app and nothing on the network can reach
/// adb (whose server protocol has no authentication) or the forwarded session sockets.
public struct AdbEnvironment: Sendable {
    public enum Failure: Error, Equatable {
        case cannotCreateDirectory
        case cannotSecure
        case socketPathTooLong
    }

    /// Longest Unix-socket path macOS accepts (mirrors the Rust allowlist's `MAX_SOCKET_PATH`).
    public static let maxSocketPath = 103
    static let serverSocketName = "cm-adb"

    public let directory: URL
    /// Holds the adb server socket and the forward sockets (short path: the container's `tmp`).
    public let socketDirectory: URL

    /// `~/Library/Application Support/CarbonMirror/adb/` (inside the sandbox container on macOS).
    public static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("CarbonMirror", isDirectory: true).appendingPathComponent("adb", isDirectory: true)
    }

    /// `<container>/Data/tmp/cm/` on macOS (sandboxed `NSTemporaryDirectory`).
    public static func defaultSocketDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cm", isDirectory: true)
    }

    /// Creates both private folders owner-only, tightens files in them, and checks socket paths fit.
    public static func prepare(directory: URL = defaultDirectory(), socketDirectory: URL = defaultSocketDirectory()) throws -> AdbEnvironment {
        let fm = FileManager.default
        for dir in [directory, socketDirectory] {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            } catch {
                throw Failure.cannotCreateDirectory
            }
        }
        do {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: socketDirectory.path)
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
        #if os(macOS)
        // adb's private key stays out of Time Machine and other backups.
        for var dir in [directory, socketDirectory] {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
        }
        #endif
        let environment = AdbEnvironment(directory: directory, socketDirectory: socketDirectory)
        guard (socketDirectory.path + "/cm-f0123456789abcdef").utf8.count <= maxSocketPath else { throw Failure.socketPathTooLong }
        return environment
    }

    public init(directory: URL, socketDirectory: URL) {
        self.directory = directory
        self.socketDirectory = socketDirectory
    }

    /// The adb server's socket file.
    public var serverSocket: String { socketDirectory.path + "/" + Self.serverSocketName }

    /// The complete environment for adb child processes — nothing is inherited from the app's environment.
    public var variables: [String: String] {
        [
            "HOME": directory.path,
            "ANDROID_USER_HOME": directory.path,
            "TMPDIR": directory.path,
            "PATH": "/usr/bin:/bin",
            "ADB_SERVER_SOCKET": "localfilesystem:\(serverSocket)",
            // No emulator scan: adb would otherwise connect, in plaintext and without authenticating the
            // device, to whatever listens on 127.0.0.1:5555–5585 and sign its challenges with the adb key.
            "ADB_EMU": "0",
            // No adb-side mDNS: discovery is CarbonMirror's own (allowlist first), and adb must never
            // auto-connect to an address taken from an mDNS answer.
            "ADB_MDNS": "0",
        ]
    }

    /// A fresh, unguessable forward socket path (`cm-f` + 16 hex digits) in the private folder.
    public func newForwardSocket() throws(CoreStatus) -> String {
        socketDirectory.path + "/cm-f" + CoreCrypto.hex(try CoreCrypto.randomBytes(8))
    }

    /// Whether a server socket from an earlier run is still there (launch-time stale cleanup).
    var hasStaleServerSocket: Bool { FileManager.default.fileExists(atPath: serverSocket) }

    /// Removes a socket file (adb does not unlink them itself).
    func removeSocket(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
