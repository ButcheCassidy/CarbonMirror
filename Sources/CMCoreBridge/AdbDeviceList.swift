// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CarbonCoreC

/// One device line from adb, already validated by the Rust parser.
public struct AdbListedDevice: Equatable, Sendable {
    public enum Link: String, Sendable { case usb, wireless }

    public let serial: String
    public let state: String
    public let model: String
    public let transportID: UInt32
    public let link: Link

    /// Ready for mirroring (authorised and online).
    public var isOnline: Bool { state == "device" }
}

/// Parsers for adb's device list output (model names come from the phone, so Rust checks them first).
public enum AdbDeviceList {
    /// Parses `adb devices -l` text / a `track-devices` payload.
    public static func parse(_ bytes: [UInt8]) throws(CoreStatus) -> [AdbListedDevice] {
        var needed = 0
        var out = [UInt8](repeating: 0, count: max(256, bytes.count * 2))
        var code = parseInto(bytes, &out, &needed)
        if code == CoreStatus.bufferTooSmall.rawValue {
            out = [UInt8](repeating: 0, count: needed)
            code = parseInto(bytes, &out, &needed)
        }
        try check(code)
        let text = String(decoding: out[0..<needed], as: UTF8.self)
        return text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count == 5, let id = UInt32(f[3]), let link = AdbListedDevice.Link(rawValue: String(f[4])) else { return nil }
            return AdbListedDevice(serial: String(f[0]), state: String(f[1]), model: String(f[2]), transportID: id, link: link)
        }
    }

    private static func parseInto(_ bytes: [UInt8], _ out: inout [UInt8], _ needed: inout Int) -> Int32 {
        let cap = out.count
        return bytes.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                cm_adb_parse_devices(src.baseAddress, src.count, dst.baseAddress, cap, &needed)
            }
        }
    }

    /// Locates one complete `track-devices` frame at the start of `buffer`; nil until enough bytes arrive.
    public static func trackFrame(_ buffer: [UInt8]) throws(CoreStatus) -> Range<Int>? {
        var offset = 0
        var length = 0
        let code = buffer.withUnsafeBufferPointer { cm_adb_track_frame($0.baseAddress, $0.count, &offset, &length) }
        if code == CoreStatus.needMoreData.rawValue { return nil }
        try check(code)
        return offset..<(offset + length)
    }
}
