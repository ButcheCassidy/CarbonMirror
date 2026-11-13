// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if os(macOS)
import AppKit
import CMCore
import CMCoreBridge
import CMTransport

/// App entry: main menu (standard macOS keys only; phone actions are toolbar buttons, Settings → Shortcuts), the phone window, the session, pairing, Settings,
/// the menu-bar extra (8.3) and `--demo`.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let demo: Bool
    private let settings = AppSettings()
    private var phone: PhoneWindowController?
    private var session: SessionController?
    private var pairing: PairingController?
    private var settingsWindow: SettingsWindowController?
    private var menuBar: MenuBarController?
    private var demoDriver: DemoDriver?

    public init(arguments: [String]) {
        demo = arguments.contains("--demo")
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        ChildProcesses.shared.installSignalHandlers()
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = Theme.appearance(settings.appearance)
        NSApp.mainMenu = buildMainMenu()

        let phone = PhoneWindowController(settings: settings)
        self.phone = phone
        phone.onStatusAction = { [weak self] action in self?.statusAction(action) }
        phone.onToolbarAction = { [weak self] item in self?.toolbar(item) }
        let settingsWindow = SettingsWindowController(settings: settings) { [weak phone] in phone?.realSizeDescription() ?? "–" }
        settingsWindow.onCreateNewKey = { [weak self] in self?.confirmCreateNewKey() }
        settingsWindow.onForgetDevice = { [weak self] in self?.confirmForget() }
        settingsWindow.onInstallCompanion = { [weak self] in self?.confirmInstallCompanion() }
        self.settingsWindow = settingsWindow
        menuBar = MenuBarController(menu: buildMenuBarMenu())
        phone.showWindowWithSplash()
        NSApp.activate()
        if demo {
            let driver = DemoDriver(controller: phone)
            driver.start()
            demoDriver = driver
        } else {
            let session = SessionController(settings: settings, phone: phone)
            let pairing = PairingController(session: session, phone: phone)
            session.onPairRequested = { [weak pairing] in pairing?.start() }
            session.onCreateKeyRequested = { [weak self] in self?.confirmCreateNewKey() }
            session.askEndpoint = { ip in EndpointPrompt.ask(suggestedIP: ip) }
            self.session = session
            self.pairing = pairing
            session.launch()
        }
        Log.info(.app, "launched", ["demo": demo ? "yes" : "no"])
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        phone?.showWindow()
        return true
    }

    /// Ends the session (turning Wireless debugging off) and stops adb before quitting.
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session else { return .terminateNow }
        session.shutdown { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    public func applicationWillTerminate(_ notification: Notification) {
        demoDriver?.stop()
        ChildProcesses.shared.terminateAll()
        Log.info(.app, "terminated")
    }

    // MARK: Actions

    private var sessionActive: Bool {
        phone?.state == .mirroring || phone?.state == .retryingSilently
    }

    private func toolbar(_ item: ToolbarItem) {
        if item == .settings { return settingsWindow?.show() ?? () }
        session?.perform(item)
    }

    private func statusAction(_ action: StatusContent.Action) {
        switch action {
        case .openSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") { NSWorkspace.shared.open(url) }
        case .useUSB: session?.useUSBOnly()
        case .pair: pairing?.start()
        case .reconnect, .retry, .connect: session?.reconnect()
        case .mirror: session?.openMirror()
        case .createNewKey: confirmCreateNewKey()
        case .howWirelessDebugging:
            inform("Turn on Wireless debugging",
                   "On your phone: Settings → System → Developer options → Wireless debugging → On.\n\nFaster: add the Wireless debugging Quick Settings tile, or the CarbonMirror tile from the companion app.")
        case .howLANSharing:
            inform("Allow local network sharing",
                   "Mac: Mullvad → Settings → VPN settings → Local network sharing → On.\nPhone: Mullvad → Settings → VPN settings → Local network sharing → On.\n\nBoth must be on the same Wi-Fi, or the Mac on the phone's hotspot.")
        case .howReinstall:
            inform("Can't start safely",
                   "CarbonMirror only starts its bundled adb when the helper is present and signed with the app's own certificate. Rebuild or reinstall CarbonMirror (see INSTALL.md), then open it again.")
        case .howInsecure:
            inform("Insecure connection refused",
                   "Your phone offered legacy adb over TCP (adb tcpip), which is not encrypted. CarbonMirror never uses it.\n\nRestart the phone to turn it off, then use Wireless debugging.")
        }
    }

    private func inform(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    private func confirm(_ title: String, _ text: String, _ button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Spec 7.5.3/7.5.4: an identity change is a possible MITM, so it needs its own explicit confirmation first.
    private func confirmCreateNewKey() {
        if phone?.state == .identityChanged,
           !confirm("This phone's identity changed",
                    "Someone may be intercepting the connection. Only continue if you reset the phone or reinstalled Android.", "I understand") {
            return
        }
        guard confirm("Create new key?", "This replaces this Mac's key and forgets the paired phone. You'll scan a new QR code.", "Create New Key") else { return }
        session?.createNewKey()
        inform("On your phone",
               "Tap Developer options → Revoke USB debugging authorizations, and remove this Mac under Wireless debugging → Paired devices.")
    }

    private func confirmForget() {
        guard confirm("Forget this phone?", "Removes its pins, saved addresses and cached data from this Mac.", "Forget") else { return }
        session?.forgetDevice()
    }

    private func confirmInstallCompanion() {
        guard confirm("Install the phone companion?",
                      "Installs CarbonMirror Companion on the phone connected by USB and grants it permission to turn Wireless debugging on and off. "
                          + "A companion from another build is replaced; its trusted Wi-Fi networks are cleared.",
                      "Install") else { return }
        Task {
            switch await session?.installCompanion() ?? .noPhone {
            case .installed:
                inform("Companion installed", "Add the CarbonMirror tile from the phone's Quick Settings editor.")
            case .replaced:
                inform("Companion replaced", "The companion from another build was removed, with its trusted Wi-Fi networks. "
                           + "Open the new one on the phone once, then add the CarbonMirror tile from the Quick Settings editor.")
            case .notGranted:
                inform("Permission not granted", "The companion is installed but can't turn Wireless debugging on and off yet. "
                           + "Keep the phone unlocked and connected, then choose Reinstall Over USB… in Settings → Connection.")
            case .noPhone:
                inform("No phone on USB", "Connect the phone by USB, unlock it, allow USB debugging and try again.")
            case .failed:
                inform("Companion not installed", "The phone refused the install. Unlock it, keep it connected and try again.")
            }
        }
    }

    @objc private func showPhone(_ sender: Any?) {
        phone?.showWindow()
        NSApp.activate()
    }

    @objc private func showSettings(_ sender: Any?) { settingsWindow?.show() }
    @objc private func toggleHUD(_ sender: Any?) { session?.toggleHUD() }
    @objc private func phoneScreenshot(_ sender: Any?) { session?.phoneScreenshot() }
    @objc private func pairNew(_ sender: Any?) { pairing?.start() }
    @objc private func newKey(_ sender: Any?) { confirmCreateNewKey() }
    @objc private func forget(_ sender: Any?) { confirmForget() }

    @objc private func connectOrDisconnect(_ sender: Any?) {
        sessionActive ? session?.disconnect() : session?.reconnect()
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = AppSettings.ConnectionMode(rawValue: raw) else { return }
        settings.connectionMode = mode
    }

    @objc private func toolbarMenuItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let item = ToolbarItem(rawValue: raw) else { return }
        toolbar(item)
    }

    @objc private func realSize(_ sender: Any?) {
        phone?.snapToRealSize()
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toolbarMenuItem(_:)):
            guard let raw = menuItem.representedObject as? String, let item = ToolbarItem(rawValue: raw) else { return false }
            switch item {
            case .pinOnTop: menuItem.state = settings.pinOnTop ? .on : .off
            case .clipboardSync: menuItem.state = settings.clipboardSync ? .on : .off
            case .typingMode: menuItem.state = settings.typingMode == .phone ? .on : .off
            default: break
            }
            return sessionActive || !item.needsSession
        case #selector(connectOrDisconnect(_:)):
            menuItem.title = sessionActive ? "Disconnect" : "Connect"
            return session != nil
        case #selector(setMode(_:)):
            menuItem.state = (menuItem.representedObject as? String) == settings.connectionMode.rawValue ? .on : .off
            return true
        case #selector(toggleHUD(_:)):
            menuItem.state = settings.showDebugHUD ? .on : .off
            return session != nil
        case #selector(phoneScreenshot(_:)):
            return sessionActive
        default:
            return true
        }
    }

    // MARK: Menus

    private func item(_ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.keyEquivalentModifierMask = modifiers
        entry.target = self
        return entry
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        let appMenu = NSMenu(title: "CarbonMirror")
        appMenu.addItem(withTitle: "About CarbonMirror", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(item("Settings…", #selector(showSettings(_:)), ","))
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
        for toolbarItem in ToolbarItem.allCases where toolbarItem != .connection && toolbarItem != .settings {
            let entry = item(toolbarItem.title, #selector(toolbarMenuItem(_:)))
            entry.representedObject = toolbarItem.rawValue
            phoneMenu.addItem(entry)
        }
        phoneMenu.addItem(item("Screenshot on Phone", #selector(phoneScreenshot(_:))))
        main.addItem(submenu: phoneMenu, title: "Phone")

        let view = NSMenu(title: "View")
        view.addItem(item("Real Size", #selector(realSize(_:))))
        view.addItem(item("Debug HUD", #selector(toggleHUD(_:))))
        main.addItem(submenu: view, title: "View")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(item("Show Phone Window", #selector(showPhone(_:))))
        main.addItem(submenu: windowMenu, title: "Window")
        NSApp.windowsMenu = windowMenu
        return main
    }

    /// Menu-bar extra (spec 8.3): Connect/Disconnect, Mode, Pair new device, Create new key, Forget device, Settings, Quit.
    private func buildMenuBarMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Show CarbonMirror", #selector(showPhone(_:))))
        menu.addItem(item("Connect", #selector(connectOrDisconnect(_:))))
        let modes = NSMenu(title: "Mode")
        for (mode, title) in zip(AppSettings.ConnectionMode.allCases, ["Auto", "USB only", "Wireless only"]) {
            let entry = item(title, #selector(setMode(_:)))
            entry.representedObject = mode.rawValue
            modes.addItem(entry)
        }
        menu.addItem(submenu: modes, title: "Mode")
        menu.addItem(.separator())
        menu.addItem(item("Pair New Device…", #selector(pairNew(_:))))
        menu.addItem(item("Create New Key…", #selector(newKey(_:))))
        menu.addItem(item("Forget Device…", #selector(forget(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings(_:)), ","))
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
#endif
