// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if os(macOS)
import AppKit
import CMCore

/// Monochrome colour that follows the view's effective appearance: (white level, alpha) for dark and for light.
/// Nonisolated on purpose: AppKit may resolve dynamic colours off the main thread.
private func adaptive(dark: (CGFloat, CGFloat), light: (CGFloat, CGFloat)) -> NSColor {
    NSColor(name: nil) { appearance in
        let (white, alpha) = appearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua ? light : dark
        return NSColor(white: white, alpha: alpha)
    }
}

/// Monochrome design tokens (spec 2.1): black, white and greys only, in a dark and a light appearance
/// (Settings → General → Appearance). The phone screen itself stays black in both (mirroring UI opaque).
@MainActor
enum Theme {
    static let background = NSColor.black
    static let primaryText = adaptive(dark: (1, 1), light: (0, 1))
    static let secondaryText = adaptive(dark: (1, 0.6), light: (0, 0.6))
    static let hairline = adaptive(dark: (1, 0.1), light: (0, 0.12))
    static let pillFill = adaptive(dark: (1, 0.16), light: (0, 0.08))
    static let pillFillPressed = adaptive(dark: (1, 0.28), light: (0, 0.16))
    static let chromeFill = adaptive(dark: (0.08, 1), light: (0.94, 1))
    /// Tint of the Liquid Glass behind Settings and the not-connected status screens.
    static let glassTint = adaptive(dark: (0, 0.45), light: (1, 0.45))
    /// Small floating panels (landscape offer).
    static let panelFill = adaptive(dark: (0.12, 0.92), light: (0.97, 0.92))

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

    /// The appearance for the setting; nil follows macOS.
    static func appearance(_ mode: AppSettings.Appearance) -> NSAppearance? {
        switch mode {
        case .automatic: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// `color` resolved for `view`'s appearance (layer colours do not follow appearance changes by themselves).
    static func cg(_ color: NSColor, for view: NSView) -> CGColor {
        var resolved = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { resolved = color.cgColor }
        return resolved
    }

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
