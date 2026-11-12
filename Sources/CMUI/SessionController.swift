// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if os(macOS)
import AppKit
import CMCore
import CMCoreBridge
import CMInput
import CMMedia
import CMSecurity
import CMTransport
import Network

/// Runs the phone link end to end: the verified adb helper and its supervisor, the keys, transport choice
/// and handover (6.3), wireless discovery and checks (6.2), sessions with the inner TLS (7.3), silent
/// reconnect (8.2.2), session-ending events (7.6), occlusion power saving (8.2.1), clipboard (5.6),
/// status line (8.2.5), landscape offer (8.2.6), adaptive USB profile (4.5) and the debug HUD (4.6).
@MainActor
final class SessionController {
    /// Everything that exists only when the bundled adb passed its signature check.
    private struct Services {
        let runner: AdbRunner
        let supervisor: AdbSupervisor
        let keys: KeyManager
        let link: AdbPhoneLink
    }

    private enum EndReason { case user, guardEvent, idle }

    var onPairRequested: (() -> Void)?
    /// Asks for the IP address and port shown in the phone's Wireless debugging screen (mDNS replies may be
    /// blocked, spec 6.2); `suggestedIP` is the last known address or, on a phone hotspot, the gateway.
    var askEndpoint: ((_ suggestedIP: String) async -> Device.Endpoint?)?

    private let settings: AppSettings
    private let phone: PhoneWindowController
    let mirror = MirrorView()
    private let decoder = VideoDecoder()
    private var services: Services?

    private var session: MirrorSession?
    private var sessionSerial: String?
    /// A new device key sent with the running USB session; kept once that session has connected.
    private var pendingDeviceKey: [UInt8]?
    private var transport: StatusLine.Transport?
    private var sessionLive = false
    private var encrypted = false
    private var tls: (suite: UInt16, group: UInt16)?
    private var codec: VideoCodecID?
    private var sessionNetwork: String?
    private var h265Failed = false

    private var devices: [AdbListedDevice] = []
    private var status = StatusLine.Snapshot()
    private var bitrate = 0.0
    private var maxSize = AdaptiveProfile.sizeSteps[0]
    private var maxFPS = 120
    /// Frames at this long side are native only when the cap did not shrink them (panel size for real-size maths).
    private var requestedMaxSize = AdaptiveProfile.sizeSteps[0]
    private var slowSince: Date?
    private var landscapeDismissed = false
    /// Short message shown in the status line for 5 s instead of the usual text.
    private var notice: (text: String, at: Date)?

    private var reconnectTask: Task<Void, Never>?
    /// Auto-connect (owner addition): background search, verified link, one-press mirroring.
    private var auto = AutoConnect()
    private var autoTask: Task<Void, Never>?
    /// The user asked for Wi-Fi (Connect, Reconnect, pairing) or a wireless session was live: connect directly.
    private var wantWireless = false
    private var reconnectAttempt = 0
    private var reconnectStarted: Date?
    private var connecting = false
    private var macLocked = false
    private var macAsleep = false
    private var wifiUp = true
    private var wifiInterface: String?

    private var blur = PrivacyBlurState()
    private var lastInput = Date()
    private var unfocusedSince: Date?
    private var hiddenTask: Task<Void, Never>?
    private var decodingSuspended = false
    private var pasteboardCount = NSPasteboard.general.changeCount
    private var clipboardSequence: Int64 = 0
    private let pathMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private var timers: [Timer] = []

    init(settings: AppSettings, phone: PhoneWindowController) {
        self.settings = settings
        self.phone = phone
        phone.content.screen.install(videoView: mirror)
        let frames = mirror.video.frames
        decoder.onFrame = { frames.put($0) }
        mirror.onActivity = { [weak self] in self?.lastInput = Date() }
        mirror.onRevealRequest = { [weak self] in self?.reveal() }
        mirror.engine.rightClickBack = settings.rightClickBack
        phone.content.screen.landscapeOffer.onAccept = { [weak self] in self?.acceptLandscape() }
        phone.content.screen.landscapeOffer.onDismiss = { [weak self] in self?.dismissLandscape() }
        settings.observe { [weak self] key in self?.settingChanged(key) }
    }

    // MARK: Launch

    func launch() {
        do {
            let environment = try AdbEnvironment.prepare()
            let adb = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/adb")
            try HelperSignature.verify(helperAt: adb)
            let runner = AdbRunner(executable: adb, environment: environment)
            let manifest = try ArtifactManifest(infoDictionary: Bundle.main.infoDictionary ?? [:])
            guard let resources = Bundle.main.resourceURL else { throw CoreStatus.invalidArgument }
            let deployer = ServerDeployer(runner: runner, serverURL: resources.appendingPathComponent("carbonmirror-server"),
                                          coreLibraryURL: resources.appendingPathComponent("libcarbon_core.so"), manifest: manifest)
            services = Services(runner: runner, supervisor: AdbSupervisor(runner: runner),
                                keys: KeyManager(store: KeychainKeyStore(), adbDirectory: environment.directory),
                                link: AdbPhoneLink(runner: runner, deployer: deployer))
        } catch {
            Log.error(.security, "launch checks failed; adb not started")
            phone.show(state: .launchCheckFailed)
            return
        }
        observeSystem()
        startTimers()
        guard services?.keys.checkHealth() == .ok else {
            phone.show(state: .authenticationFailed)
            return
        }
        startAdb()
        if settings.rotationReminderDue(now: Date()) { remindRotation() }
    }

