// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if os(macOS)
import AppKit
import CMCore

/// Hover chrome (spec 2.3): 44 pt toolbar with the traffic lights and the monochrome buttons in spec order,
/// an overflow (…) menu for the buttons that do not fit the current width, and the one-line status line
/// underneath. Dragging empty toolbar space moves the window (the mirrored screen itself never does).
@MainActor
final class ChromeView: NSView {
    var onAction: ((ToolbarItem) -> Void)?
    var onClose: (() -> Void)?
    var onMinimise: (() -> Void)?
    var onZoom: (() -> Void)?

    private var buttons: [ToolbarItem: NSButton] = [:]
    private let trafficLights: [NSButton]
    private let overflowButton = NSButton()
    private let statusLine = NSTextField(labelWithString: "")
    private var overflowItems: [ToolbarItem] = []
    private var toggles: Set<ToolbarItem> = []
    private var sessionActive = false
    private var typingMode: AppSettings.TypingMode = .hardware

    override init(frame: NSRect) {
        let mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        trafficLights = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap {
            NSWindow.standardWindowButton($0, for: mask)
        }
        super.init(frame: frame)
        appearance = Theme.darkAppearance
        for (index, light) in trafficLights.enumerated() {
            light.target = self
            light.tag = index
            light.action = #selector(trafficLightPressed(_:))
            addSubview(light)
        }
        for item in ToolbarItem.allCases {
            let button = NSButton()
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageOnly
            button.contentTintColor = Theme.primaryText
            button.toolTip = item.title
            button.setAccessibilityLabel(item.title)
            button.target = self
            button.action = #selector(itemPressed(_:))
            button.identifier = NSUserInterfaceItemIdentifier(item.rawValue)
            if item == .connection {
                button.imagePosition = .imageTrailing
                button.font = Theme.statusLineFont
                button.lineBreakMode = .byTruncatingTail
            }
            buttons[item] = button
            addSubview(button)
        }
        overflowButton.isBordered = false
        overflowButton.image = Theme.symbol("ellipsis", size: Theme.toolbarGlyphPointSize, weight: .semibold)
        overflowButton.contentTintColor = Theme.primaryText
        overflowButton.toolTip = "More"
        overflowButton.setAccessibilityLabel("More")
        overflowButton.target = self
        overflowButton.action = #selector(showOverflow(_:))
        addSubview(overflowButton)

        statusLine.font = Theme.statusLineFont
        statusLine.textColor = Theme.secondaryText
        statusLine.alignment = .center
        statusLine.lineBreakMode = .byTruncatingTail
        statusLine.cell?.truncatesLastVisibleLine = true
        addSubview(statusLine)
        setConnectionBadge(text: "Offline", symbol: nil)
        refreshImages()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: State

    /// Enables session-only buttons while mirroring.
    func setSessionActive(_ active: Bool) {
        sessionActive = active
        for (item, button) in buttons { button.isEnabled = active || !item.needsSession }
    }

    /// On/off state of a toggle button (clipboard sync, privacy blur, pin on top, mute).
    func setToggle(_ item: ToolbarItem, on: Bool) {
        if on { toggles.insert(item) } else { toggles.remove(item) }
        refreshImages()
    }

    func setTypingMode(_ mode: AppSettings.TypingMode) {
        typingMode = mode
        buttons[.typingMode]?.toolTip = mode == .hardware ? "Typing: Hardware keyboard (⌥⌘K)" : "Typing: Phone keyboard (⌥⌘K)"
        refreshImages()
    }

    /// Connection badge text (`USB · 120`, `Wi-Fi`) with an optional trailing symbol (lock for encrypted).
    func setConnectionBadge(text: String, symbol: String?) {
        guard let badge = buttons[.connection] else { return }
        badge.attributedTitle = NSAttributedString(string: text, attributes: [.font: Theme.statusLineFont, .foregroundColor: Theme.primaryText,
                                                                              .paragraphStyle: Theme.singleLine(.center)])
        badge.image = symbol.flatMap { Theme.symbol($0, size: 10, weight: .semibold) }
        badge.toolTip = "Connection: \(text)"
    }

    /// Status line (spec 8.2.5) with an optional leading monochrome battery glyph.
    func setStatusLine(_ text: String, batterySymbol: String?, visible: Bool) {
        let line = NSMutableAttributedString()
        if let batterySymbol, let image = Theme.symbol(batterySymbol, size: 10) {
            let glyph = NSTextAttachment()
            glyph.image = image
            line.append(NSAttributedString(attachment: glyph))
            line.append(NSAttributedString(string: " "))
        }
        line.append(NSAttributedString(string: text))
        line.addAttributes([.font: Theme.statusLineFont, .foregroundColor: Theme.secondaryText, .paragraphStyle: Theme.singleLine(.center)],
                           range: NSRange(location: 0, length: line.length))
        statusLine.attributedStringValue = line
        statusLine.isHidden = !visible
    }

    private func refreshImages() {
        for (item, button) in buttons where item != .connection {
            button.image = Theme.symbol(symbolName(item), size: Theme.toolbarGlyphPointSize)
        }
    }

    private func symbolName(_ item: ToolbarItem) -> String {
        switch item {
        case .typingMode: typingMode == .hardware ? "keyboard" : "keyboard.chevron.compact.down"
        case .clipboardSync: toggles.contains(item) ? "doc.on.clipboard.fill" : "doc.on.clipboard"
        case .privacyBlur: toggles.contains(item) ? "eye.slash.fill" : "eye.slash"
        case .pinOnTop: toggles.contains(item) ? "pin.fill" : "pin"
        case .mute: toggles.contains(item) ? "speaker.slash.fill" : "speaker.slash"
        default: item.symbol
        }
    }

    // MARK: Layout

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let toolbarHeight = Theme.toolbarHeight
        for (index, light) in trafficLights.enumerated() {
            let size = light.frame.size == .zero ? NSSize(width: 14, height: 16) : light.frame.size
            light.setFrameOrigin(NSPoint(x: ChromeLayout.trafficLightX(index), y: (toolbarHeight - size.height) / 2))
        }
        let result = ChromeLayout.layout(width: Double(bounds.width))
        let shown = Set(result.visible.map(\.item))
        let side = CGFloat(ChromeLayout.buttonSize)
        for placement in result.visible {
            buttons[placement.item]?.frame = NSRect(x: placement.x, y: (toolbarHeight - side) / 2, width: placement.width, height: side)
        }
        for (item, button) in buttons { button.isHidden = !shown.contains(item) }
        overflowItems = result.overflow
        overflowButton.isHidden = result.overflowX == nil
        if let x = result.overflowX {
            overflowButton.frame = NSRect(x: x, y: (toolbarHeight - side) / 2, width: side, height: side)
        }
        statusLine.frame = NSRect(x: Theme.chromeMargin, y: toolbarHeight, width: max(0, bounds.width - 2 * Theme.chromeMargin),
                                  height: Theme.statusLineHeight)
    }

    // MARK: Events

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    @objc private func itemPressed(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let item = ToolbarItem(rawValue: raw) else { return }
        onAction?(item)
    }

    @objc private func trafficLightPressed(_ sender: NSButton) {
        switch sender.tag {
        case 0: onClose?()
        case 1: onMinimise?()
        default: onZoom?()
        }
    }

    @objc private func showOverflow(_ sender: NSButton) {
        let menu = NSMenu()
        menu.appearance = Theme.darkAppearance
        for item in overflowItems {
            let entry = NSMenuItem(title: item == .connection ? (buttons[.connection]?.toolTip ?? item.title) : item.title,
                                   action: #selector(overflowPicked(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = item.rawValue
            entry.image = Theme.symbol(symbolName(item), size: Theme.toolbarGlyphPointSize)
            entry.state = toggles.contains(item) ? .on : .off
            entry.isEnabled = sessionActive || !item.needsSession
            menu.addItem(entry)
        }
        menu.autoenablesItems = false
        _ = menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func overflowPicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let item = ToolbarItem(rawValue: raw) else { return }
        onAction?(item)
    }
}
#endif
