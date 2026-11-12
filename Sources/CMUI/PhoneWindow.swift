// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if os(macOS)
import AppKit

/// Borderless, phone-shaped window (spec 2.2): no title bar, bezel or frame; the content view draws the
/// continuous-corner shape, so the window itself is clear and casts the standard soft shadow around it.
@MainActor
final class PhoneWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .resizable, .miniaturizable, .closable],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = Theme.darkAppearance
        sharingType = .none
        isReleasedWhenClosed = false
        // No "Resume" snapshot of the phone screen in ~/Library/Saved Application State (spec 7.6: no thumbnails).
        isRestorable = false
        isMovableByWindowBackground = false
        collectionBehavior = [.managed, .fullScreenNone]
        title = "CarbonMirror"
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
#endif
