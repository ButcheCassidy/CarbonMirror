// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CMCore
import CMCoreBridge

/// Pointer input in view coordinates (points, origin top-left).
public enum PointerInput: Equatable, Sendable {
    case down(x: Double, y: Double)
    case dragged(x: Double, y: Double)
    case up(x: Double, y: Double)
    case secondaryClick
    case scroll(x: Double, y: Double, dx: Double, dy: Double, precise: Bool)
    case pinchBegan(x: Double, y: Double)
    case pinchChanged(magnification: Double)
    case pinchEnded
}

/// Turns Mac input into control messages (spec 5.2–5.4, 8.2.3): click = tap, drag = swipe, hold = long press,
/// two-finger scroll = scroll, pinch = two virtual fingers, right-click = Back, and the two typing modes.
/// Pure logic (no AppKit) so every mapping is tested on Linux; the window feeds it events on the main thread.
public final class InputEngine {
    /// UHID id of the virtual keyboard.
    public static let keyboardID: UInt16 = 1
    public static let keyboardName = "CarbonMirror Keyboard"
    /// Spread of the two virtual fingers when a pinch starts, phone pixels.
    public static let pinchStartSpread = 400.0
    /// Android key codes used by toolbar actions.
    public enum AndroidKey: Int32 {
        case home = 3, back = 4, volumeUp = 24, volumeDown = 25, power = 26, screenshot = 120, appSwitch = 187, mute = 164, allApps = 284
    }

