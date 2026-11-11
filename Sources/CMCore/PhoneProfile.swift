import CMCoreBridge

/// Physical facts about the mirrored phone's panel. Defaults are the Pixel 10 Pro XL; at connect time the
/// device meta (Phase 4) replaces the pixel size.
public struct PhoneProfile: Equatable, Sendable, Codable {
    /// Native panel size in portrait, pixels.
    public var widthPixels: Double
    public var heightPixels: Double
    /// Panel density, pixels per inch.
    public var pixelsPerInch: Double
    /// Rounded-corner radius in pixels from `dumpsys display`; nil until read.
    public var cornerRadiusPixels: Double?

    public init(widthPixels: Double, heightPixels: Double, pixelsPerInch: Double, cornerRadiusPixels: Double? = nil) {
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
        self.pixelsPerInch = pixelsPerInch
        self.cornerRadiusPixels = cornerRadiusPixels
    }

    /// Google Pixel 10 Pro XL: 1344 × 2992 px, ~486 ppi (70.2 × 156.4 mm active area).
    public static let pixel10ProXL = PhoneProfile(widthPixels: 1344, heightPixels: 2992, pixelsPerInch: 486)

    /// Panel size for an orientation.
    public func pixels(landscape: Bool) -> CoreSize {
        let portrait = CoreSize(width: widthPixels, height: heightPixels)
        return landscape ? portrait.rotated : portrait
    }
}
