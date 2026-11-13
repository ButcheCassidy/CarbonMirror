// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if os(macOS)
import AppKit
import CMCore
import CMInput
import CMMedia

/// The live phone screen: hosts the Metal video surface and turns Mac input into control messages
/// (spec 5.2–5.5): click = tap, drag = swipe, hold = long press, two-finger scroll = scroll, pinch = pinch,
/// right-click = Back (setting), keyboard in either typing mode. Messages leave on a dedicated serial
/// high-priority queue, in order. While the privacy blur is on, nothing is sent and a lock glyph is shown;
/// a click asks to reveal.
@MainActor
final class MirrorView: NSView {
    let video = MetalScreenView()
    let engine = InputEngine()
    /// Sends one encoded control message (the session's thread-safe, ordered `send`).
    var sender: (@Sendable ([UInt8]) -> Void)?
    /// Any user input (idle timeout, spec 7.6).
    var onActivity: (() -> Void)?
    /// Click while blurred.
    var onRevealRequest: (() -> Void)?

    private let lockGlyph = NSImageView()
    /// Debug HUD (View menu, spec 4.6): hidden by default.
    private let hud = NSTextField(wrappingLabelWithString: "")
    private let inputQueue = DispatchQueue(label: "com.nomadicrebel.carbonmirror.input", qos: .userInteractive)
    private var frameWidth = 0
    private var frameHeight = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.background.cgColor
        video.frame = bounds
        video.autoresizingMask = [.width, .height]
        addSubview(video)
        lockGlyph.image = Theme.symbol("lock.fill", size: 28, weight: .semibold)
        lockGlyph.contentTintColor = .white  // on the always-black screen, in both appearances
        lockGlyph.isHidden = true
        lockGlyph.setAccessibilityLabel("Screen hidden. Click to reveal.")
        addSubview(lockGlyph)
        hud.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        hud.textColor = .white
        hud.drawsBackground = true
        hud.backgroundColor = NSColor(white: 0, alpha: 0.6)
        hud.isHidden = true
        addSubview(hud)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: State

    /// Phone frame size (pixels) from the stream; drives the input mapping.
    func setFrameSize(width: Int, height: Int) {
        frameWidth = width
        frameHeight = height
        needsLayout = true
    }

    /// Privacy blur: renders the blurred frame, shows the lock and blocks input (releasing anything held).
    func setBlurred(_ blurred: Bool) {
        video.blurred = blurred
        lockGlyph.isHidden = !blurred
        deliver(engine.setBlocked(blurred))
    }

    /// Shows the HUD text (nil hides it).
    func setHUD(_ text: String?) {
        hud.isHidden = text == nil
        hud.stringValue = text ?? ""
        needsLayout = true
    }

    /// New session: fresh input state, keyboard created before the first key.
    func sessionStarted(typingMode mode: AppSettings.TypingMode) {
        deliver(engine.sessionStarted(typingMode: mode))
    }

    func setTypingMode(_ mode: AppSettings.TypingMode) {
        deliver(engine.setTypingMode(mode))
    }

    /// Lifts fingers and keys (focus loss, session end).
    func releaseAll() {
        deliver(engine.releaseAll())
    }

    /// Sends messages produced outside the view (toolbar and menu actions) through the same ordered queue.
    func deliver(_ messages: [[UInt8]]) {
        guard !messages.isEmpty, let sender else { return }
        inputQueue.async {
            for message in messages { sender(message) }
        }
    }

    override func layout() {
        super.layout()
        engine.layout(viewWidth: Double(bounds.width), viewHeight: Double(bounds.height), frameWidth: frameWidth, frameHeight: frameHeight)
        let side: CGFloat = 40
        lockGlyph.frame = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        let width = max(0, min(260, bounds.width - 16))
        hud.preferredMaxLayoutWidth = width
        hud.frame = NSRect(origin: NSPoint(x: 8, y: 8), size: NSSize(width: width, height: hud.fittingSize.height))
    }

    // MARK: Pointer

    private func location(_ event: NSEvent) -> (x: Double, y: Double) {
        let p = convert(event.locationInWindow, from: nil)
        return (Double(p.x), Double(p.y))
    }

    private func pointer(_ input: PointerInput) {
        onActivity?()
        deliver(engine.pointer(input))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if engine.blocked {
            onRevealRequest?()
            return
        }
        let p = location(event)
        pointer(.down(x: p.x, y: p.y))
    }

    override func mouseDragged(with event: NSEvent) {
        let p = location(event)
        pointer(.dragged(x: p.x, y: p.y))
    }

    override func mouseUp(with event: NSEvent) {
        let p = location(event)
        pointer(.up(x: p.x, y: p.y))
    }

    override func rightMouseDown(with event: NSEvent) {
        pointer(.secondaryClick)
    }

    override func scrollWheel(with event: NSEvent) {
        let p = location(event)
        pointer(.scroll(x: p.x, y: p.y, dx: Double(event.scrollingDeltaX), dy: Double(event.scrollingDeltaY),
                        precise: event.hasPreciseScrollingDeltas))
    }

    override func magnify(with event: NSEvent) {
        switch event.phase {
        case .began:
            let p = location(event)
            pointer(.pinchBegan(x: p.x, y: p.y))
            pointer(.pinchChanged(magnification: Double(event.magnification)))
        case .changed:
            pointer(.pinchChanged(magnification: Double(event.magnification)))
        case .ended, .cancelled:
            pointer(.pinchEnded)
        default:
            break
        }
    }

    // MARK: Keyboard

    private static func flags(_ event: NSEvent) -> UInt32 {
        UInt32(truncatingIfNeeded: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
    }

    override func keyDown(with event: NSEvent) {
        onActivity?()
        deliver(engine.keyDown(keyCode: event.keyCode, flags: Self.flags(event), characters: event.characters, isRepeat: event.isARepeat))
    }

    override func keyUp(with event: NSEvent) {
        deliver(engine.keyUp(keyCode: event.keyCode, flags: Self.flags(event)))
    }

    override func flagsChanged(with event: NSEvent) {
        deliver(engine.flagsChanged(flags: Self.flags(event)))
    }

    /// ⌘-combinations other than the standard macOS menu keys go to the phone (⌘ is sent as Ctrl, so ⌘C/⌘V/⌘A/⌘Z
    /// work as on a Mac). AppKit sends no key-up while ⌘ is held, so the release follows immediately.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.type == .keyDown, !AppShortcuts.matches(event) else {
            return super.performKeyEquivalent(with: event)
        }
        onActivity?()
        let flags = Self.flags(event)
        deliver(engine.keyDown(keyCode: event.keyCode, flags: flags, characters: event.characters, isRepeat: event.isARepeat)
            + engine.keyUp(keyCode: event.keyCode, flags: flags))
        return true
    }

    override func resignFirstResponder() -> Bool {
        releaseAll()
        return super.resignFirstResponder()
    }
}

/// Key equivalents that belong to CarbonMirror (standard macOS menu keys), never forwarded to the phone.
enum AppShortcuts {
    /// Quit, Hide, Minimise, Close and Settings.
    private static let keys: [(key: String, modifiers: NSEvent.ModifierFlags)] = [
        ("q", .command), ("h", .command), ("m", .command), ("w", .command), (",", .command),
    ]

    static func matches(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        return keys.contains { $0.key == key && $0.modifiers == mods }
    }
}
#endif
