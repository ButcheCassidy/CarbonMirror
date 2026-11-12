// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if os(macOS)
import AppKit
import CMCore

/// Monochrome design tokens (spec 2.1): black, white and greys only; dark appearance always.
@MainActor
enum Theme {
    static let background = NSColor.black
    static let primaryText = NSColor.white
    static let secondaryText = NSColor(white: 1, alpha: 0.6)
    static let hairline = NSColor(white: 1, alpha: 0.1)
    static let pillFill = NSColor(white: 1, alpha: 0.16)
    static let pillFillPressed = NSColor(white: 1, alpha: 0.28)
    static let chromeFill = NSColor(white: 0.08, alpha: 1)

    static let titleFont = NSFont.systemFont(ofSize: 17, weight: .bold)
    static let subtitleFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let pillFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    /// Status line: SF Pro 11 pt with tabular digits (spec 8.2.5).
    static let statusLineFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    /// Hover chrome geometry (spec 2.3).
    static let toolbarHeight = CGFloat(ChromeGeometry.toolbarHeight)
    static let statusLineHeight = CGFloat(ChromeGeometry.statusLineHeight)
    static let chromeMargin = CGFloat(ChromeGeometry.margin)
    /// Window corners while the toolbar shows: a standard macOS window radius, so nothing in the toolbar is clipped.
    static let windowCornerRadius: CGFloat = 12
    static let revealDuration: TimeInterval = 0.2
    static let hideDelay: TimeInterval = 1.2

    /// Glyph size inside status screens and toolbar.
    static let statusGlyphPointSize: CGFloat = 40
    static let toolbarGlyphPointSize: CGFloat = 13

    static let darkAppearance = NSAppearance(named: .darkAqua)

    /// Space the chrome adds around the screen for a reveal progress 0…1.
    static func chromeInsets(progress: CGFloat) -> NSEdgeInsets {
        let i = ChromeGeometry.insets(progress: Double(progress))
        return NSEdgeInsets(top: i.top, left: i.left, bottom: i.bottom, right: i.right)
    }

    /// One line that ends in "…" instead of clipping or wrapping (attributed titles drop the control's own setting).
    static func singleLine(_ alignment: NSTextAlignment) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    /// Monochrome SF Symbol image at a point size.
    static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight))
    }

    /// One device pixel for hairlines.
    static func pixel(for window: NSWindow?) -> CGFloat {
        1 / (window?.backingScaleFactor ?? 2)
    }
}
#endif