    private func startAdb() {
        guard let services else { return }
        Task {
            do {
                try await services.supervisor.start()
                try services.keys.recordAdbKey()
                if settings.lastKeyRotation == nil { settings.lastKeyRotation = Date() }
            } catch {
                phone.show(state: .disconnected)
                return
            }
            for await list in services.supervisor.deviceUpdates { devicesChanged(list) }
        }
    }

    /// Ends the session, turns Wireless debugging off (9.1) and stops adb; then `done`.
    func shutdown(_ done: @escaping @MainActor () -> Void) {
        Task {
            await end(.user)
            autoTask?.cancel()
            await services?.supervisor.stop()
            done()
        }
    }

    // MARK: Devices and transport choice (6.3)

    private var pinned: Device? { services?.keys.pairedDevice() }

    private func devicesChanged(_ list: [AdbListedDevice]) {
        devices = list
        if let serial = sessionSerial, !list.contains(where: { $0.serial == serial && $0.isOnline }), session != nil {
            Log.info(.transport, "session device left")
        }
        if case let .ready(e) = auto.phase, !list.contains(where: { $0.serial == Self.adbSerial(e) && $0.isOnline }) {
            apply(auto.linkLost())
        }
        if let usb = list.first(where: { $0.link == .usb }), usb.state == "unauthorized" {
            show(failure: .adbUnauthorized)
            return
        }
        if let usb = usbDevice, settings.companionInstalled {
            Task { await regrantCompanion(serial: usb.serial) }
        }
        evaluate()
    }

    private var usbDevice: AdbListedDevice? {
        devices.first { $0.link == .usb && $0.isOnline }
    }

    /// Picks the transport and (re)starts the session when it should change.
    private func evaluate() {
        guard services != nil, !connecting, !macLocked, !macAsleep else { return }
        let usb = usbDevice
        if let usb, let pinned, pinned.serial != usb.serial, transport == nil {
            phone.show(state: .untrustedDevice)
            return
        }
        let wirelessPossible = pinned?.pins != nil && wifiUp
        switch TransportChoice.choose(mode: settings.connectionMode, usbAvailable: usb != nil, wirelessReachable: wirelessPossible) {
        case .usb:
            guard transport != .usb, let usb else { return }
            switchSession { await self.startSession(serial: usb.serial, wireless: false) }
        case .wireless:
            guard session == nil else { return }
            guard wantWireless else { return refreshAuto() }
            switchSession { await self.connectWireless() }
        case .none:
            refreshAuto()
            guard session == nil, reconnectTask == nil else { return }
            if !wifiUp && settings.connectionMode != .usbOnly { phone.show(state: .wifiOff) }
            else if pinned == nil { phone.show(state: .notPaired) }
            else { phone.show(state: .searching) }
        }
    }

    /// Replaces any running session without closing the window: the last frame stays, dimmed.
    /// `connecting` is set before the task starts, so overlapping device events never start two sessions.
    private func switchSession(_ start: @escaping @MainActor () async -> Void) {
        connecting = true
        Task {
            if let old = session {
                session = nil
                mirror.video.dimmed = true
                await old.stop()
            }
            await start()
            connecting = false
        }
    }

    // MARK: Wireless (6.1, 6.2)

