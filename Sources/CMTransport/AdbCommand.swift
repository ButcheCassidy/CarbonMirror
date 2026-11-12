import CMCoreBridge

/// Video codec requested from the phone.
public enum VideoCodec: String, Sendable, Codable { case h264, h265 }

/// Typed options for starting the forked scrcpy server. Only numbers, hex and fixed words — nothing that
/// could be interpreted by the phone's shell. The Rust allowlist re-checks every value.
public struct ServerOptions: Equatable, Sendable {
    public var version: String
    public var scid: UInt32
    public var codec: VideoCodec
    public var maxSize: Int
    public var maxFPS: Int
    public var bitRate: Int
    public var clipboardAutosync: Bool
    public var stayAwake: Bool

    public init(version: String, scid: UInt32, codec: VideoCodec, maxSize: Int, maxFPS: Int, bitRate: Int, clipboardAutosync: Bool, stayAwake: Bool) {
        self.version = version
        self.scid = scid
        self.codec = codec
        self.maxSize = maxSize
        self.maxFPS = maxFPS
        self.bitRate = bitRate
        self.clipboardAutosync = clipboardAutosync
        self.stayAwake = stayAwake
    }

    /// USB "Performance" profile: 120 fps, H.264, 32 Mbps, native resolution (2992 long side).
    public static func usbPerformance(version: String, scid: UInt32, clipboardAutosync: Bool) -> ServerOptions {
        ServerOptions(version: version, scid: scid, codec: .h264, maxSize: 2992, maxFPS: 120, bitRate: 32_000_000,
                      clipboardAutosync: clipboardAutosync, stayAwake: true)
    }

    /// Socket id as scrcpy expects it: 8 lower-case hex digits, 31-bit.
    public var scidHex: String { ServerOptions.hex8(scid & 0x7FFF_FFFF) }

    static func hex8(_ v: UInt32) -> String {
        let s = String(v, radix: 16)
        return String(repeating: "0", count: 8 - s.count) + s
    }

    var parameters: [String] {
        [
            "scid=\(scidHex)", "log_level=info", "audio=false", "video=true", "control=true", "tunnel_forward=true",
            "video_source=display", "display_id=0", "video_codec=\(codec.rawValue)", "max_size=\(maxSize)",
            "max_fps=\(maxFPS)", "video_bit_rate=\(bitRate)", "clipboard_autosync=\(clipboardAutosync)",
            "stay_awake=\(stayAwake)", "send_device_meta=true", "send_frame_meta=true", "send_dummy_byte=true",
            "send_stream_meta=true", "cleanup=true", "power_on=true",
        ]
    }
}

/// Every adb invocation CarbonMirror can make. There is no case for arbitrary arguments.
public enum AdbCommand: Equatable, Sendable {
    case startServer
    case killServer
    case listDevices
    case trackDevices
    case connect(ip: String, port: UInt16)
    case disconnect(ip: String, port: UInt16)
    case pair(ip: String, port: UInt16, secret: String)
    case forward(serial: String, localSocket: String, scid: UInt32)
    case removeForward(serial: String, localSocket: String)
    case pushServer(serial: String, localPath: String)
    case pushCoreLibrary(serial: String, localPath: String)
    case startMirrorServer(serial: String, options: ServerOptions)
    case disableWirelessDebugging(serial: String)
    case grantCompanionPermission(serial: String)
    case readDisplayInfo(serial: String)
    case removeServerFiles(serial: String)
    /// "Create new key": lets the phone pin the new Mac identity on the next session.
    case removeMacPin(serial: String)
    case installCompanion(serial: String, apkPath: String)

    public static let remoteServerPath = "/data/local/tmp/carbonmirror-server.jar"
    public static let remoteCoreLibraryPath = "/data/local/tmp/libcarbon_core.so"
    public static let remoteMacPinPath = "/data/local/tmp/carbonmirror-mac.pin"
    public static let companionPackage = "com.nomadicrebel.carbonmirror.companion"
    public static let serverClass = "com.genymobile.scrcpy.Server"

    private static func hostPort(_ ip: String, _ port: UInt16) -> String {
        ip.contains(":") ? "[\(ip)]:\(port)" : "\(ip):\(port)"
    }

    /// Arguments after the adb executable path.
    public var argv: [String] {
        switch self {
        case .startServer: ["start-server"]
        case .killServer: ["kill-server"]
        case .listDevices: ["devices", "-l"]
        case .trackDevices: ["track-devices", "-l"]
        case let .connect(ip, port): ["connect", Self.hostPort(ip, port)]
        case let .disconnect(ip, port): ["disconnect", Self.hostPort(ip, port)]
        case let .pair(ip, port, secret): ["pair", Self.hostPort(ip, port), secret]
        case let .forward(serial, socket, scid):
            ["-s", serial, "forward", "localfilesystem:\(socket)", "localabstract:scrcpy_\(ServerOptions.hex8(scid & 0x7FFF_FFFF))"]
        case let .removeForward(serial, socket): ["-s", serial, "forward", "--remove", "localfilesystem:\(socket)"]
        case let .pushServer(serial, path): ["-s", serial, "push", path, Self.remoteServerPath]
        case let .pushCoreLibrary(serial, path): ["-s", serial, "push", path, Self.remoteCoreLibraryPath]
        case let .startMirrorServer(serial, o):
            ["-s", serial, "shell", "CLASSPATH=\(Self.remoteServerPath)", "app_process", "/", Self.serverClass, o.version] + o.parameters
        case let .disableWirelessDebugging(serial): ["-s", serial, "shell", "settings", "put", "global", "adb_wifi_enabled", "0"]
        case let .grantCompanionPermission(serial):
            ["-s", serial, "shell", "pm", "grant", Self.companionPackage, "android.permission.WRITE_SECURE_SETTINGS"]
        case let .readDisplayInfo(serial): ["-s", serial, "shell", "dumpsys", "display"]
        case let .removeServerFiles(serial): ["-s", serial, "shell", "rm", "-f", Self.remoteServerPath, Self.remoteCoreLibraryPath]
        case let .removeMacPin(serial): ["-s", serial, "shell", "rm", "-f", Self.remoteMacPinPath]
        case let .installCompanion(serial, path): ["-s", serial, "install", "-r", path]
        }
    }
}
