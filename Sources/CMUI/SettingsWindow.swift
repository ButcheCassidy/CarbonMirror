#if os(macOS)
import AppKit
import CMCore
import CMMedia
import ServiceManagement

/// Closure target for AppKit controls.
@MainActor
private final class Action: NSObject {
    let body: (NSControl) -> Void
    init(_ body: @escaping (NSControl) -> Void) { self.body = body }
    @objc func fire(_ sender: NSControl) { body(sender) }
}

/// Settings (spec 8.3): monochrome sections on Liquid Glass (`NSGlassEffectView`, macOS 26+; dark
/// behind-window blur on 15–25). Every control writes `AppSettings` directly, so changes apply live.
@MainActor
final class SettingsWindowController {
    enum Section: String, CaseIterable { case connection = "Connection", display = "Display", experience = "Experience",
                                              security = "Security", screenshots = "Screenshots", general = "General", about = "About" }

    var onCreateNewKey: (() -> Void)?
    var onForgetDevice: (() -> Void)?
    var onInstallCompanion: (() -> Void)?

    private let settings: AppSettings
    private let realSize: () -> String
    private var window: NSWindow?
    private var actions: [Action] = []
    private var pickerAction: Action? { actions.first }
    private let picker = NSSegmentedControl()
    private let scroll = NSScrollView()

    init(settings: AppSettings, realSize: @escaping () -> String) {
        self.settings = settings
        self.realSize = realSize
    }