    private func connectWireless() async {
        guard let services, let device = pinned, let pins = device.pins else { return }
        let interactive = !status.reconnecting
        if interactive { phone.show(state: .searching) }
        let prompt = interactive ? askEndpoint : nil
        let networkKey = currentNetworkKey()
        var endpoint: Device.Endpoint?
        for service in await Bonjour.browse(type: Bonjour.connectType, for: .seconds(3)) where service.name.hasPrefix("adb-\(pins.serial)-") {
            if let found = await Bonjour.resolve(service) { endpoint = Device.Endpoint(ip: found.ip, port: found.port) }
        }
        if endpoint == nil, let key = networkKey, let last = device.lastKnownEndpoints[key] { endpoint = last }
        if endpoint == nil {
            let gateway = wifiInterface.flatMap(NetworkIdentity.subnet(ofInterface:)).flatMap(NetworkIdentity.hotspotGateway(subnet:))
            endpoint = await prompt?(gateway ?? "")
        }
        guard var target = endpoint else {
            show(failure: .wirelessDebuggingOff)
            return
        }
        var result = await WirelessProbe.probe(ip: target.ip, port: target.port)
        if result == .unreachable, let entered = await prompt?(target.ip) {
            target = entered
            result = await WirelessProbe.probe(ip: target.ip, port: target.port)
        }
        switch result {
        case let .wirelessDebugging(keyHash):
            do {
                try services.keys.verify(serial: pins.serial, keyHash: keyHash)
            } catch {
                show(failure: error == .trustIdentityChanged ? .pinMismatchKnownDevice : .unknownDevice)
                return
            }
        case .plaintextRefused: return show(failure: .legacyPlaintextOffered)
        case .viaTunnel: return show(failure: .routeViaTunnel)
        case .unreachable, .notAdb: return show(failure: .lanUnreachable)
        case .refusedAddress: return show(failure: .lanUnreachable)
        }
        if let key = networkKey {
            var updated = device
            updated.lastKnownEndpoints[key] = target
            try? services.keys.pin(updated)
        }
        let serial = target.ip.contains(":") ? "[\(target.ip)]:\(target.port)" : "\(target.ip):\(target.port)"
        guard (try? await services.runner.runChecked(.connect(ip: target.ip, port: target.port), timeout: 10)) != nil,
              await waitForDevice(serial) else {
            show(failure: .connectionLost)
            return
        }
        sessionNetwork = networkKey
        await startSession(serial: serial, wireless: true)
    }

    // MARK: Auto-connect

    private static func adbSerial(_ e: Device.Endpoint) -> String {
        e.ip.contains(":") ? "[\(e.ip)]:\(e.port)" : "\(e.ip):\(e.port)"
    }

    private func autoConditions() -> AutoConnect.Conditions {
        let device = pinned
        let subnet = wifiUp ? wifiInterface.flatMap(NetworkIdentity.subnet(ofInterface:)) : nil
        let key = subnet.flatMap { try? NetworkIdentity.key(subnet: $0) }
        let proof = device.flatMap { services?.keys.deviceKey(serial: $0.serial) } != nil
        return AutoConnect.Conditions(enabled: settings.autoConnect && settings.connectionMode != .usbOnly,
                                      paired: device?.pins != nil && proof, macLocked: macLocked, macAsleep: macAsleep,
                                      subnet: subnet, knownNetwork: key.map { device?.lastKnownEndpoints[$0] != nil } ?? false,
                                      busy: session != nil || connecting || reconnectTask != nil
                                          || (usbDevice != nil && settings.connectionMode != .wirelessOnly))
    }

    private func refreshAuto() {
        guard services != nil else { return }
        apply(auto.update(autoConditions()))
    }

    /// Runs one step of the auto-connect machine; stale results are ignored by the machine itself.
    private func apply(_ step: AutoConnect.Step) {
        switch step {
        case .none:
            break
        case .browse:
            autoTask?.cancel()
            autoTask = Task {
                let found = await browsePinned()
                guard !Task.isCancelled else { return }
                apply(auto.found(found))
            }
        case let .wait(seconds):
            autoTask?.cancel()
            autoTask = Task {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                apply(auto.retry())
            }
        case let .verify(endpoint):
            autoTask?.cancel()
            autoTask = Task {
                let result = await link(endpoint)
                let next = auto.verified(result, for: endpoint)
                // A link that finished after the machine moved on is closed, unless a session now uses it.
                if result == .linked, auto.phase != .ready(endpoint), !connecting, session == nil || sessionSerial != Self.adbSerial(endpoint) {
                    return apply(.drop(endpoint))
                }
                apply(next)
            }
        case let .mirror(endpoint):
            wantWireless = true
            switchSession {
                self.sessionNetwork = self.currentNetworkKey()
                await self.startSession(serial: Self.adbSerial(endpoint), wireless: true)
            }
        case let .drop(endpoint):
            autoTask?.cancel()
            guard let runner = services?.runner else { break }
            Task { _ = try? await runner.run(.disconnect(ip: endpoint.ip, port: endpoint.port), timeout: 5) }
        }
        showAutoState()
    }

    /// Shows the machine's state on the idle screens only; failure screens stay until the user acts.
    private func showAutoState() {
        guard session == nil, !connecting, reconnectTask == nil, !wantWireless, pinned?.pins != nil, wifiUp,
              settings.connectionMode != .usbOnly, usbDevice == nil else { return }
        let idle: Set<UIStateCode> = [.searching, .notConnected, .phoneReady, .notPaired, .wifiOff, .disconnected]
        guard idle.contains(phone.state) else { return }
        switch auto.phase {
        case .searching, .verifying: phone.show(state: .searching)
        case .ready: phone.show(state: .phoneReady)
        case .off, .waiting: phone.show(state: .notConnected)
        case .mirroring, .halted: break
        }
    }

