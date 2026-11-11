/// Toolbar buttons of the hover chrome, in the order the spec puts them (2.3, left → right after the
/// traffic lights).
public enum ToolbarItem: String, CaseIterable, Sendable {
    case back, home, recents, appDrawer, notifications, quickSettings, screenshot, clipboardSync, privacyBlur
    case typingMode, rotate, volumeDown, volumeUp, mute, lock, connection, pinOnTop, settings

    /// Monochrome SF Symbol.
    public var symbol: String {
        switch self {
        case .back: "chevron.backward"
        case .home: "circle"
        case .recents: "square.on.square"
        case .appDrawer: "square.grid.3x3"
        case .notifications: "bell"
        case .quickSettings: "switch.2"
        case .screenshot: "camera.viewfinder"
        case .clipboardSync: "doc.on.clipboard"
        case .privacyBlur: "eye.slash"
        case .typingMode: "keyboard"
        case .rotate: "rotate.right"
        case .volumeDown: "speaker.wave.1"
        case .volumeUp: "speaker.wave.3"
        case .mute: "speaker.slash"
        case .lock: "power"
        case .connection: "cable.connector"
        case .pinOnTop: "pin"
        case .settings: "gearshape"
        }
    }

    /// Tooltip and overflow-menu title, with the keyboard shortcut (spec 5.4 / 8.2).
    public var title: String {
        switch self {
        case .back: "Back (⌘[)"
        case .home: "Home (⌘1)"
        case .recents: "Recents (⌘2)"
        case .appDrawer: "App drawer (⌘3)"
        case .notifications: "Notifications (⌘4)"
        case .quickSettings: "Quick Settings (⌘5)"
        case .screenshot: "Screenshot to Mac (⌘S)"
        case .clipboardSync: "Clipboard sync (⇧⌘C)"
        case .privacyBlur: "Privacy blur (⇧⌘H)"
        case .typingMode: "Typing mode (⌥⌘K)"
        case .rotate: "Rotate (⌘R)"
        case .volumeDown: "Volume down (⌘↓)"
        case .volumeUp: "Volume up (⌘↑)"
        case .mute: "Mute"
        case .lock: "Lock (⌘L)"
        case .connection: "Connection"
        case .pinOnTop: "Pin on top (⌘P)"
        case .settings: "Settings (⌘,)"
        }
    }

    /// Needs a live session (disabled while a status screen is shown).
    public var needsSession: Bool {
        switch self {
        case .pinOnTop, .settings, .connection, .clipboardSync, .typingMode: false
        default: true
        }
    }

    /// Width in points: icon buttons are square, the connection badge carries text.
    public var width: Double {
        self == .connection ? ChromeLayout.badgeWidth : ChromeLayout.buttonSize
    }
}

/// Geometry of the hover-chrome toolbar row (spec 2.3). Pure maths so it is tested on Linux at every
/// window width from 0.75× to the maximum: buttons never overlap, never leave the toolbar, and the ones
/// that do not fit collapse — trailing first — into the overflow (…) menu.
public enum ChromeLayout {
    public static let buttonSize = 22.0
    public static let spacing = 2.0
    public static let badgeWidth = 66.0
    /// Traffic lights: three 14 pt buttons, 20 pt apart, 8 pt from the leading edge, then a 10 pt gap.
    public static let trafficLightSize = 14.0
    public static let trafficLightPitch = 20.0
    public static let leadingInset = 8.0
    public static let trafficLightsWidth = leadingInset + 2 * trafficLightPitch + trafficLightSize + 10
    public static let trailingInset = 8.0

    public struct Placement: Equatable, Sendable {
        public let item: ToolbarItem
        /// Leading x inside the toolbar, points.
        public let x: Double
        public let width: Double
    }

    public struct Result: Equatable, Sendable {
        public let visible: [Placement]
        public let overflow: [ToolbarItem]
        /// Leading x of the overflow (…) button; nil when everything fits.
        public let overflowX: Double?
    }

    /// Lays out `items` in a toolbar `width` points wide.
    public static func layout(width: Double, items: [ToolbarItem] = ToolbarItem.allCases) -> Result {
        let available = max(0, width - trafficLightsWidth - trailingInset)
        let total = items.reduce(0) { $0 + $1.width } + spacing * Double(max(0, items.count - 1))
        if total <= available {
            return Result(visible: place(items, from: trafficLightsWidth), overflow: [], overflowX: nil)
        }
        let room = available - buttonSize - spacing
        var used = 0.0
        var count = 0
        for item in items {
            let next = used + (count > 0 ? spacing : 0) + item.width
            if next > room { break }
            used = next
            count += 1
        }
        let shown = Array(items.prefix(count))
        let overflowX = trafficLightsWidth + used + (count > 0 ? spacing : 0)
        return Result(visible: place(shown, from: trafficLightsWidth), overflow: Array(items.dropFirst(count)), overflowX: overflowX)
    }

    private static func place(_ items: [ToolbarItem], from start: Double) -> [Placement] {
        var x = start
        return items.map { item in
            defer { x += item.width + spacing }
            return Placement(item: item, x: x, width: item.width)
        }
    }

    /// Leading x of traffic light `index` (0 close, 1 minimise, 2 zoom).
    public static func trafficLightX(_ index: Int) -> Double {
        leadingInset + Double(index) * trafficLightPitch
    }
}

/// Where the mirrored screen sits inside the window while the chrome grows around it (spec 2.3): the screen
/// keeps its size and its place on the desktop, the window gains `top` above and `margin` on the other sides.
public enum ChromeGeometry {
    public static let toolbarHeight = 44.0
    public static let statusLineHeight = 14.0
    public static let margin = 10.0
    public static let hoverZoneHeight = 28.0

    public static let top = toolbarHeight + statusLineHeight

    /// Insets for a chrome reveal progress 0 (hidden) … 1 (shown).
    public static func insets(progress: Double) -> (top: Double, left: Double, bottom: Double, right: Double) {
        let p = min(1, max(0, progress))
        return (top * p, margin * p, margin * p, margin * p)
    }

    /// Screen origin inside a window of `frame` size holding a screen of `screen` size: horizontally centred,
    /// vertically split in the top : bottom inset ratio, so a linear frame animation never moves the screen.
    public static func screenOrigin(frameWidth: Double, frameHeight: Double, screenWidth: Double, screenHeight: Double) -> (x: Double, y: Double) {
        let x = (frameWidth - screenWidth) / 2
        let y = (frameHeight - screenHeight) * margin / (margin + top)
        return (max(0, x), max(0, y))
    }

    /// True when a pointer at `yFromTop` points below the window's top edge is in the reveal zone.
    public static func inRevealZone(yFromTop: Double, chromeShown: Bool) -> Bool {
        yFromTop >= 0 && yFromTop <= hoverZoneHeight + (chromeShown ? top : 0)
    }
}
