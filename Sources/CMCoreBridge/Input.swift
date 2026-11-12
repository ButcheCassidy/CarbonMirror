// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CarbonCoreC

/// Rectangle in view points, origin top-left.
public struct ViewRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var c: CmRect { CmRect(x: x, y: y, w: width, h: height) }
    init(_ r: CmRect) { self.init(x: r.x, y: r.y, width: r.w, height: r.h) }
}

/// Pointer geometry from the Rust core (spec 5.2/5.5).
public enum InputMapping {
    /// Where a frame sits inside a view (aspect fit, centred).
    public static func letterbox(viewWidth: Double, viewHeight: Double, frameWidth: Int, frameHeight: Int) throws(CoreStatus) -> ViewRect {
        guard let fw = UInt16(exactly: frameWidth), let fh = UInt16(exactly: frameHeight) else { throw CoreStatus.invalidArgument }
        var r = CmRect()
        try check(cm_input_letterbox(viewWidth, viewHeight, fw, fh, &r))
        return ViewRect(r)
    }

    /// View point → phone pixels; outside points throw `inputOutside` unless `clamp`.
    public static func map(x: Double, y: Double, content: ViewRect, frameWidth: Int, frameHeight: Int, clamp: Bool) throws(CoreStatus) -> PhonePoint {
        guard let fw = UInt16(exactly: frameWidth), let fh = UInt16(exactly: frameHeight) else { throw CoreStatus.invalidArgument }
        var p = CmPosition()
        try check(cm_input_map_point(content.c, x, y, fw, fh, clamp ? 1 : 0, &p))
        return PhonePoint(p)
    }

    /// Mac scroll delta → scrcpy units.
    public static func scrollUnits(_ delta: Double, precise: Bool) -> Float {
        var out: Float = 0
        _ = cm_input_scroll_units(delta, precise ? 1 : 0, &out)
        return out
    }

    /// Two virtual-finger positions for a pinch of `spread` pixels around `center`.
    public static func pinch(center: PhonePoint, spread: Double) throws(CoreStatus) -> (PhonePoint, PhonePoint) {
        var a = CmPosition(), b = CmPosition()
        try check(cm_input_pinch(center.c, spread, &a, &b))
        return (PhonePoint(a), PhonePoint(b))
    }
}

/// Keyboard maps from the Rust core (spec 8.2.3).
public enum KeyboardMapping {
    public static let reportLength = Int(HID_REPORT_LEN)

    /// HID report for NSEvent modifier flags + held macOS key codes.
    public static func hidReport(modifierFlags: UInt32, held: [UInt16]) throws(CoreStatus) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: reportLength)
        let code = held.withUnsafeBufferPointer { h in
            out.withUnsafeMutableBufferPointer { cm_key_hid_report(modifierFlags, h.baseAddress, h.count, $0.baseAddress) }
        }
        try check(code)
        return out
    }

    /// The virtual keyboard's HID report descriptor.
    public static func hidDescriptor() throws(CoreStatus) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 128)
        var len = 0
        let code = out.withUnsafeMutableBufferPointer { cm_key_hid_descriptor($0.baseAddress, $0.count, &len) }
        try check(code)
        return Array(out[0..<len])
    }

    /// Android key code and meta state for a macOS key; nil for keys without an Android equivalent.
    public static func android(macKeyCode: UInt16, modifierFlags: UInt32) -> (keycode: Int32, meta: Int32)? {
        var keycode: Int32 = 0, meta: Int32 = 0
        guard cm_key_android(macKeyCode, modifierFlags, &keycode, &meta) == CoreStatus.ok.rawValue else { return nil }
        return (keycode, meta)
    }
}
