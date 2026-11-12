// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if os(macOS)
import AppKit
import CMCore

/// The mirrored screen: a black, continuous-corner surface that hosts the video view (Phase 4) and, when
/// not connected, the glass status screen. Black fill behind the content means no corner bleed during resize.
@MainActor
final class ScreenView: NSView {
    let statusView = StatusView()
    let landscapeOffer = LandscapeOfferView()
    /// Video surface (Metal layer view); installed once the media pipeline exists.
    private(set) var videoView: NSView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = Theme.background.cgColor
        statusView.autoresizingMask = [.width, .height]
        statusView.frame = bounds
        addSubview(statusView)
        addSubview(landscapeOffer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Landscape offer pill: centred, 12 pt below the top edge, never wider than the screen minus margins.
    override func layout() {
        super.layout()
        let size = landscapeOffer.fittingSize
        let width = min(size.width, max(0, bounds.width - 24))
        landscapeOffer.frame = NSRect(x: (bounds.width - width) / 2, y: bounds.height - 12 - size.height, width: width, height: size.height)
    }

    func install(videoView view: NSView) {
        videoView?.removeFromSuperview()
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view, positioned: .below, relativeTo: statusView)
        addSubview(landscapeOffer, positioned: .above, relativeTo: statusView)
        videoView = view
    }

    var cornerRadius: CGFloat = 0 {
        didSet {
            layer?.cornerRadius = cornerRadius
            statusView.cornerRadius = cornerRadius
        }
    }

    private var status: StatusContent?
    private var overlay: NSView?

    /// Status screens sit on glass (clear fill); mirroring is fully opaque black.
    func showStatus(_ content: StatusContent?) {
        status = content
        let glass = content != nil || overlay != nil
        if let content { statusView.show(content) }
        statusView.isHidden = !glass
        statusView.setContentHidden(overlay != nil)
        layer?.backgroundColor = (glass ? NSColor.clear : Theme.background).cgColor
        videoView?.isHidden = glass
    }

    /// Startup animation on OLED black above everything, until the clip ends.
    func playSplash(onFinished: @escaping () -> Void) {
        guard let splash = SplashView(frame: bounds, onFinished: onFinished) else { return onFinished() }
        splash.autoresizingMask = [.width, .height]
        addSubview(splash)
    }

    /// The hover chrome stays hidden meanwhile.
    var splashPlaying: Bool { subviews.contains { $0 is SplashView } }

    /// A full-screen view on the status glass (QR pairing); nil returns to the current state.
    func showOverlay(_ view: NSView?) {
        overlay?.removeFromSuperview()
        overlay = view
        if let view {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view, positioned: .above, relativeTo: statusView)
        }
        showStatus(status)
    }

    /// 1 px inner hairline while the chrome is shown.
    func setInnerHairline(_ on: Bool) {
        layer?.borderWidth = on ? Theme.pixel(for: window) : 0
        layer?.borderColor = Theme.hairline.cgColor
    }
}

/// Window content: the outer continuous-corner shape with its hairline, the screen and the hover chrome.
/// While the chrome animates the window frame grows around the screen; the screen keeps its size and
/// position (`ChromeGeometry.screenOrigin`), so the video never jumps or rescales.
@MainActor
final class PhoneContentView: NSView {
    let screen = ScreenView()
    let chrome = ChromeView()
    /// Called on pointer moves with the distance below the window's top edge (nil = pointer left).
    var onPointer: ((CGFloat?) -> Void)?
    /// Corner radius in points for a screen of the given width.
    var cornerRadius: (CGFloat) -> CGFloat = { $0 * 0.095 }

    /// Fixed while the chrome animates; follows the window otherwise.
    private(set) var screenSize: NSSize = .zero
    private(set) var chromeShown = false
    private var chromeAnimating = false
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderColor = Theme.hairline.cgColor
        addSubview(screen)
        addSubview(chrome)
        chrome.wantsLayer = true
        chrome.layer?.masksToBounds = true
        chrome.alphaValue = 0
        chrome.isHidden = true
        screenSize = frame.size
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    var insets: NSEdgeInsets { Theme.chromeInsets(progress: chromeShown ? 1 : 0) }

    /// Starts or ends a chrome transition; the screen size stays frozen until `endChromeTransition`.
    func beginChromeTransition(show: Bool) {
        chromeAnimating = true
        chromeShown = show
        chrome.isHidden = false
        screen.setInnerHairline(show)
    }

    func endChromeTransition() {
        chromeAnimating = false
        chrome.isHidden = !chromeShown
        needsLayout = true
    }

    override func layout() {
        super.layout()
        if !chromeAnimating {
            let i = insets
            screenSize = NSSize(width: max(1, bounds.width - i.left - i.right), height: max(1, bounds.height - i.top - i.bottom))
        }
        let origin = ChromeGeometry.screenOrigin(frameWidth: Double(bounds.width), frameHeight: Double(bounds.height),
                                                 screenWidth: Double(screenSize.width), screenHeight: Double(screenSize.height))
        screen.frame = NSRect(x: origin.x, y: origin.y, width: screenSize.width, height: screenSize.height)
        let topInset = max(0, bounds.height - screen.frame.maxY)
        chrome.frame = NSRect(x: 0, y: screen.frame.maxY, width: bounds.width, height: topInset)
        let radius = cornerRadius(screenSize.width)
        screen.cornerRadius = radius
        let margin = max(0, screen.frame.minX)
        // Resting: the window is the phone's own shape. Toolbar shown: a normal window with standard corners.
        layer?.cornerRadius = margin > 0.5 ? Theme.windowCornerRadius : radius
        layer?.borderWidth = Theme.pixel(for: window)
        layer?.backgroundColor = (margin > 0.5 ? Theme.chromeFill : NSColor.clear).cgColor
        window?.invalidateShadow()
    }

    // MARK: Hover tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onPointer?(bounds.height - point.y)
    }

    override func mouseEntered(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onPointer?(nil)
    }
}
#endif
