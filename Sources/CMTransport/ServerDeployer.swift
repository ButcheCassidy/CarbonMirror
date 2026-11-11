import CMCore
import CMCoreBridge
import Foundation

/// Expected SHA-256s of the files pushed to the phone, read from the app's signed Info.plist
/// (`CMServerSHA256`, `CMCoreLibSHA256`, written by `scripts/build.sh`).
public struct ArtifactManifest: Equatable, Sendable {
    public static let serverKey = "CMServerSHA256"
    public static let coreLibraryKey = "CMCoreLibSHA256"

    public let serverSHA256: [UInt8]
    public let coreLibrarySHA256: [UInt8]

    public init(serverSHA256Hex: String, coreLibrarySHA256Hex: String) throws(CoreStatus) {
        serverSHA256 = try CoreCrypto.bytes(fromHex: serverSHA256Hex)
        coreLibrarySHA256 = try CoreCrypto.bytes(fromHex: coreLibrarySHA256Hex)
    }

    /// Reads both hashes from an Info.plist dictionary.
    public init(infoDictionary: [String: Any]) throws(CoreStatus) {
        guard let s = infoDictionary[Self.serverKey] as? String, let l = infoDictionary[Self.coreLibraryKey] as? String else {
            throw CoreStatus.invalidArgument
        }
        try self.init(serverSHA256Hex: s, coreLibrarySHA256Hex: l)
    }
}

/// Pushes the forked server and `libcarbon_core.so` to their fixed paths on the phone — only after their
/// bytes match the pinned hashes. The verified bytes are copied to a private staging file first and that copy
/// is pushed, so the file can't be swapped between the check and the push.
public struct ServerDeployer: Sendable {
    public enum Failure: Error, Equatable {
        case unreadable
        case tooLarge
        case hashMismatch
        case stagingFailed
        case pushFailed(AdbRunError)
    }

    /// Largest artifact accepted (the server jar is ~100 KB, the core library a few MB).
    public static let maxArtifactBytes = 64 << 20
    static let stagingFolder = "staging"
    static let serverFileName = "carbonmirror-server"
    static let coreLibraryFileName = "libcarbon_core.so"

    public let runner: AdbRunner
    public let serverURL: URL
    public let coreLibraryURL: URL
    public let manifest: ArtifactManifest

    public init(runner: AdbRunner, serverURL: URL, coreLibraryURL: URL, manifest: ArtifactManifest) {
        self.runner = runner
        self.serverURL = serverURL
        self.coreLibraryURL = coreLibraryURL
        self.manifest = manifest
    }

    /// Verifies, stages and pushes both artifacts to `serial`.
    public func deploy(to serial: String) async throws(Failure) {
        let server = try stage(serverURL, expected: manifest.serverSHA256, as: Self.serverFileName)
        let library = try stage(coreLibraryURL, expected: manifest.coreLibrarySHA256, as: Self.coreLibraryFileName)
        defer {
            try? FileManager.default.removeItem(at: server)
            try? FileManager.default.removeItem(at: library)
        }
        do {
            try await runner.runChecked(.pushServer(serial: serial, localPath: server.path), timeout: 60)
            try await runner.runChecked(.pushCoreLibrary(serial: serial, localPath: library.path), timeout: 60)
        } catch {
            Log.error(.adb, "server push failed")
            throw .pushFailed(error)
        }
        Log.info(.adb, "server and core library pushed (hash-verified)")
    }

    /// Removes the server's files from the phone (on session end and on quit).
    public func cleanup(on serial: String) async {
        _ = try? await runner.run(.removeServerFiles(serial: serial), timeout: 10)
    }

    /// Reads `url`, checks its SHA-256, and writes the verified bytes to an owner-only staging file.
    func stage(_ url: URL, expected: [UInt8], as name: String) throws(Failure) -> URL {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes?[.size] as? Int else { throw .unreadable }
        guard size <= Self.maxArtifactBytes else { throw .tooLarge }
        guard let data = FileManager.default.contents(atPath: url.path) else { throw .unreadable }
        let bytes = [UInt8](data)
        guard bytes.count <= Self.maxArtifactBytes else { throw .tooLarge }
        do {
            try CoreCrypto.verifySHA256(bytes, expected: expected)
        } catch {
            Log.error(.security, "bundled artifact hash mismatch")
            throw .hashMismatch
        }
        let folder = runner.environment.directory.appendingPathComponent(Self.stagingFolder, isDirectory: true)
        let target = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? FileManager.default.removeItem(at: target)
        } catch {
            throw .stagingFailed
        }
        guard FileManager.default.createFile(atPath: target.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw .stagingFailed
        }
        return target
    }
}
