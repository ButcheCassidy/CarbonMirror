// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if os(macOS)
import AppKit
import CMCore
import CMCoreBridge

/// Owns the phone window: status states, hover chrome reveal/hide, sizing, pinning and rotation.
@MainActor
final class PhoneWindowController: NSObject, NSWindowDelegate {
    let window: PhoneWindow
    let content: PhoneContentView
    let sizer: WindowSizer
    private let settings: AppSettings

    var onToolbarAction: ((ToolbarItem) -> Void)?
    var onStatusAction: ((StatusContent.Action) -> Void)?

    private(set) var state: UIStateCode = .notPaired
    private var hideTask: Task<Void, Never>?
    private var pointerInZone = false
    private var chromeTransition = 0

    init(settings: AppSettings) {
        self.settings = settings
        let sizer = WindowSizer(settings: settings)
        self.sizer = sizer
        let rect: NSRect
        if let remembered = sizer.rememberedScreenRect() {
            rect = remembered
        } else if let screen = NSScreen.main ?? NSScreen.screens.first {
            rect = sizer.screenRect(scale: 1, center: NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY), on: screen)
        } else {
            // No display at all (launch at login with the lid closed): real size at the origin.
            rect = NSRect(x: 0, y: 0, width: 351, height: 782)
        }
        window = PhoneWindow(contentRect: rect)
        content = PhoneContentView(frame: NSRect(origin: .zero, size: rect.size))
        super.init()
        window.contentView = content
        window.delegate = self
        content.cornerRadius = { [weak self] width in self?.cornerRadius(forScreenWidth: width) ?? width * 0.095 }
        content.onPointer = { [weak self] y in self?.pointerMoved(yFromTop: y) }
        content.chrome.onAction = { [weak self] item in self?.onToolbarAction?(item) }
        content.chrome.onClose = { [weak self] in self?.window.orderOut(nil) }
        content.chrome.onMinimise = { [weak self] in self?.window.miniaturize(nil) }
        content.chrome.onZoom = { [weak self] in self?.toggleZoom() }
        content.screen.statusView.onAction = { [weak self] action in self?.onStatusAction?(action) }
        applySettings()
        settings.observe { [weak self] _ in self?.applySettings() }
        show(state: .notPaired)
    }

    func showWindow() {
        window.makeKeyAndOrderFront(nil)
    }

    /// First show after launch: the startup animation plays at once, before the window is on screen.
    func showWindowWithSplash() {
        content.screen.playSplash { [weak self] in
            guard let self, self.window.isKeyWindow else { return }
            self.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        }
        showWindow()
    }

    // MARK: States

    func show(state: UIStateCode) {
        self.state = state
        content.screen.showStatus(StatusContent.forState(state))
        content.chrome.setSessionActive(state == .mirroring || state == .retryingSilently)
    }

    // MARK: Settings applied live

    private func applySettings() {
        window.sharingType = settings.hideFromCapture ? .none : .readOnly
        window.level = settings.pinOnTop ? .floating : .normal
        var behaviour: NSWindow.CollectionBehavior = [.managed, .fullScreenNone]
        if settings.pinOnTop && settings.pinAcrossSpaces { behaviour.insert(.canJoinAllSpaces) }
        window.collectionBehavior = behaviour
        content.chrome.setToggle(.pinOnTop, on: settings.pinOnTop)
        content.chrome.setToggle(.clipboardSync, on: settings.clipboardSync)
        content.chrome.setTypingMode(settings.typingMode)
        content.needsLayout = true
    }

    private func cornerRadius(forScreenWidth width: CGFloat) -> CGFloat {
        let phoneWidth = sizer.profile.pixels(landscape: sizer.landscape).width
        let radius = try? SizeMath.cornerRadius(windowWidth: Double(width), deviceRadiusPixels: sizer.profile.cornerRadiusPixels,
                                                phoneWidthPixels: phoneWidth, fineTune: settings.cornerFineTune)
        return CGFloat(radius ?? Double(width) * 0.095)
    }

    // MARK: Hover chrome (spec 2.3)

    private func pointerMoved(yFromTop: CGFloat?) {
        let inZone = yFromTop.map { ChromeGeometry.inRevealZone(yFromTop: Double($0), chromeShown: content.chromeShown) } ?? false
        pointerInZone = inZone
        if inZone {
            hideTask?.cancel()
            hideTask = nil
            if !content.chromeShown { setChrome(shown: true) }
        } else if content.chromeShown {
            scheduleHide()
        }
    }

    private func scheduleHide() {
        guard hideTask == nil else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.hideDelay))
            guard let self, !Task.isCancelled else { return }
            self.hideTask = nil
            if !self.pointerInZone { self.setChrome(shown: false) }
        }
    }

    /// Grows (or shrinks) the window around the unmoved, unscaled screen in 200 ms, ease-out.
    func setChrome(shown: Bool) {
        guard shown != content.chromeShown, !window.inLiveResize, !content.screen.splashPlaying else { return }
        let i = Theme.chromeInsets(progress: 1)
        let screenRect = content.convert(content.screen.frame, to: nil)
        let screenOnDesktop = window.convertToScreen(screenRect)
        var target = shown
            ? NSRect(x: screenOnDesktop.minX - i.left, y: screenOnDesktop.minY - i.bottom,
                     width: screenOnDesktop.width + i.left + i.right, height: screenOnDesktop.height + i.top + i.bottom)
            : screenOnDesktop
        if shown, let visible = window.screen?.visibleFrame {
            target.origin.x = max(visible.minX, min(target.minX, visible.maxX - target.width))
            target.origin.y = max(visible.minY, min(target.minY, visible.maxY - target.height))
        }
        chromeTransition += 1
        let transition = chromeTransition
        content.beginChromeTransition(show: shown)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Theme.revealDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(target, display: true)
            content.chrome.animator().alphaValue = shown ? 1 : 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A reveal interrupted by a hide (or the reverse) must not unfreeze the screen size mid-animation.
                guard let self, transition == self.chromeTransition else { return }
                self.content.endChromeTransition()
            }
        })
    }

    // MARK: Sizing

    /// Animates the screen to `scale` × real size around its centre (clamped).
    func setScale(_ scale: Double, animated: Bool = true) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let current = window.convertToScreen(content.convert(content.screen.frame, to: nil))
        let rect = sizer.screenRect(scale: scale, center: NSPoint(x: current.midX, y: current.midY), on: screen)
        let i = content.insets
        let frame = NSRect(x: rect.minX - i.left, y: rect.minY - i.bottom, width: rect.width + i.left + i.right, height: rect.height + i.top + i.bottom)
        window.setFrame(frame, display: true, animate: animated)
    }

    /// "1:1 = 351 × 782 pt" for Settings → Display.
    func realSizeDescription() -> String {
        guard let screen = window.screen ?? NSScreen.main else { return "–" }
        let real = sizer.realSize(on: screen)
        return "1:1 = \(Int(real.width.rounded())) × \(Int(real.height.rounded())) pt (\(Int(sizer.pointsPerInch(on: screen).rounded())) pt per inch)"
    }

    /// ⌘0: real size.
    func snapToRealSize() {
        setScale(1)
    }

    /// Zoom button: real size ⇄ largest size that fits.
    func toggleZoom() {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let current = sizer.scale(of: content.screenSize, on: screen)
        setScale(current < 1.05 ? SizeMath.maxScale : 1)
    }

    /// Rotates the window around its centre to the other orientation (spec 2.5 / 8.2.6).
    func setLandscape(_ landscape: Bool) {
        guard landscape != sizer.landscape, let screen = window.screen ?? NSScreen.main else { return }
        let current = window.convertToScreen(content.convert(content.screen.frame, to: nil))
        sizer.remember(screenRect: current)
        let scale = sizer.scale(of: content.screenSize, on: screen)
        sizer.landscape = landscape
        let rect = sizer.rememberedScreenRect() ?? sizer.screenRect(scale: scale, center: NSPoint(x: current.midX, y: current.midY), on: screen)
        let centred = sizer.constrain(NSRect(x: current.midX - rect.width / 2, y: current.midY - rect.height / 2,
                                             width: rect.width, height: rect.height), to: screen)
        let i = content.insets
        window.setFrame(NSRect(x: centred.minX - i.left, y: centred.minY - i.bottom, width: centred.width + i.left + i.right,
                               height: centred.height + i.top + i.bottom), display: true, animate: true)
    }

    // MARK: NSWindowDelegate

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let screen = sender.screen ?? NSScreen.main else { return frameSize }
        return sizer.lockedFrameSize(proposed: frameSize, currentScreen: content.screenSize, chromeInsets: content.insets, on: screen)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        rememberFrame()
    }

    func windowDidMove(_ notification: Notification) {
        rememberFrame()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        setChrome(shown: true)
        if !pointerInZone { scheduleHide() }
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let screen = window.screen else { return }
        setScale(sizer.scale(of: content.screenSize, on: screen), animated: false)
    }

    private func rememberFrame() {
        guard !window.inLiveResize else { return }
        sizer.remember(screenRect: window.convertToScreen(content.convert(content.screen.frame, to: nil)))
    }
}
#endif
