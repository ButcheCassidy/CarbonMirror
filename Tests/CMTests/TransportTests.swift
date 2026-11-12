import CMCoreBridge
import CMTransport
import Foundation
import Testing

/// A private adb directory and a runner that executes the fake adb fixture instead of the real one.
struct FakeAdb {
    let directory: URL
    let runner: AdbRunner

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("cm-test-\(UUID().uuidString)", isDirectory: true)
        let env = try AdbEnvironment.prepare(directory: directory, socketDirectory: directory.appendingPathComponent("s", isDirectory: true))
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/fake-adb.sh")
        runner = AdbRunner(executable: fixture, environment: env)
    }

    var log: [String] {
        let text = (try? String(contentsOf: directory.appendingPathComponent("fake-adb.log"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@Suite("adb transport", .serialized)
struct TransportTests {
    static let serial = "3A091FDJH00ABC"
    static let resources = "/Applications/CarbonMirror.app/Contents/Resources"

    @Test func everyCommandTheAppCanBuildIsAllowlisted() throws {
        let options = ServerOptions.usbPerformance(version: "5.0", scid: 0x0BAD_CAFE, clipboardAutosync: true)
        let commands: [(AdbCommand, Bool, Bool)] = [
            (.startServer, false, false), (.killServer, false, false), (.listDevices, false, false), (.trackDevices, false, false),
            (.connect(ip: "192.168.1.20", port: 37099), false, false), (.disconnect(ip: "fe80::1%en0", port: 40001), false, false),
            (.pair(ip: "192.168.1.20", port: 41234, secret: "482913"), false, false),
            (.forward(serial: Self.serial, localSocket: "/tmp/cm/cm-f0123456789abcdef", scid: 0xFBAD_CAFE), false, false),
            (.removeForward(serial: Self.serial, localSocket: "/tmp/cm/cm-f0123456789abcdef"), false, false),
            (.pushServer(serial: Self.serial, localPath: "\(Self.resources)/carbonmirror-server"), false, false),
            (.pushCoreLibrary(serial: Self.serial, localPath: "\(Self.resources)/libcarbon_core.so"), false, false),
            (.startMirrorServer(serial: Self.serial, options: options), false, false),
            (.disableWirelessDebugging(serial: Self.serial), false, false), (.grantCompanionPermission(serial: Self.serial), false, false),
            (.readDisplayInfo(serial: Self.serial), false, false), (.removeServerFiles(serial: Self.serial), false, false),
            (.removeMacPin(serial: Self.serial), false, false),
            (.installCompanion(serial: Self.serial, apkPath: "\(Self.resources)/CarbonMirrorCompanion.apk"), true, true),
        ]
        for (command, usb, confirmed) in commands {
            #expect(throws: Never.self, "\(command.argv)") { try AdbPolicy.validate(command.argv, usb: usb, confirmed: confirmed) }
        }
    }

    @Test func injectedValuesAreRefusedBeforeAdbStarts() async throws {
        let fake = try FakeAdb()
        defer { fake.remove() }
        let hostile: [AdbCommand] = [
            .readDisplayInfo(serial: "SERIAL;reboot"),
            .readDisplayInfo(serial: "-a"),
            .connect(ip: "$(reboot)", port: 37099),
            .connect(ip: "8.8.8.8", port: 37099),
            .connect(ip: "192.168.1.20", port: 5555),
            .pair(ip: "192.168.1.20", port: 41234, secret: "1 2 3"),
            .pushServer(serial: Self.serial, localPath: "/Users/me/Documents/notes.txt"),
            .startMirrorServer(serial: Self.serial, options: ServerOptions(version: "5.0;id", scid: 1, codec: .h264, maxSize: 2992, maxFPS: 120, bitRate: 32_000_000, clipboardAutosync: true, stayAwake: true)),
            .startMirrorServer(serial: Self.serial, options: ServerOptions(version: "5.0", scid: 1, codec: .h264, maxSize: 99999, maxFPS: 120, bitRate: 32_000_000, clipboardAutosync: true, stayAwake: true)),
        ]
        for command in hostile {
            await #expect(throws: AdbRunError.self, "\(command.argv)") { _ = try await fake.runner.run(command) }
        }
        #expect(fake.log.isEmpty, "adb must never have been started")
    }

    @Test func installNeedsUSBAndConfirmation() async throws {
        let fake = try FakeAdb()
        defer { fake.remove() }
        let install = AdbCommand.installCompanion(serial: Self.serial, apkPath: "\(Self.resources)/CarbonMirrorCompanion.apk")
        await #expect(throws: AdbRunError.refused(.adbInstallNeedsConfirmation)) { _ = try await fake.runner.run(install, usb: true) }
        await #expect(throws: AdbRunError.refused(.adbInstallNeedsUsb)) { _ = try await fake.runner.run(install, confirmed: true) }
        let ok = try await fake.runner.run(install, usb: true, confirmed: true)
        #expect(ok.succeeded)
        #expect(fake.log == ["-s \(Self.serial) install -r \(Self.resources)/CarbonMirrorCompanion.apk"])
    }

    @Test func environmentIsPrivateAndLocalOnly() throws {
        let fake = try FakeAdb()
        defer { fake.remove() }
        let env = fake.runner.environment
        let perms = try FileManager.default.attributesOfItem(atPath: env.directory.path)[.posixPermissions] as? Int
        #expect(perms == 0o700)
        #expect(env.variables["ADB_SERVER_SOCKET"] == "localfilesystem:\(env.serverSocket)", "Unix socket, never TCP")
        #expect(env.variables["ADB_EMU"] == "0", "no plaintext emulator transports on localhost")
        #expect(env.variables["ADB_MDNS"] == "0", "adb never auto-connects from mDNS answers")
        #expect(!env.variables.values.contains { $0.contains("tcp:") })
        let socketPerms = try FileManager.default.attributesOfItem(atPath: env.socketDirectory.path)[.posixPermissions] as? Int
        #expect(socketPerms == 0o700)
        let forward = try env.newForwardSocket()
        #expect(forward.hasPrefix(env.socketDirectory.path + "/cm-f") && forward.utf8.count <= AdbEnvironment.maxSocketPath)
        #expect(forward != (try env.newForwardSocket()), "unguessable per session")
        #expect(throws: AdbEnvironment.Failure.socketPathTooLong) {
            try AdbEnvironment.prepare(directory: env.directory, socketDirectory: env.directory.appendingPathComponent(String(repeating: "x", count: 100)))
        }
        #expect(env.variables["HOME"] == env.directory.path)
        #expect(env.variables["ANDROID_USER_HOME"] == env.directory.path)
        #expect(!(env.variables["HOME"] ?? "").hasSuffix(".android"))
    }

    @Test func runnerReturnsOutputAndExitCode() async throws {
        let fake = try FakeAdb()
        defer { fake.remove() }
        let result = try await fake.runner.run(.listDevices)
        #expect(result.succeeded)
        let devices = try AdbDeviceList.parse(result.output)
        #expect(devices.map(\.serial) == ["SERIAL1"])
        #expect(devices.first?.link == .usb)
    }

    @Test func supervisorLifecycle() async throws {
        let fake = try FakeAdb()
        defer { fake.remove() }
        #expect(FileManager.default.createFile(atPath: fake.runner.environment.serverSocket, contents: nil), "stale socket from a previous run")
        let supervisor = AdbSupervisor(runner: fake.runner)
        try await supervisor.start()
        #expect(await supervisor.state == .running)

        var iterator = supervisor.deviceUpdates.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.map(\.serial) == ["SERIAL1"])
        #expect(first?.first?.model == "Pixel_10_Pro_XL")

        await supervisor.stop()
        #expect(await supervisor.state == .stopped)
        #expect(ChildProcesses.shared.count == 0)
        let log = fake.log
        #expect(log.first == "kill-server", "stale server from the previous run is killed first")
        #expect(log.contains("start-server"))
        #expect(log.contains("track-devices -l"))
        #expect(log.last == "kill-server")
        #expect(!FileManager.default.fileExists(atPath: fake.runner.environment.serverSocket))
    }

    @Test func supervisorRestartsAfterCrash() async throws {
        let fake = try FakeAdb()
        defer { fake.remove() }
        #expect(FileManager.default.createFile(atPath: fake.directory.appendingPathComponent("crash-once").path, contents: Data()))
        let supervisor = AdbSupervisor(runner: fake.runner)
        try await supervisor.start()
        let deadline = Date().addingTimeInterval(5)
        while fake.log.filter({ $0 == "track-devices -l" }).count < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let log = fake.log
        #expect(log.filter { $0 == "track-devices -l" }.count == 2, "watch restarted after the crash")
        #expect(log.filter { $0 == "start-server" }.count == 2, "server restarted after the crash")
        await supervisor.stop()
        #expect(ChildProcesses.shared.count == 0)
    }

    @Test func deployerPushesOnlyVerifiedBytes() async throws {
        let fake = try FakeAdb()
        defer { fake.remove() }
        let source = fake.directory.appendingPathComponent("bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let server = source.appendingPathComponent("carbonmirror-server")
        let library = source.appendingPathComponent("libcarbon_core.so")
        try Data("server-bytes".utf8).write(to: server)
        try Data("library-bytes".utf8).write(to: library)
        let manifest = try ArtifactManifest(serverSHA256Hex: try CoreCrypto.sha256Hex(Array("server-bytes".utf8)),
                                            coreLibrarySHA256Hex: try CoreCrypto.sha256Hex(Array("library-bytes".utf8)))
        let deployer = ServerDeployer(runner: fake.runner, serverURL: server, coreLibraryURL: library, manifest: manifest)
        try await deployer.deploy(to: Self.serial)
        let staging = fake.directory.appendingPathComponent("staging").path
        #expect(fake.log == [
            "-s \(Self.serial) push \(staging)/carbonmirror-server /data/local/tmp/carbonmirror-server.jar",
            "-s \(Self.serial) push \(staging)/libcarbon_core.so /data/local/tmp/libcarbon_core.so",
        ])
        #expect((try FileManager.default.contentsOfDirectory(atPath: staging)).isEmpty, "staging copies removed after push")

        try Data("tampered".utf8).write(to: server)
        await #expect(throws: ServerDeployer.Failure.hashMismatch) { try await deployer.deploy(to: Self.serial) }
        #expect(fake.log.count == 2, "nothing pushed after tampering")

        await deployer.cleanup(on: Self.serial)
        #expect(fake.log.last == "-s \(Self.serial) shell rm -f /data/local/tmp/carbonmirror-server.jar /data/local/tmp/libcarbon_core.so")
    }

    @Test func manifestNeedsBothHashes() {
        #expect(throws: CoreStatus.invalidArgument) { try ArtifactManifest(infoDictionary: ["CMServerSHA256": String(repeating: "a", count: 64)]) }
        #expect(throws: CoreStatus.invalidArgument) { try ArtifactManifest(serverSHA256Hex: "", coreLibrarySHA256Hex: "") }
    }
}
