import CarbonCoreC

/// Video codec announced by the phone.
public enum VideoCodecID: UInt32, Sendable {
    case h264 = 1
    case h265 = 2
}

/// One parsed video header (payload bytes follow `config` and `frame`).
public enum VideoHeader: Equatable, Sendable {
    case session(width: Int, height: Int)
    case config(size: Int)
    case frame(pts: UInt64, keyFrame: Bool, size: Int)
}

/// One allowlisted message from the phone's control socket; payloads are ranges in the parsed buffer.
public enum DeviceMessage: Equatable, Sendable {
    case clipboard(Range<Int>)
    case ackClipboard(sequence: UInt64)
    case uhidOutput(id: UInt16, Range<Int>)
    case battery(level: Int, charging: Bool)
    case pong(value: UInt64)
}

/// scrcpy framing parsers from the Rust core. Every byte from the phone passes through here first.
public enum ScrcpyProtocol {
    public static let deviceNameLength = Int(DEVICE_NAME_LEN)
    public static let videoHeaderLength = Int(VIDEO_HEADER_LEN)
    public static let maxVideoPacket = Int(MAX_VIDEO_PACKET)
    public static let maxClipboardBytes = Int(MAX_CLIPBOARD_BYTES)

    /// Device name from the 64-byte meta field.
    public static func deviceName(_ buf: UnsafeRawBufferPointer) throws(CoreStatus) -> String {
        var len = 0
        try check(cm_proto_device_name(buf.bindMemory(to: UInt8.self).baseAddress, buf.count, &len))
        return String(decoding: UnsafeRawBufferPointer(rebasing: buf[0..<len]), as: UTF8.self)
    }

    public static func codec(_ buf: UnsafeRawBufferPointer) throws(CoreStatus) -> VideoCodecID {
        var raw: UInt32 = 0
        try check(cm_proto_codec(buf.bindMemory(to: UInt8.self).baseAddress, buf.count, &raw))
        guard let codec = VideoCodecID(rawValue: raw) else { throw CoreStatus.parseMalformed }
        return codec
    }

    public static func videoHeader(_ buf: UnsafeRawBufferPointer) throws(CoreStatus) -> VideoHeader {
        var h = CmVideoHeader()
        try check(cm_proto_video_header(buf.bindMemory(to: UInt8.self).baseAddress, buf.count, &h))
        switch h.kind {
        case 1: return .session(width: Int(h.width), height: Int(h.height))
        case 2: return .config(size: Int(h.size))
        case 3: return .frame(pts: h.pts, keyFrame: h.key_frame != 0, size: Int(h.size))
        default: throw CoreStatus.parseMalformed
        }
    }

    /// Parses one device message at the start of `buf`; returns it and the bytes consumed.
    public static func deviceMessage(_ buf: UnsafeRawBufferPointer) throws(CoreStatus) -> (DeviceMessage, Int) {
        var m = CmDeviceMessage()
        try check(cm_proto_device_message(buf.bindMemory(to: UInt8.self).baseAddress, buf.count, &m))
        let range = m.offset..<(m.offset + m.len)
        switch m.kind {
        case 0: return (.clipboard(range), m.consumed)
        case 1: return (.ackClipboard(sequence: m.sequence), m.consumed)
        case 2: return (.uhidOutput(id: m.id, range), m.consumed)
        case 0x40: return (.battery(level: Int(m.level), charging: m.charging != 0), m.consumed)
        case 0x41: return (.pong(value: m.sequence), m.consumed)
        default: throw CoreStatus.parseMalformed
        }
    }

    /// Video header at `offset` in `buffer`.
    public static func videoHeader(in buffer: [UInt8], at offset: Int) throws(CoreStatus) -> VideoHeader {
        guard offset >= 0, offset <= buffer.count else { throw CoreStatus.invalidArgument }
        var h = CmVideoHeader()
        try check(buffer.withUnsafeBufferPointer { cm_proto_video_header($0.baseAddress.map { $0 + offset }, $0.count - offset, &h) })
        switch h.kind {
        case 1: return .session(width: Int(h.width), height: Int(h.height))
        case 2: return .config(size: Int(h.size))
        case 3: return .frame(pts: h.pts, keyFrame: h.key_frame != 0, size: Int(h.size))
        default: throw CoreStatus.parseMalformed
        }
    }