    /// mDNS answers for the pinned serial's Wireless debugging service; no port scan.
    private func browsePinned() async -> [Device.Endpoint] {
        guard let serial = pinned?.pins?.serial else { return [] }
        var found: [Device.Endpoint] = []
        for service in await Bonjour.browse(type: Bonjour.connectType, for: .seconds(3)) where service.name.hasPrefix("adb-\(serial)-") {
            if let r = await Bonjour.resolve(service) { found.append(Device.Endpoint(ip: r.ip, port: r.port)) }
        }
        return found
    }

    /// Probe (route, plaintext refusal), pinned adb TLS key, then `adb connect`; remembers the endpoint for this network.
    private func link(_ endpoint: Device.Endpoint) async -> AutoConnect.Verification {
        guard let services, let device = pinned, let pins = device.pins, stillWanted(endpoint) else { return .unreachable }
        switch await WirelessProbe.probe(ip: endpoint.ip, port: endpoint.port) {
        case let .wirelessDebugging(keyHash):
            do {
                try services.keys.verify(serial: pins.serial, keyHash: keyHash)
            } catch {
                showIfIdle(failure: error == .trustIdentityChanged ? .pinMismatchKnownDevice : .unknownDevice)
                return .refused
            }
        case .plaintextRefused:
            showIfIdle(failure: .legacyPlaintextOffered)
            return .refused
        case .viaTunnel, .unreachable, .notAdb, .refusedAddress:
            return .unreachable
        }
        // Conditions may have changed during the probe (lock, sleep, USB, network): never connect then.
        guard stillWanted(endpoint),
              (try? await services.runner.runChecked(.connect(ip: endpoint.ip, port: endpoint.port), timeout: 10)) != nil,
              await waitForDevice(Self.adbSerial(endpoint)) else { return .unreachable }
        if let key = currentNetworkKey() {
            var updated = device
            updated.lastKnownEndpoints[key] = endpoint
            try? services.keys.pin(updated)
        }
        return .linked
    }

    private func stillWanted(_ endpoint: Device.Endpoint) -> Bool {
        auto.phase == .verifying(endpoint) && !macLocked && !macAsleep && autoConditions().busy == false
    }

    /// An auto-connect refusal never covers a session that started meanwhile.
    private func showIfIdle(failure: FailureClass) {
        guard session == nil, !connecting else { return }
        show(failure: failure)
    }

    /// The "Mirror" button on the Ready screen.
    func openMirror() {
        apply(auto.openMirror())
    }