    func show() {
        if window == nil { window = makeWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "CarbonMirror Settings"
        window.titlebarAppearsTransparent = true
        window.appearance = Theme.darkAppearance
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.minSize = NSSize(width: 600, height: 360)
        window.center()

        picker.segmentCount = Section.allCases.count
        for (i, section) in Section.allCases.enumerated() { picker.setLabel(section.rawValue, forSegment: i) }
        picker.segmentStyle = .automatic
        picker.trackingMode = .selectOne
        picker.selectedSegment = 0
        bind(picker) { [weak self] control in
            self?.show(Section.allCases[max(0, (control as? NSSegmentedControl)?.selectedSegment ?? 0)])
        }
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let column = NSStackView(views: [picker, scroll])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 12
        column.edgeInsets = NSEdgeInsets(top: 36, left: 16, bottom: 16, right: 16)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -32).isActive = true

        let backdrop: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.tintColor = NSColor(white: 0, alpha: 0.45)
            glass.contentView = column
            backdrop = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            column.frame = blur.bounds
            column.autoresizingMask = [.width, .height]
            blur.addSubview(column)
            backdrop = blur
        }
        window.contentView = backdrop
        show(.connection)
        return window
    }

    // MARK: Sections

    private func show(_ section: Section) {
        actions.removeAll { $0 !== pickerAction }
        let rows: [(String, NSView)]
        switch section {
        case .connection: rows = connectionRows()
        case .display: rows = displayRows()
        case .experience: rows = experienceRows()
        case .security: rows = securityRows()
        case .screenshots: rows = [("Folder", button("Open Screenshots Folder") { _ in Self.openScreenshots() })]
        case .general: rows = generalRows()
        case .about: rows = aboutRows()
        }
        let grid = NSGridView(views: rows.map { [label($0.0), $0.1] })
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        let document = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: document.topAnchor, constant: 8),
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: document.leadingAnchor),
            grid.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            grid.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -8),
        ])
        document.frame = NSRect(origin: .zero, size: NSSize(width: scroll.contentSize.width, height: grid.fittingSize.height + 16))
        document.autoresizingMask = [.width]
        scroll.documentView = document
    }

    private func connectionRows() -> [(String, NSView)] {
        let s = settings
        return [
            ("Mode", popup(["Auto", "USB only", "Wireless only"], AppSettings.ConnectionMode.allCases.firstIndex(of: s.connectionMode) ?? 0) {
                s.connectionMode = AppSettings.ConnectionMode.allCases[$0]
            }),
            ("USB frame rate", popup(AppSettings.usbFPSChoices.map { "\($0) fps" }, AppSettings.usbFPSChoices.firstIndex(of: s.usbProfile.maxFPS) ?? 2) {
                s.usbProfile.maxFPS = AppSettings.usbFPSChoices[$0]
            }),
            ("USB bitrate", popup(Self.usbRates.map { "\($0) Mbit/s" }, Self.usbRates.firstIndex(of: s.usbProfile.bitrateMbps) ?? 3) {
                s.usbProfile.bitrateMbps = Self.usbRates[$0]
            }),
            ("USB codec", popup(["H.264", "H.265"], s.usbProfile.codec == .h264 ? 0 : 1) { s.usbProfile.codec = $0 == 0 ? .h264 : .h265 }),
            ("Wi-Fi frame rate", popup(AppSettings.wifiFPSChoices.map { $0 > 60 ? "\($0) fps (Experimental)" : "\($0) fps" },
                                       AppSettings.wifiFPSChoices.firstIndex(of: s.wirelessProfile.maxFPS) ?? 1) {
                s.wirelessProfile.maxFPS = AppSettings.wifiFPSChoices[$0]
            }),
            ("Wi-Fi bitrate", popup(Self.wifiRates.map { "\($0) Mbit/s" }, Self.wifiRates.firstIndex(of: s.wirelessProfile.bitrateMbps) ?? 2) {
                s.wirelessProfile.bitrateMbps = Self.wifiRates[$0]
            }),
            ("Wi-Fi codec", popup(["H.264", "H.265"], s.wirelessProfile.codec == .h264 ? 0 : 1) { s.wirelessProfile.codec = $0 == 0 ? .h264 : .h265 }),
            ("Phone companion", button("Install over USB…") { [weak self] _ in self?.onInstallCompanion?() }),
        ]
    }

    static let usbRates = [8, 16, 24, 32, 48, 64]
    static let wifiRates = [4, 8, 12, 16, 24, 40]

    private func displayRows() -> [(String, NSView)] {
        let s = settings
        let slider = NSSlider(value: s.cornerFineTune * 100, minValue: -15, maxValue: 15, target: nil, action: nil)
        slider.numberOfTickMarks = 7
        bind(slider) { s.cornerFineTune = ($0 as? NSSlider)?.doubleValue.map { $0 / 100 } ?? 0 }
        return [
            ("Corner fine-tune", slider),
            ("Real size", label(realSize(), secondary: true)),
            ("", toggle("Remember size and position", s.rememberSize) { s.rememberSize = $0 }),
        ]
    }

    private func experienceRows() -> [(String, NSView)] {
        let s = settings
        let blurNames = AppSettings.autoBlurChoices.map { $0 == 0 ? "Off" : "After \($0) s without focus" }
        return [
            ("Auto-blur", popup(blurNames, AppSettings.autoBlurChoices.firstIndex(of: s.autoBlurSeconds) ?? 0) {
                s.autoBlurSeconds = AppSettings.autoBlurChoices[$0]
            }),
            ("", toggle("Require Touch ID to reveal", s.touchIDToReveal) { s.touchIDToReveal = $0 }),
            ("Typing mode", popup(["Hardware keyboard", "Phone keyboard"], s.typingMode == .hardware ? 0 : 1) { s.typingMode = $0 == 0 ? .hardware : .phone }),
            ("", toggle("Offer landscape window when the phone rotates", s.landscapeOffer) { s.landscapeOffer = $0 }),
            ("Landscape", popup(["Ask", "Always rotate", "Stay portrait"], AppSettings.LandscapeBehaviour.allCases.firstIndex(of: s.landscapeBehaviour) ?? 0) {
                s.landscapeBehaviour = AppSettings.LandscapeBehaviour.allCases[$0]
            }),
            ("", toggle("Save power when the window is hidden", s.powerSavingWhenHidden) { s.powerSavingWhenHidden = $0 }),
            ("", toggle("Show status line", s.statusLine) { s.statusLine = $0 }),
            ("", toggle("Pinned window follows me across Spaces", s.pinAcrossSpaces) { s.pinAcrossSpaces = $0 }),
            ("", toggle("Right-click is Back", s.rightClickBack) { s.rightClickBack = $0 }),
            ("", toggle("Turn phone screen off while mirroring", s.phoneScreenOff) { s.phoneScreenOff = $0 }),
        ]
    }

    private func securityRows() -> [(String, NSView)] {
        let s = settings
        let idle = NSTextField(labelWithString: "\(s.idleTimeoutMinutes) min")
        let stepper = NSStepper()
        stepper.minValue = Double(AppSettings.idleTimeoutRange.lowerBound)
        stepper.maxValue = Double(AppSettings.idleTimeoutRange.upperBound)
        stepper.integerValue = s.idleTimeoutMinutes
        bind(stepper) {
            s.idleTimeoutMinutes = $0.integerValue
            idle.stringValue = "\(s.idleTimeoutMinutes) min"
        }
        let idleRow = NSStackView(views: [idle, stepper])
        let reminders = [0, 30, 90, 180, 365]
        return [
            ("", toggle("Encrypt over USB too", s.encryptOverUSB) { s.encryptOverUSB = $0 }),
            ("End session when idle for", idleRow),
            ("", toggle("Hide from screen recording and sharing", s.hideFromCapture) { s.hideFromCapture = $0 }),
            ("", toggle("Clipboard sync (plain text)", s.clipboardSync) { s.clipboardSync = $0 }),
            ("New-key reminder", popup(reminders.map { $0 == 0 ? "Off" : "Every \($0) days" }, reminders.firstIndex(of: s.rotationReminderDays) ?? 3) {
                s.rotationReminderDays = reminders[$0]
            }),
            ("Keys", button("Create New Key…") { [weak self] _ in self?.onCreateNewKey?() }),
            ("Phone", button("Forget Device…") { [weak self] _ in self?.onForgetDevice?() }),
        ]
    }

    private func generalRows() -> [(String, NSView)] {
        let shortcuts = ToolbarItem.allCases.compactMap { item in item.shortcut.map { _ in item.title } }
            + ["Real size (⌘0)", "Screenshot on the phone (⇧⌘S)", "Debug HUD (⌥⌘D)"]
        return [
            ("", toggle("Launch at login", SMAppService.mainApp.status == .enabled) { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    Log.error(.app, "login item change failed")
                }
            }),
            ("Shortcuts", label(shortcuts.joined(separator: "\n"), secondary: true)),
        ]
    }

    private func aboutRows() -> [(String, NSView)] {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        return [
            ("CarbonMirror", label("Version \(version)", secondary: true)),
            ("Author", label("ButcheCassidy - The Nomadic Rebel")),
            ("Licence", label("PolyForm Noncommercial 1.0.0", secondary: true)),
            ("Includes", label("scrcpy server (Apache-2.0), rustls, aws-lc-rs, rcgen,\nwebpki, time, zeroize, jni — see THIRD_PARTY_NOTICES.md", secondary: true)),
        ]
    }

    // MARK: Controls

    private func label(_ text: String, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = secondary ? Theme.subtitleFont : NSFont.systemFont(ofSize: 13, weight: .medium)
        field.textColor = secondary ? Theme.secondaryText : Theme.primaryText
        return field
    }

    private func bind(_ control: NSControl, _ body: @escaping (NSControl) -> Void) {
        let action = Action(body)
        actions.append(action)
        control.target = action
        control.action = #selector(Action.fire(_:))
    }

    private func toggle(_ title: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        box.state = on ? .on : .off
        box.contentTintColor = Theme.primaryText
        bind(box) { set(($0 as? NSButton)?.state == .on) }
        return box
    }

    private func popup(_ items: [String], _ selected: Int, _ set: @escaping (Int) -> Void) -> NSPopUpButton {
        let menu = NSPopUpButton(frame: .zero, pullsDown: false)
        menu.addItems(withTitles: items)
        menu.selectItem(at: selected)
        bind(menu) { set(max(0, ($0 as? NSPopUpButton)?.indexOfSelectedItem ?? 0)) }
        return menu
    }

    private func button(_ title: String, _ body: @escaping (NSControl) -> Void) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
        b.bezelStyle = .push
        bind(b, body)
        return b
    }

    private static func openScreenshots() {
        guard let folder = ScreenshotLocation.folder() else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
#endif