    /// Device message at the start of `buffer`; returns it and the bytes consumed.
    public static func deviceMessage(in buffer: [UInt8]) throws(CoreStatus) -> (DeviceMessage, Int) {
        var m = CmDeviceMessage()
        try check(buffer.withUnsafeBufferPointer { cm_proto_device_message($0.baseAddress, $0.count, &m) })
        let range = m.offset..<(m.offset + m.len)
        switch m.kind {
        case 0: return (.clipboard(range), m.consumed)
        case 1: return (.ackClipboard(sequence: m.sequence), m.consumed)
        case 2: return (.uhidOutput(id: m.id, range), m.consumed)
        case 0x40: return (.battery(level: Int(m.level), charging: m.charging != 0), m.consumed)
        case 0x41: return (.pong(value: m.sequence), m.consumed)
        default: throw CoreStatus.parseMalformed
        }
    }

    /// Device name and codec from the 68-byte stream preamble.
    public static func preamble(_ buffer: [UInt8]) throws(CoreStatus) -> (name: String, codec: VideoCodecID) {
        guard buffer.count >= deviceNameLength + 4 else { throw CoreStatus.needMoreData }
        var len = 0
        try check(buffer.withUnsafeBufferPointer { cm_proto_device_name($0.baseAddress, deviceNameLength, &len) })
        var raw: UInt32 = 0
        try check(buffer.withUnsafeBufferPointer { cm_proto_codec($0.baseAddress! + deviceNameLength, 4, &raw) })
        guard let codec = VideoCodecID(rawValue: raw) else { throw CoreStatus.parseMalformed }
        return (String(decoding: buffer[0..<len], as: UTF8.self), codec)
    }

    /// Converts Annex B `input` into 4-byte length-prefixed NAL units in `out` (reused by the caller);
    /// returns the bytes written. `out` must hold at least `input.count + 4 * NAL count`.
    public static func lengthPrefixed(_ input: UnsafeRawBufferPointer, into out: UnsafeMutableRawBufferPointer) throws(CoreStatus) -> Int {
        var written = 0
        try check(cm_annexb_to_avcc(input.bindMemory(to: UInt8.self).baseAddress, input.count,
                                    out.bindMemory(to: UInt8.self).baseAddress, out.count, &written))
        return written
    }

    /// Rounded-corner radius (pixels) from `dumpsys display` output.
    public static func cornerRadius(dumpsys: [UInt8]) throws(CoreStatus) -> Int {
        var radius: UInt32 = 0
        let code = dumpsys.withUnsafeBufferPointer { cm_display_corner_radius($0.baseAddress, $0.count, &radius) }
        try check(code)
        return Int(radius)
    }

    /// Clipboard filter: plain UTF-8, no NUL, ≤ 1 MB.
    public static func checkClipboard(_ text: [UInt8]) throws(CoreStatus) {
        try check(text.withUnsafeBufferPointer { cm_clipboard_check($0.baseAddress, $0.count) })
    }
}

/// Phone-pixel position plus the frame size it refers to.
public struct PhonePoint: Equatable, Sendable {
    public var x: Int32
    public var y: Int32
    public var frameWidth: UInt16
    public var frameHeight: UInt16

    public init(x: Int32, y: Int32, frameWidth: UInt16, frameHeight: UInt16) {
        self.x = x
        self.y = y
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
    }

    var c: CmPosition { CmPosition(x: x, y: y, frame_width: frameWidth, frame_height: frameHeight) }
    init(_ p: CmPosition) { self.init(x: p.x, y: p.y, frameWidth: p.frame_width, frameHeight: p.frame_height) }
}

/// Control messages to the phone, encoded by the Rust core.
public enum ControlMessage {
    /// Payload-free / single-byte messages.
    public enum Simple: UInt32, Sendable {
        case backDown = 1, backUp, expandNotifications, expandSettings, collapsePanels, getClipboard
        case displayPowerOff, displayPowerOn, rotateDevice, openHardKeyboardSettings, resetVideo
    }

