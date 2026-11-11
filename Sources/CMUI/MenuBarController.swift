#if os(macOS)
import AppKit

/// Monochrome menu-bar extra. The icon is a template image drawn in code at 18 pt (two overlapping phone
/// outlines, no colour), so macOS tints it for light and dark menu bars.
@MainActor
final class MenuBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(menu: NSMenu) {
        super.init()
        item.button?.image = Self.templateIcon()
        item.button?.setAccessibilityLabel("CarbonMirror")
        item.menu = menu
    }

    /// Two overlapping continuous-corner phone outlines: the back one offset up-right, the front one down-left.
    static func templateIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let back = NSBezierPath(roundedRect: NSRect(x: 7.5, y: 3.5, width: 7.5, height: 13), xRadius: 2, yRadius: 2)
            back.lineWidth = 1.4
            back.stroke()
            let front = NSRect(x: 3, y: 1.5, width: 7.5, height: 13)
            NSColor.clear.setFill()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(roundedRect: front.insetBy(dx: -1, dy: -1), xRadius: 2.5, yRadius: 2.5).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            let outline = NSBezierPath(roundedRect: front, xRadius: 2, yRadius: 2)
            outline.lineWidth = 1.4
            outline.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "CarbonMirror"
        return image
    }
}
#endif