    private func waitForDevice(_ serial: String) async -> Bool {
        for _ in 0..<50 {
            if devices.contains(where: { $0.serial == serial && $0.isOnline }) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private func currentNetworkKey() -> String? {
        wifiInterface.flatMap(NetworkIdentity.subnet(ofInterface:)).flatMap { try? NetworkIdentity.key(subnet: $0) }
    }

    // MARK: Sessions

    private func startSession(serial: String, wireless: Bool) async {
        guard let services else { return }
        if settings.macPinResetPending {
            guard (try? await services.runner.runChecked(.removeMacPin(serial: serial), timeout: 10)) != nil else {
                return show(failure: .connectionLost)
            }
            settings.macPinResetPending = false
        }
        let profile = wireless ? settings.wirelessProfile : settings.usbProfile
        let encryption: Encryption?
        if wireless || settings.encryptOverUSB {
            guard let e = try? services.keys.encryption() else { return show(failure: .keyMissing) }
            encryption = e
        } else {
            encryption = nil
        }
        if !wireless { maxFPS = profile.maxFPS }
        // USB provisions the device key (a new one until the first USB session has connected); wireless must prove it.
        let stored = (wireless ? pinned?.serial : serial).flatMap { services.keys.deviceKey(serial: $0) }
        let deviceKey = stored ?? (wireless ? nil : try? CoreCrypto.randomBytes(32))
        pendingDeviceKey = stored == nil ? deviceKey : nil
        let codec: VideoCodec = profile.codec == .h265 && !h265Failed ? .h265 : .h264
        requestedMaxSize = wireless ? AdaptiveProfile.sizeSteps[0] : maxSize
        let parameters = SessionParameters(serial: serial, wireless: wireless,
                                           serverVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                                           codec: codec, maxSize: requestedMaxSize,
                                           maxFPS: wireless ? profile.maxFPS : maxFPS, bitRate: profile.bitrateMbps * 1_000_000,
                                           clipboardSync: settings.clipboardSync, encryption: encryption, deviceKey: deviceKey)
        let session = MirrorSession(parameters: parameters, link: services.link, connector: { path in try await POSIXStream.connect(unixPath: path) },
                                    video: decoder)
        self.session = session
        sessionSerial = serial
        transport = wireless ? .wifi : .usb
        encrypted = encryption != nil
        status.transport = transport
        Task {
            for await event in session.events { handle(event, from: session) }
        }
        do {
            try await session.start()
        } catch {
            if codec == .h265, !sessionLive { h265Failed = true }
            ended(error, session: session)
        }
    }

    private func handle(_ event: SessionEvent, from source: MirrorSession) {
        guard source === session else { return }
        switch event {
        case let .connected(_, codec, suite, group):
            sessionLive = true
            if let key = pendingDeviceKey, let serial = sessionSerial {
                try? services?.keys.storeDeviceKey(key, serial: serial)
                pendingDeviceKey = nil
            }
            self.codec = codec
            tls = suite.flatMap { s in group.map { (suite: s, group: $0) } }
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = 0
            status.reconnecting = false
            mirror.video.dimmed = false
            mirror.sender = { [source] message in source.send(message) }
            mirror.setTypingMode(settings.typingMode)
            if settings.phoneScreenOff { mirror.deliver([try? ControlMessage.simple(.displayPowerOff)].compactMap { $0 }) }
            phone.show(state: .mirroring)
            phone.content.chrome.setConnectionBadge(text: transport == .usb ? "USB · \(maxFPS)" : "Wi-Fi",
                                                    symbol: encrypted ? "lock.fill" : nil)
            phone.window.makeFirstResponder(mirror)
        case let .cornerRadius(pixels):
            phone.sizer.profile.cornerRadiusPixels = Double(pixels)
            phone.content.needsLayout = true
        case let .videoSize(width, height):
            mirror.setFrameSize(width: width, height: height)
            if max(width, height) < requestedMaxSize || requestedMaxSize == AdaptiveProfile.sizeSteps[0] {
                phone.sizer.profile.widthPixels = Double(min(width, height))
                phone.sizer.profile.heightPixels = Double(max(width, height))
            }
            landscapeChanged(phoneLandscape: width > height)
        case let .clipboard(text):
            guard settings.clipboardSync else { return }
            let board = NSPasteboard.general
            // This Mac only: phone text never syncs to other devices through Universal Clipboard.
            board.prepareForNewContents(with: .currentHostOnly)
            board.setString(text, forType: .string)
            pasteboardCount = board.changeCount
        case let .battery(level, charging):
            status.batteryLevel = level
            status.charging = charging
        case let .latency(ms):
            status.latencyMs = ms
        case let .throughput(fps, mbps):
            status.fps = fps
            bitrate = mbps
            adapt(fps: fps)
        case let .ended(reason):
            ended(reason, session: source)
        }
    }

    private func ended(_ reason: SessionEnd, session source: MirrorSession) {
        guard source === session else { return }
        session = nil
        mirror.sender = nil
        _ = mirror.engine.releaseAll()
        let wasLive = sessionLive
        sessionLive = false
        transport = nil
        status = StatusLine.Snapshot()
        defer { refreshAuto() }
        guard let failure = reason.failureClass else { return }
        if wasLive, failure == .connectionLost {
            scheduleReconnect()
        } else if failure == .pinMismatchKnownDevice {
            mirror.video.reset()
            phone.show(state: .identityChanged)
        } else {
            show(failure: failure)
        }
    }

    /// Failure → state through the Rust mapping; "retry silently" schedules a reconnect (7.5.2, 8.2.2).
    private func show(failure: FailureClass) {
        let state = (try? FailureMap.uiState(for: failure, attempt: UInt32(reconnectAttempt))) ?? .disconnected
        if state == .retryingSilently {
            scheduleReconnect()
        } else {
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = 0
            mirror.video.reset()
            phone.show(state: state)
        }
    }

    // MARK: Silent reconnect (8.2.2)

    private func scheduleReconnect() {
        let started = reconnectStarted ?? Date()
        reconnectStarted = started
        guard let delay = ReconnectSchedule.delay(attempt: reconnectAttempt, elapsed: Date().timeIntervalSince(started)) else {
            reconnectTask = nil
            reconnectStarted = nil
            reconnectAttempt = 0
            mirror.video.reset()
            phone.show(state: .disconnected)
            return
        }
        reconnectAttempt += 1
        status.reconnecting = true
        mirror.video.dimmed = true
        phone.show(state: .retryingSilently)
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            reconnectTask = nil
            guard ReconnectSchedule.allowed(macLocked: macLocked, macAsleep: macAsleep, targetIsPinned: pinned != nil || usbDevice != nil) else {
                return
            }
            evaluate()
            if session == nil, !connecting { scheduleReconnect() }
        }
    }

    // MARK: Ending (7.6, 9.1)

    private func end(_ reason: EndReason) async {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectStarted = nil
        wantWireless = false
        defer { refreshAuto() }
        guard let current = session else { return }
        let serial = sessionSerial
        let wasWireless = transport == .wifi
        session = nil
        sessionLive = false
        transport = nil
        mirror.sender = nil
        await current.stop()
        mirror.video.reset()
        status = StatusLine.Snapshot()
        // With auto-connect the companion keeps Wireless debugging on for the trusted network only.
        if wasWireless, reason != .guardEvent, !settings.autoConnect, let serial, let services {
            _ = try? await services.runner.run(.disableWirelessDebugging(serial: serial), timeout: 5)
        }
        phone.show(state: .disconnected)
        Log.info(.transport, "session ended", ["by": "\(reason)"])
    }

    // MARK: Adaptive USB profile (4.5)

    /// Judges only seconds with moving content (Android sends no frames for a still screen).
    private func adapt(fps: Double) {
        guard transport == .usb, fps >= 30 else { slowSince = nil; return }
        guard fps < AdaptiveProfile.threshold else { slowSince = nil; return }
        let since = slowSince ?? Date()
        slowSince = since
        guard Date().timeIntervalSince(since) >= AdaptiveProfile.window, let next = AdaptiveProfile.next(maxSize: maxSize, maxFPS: maxFPS),
              let serial = sessionSerial else { return }
        slowSince = nil
        maxSize = next.maxSize
        maxFPS = next.maxFPS
        Log.info(.media, "adaptive step", ["size": "\(maxSize)", "fps": "\(maxFPS)"])
        switchSession { await self.startSession(serial: serial, wireless: false) }
    }

    // MARK: Landscape (8.2.6)

    private func landscapeChanged(phoneLandscape: Bool) {
        if !phoneLandscape { landscapeDismissed = false }
        let decision = LandscapeDecision.decide(offerEnabled: settings.landscapeOffer, behaviour: settings.landscapeBehaviour,
                                                phoneLandscape: phoneLandscape, windowLandscape: phone.sizer.landscape)
        phone.content.screen.landscapeOffer.isHidden = !(decision == .offer && !landscapeDismissed)
        phone.content.screen.needsLayout = true
        switch decision {
        case .rotateToLandscape: phone.setLandscape(true)
        case .returnToPortrait: phone.setLandscape(false)
        case .keep, .offer: break
        }
    }

    private func acceptLandscape() {
        phone.content.screen.landscapeOffer.isHidden = true
        phone.setLandscape(true)
    }

    private func dismissLandscape() {
        landscapeDismissed = true
        phone.content.screen.landscapeOffer.isHidden = true
    }

    // MARK: Toolbar and menu actions

    func perform(_ item: ToolbarItem) {
        switch item {
        case .screenshot:
            if mirror.video.saveScreenshot() == nil { NSSound.beep() }
        case .privacyBlur:
            blur.blurred ? reveal() : setBlur(true)
        case .clipboardSync:
            settings.clipboardSync.toggle()
        case .typingMode:
            settings.typingMode = settings.typingMode == .hardware ? .phone : .hardware
        case .pinOnTop:
            settings.pinOnTop.toggle()
        case .settings, .connection:
            break
        default:
            mirror.deliver(mirror.engine.action(item))
        }
    }

    func phoneScreenshot() {
        mirror.deliver(mirror.engine.phoneScreenshot())
    }

    func toggleHUD() {
        settings.showDebugHUD.toggle()
    }

    func disconnect() {
        Task { await end(.user) }
    }

    func reconnect() {
        reconnectAttempt = 0
        reconnectStarted = nil
        h265Failed = false
        wantWireless = true
        auto.resume()
        evaluate()
    }

    func useUSBOnly() {
        settings.connectionMode = .usbOnly
    }

    /// Pairing finished: pin (with the endpoint for this network), then connect.
    func paired(_ device: Device, endpoint: Device.Endpoint) {
        var device = device
        if let key = currentNetworkKey() { device.lastKnownEndpoints[key] = endpoint }
        do {
            try services?.keys.pin(device)
        } catch {
            return phone.show(state: .authenticationFailed)
        }
        Log.info(.security, "phone paired and pinned")
        reconnect()
    }

    /// "Forget device" (7.6): pins, endpoints and cached data.
    func forgetDevice() {
        Task {
            await end(.user)
            try? services?.keys.forgetDevice()
            phone.show(state: .notPaired)
        }
    }

    /// "Create new key" (7.5.3), after the caller's confirmation.
    func createNewKey() {
        guard let services else { return }
        Task {
            await end(.user)
            await services.supervisor.stop()
            do {
                try services.keys.createNewKey()
            } catch {
                phone.show(state: .authenticationFailed)
                return
            }
            settings.lastKeyRotation = Date()
            settings.macPinResetPending = true
            phone.show(state: .notPaired)
            startAdb()
            onPairRequested?()
        }
    }

    /// Runs `adb pair` (allowlisted command, private-range address); returns the phone's mDNS name
    /// (`adb-<serial>-<suffix>`) from adb's `[guid=…]` answer.
    func pair(ip: String, port: UInt16, secret: String) async -> String? {
        guard let runner = services?.runner, let result = try? await runner.run(.pair(ip: ip, port: port, secret: secret), timeout: 20),
              result.succeeded, result.text.contains("Successfully paired"), let start = result.text.range(of: "[guid=") else { return nil }
        let rest = result.text[start.upperBound...]
        guard let end = rest.firstIndex(of: "]") else { return nil }
        let guid = String(rest[..<end])
        let safe = guid.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) || [0x2D, 0x2E, 0x5F].contains($0) }
        return guid.hasPrefix("adb-") && guid.utf8.count <= 128 && safe ? guid : nil
    }

    /// Probes a just-paired phone to read its adb TLS key for the pin (7.2).
    func probeKey(ip: String, port: UInt16) async -> ProbeResult {
        await WirelessProbe.probe(ip: ip, port: port)
    }

    /// Installs the companion over USB after the user confirmed, then grants its one permission (9.1).
    func installCompanion() async -> Bool {
        guard let runner = services?.runner, let usb = usbDevice,
              let apk = Bundle.main.resourceURL?.appendingPathComponent("CarbonMirrorCompanion.apk") else { return false }
        guard (try? await runner.runChecked(.installCompanion(serial: usb.serial, apkPath: apk.path), usb: true, confirmed: true, timeout: 120)) != nil,
              (try? await runner.runChecked(.grantCompanionPermission(serial: usb.serial), timeout: 10)) != nil else { return false }
        settings.companionInstalled = true
        return true
    }

    /// GrapheneOS may reset special permissions after an update (9.3): re-grant silently on every USB connect.
    private func regrantCompanion(serial: String) async {
        guard let result = try? await services?.runner.run(.grantCompanionPermission(serial: serial), timeout: 10), result.succeeded else { return }
        notice = ("Companion permission re-granted", Date())
    }

    // MARK: Privacy blur (8.2.4)

    private func setBlur(_ on: Bool) {
        if on, !blur.blurred { blur.toggle() }
        if !on { blur.reveal() }
        mirror.setBlurred(blur.blurred)
        phone.content.chrome.setToggle(.privacyBlur, on: blur.blurred)
    }

    private func reveal() {
        guard blur.blurred else { return }
        guard settings.touchIDToReveal else { return setBlur(false) }
        Task {
            if await OwnerCheck.authenticate(reason: "reveal the mirrored phone screen") { setBlur(false) }
        }
    }

    // MARK: Settings applied live (8.3)

    private func settingChanged(_ key: AppSettings.Key) {
        switch key {
        case .typingMode:
            mirror.setTypingMode(settings.typingMode)
        case .rightClickBack:
            mirror.engine.rightClickBack = settings.rightClickBack
        case .phoneScreenOff:
            mirror.deliver([try? ControlMessage.simple(settings.phoneScreenOff ? .displayPowerOff : .displayPowerOn)].compactMap { $0 })
        case .connectionMode:
            let wanted = TransportChoice.choose(mode: settings.connectionMode, usbAvailable: usbDevice != nil, wirelessReachable: pinned?.pins != nil)
            if session != nil, wanted != (transport == .usb ? .usb : .wireless) {
                Task { await end(.user); evaluate() }
            } else {
                evaluate()
            }
        case .usbFPS, .usbBitrate, .usbCodec, .encryptOverUSB:
            guard transport == .usb, let serial = sessionSerial else { return }
            maxFPS = settings.usbProfile.maxFPS
            maxSize = AdaptiveProfile.sizeSteps[0]
            switchSession { await self.startSession(serial: serial, wireless: false) }
        case .wifiFPS, .wifiBitrate, .wifiCodec:
            guard transport == .wifi, let serial = sessionSerial else { return }
            h265Failed = false
            switchSession { await self.startSession(serial: serial, wireless: true) }
        case .showDebugHUD:
            refreshHUD()
        case .autoConnect:
            refreshAuto()
        default:
            break
        }
    }

    // MARK: Timers: status line, HUD, auto-blur, idle, clipboard

    private func startTimers() {
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.everySecond() } }
        let clip = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.pollPasteboard() } }
        for timer in [tick, clip] {
            RunLoop.main.add(timer, forMode: .common)
            timers.append(timer)
        }
    }

    private func everySecond() {
        if sessionLive {
            status.quality = ConnectionQuality.classify(fps: (status.fps ?? 0) >= 1 ? status.fps : nil,
                                                        targetFPS: Double(transport == .usb ? maxFPS : settings.wirelessProfile.maxFPS),
                                                        latencyMs: status.latencyMs)
            if Date().timeIntervalSince(lastInput) >= Double(settings.idleTimeoutMinutes * 60) {
                Task { await end(.idle) }
            }
        }
        let symbol = status.batteryLevel.map { StatusLine.batterySymbol(level: $0, charging: status.charging) }
        if let n = notice, Date().timeIntervalSince(n.at) < 5 {
            phone.content.chrome.setStatusLine(n.text, batterySymbol: nil, visible: true)
        } else {
            notice = nil
            phone.content.chrome.setStatusLine(StatusLine.text(status), batterySymbol: symbol, visible: settings.statusLine)
        }
        if phone.window.isKeyWindow { unfocusedSince = nil } else if unfocusedSince == nil { unfocusedSince = Date() }
        if blur.update(autoBlurSeconds: settings.autoBlurSeconds, unfocusedFor: unfocusedSince.map { Date().timeIntervalSince($0) } ?? 0,
                       screensaverOrDisplaySleep: false) {
            setBlur(true)
        }
        refreshHUD()
    }

    private func refreshHUD() {
        guard settings.showDebugHUD else { return mirror.setHUD(nil) }
        let lines = [
            "fps \(Int((status.fps ?? 0).rounded()))  decode \(String(format: "%.1f", decoder.lastDecodeMs)) ms",
            "latency \(status.latencyMs.map { String(format: "%.0f ms (round trip)", $0) } ?? "–")",
            "bitrate \(String(format: "%.1f", bitrate)) Mbit/s  codec \(codec == .h265 ? "H.265" : codec == .h264 ? "H.264" : "–")",
            "transport \(transport == .usb ? "USB" : transport == .wifi ? "Wi-Fi" : "–")  size \(maxSize)",
            "TLS \(tls.map { "\(InnerTLS.describe(suite: $0.suite)) · \(InnerTLS.describe(group: $0.group))" } ?? (encrypted ? "…" : "off"))",
        ]
        mirror.setHUD(lines.joined(separator: "\n"))
    }

    static let privatePasteboardTypes: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                                                      "org.nspasteboard.AutoGeneratedType"]

    /// Mac → phone clipboard (5.6, 7.6): plain text only, read only while sync is on and the window is focused.
    private func pollPasteboard() {
        guard sessionLive, settings.clipboardSync, phone.window.isKeyWindow, !blur.blurred else { return }
        let board = NSPasteboard.general
        guard board.changeCount != pasteboardCount else { return }
        pasteboardCount = board.changeCount
        // Password managers mark secrets as concealed/transient (nspasteboard.org); those never leave the Mac.
        if let types = board.types, types.contains(where: { Self.privatePasteboardTypes.contains($0.rawValue) }) { return }
        guard let text = board.string(forType: .string) else { return }
        let bytes = Array(text.utf8)
        guard (try? ScrcpyProtocol.checkClipboard(bytes)) != nil else { return }
        clipboardSequence += 1
        mirror.deliver([try? ControlMessage.setClipboard(sequence: clipboardSequence, text: bytes)].compactMap { $0 })
    }

    // MARK: System events (7.6, 8.2.1, 8.2.4)

    private func observeSystem() {
        macLocked = Self.screenIsLocked()
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        func on(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor () -> Void) {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated(body) }
        }
        on(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.macAsleep = true
            Task { await self?.end(.guardEvent) }
        }
        on(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            self?.macAsleep = false
            self?.evaluate()
        }
        on(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in Task { await self?.end(.guardEvent) } }
        on(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.setBlur(true) }
        on(distributed, Notification.Name("com.apple.screensaver.didstart")) { [weak self] in self?.setBlur(true) }
        on(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.macLocked = true
            Task { await self?.end(.guardEvent) }
        }
        on(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            // Any process can post this notification: trust it only when the window server agrees.
            guard !Self.screenIsLocked() else { return Log.error(.security, "unlock notification ignored: screen still locked") }
            self?.macLocked = false
            self?.evaluate()
        }
        on(NotificationCenter.default, NSWindow.didChangeOcclusionStateNotification) { [weak self] in self?.occlusionChanged() }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            let name = path.availableInterfaces.first { $0.type == .wifi }?.name
            Task { @MainActor in self?.networkChanged(up: up, interface: name) }
        }
        pathMonitor.start(queue: .global(qos: .utility))
    }

    /// The window server's own lock state (`CGSSessionScreenIsLocked`).
    static func screenIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    /// Wi-Fi off/on, and "change to an unknown network" ends a wireless session (7.6).
    private func networkChanged(up: Bool, interface: String?) {
        wifiUp = up
        wifiInterface = interface
        if transport == .wifi, currentNetworkKey() != sessionNetwork {
            Task { await end(.guardEvent); evaluate() }
        } else {
            evaluate()
        }
    }

    /// Fully hidden: stop rendering now, pause decoding after 5 s; on return ask for a fresh key frame.
    private func occlusionChanged() {
        let visible = phone.window.occlusionState.contains(.visible)
        mirror.video.renderingPaused = !visible
        hiddenTask?.cancel()
        hiddenTask = nil
        if visible {
            if decodingSuspended {
                decodingSuspended = false
                decoder.resume()
                mirror.deliver([try? ControlMessage.simple(.resetVideo)].compactMap { $0 })
            }
        } else if settings.powerSavingWhenHidden {
            hiddenTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                decoder.suspend()
                decodingSuspended = true
            }
        }
    }

    // MARK: Rotation reminder (7.5.5)

    private func remindRotation() {
        let alert = NSAlert()
        alert.messageText = "Time for a new key"
        alert.informativeText = "It has been \(settings.rotationReminderDays) days since this Mac's key was created. Create a new key and pair your phone again?"
        alert.addButton(withTitle: "Create new key")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { createNewKey() } else { settings.lastKeyRotation = Date() }
    }
}
#endif
