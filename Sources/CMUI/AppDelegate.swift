#if os(macOS)
import AppKit
import CMCore
import CMCoreBridge
import CMTransport

/// App entry: main menu with every shortcut (spec 5.4), the phone window, the menu-bar extra and `--demo`.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let demo: Bool
    private let settings = AppSettings()
    private var phone: PhoneWindowController?
    private var menuBar: MenuBarController?
    private var demoDriver: DemoDriver?

    public init(arguments: [String]) {
        demo = arguments.contains("--demo")
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        ChildProcesses.shared.installSignalHandlers()
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = Theme.darkAppearance
        NSApp.mainMenu = buildMainMenu()

        let phone = PhoneWindowController(settings: settings)
        phone.onToolbarAction = { [weak self] item in self?.handle(item) }
        self.phone = phone
        menuBar = MenuBarController(menu: buildMenuBarMenu())
        phone.showWindow()
        NSApp.activate()
        if demo {
            let driver = DemoDriver(controller: phone)
            driver.start()
            demoDriver = driver
        }
        Log.info(.app, "launched", ["demo": demo ? "yes" : "no"])
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        phone?.showWindow()
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        demoDriver?.stop()
        ChildProcesses.shared.terminateAll()
        Log.info(.app, "terminated")
    }

    // MARK: Actions

    /// Whether a live session can take phone actions right now.
    private var sessionActive: Bool {
        phone?.state == .mirroring || phone?.state == .retryingSilently
    }

    private func handle(_ item: ToolbarItem) {
        switch item {
        case .pinOnTop:
            settings.pinOnTop.toggle()
        case .clipboardSync:
            settings.clipboardSync.toggle()
        case .typingMode:
            settings.typingMode = settings.typingMode == .hardware ? .phone : .hardware
        default:
            break
        }
    }

    @objc private func showPhone(_ sender: Any?) {
        phone?.showWindow()
        NSApp.activate()
    }

    @objc private func toolbarMenuItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let item = ToolbarItem(rawValue: raw) else { return }
        handle(item)
    }

    @objc private func realSize(_ sender: Any?) {
        phone?.snapToRealSize()
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toolbarMenuItem(_:)),
           let raw = menuItem.representedObject as? String, let item = ToolbarItem(rawValue: raw) {
            switch item {
            case .pinOnTop: menuItem.state = settings.pinOnTop ? .on : .off
            case .clipboardSync: menuItem.state = settings.clipboardSync ? .on : .off
            case .typingMode: menuItem.state = settings.typingMode == .phone ? .on : .off
            default: break
            }
            return sessionActive || !item.needsSession
        }
        return true
    }

    // MARK: Menus

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        let appMenu = NSMenu(title: "CarbonMirror")
        appMenu.addItem(withTitle: "About CarbonMirror", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide CarbonMirror", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit CarbonMirror", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "CarbonMirror")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: edit, title: "Edit")

        let phoneMenu = NSMenu(title: "Phone")
        for item in ToolbarItem.allCases where item != .connection && item != .settings {
            let entry = NSMenuItem(title: item.menuTitle, action: #selector(toolbarMenuItem(_:)), keyEquivalent: item.shortcut?.key ?? "")
            entry.keyEquivalentModifierMask = item.shortcut?.modifiers ?? []
            entry.representedObject = item.rawValue
            entry.target = self
            phoneMenu.addItem(entry)
        }
        main.addItem(submenu: phoneMenu, title: "Phone")

        let view = NSMenu(title: "View")
        let real = NSMenuItem(title: "Real Size", action: #selector(realSize(_:)), keyEquivalent: "0")
        real.target = self
        view.addItem(real)
        main.addItem(submenu: view, title: "View")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let show = NSMenuItem(title: "Show Phone Window", action: #selector(showPhone(_:)), keyEquivalent: "")
        show.target = self
        windowMenu.addItem(show)
        main.addItem(submenu: windowMenu, title: "Window")
        NSApp.windowsMenu = windowMenu
        return main
    }

    private func buildMenuBarMenu() -> NSMenu {
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show CarbonMirror", action: #selector(showPhone(_:)), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit CarbonMirror", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
}

extension NSMenu {
    fileprivate func addItem(submenu: NSMenu, title: String) {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = submenu
        addItem(holder)
    }
}

extension ToolbarItem {
    /// Menu title without the shortcut hint (the menu shows the key equivalent itself).
    var menuTitle: String {
        title.components(separatedBy: " (").first ?? title
    }

    /// Key equivalent from spec 5.4 / 8.2.
    var shortcut: (key: String, modifiers: NSEvent.ModifierFlags)? {
        switch self {
        case .back: ("[", .command)
        case .home: ("1", .command)
        case .recents: ("2", .command)
        case .appDrawer: ("3", .command)
        case .notifications: ("4", .command)
        case .quickSettings: ("5", .command)
        case .screenshot: ("s", .command)
        case .clipboardSync: ("c", [.command, .shift])
        case .privacyBlur: ("h", [.command, .shift])
        case .typingMode: ("k", [.command, .option])
        case .rotate: ("r", .command)
        case .volumeDown: (String(UnicodeScalar(NSDownArrowFunctionKey).map(Character.init) ?? "↓"), .command)
        case .volumeUp: (String(UnicodeScalar(NSUpArrowFunctionKey).map(Character.init) ?? "↑"), .command)
        case .lock: ("l", .command)
        case .pinOnTop: ("p", .command)
        case .settings: (",", .command)
        case .mute, .connection: nil
        }
    }
}
#endif
