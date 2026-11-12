// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CarbonCoreC

/// Width/height in points or pixels.
public struct CoreSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// The same size turned 90°.
    public var rotated: CoreSize { CoreSize(width: height, height: width) }

    var c: CmSize { CmSize(w: width, h: height) }
    init(_ s: CmSize) { self.init(width: s.w, height: s.h) }
}

/// Space the hover chrome adds around the mirrored screen.
public struct CoreInsets: Equatable, Sendable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = CoreInsets(top: 0, left: 0, bottom: 0, right: 0)

    var c: CmInsets { CmInsets(top: top, left: left, bottom: bottom, right: right) }
}

/// Window sizing maths from the Rust core (real size, 0.75×–2.0× clamp, aspect lock, corner radius).
public enum SizeMath {
    public static let minScale = 0.75
    public static let maxScale = 2.0

    /// Mac points per physical inch from the display width in points and in millimetres.
    public static func pointsPerInch(displayWidthPoints: Double, displayWidthMillimetres: Double) throws(CoreStatus) -> Double {
        var out = 0.0
        try check(cm_mac_points_per_inch(displayWidthPoints, displayWidthMillimetres, &out))
        return out
    }

    /// Size in points at which the phone appears at its real physical size.
    public static func realSize(phonePixels: CoreSize, phonePPI: Double, macPointsPerInch: Double) throws(CoreStatus) -> CoreSize {
        var out = CmSize(w: 0, h: 0)
        try check(cm_size_real(phonePixels.c, phonePPI, macPointsPerInch, &out))
        return CoreSize(out)
    }

    /// Screen size and effective scale for a requested scale.
    public static func clamp(real: CoreSize, scale: Double, insets: CoreInsets, visible: CoreSize) throws(CoreStatus) -> (size: CoreSize, scale: Double) {
        var out = CmSize(w: 0, h: 0)
        var used = 0.0
        try check(cm_size_clamp(real.c, scale, insets.c, visible.c, &out, &used))
        return (CoreSize(out), used)
    }

    /// Frame size for one aspect-locked live-resize step.
    public static func lockedResize(currentScreen: CoreSize, proposedFrame: CoreSize, insets: CoreInsets, real: CoreSize, visible: CoreSize) throws(CoreStatus) -> CoreSize {
        var out = CmSize(w: 0, h: 0)
        try check(cm_size_locked_resize(currentScreen.c, proposedFrame.c, insets.c, real.c, visible.c, &out))
        return CoreSize(out)
    }

    /// Continuous-corner radius in points; `deviceRadiusPixels` nil means "not reported yet".
    public static func cornerRadius(windowWidth: Double, deviceRadiusPixels: Double?, phoneWidthPixels: Double, fineTune: Double) throws(CoreStatus) -> Double {
        var out = 0.0
        try check(cm_corner_radius(windowWidth, deviceRadiusPixels ?? 0, phoneWidthPixels, fineTune, &out))
        return out
    }
}