    /// Android MotionEvent actions used for touches.
    public enum TouchAction: UInt8, Sendable { case down = 0, up = 1, move = 2 }

    /// Pointer ids: a generic finger, and the second virtual finger of a pinch.
    public static let fingerPointer: Int64 = -2
    public static let secondFingerPointer: Int64 = -3

    static let maxMessage = 16 + Int(MAX_CLIPBOARD_BYTES)

    private static func encode(capacity: Int = 64, _ body: (UnsafeMutablePointer<UInt8>?, Int, UnsafeMutablePointer<Int>) -> Int32) throws(CoreStatus) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: capacity)
        var written = 0
        let code = out.withUnsafeMutableBufferPointer { body($0.baseAddress, $0.count, &written) }
        try check(code)
        out.removeSubrange(written...)
        return out
    }

    public static func simple(_ kind: Simple) throws(CoreStatus) -> [UInt8] {
        try encode { cm_ctrl_simple(kind.rawValue, $0, $1, $2) }
    }

    public static func keycode(down: Bool, keycode: Int32, repeatCount: Int32 = 0, meta: Int32) throws(CoreStatus) -> [UInt8] {
        try encode { cm_ctrl_keycode(down ? 0 : 1, keycode, repeatCount, meta, $0, $1, $2) }
    }

    public static func text(_ text: String) throws(CoreStatus) -> [UInt8] {
        let bytes = Array(text.utf8)
        return try encode(capacity: bytes.count + 8) { out, cap, written in
            bytes.withUnsafeBufferPointer { cm_ctrl_text($0.baseAddress, $0.count, out, cap, written) }
        }
    }

    public static func touch(_ action: TouchAction, pointer: Int64 = fingerPointer, at p: PhonePoint, pressure: Float) throws(CoreStatus) -> [UInt8] {
        try encode { cm_ctrl_touch(action.rawValue, pointer, p.c, pressure, 0, 0, $0, $1, $2) }
    }

    public static func scroll(at p: PhonePoint, horizontal: Float, vertical: Float) throws(CoreStatus) -> [UInt8] {
        try encode { cm_ctrl_scroll(p.c, horizontal, vertical, 0, $0, $1, $2) }
    }

    public static func setClipboard(sequence: Int64, text: [UInt8], paste: Bool = false) throws(CoreStatus) -> [UInt8] {
        try encode(capacity: text.count + 16) { out, cap, written in
            text.withUnsafeBufferPointer { cm_ctrl_set_clipboard(sequence, paste ? 1 : 0, $0.baseAddress, $0.count, out, cap, written) }
        }
    }

    public static func uhidCreate(id: UInt16, name: String, descriptor: [UInt8]) throws(CoreStatus) -> [UInt8] {
        let n = Array(name.utf8)
        return try encode(capacity: 16 + n.count + descriptor.count) { out, cap, written in
            n.withUnsafeBufferPointer { nb in
                descriptor.withUnsafeBufferPointer { db in
                    cm_ctrl_uhid_create(id, 0x18D1, 0x4EE7, nb.baseAddress, nb.count, db.baseAddress, db.count, out, cap, written)
                }
            }
        }
    }

    public static func uhidInput(id: UInt16, report: [UInt8]) throws(CoreStatus) -> [UInt8] {
        try encode { out, cap, written in report.withUnsafeBufferPointer { cm_ctrl_uhid_input(id, $0.baseAddress, $0.count, out, cap, written) } }
    }

    public static func uhidDestroy(id: UInt16) throws(CoreStatus) -> [UInt8] {
        try encode { cm_ctrl_uhid_destroy(id, $0, $1, $2) }
    }

    public static func ping(_ value: UInt64) throws(CoreStatus) -> [UInt8] {
        try encode { cm_ctrl_ping(value, $0, $1, $2) }
    }

    public static func startApp(_ package: String) throws(CoreStatus) -> [UInt8] {
        let bytes = Array(package.utf8)
        return try encode(capacity: bytes.count + 4) { out, cap, written in
            bytes.withUnsafeBufferPointer { cm_ctrl_start_app($0.baseAddress, $0.count, out, cap, written) }
        }
    }
}