    /// macOS keys that are actions, not text, in "Phone keyboard" mode.
    static let nonTextKeys: Set<UInt16> = [0x24, 0x30, 0x33, 0x35, 0x4C, 0x75, 0x73, 0x77, 0x74, 0x79, 0x7B, 0x7C, 0x7D, 0x7E,
                                           0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
    static let macCommandOrControl: UInt32 = (1 << 18) | (1 << 20)

    public var frameWidth = 0
    public var frameHeight = 0
    /// Where the video sits inside the view.
    public var content = ViewRect(x: 0, y: 0, width: 0, height: 0)
    public var rightClickBack = true
    public private(set) var typingMode: AppSettings.TypingMode = .hardware
    /// Privacy blur: everything is dropped while true.
    public private(set) var blocked = false

    private var touching = false
    private var pinchCenter: PhonePoint?
    private var pinchSpread = InputEngine.pinchStartSpread
    private var heldKeys: [UInt16] = []
    private var keyboardCreated = false

    public init() {}

    /// Updates the geometry after a resize, rotation or new frame size.
    public func layout(viewWidth: Double, viewHeight: Double, frameWidth: Int, frameHeight: Int) {
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        content = (try? InputMapping.letterbox(viewWidth: viewWidth, viewHeight: viewHeight, frameWidth: frameWidth, frameHeight: frameHeight))
            ?? ViewRect(x: 0, y: 0, width: viewWidth, height: viewHeight)
    }

    private func map(_ x: Double, _ y: Double, clamp: Bool) -> PhonePoint? {
        try? InputMapping.map(x: x, y: y, content: content, frameWidth: frameWidth, frameHeight: frameHeight, clamp: clamp)
    }

    // MARK: Blocking (privacy blur)

    /// Blocks or unblocks input; releases anything held so nothing stays pressed on the phone.
    public func setBlocked(_ value: Bool) -> [[UInt8]] {
        var out: [[UInt8]] = []
        if value { out = releaseAll() }
        blocked = value
        return out
    }

    /// Lifts fingers and keys (focus loss, blur, session end).
    public func releaseAll() -> [[UInt8]] {
        var out: [[UInt8]] = []
        if touching, let last = lastTouch {
            out += [try? ControlMessage.touch(.up, at: last, pressure: 0)].compactMap { $0 }
            touching = false
        }
        if let center = pinchCenter, let (a, b) = try? InputMapping.pinch(center: center, spread: pinchSpread) {
            out += [try? ControlMessage.touch(.up, pointer: ControlMessage.fingerPointer, at: a, pressure: 0),
                    try? ControlMessage.touch(.up, pointer: ControlMessage.secondFingerPointer, at: b, pressure: 0)].compactMap { $0 }
            pinchCenter = nil
        }
        if !heldKeys.isEmpty {
            heldKeys = []
            if typingMode == .hardware, keyboardCreated, let report = try? KeyboardMapping.hidReport(modifierFlags: 0, held: []) {
                out += [try? ControlMessage.uhidInput(id: Self.keyboardID, report: report)].compactMap { $0 }
            }
        }
        return out
    }

    private var lastTouch: PhonePoint?

    // MARK: Pointer

    public func pointer(_ input: PointerInput) -> [[UInt8]] {
        guard !blocked, frameWidth > 0, frameHeight > 0 else { return [] }
        switch input {
        case let .down(x, y):
            guard let p = map(x, y, clamp: false), let m = try? ControlMessage.touch(.down, at: p, pressure: 1) else { return [] }
            touching = true
            lastTouch = p
            return [m]
        case let .dragged(x, y):
            guard touching, let p = map(x, y, clamp: true), let m = try? ControlMessage.touch(.move, at: p, pressure: 1) else { return [] }
            lastTouch = p
            return [m]
        case let .up(x, y):
            guard touching, let p = map(x, y, clamp: true), let m = try? ControlMessage.touch(.up, at: p, pressure: 0) else { return [] }
            touching = false
            lastTouch = nil
            return [m]
        case .secondaryClick:
            guard rightClickBack else { return [] }
            return [try? ControlMessage.simple(.backDown), try? ControlMessage.simple(.backUp)].compactMap { $0 }
        case let .scroll(x, y, dx, dy, precise):
            guard let p = map(x, y, clamp: false) else { return [] }
            let h = -InputMapping.scrollUnits(dx, precise: precise)
            let v = InputMapping.scrollUnits(dy, precise: precise)
            guard h != 0 || v != 0, let m = try? ControlMessage.scroll(at: p, horizontal: h, vertical: v) else { return [] }
            return [m]
        case let .pinchBegan(x, y):
            guard pinchCenter == nil, let c = map(x, y, clamp: false) else { return [] }
            pinchCenter = c
            pinchSpread = Self.pinchStartSpread
            return pinchMessages(.down)
        case let .pinchChanged(magnification):
            guard pinchCenter != nil, magnification.isFinite else { return [] }
            pinchSpread = min(Double(frameWidth), max(40, pinchSpread * (1 + magnification)))
            return pinchMessages(.move)
        case .pinchEnded:
            let out = pinchMessages(.up)
            pinchCenter = nil
            return out
        }
    }

    private func pinchMessages(_ action: ControlMessage.TouchAction) -> [[UInt8]] {
        guard let center = pinchCenter, let (a, b) = try? InputMapping.pinch(center: center, spread: pinchSpread) else { return [] }
        let pressure: Float = action == .up ? 0 : 1
        return [try? ControlMessage.touch(action, pointer: ControlMessage.fingerPointer, at: a, pressure: pressure),
                try? ControlMessage.touch(action, pointer: ControlMessage.secondFingerPointer, at: b, pressure: pressure)].compactMap { $0 }
    }

    // MARK: Keyboard

    /// Switches typing mode; creates or removes the virtual UHID keyboard as needed.
    public func setTypingMode(_ mode: AppSettings.TypingMode) -> [[UInt8]] {
        var out = releaseAll()
        if mode == .phone, keyboardCreated, let m = try? ControlMessage.uhidDestroy(id: Self.keyboardID) {
            out.append(m)
            keyboardCreated = false
        }
        typingMode = mode
        return out
    }

    private func ensureKeyboard() -> [[UInt8]] {
        guard !keyboardCreated, let descriptor = try? KeyboardMapping.hidDescriptor(),
              let m = try? ControlMessage.uhidCreate(id: Self.keyboardID, name: Self.keyboardName, descriptor: descriptor) else { return [] }
        keyboardCreated = true
        return [m]
    }

    private func hidReport(flags: UInt32) -> [[UInt8]] {
        guard let report = try? KeyboardMapping.hidReport(modifierFlags: flags, held: heldKeys),
              let m = try? ControlMessage.uhidInput(id: Self.keyboardID, report: report) else { return [] }
        return [m]
    }

    /// A key went down. `characters` is the typed text (Phone keyboard mode).
    public func keyDown(keyCode: UInt16, flags: UInt32, characters: String?, isRepeat: Bool) -> [[UInt8]] {
        guard !blocked else { return [] }
        switch typingMode {
        case .hardware:
            var out = ensureKeyboard()
            if !heldKeys.contains(keyCode) { heldKeys.append(keyCode) }
            out += hidReport(flags: flags)
            return out
        case .phone:
            let shortcut = flags & Self.macCommandOrControl != 0
            if !shortcut, !Self.nonTextKeys.contains(keyCode), let text = characters, !text.isEmpty,
               !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || $0.value >= 0xF700 && $0.value <= 0xF8FF }) {
                return Self.chunks(of: text).compactMap { try? ControlMessage.text($0) }
            }
            guard let key = KeyboardMapping.android(macKeyCode: keyCode, modifierFlags: flags),
                  let m = try? ControlMessage.keycode(down: true, keycode: key.keycode, repeatCount: isRepeat ? 1 : 0, meta: key.meta) else { return [] }
            if !heldKeys.contains(keyCode) { heldKeys.append(keyCode) }
            return [m]
        }
    }

    public func keyUp(keyCode: UInt16, flags: UInt32) -> [[UInt8]] {
        guard !blocked else { return [] }
        let wasHeld = heldKeys.contains(keyCode)
        heldKeys.removeAll { $0 == keyCode }
        switch typingMode {
        case .hardware:
            return keyboardCreated ? hidReport(flags: flags) : []
        case .phone:
            guard wasHeld, let key = KeyboardMapping.android(macKeyCode: keyCode, modifierFlags: flags),
                  let m = try? ControlMessage.keycode(down: false, keycode: key.keycode, meta: key.meta) else { return [] }
            return [m]
        }
    }

    /// Modifier keys changed (hardware keyboard reports them in the modifier byte).
    public func flagsChanged(flags: UInt32) -> [[UInt8]] {
        guard !blocked, typingMode == .hardware else { return [] }
        return ensureKeyboard() + hidReport(flags: flags)
    }

    /// Splits text into ≤ 300-byte pieces on character boundaries (the server's inject-text cap).
    static func chunks(of text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            if current.utf8.count + String(ch).utf8.count > 300 {
                out.append(current)
                current = ""
            }
            current.append(ch)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    // MARK: Toolbar actions and shortcuts (spec 5.4)

    /// Control messages for a toolbar action; empty for actions handled on the Mac.
    public func action(_ item: ToolbarItem) -> [[UInt8]] {
        guard !blocked else { return [] }
        switch item {
        case .back: return press(.back)
        case .home: return press(.home)
        case .recents: return press(.appSwitch)
        case .appDrawer: return press(.allApps)
        case .notifications: return [try? ControlMessage.simple(.expandNotifications)].compactMap { $0 }
        case .quickSettings: return [try? ControlMessage.simple(.expandSettings)].compactMap { $0 }
        case .rotate: return [try? ControlMessage.simple(.rotateDevice)].compactMap { $0 }
        case .volumeDown: return press(.volumeDown)
        case .volumeUp: return press(.volumeUp)
        case .mute: return press(.mute)
        case .lock: return press(.power)
        case .screenshot, .clipboardSync, .privacyBlur, .typingMode, .connection, .pinOnTop, .settings: return []
        }
    }

    /// ⇧⌘S: screenshot on the phone only.
    public func phoneScreenshot() -> [[UInt8]] {
        blocked ? [] : press(.screenshot)
    }

    private func press(_ key: AndroidKey) -> [[UInt8]] {
        [try? ControlMessage.keycode(down: true, keycode: key.rawValue, meta: 0),
         try? ControlMessage.keycode(down: false, keycode: key.rawValue, meta: 0)].compactMap { $0 }
    }
}
