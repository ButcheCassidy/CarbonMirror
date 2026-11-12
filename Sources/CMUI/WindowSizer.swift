#if os(macOS)
import AppKit
import CMCore
import CMCoreBridge

/// Window sizing relative to the real phone (spec 2.5): real size from `CGDisplayScreenSize()` and the
/// screen's point width (correct at any scaled resolution), 0.75×–2.0× clamped to the visible frame,
/// aspect locked during live resize, ⌘0 real size, and size/position remembered per orientation.
@MainActor
final class WindowSizer {
    /// Points per inch of the default 16" MacBook Pro "Looks like 1728×1117" — used only if a display
    /// reports no physical size (some projectors and virtual displays).
    static let fallbackPointsPerInch = 127.0
    static let plausiblePointsPerInch = 96.0...254.0

    var profile = PhoneProfile.pixel10ProXL
    var landscape = false
    private let settings: AppSettings
    private let defaults: UserDefaults

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
    }

    /// Mac points per physical inch on `screen`.
    func pointsPerInch(on screen: NSScreen) -> Double {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return Self.fallbackPointsPerInch
        }
        let millimetres = CGDisplayScreenSize(CGDirectDisplayID(number.uint32Value))
        let measured = (try? SizeMath.pointsPerInch(displayWidthPoints: Double(screen.frame.width),
                                                    displayWidthMillimetres: Double(millimetres.width))) ?? Self.fallbackPointsPerInch
        // TVs, projectors and virtual displays report sizes that would make the window unusably small or huge.
        return min(Self.plausiblePointsPerInch.upperBound, max(Self.plausiblePointsPerInch.lowerBound, measured))
    }

    /// Screen size (points) at which the phone appears at its real size on `screen`.
    func realSize(on screen: NSScreen) -> CoreSize {
        let pixels = profile.pixels(landscape: landscape)
        return (try? SizeMath.realSize(phonePixels: pixels, phonePPI: profile.pixelsPerInch, macPointsPerInch: pointsPerInch(on: screen)))
            ?? CoreSize(width: pixels.width / 2, height: pixels.height / 2)
    }

    /// Screen size for a requested scale, leaving room for the chrome so revealing it never overflows.
    func screenSize(scale: Double, on screen: NSScreen) -> NSSize {
        let real = realSize(on: screen)
        let visible = CoreSize(width: Double(screen.visibleFrame.width), height: Double(screen.visibleFrame.height))
        let full = ChromeGeometry.insets(progress: 1)
        let insets = CoreInsets(top: full.top, left: full.left, bottom: full.bottom, right: full.right)
        guard let fitted = try? SizeMath.clamp(real: real, scale: scale, insets: insets, visible: visible) else {
            return NSSize(width: real.width, height: real.height)
        }
        return NSSize(width: fitted.size.width, height: fitted.size.height)
    }

    /// Frame size for one live-resize step (aspect locked, scale limits, fits the visible frame with chrome).
    func lockedFrameSize(proposed: NSSize, currentScreen: NSSize, chromeInsets: NSEdgeInsets, on screen: NSScreen) -> NSSize {
        let full = ChromeGeometry.insets(progress: 1)
        let visible = CoreSize(width: Double(screen.visibleFrame.width) - (full.left + full.right - chromeInsets.left - chromeInsets.right),
                               height: Double(screen.visibleFrame.height) - (full.top + full.bottom - chromeInsets.top - chromeInsets.bottom))
        let insets = CoreInsets(top: chromeInsets.top, left: chromeInsets.left, bottom: chromeInsets.bottom, right: chromeInsets.right)
        guard let size = try? SizeMath.lockedResize(currentScreen: CoreSize(width: currentScreen.width, height: currentScreen.height),
                                                    proposedFrame: CoreSize(width: proposed.width, height: proposed.height),
                                                    insets: insets, real: realSize(on: screen), visible: visible) else {
            return NSSize(width: currentScreen.width + chromeInsets.left + chromeInsets.right,
                          height: currentScreen.height + chromeInsets.top + chromeInsets.bottom)
        }
        return NSSize(width: size.width, height: size.height)
    }

    /// Screen rect for `scale`, centred on `center`, kept inside the visible frame.
    func screenRect(scale: Double, center: NSPoint, on screen: NSScreen) -> NSRect {
        let size = screenSize(scale: scale, on: screen)
        let rect = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        return constrain(rect, to: screen)
    }

    /// Current scale of a screen size relative to the real phone.
    func scale(of screenSize: NSSize, on screen: NSScreen) -> Double {
        let real = realSize(on: screen)
        return real.width > 0 ? Double(screenSize.width) / real.width : 1
    }

    /// Moves `rect` so that it, plus the chrome, lies inside the visible frame.
    func constrain(_ rect: NSRect, to screen: NSScreen) -> NSRect {
        let full = ChromeGeometry.insets(progress: 1)
        let area = screen.visibleFrame
        var r = rect
        r.origin.x = min(max(r.minX, area.minX + full.left), area.maxX - full.right - r.width)
        r.origin.y = min(max(r.minY, area.minY + full.bottom), area.maxY - full.top - r.height)
        return r
    }

    // MARK: Memory per orientation

    private var memoryKey: String { landscape ? "window.landscape.screenRect" : "window.portrait.screenRect" }

    func remember(screenRect: NSRect) {
        guard settings.rememberSize else { return }
        defaults.set(NSStringFromRect(screenRect), forKey: memoryKey)
    }

    /// Remembered screen rect for the current orientation, re-clamped to the screen it is on now.
    func rememberedScreenRect() -> NSRect? {
        guard settings.rememberSize, let text = defaults.string(forKey: memoryKey) else { return nil }
        let rect = NSRectFromString(text)
        guard rect.width > 0, rect.height > 0,
              let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(rect) }) else { return nil }
        let scale = self.scale(of: rect.size, on: screen)
        return screenRect(scale: scale, center: NSPoint(x: rect.midX, y: rect.midY), on: screen)
    }
}
#endif
