// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if os(macOS)
import AppKit
import CMCore
import CMCoreBridge
import CMTransport
import CoreImage
import CoreImage.CIFilterBuiltins

/// Full-window monochrome QR for Android's "Pair device with QR code" (spec 7.2), on the status-screen glass.
@MainActor
final class PairingView: NSView {
    var onCodeEntry: (() -> Void)?
    var onCancel: (() -> Void)?

    private let title = NSTextField(labelWithString: "Scan with your phone")
    private let subtitle = NSTextField(wrappingLabelWithString: "Wireless debugging → Pair device with QR code")
    private let qr = NSImageView()
    private let countdown = NSTextField(labelWithString: "")
    private let buttons = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = Theme.titleFont
        title.textColor = Theme.primaryText
        title.alignment = .center
        subtitle.font = Theme.subtitleFont
        subtitle.textColor = Theme.secondaryText
        subtitle.alignment = .center
        countdown.font = Theme.statusLineFont
        countdown.textColor = Theme.secondaryText
        countdown.alignment = .center
        qr.imageScaling = .scaleProportionallyUpOrDown
        qr.wantsLayer = true
        qr.layer?.magnificationFilter = .nearest
        qr.layer?.backgroundColor = NSColor.white.cgColor
        qr.layer?.cornerCurve = .continuous
        qr.layer?.cornerRadius = 12
        qr.setAccessibilityLabel("Pairing QR code")
        let code = PillButton(title: "Use pairing code")
        code.target = self
        code.action = #selector(codeEntry)
        let cancel = PillButton(title: "Cancel")
        cancel.target = self
        cancel.action = #selector(cancelPressed)
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.addArrangedSubview(code)
        buttons.addArrangedSubview(cancel)
        for view in [title, subtitle, qr, countdown, buttons] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func show(payload: String, secondsLeft: Int) {
        qr.image = Self.qrImage(payload)
        update(secondsLeft: secondsLeft)
    }

    func update(secondsLeft: Int) {
        countdown.stringValue = String(format: "Expires in %d:%02d", secondsLeft / 60, secondsLeft % 60)
    }

    /// Centred column; the QR takes what is left so nothing clips from 0.75× to the maximum size.
    override func layout() {
        super.layout()
        let width = max(0, bounds.width - 32)
        subtitle.preferredMaxLayoutWidth = width
        buttons.orientation = buttons.fittingSize.width > width ? .vertical : .horizontal
        let heights = [title.fittingSize.height, subtitle.fittingSize.height, countdown.fittingSize.height, buttons.fittingSize.height]
        let fixed = heights.reduce(0, +) + 8 + 16 + 12 + 18
        let side = max(0, min(240, width, bounds.height - fixed - 32))
        var y = max(16, (bounds.height - fixed - side) / 2)
        func place(_ view: NSView, _ height: CGFloat, _ w: CGFloat, gap: CGFloat) {
            view.frame = NSRect(x: (bounds.width - w) / 2, y: y, width: w, height: height)
            y += height + gap
        }
        place(title, heights[0], width, gap: 8)
        place(subtitle, heights[1], width, gap: 16)
        place(qr, side, side, gap: 12)
        place(countdown, heights[2], width, gap: 18)
        place(buttons, heights[3], min(width, buttons.fittingSize.width), gap: 0)
    }

    /// Black modules on white, 3-pixel quiet zone handled by CoreImage plus the white tile.
    static func qrImage(_ payload: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 10, y: 10)), from: output.extent.applying(CGAffineTransform(scaleX: 10, y: 10))) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    @objc private func codeEntry() { onCodeEntry?() }
    @objc private func cancelPressed() { onCancel?() }
}

/// Runs a pairing: single-use 120 s QR codes, the phone's pairing service found by its random name over
/// mDNS, `adb pair`, then the phone's adb TLS key is read and pinned with its serial (spec 7.2).
@MainActor
final class PairingController {
    private let session: SessionController
    private let phone: PhoneWindowController
    private let view = PairingView()
    private var task: Task<Void, Never>?

    init(session: SessionController, phone: PhoneWindowController) {
        self.session = session
        self.phone = phone
        view.onCancel = { [weak self] in self?.stop() }
        view.onCodeEntry = { [weak self] in self?.codeEntry() }
    }

    func start() {
        stop()
        phone.content.screen.showOverlay(view)
        task = Task { await runQR() }
    }

    func stop() {
        task?.cancel()
        task = nil
        phone.content.screen.showOverlay(nil)
    }

    private static var now: UInt64 { UInt64(Date().timeIntervalSince1970) }

    /// New code every 120 s until the phone's pairing service with this code's name appears.
    private func runQR() async {
        while !Task.isCancelled {
            guard let code = try? PairingCode(now: Self.now) else { return fail() }
            let expires = Date().addingTimeInterval(120)
            view.show(payload: code.qrPayload, secondsLeft: 120)
            while !Task.isCancelled, Date() < expires {
                view.update(secondsLeft: max(0, Int(expires.timeIntervalSinceNow.rounded())))
                let services = await Bonjour.browse(type: Bonjour.pairingType, for: .seconds(2))
                guard let service = services.first(where: { $0.name == code.serviceName }) else { continue }
                guard let endpoint = await Bonjour.resolve(service), WirelessProbe.check(ip: endpoint.ip, port: endpoint.port) == nil,
                      (try? code.consume(now: Self.now)) != nil else { return fail() }
                return await finish(ip: endpoint.ip, port: endpoint.port, secret: code.password)
            }
        }
    }

    /// 6-digit fallback ("Pair device with pairing code").
    private func codeEntry() {
        task?.cancel()
        let fields = EndpointPrompt.Fields(code: true)
        guard EndpointPrompt.run(title: "Pair with code", info: "Enter the IP address, port and 6-digit code shown on your phone.",
                                 fields: fields),
              let endpoint = fields.endpoint, let secret = fields.code else { return start() }
        task = Task { await finish(ip: endpoint.ip, port: endpoint.port, secret: secret) }
    }

    private func finish(ip: String, port: UInt16, secret: String) async {
        guard let guid = await session.pair(ip: ip, port: port, secret: secret) else { return fail() }
        let serialPart = guid.dropFirst(4)
        guard let dash = serialPart.lastIndex(of: "-") else { return fail() }
        let serial = String(serialPart[..<dash])
        var connect: Device.Endpoint?
        for _ in 0..<5 where connect == nil {
            let found = await Bonjour.browse(type: Bonjour.connectType, for: .seconds(2)).first { $0.name == guid }
            // Only the address that just completed the password-authenticated pairing: an mDNS answer
            // pointing elsewhere is ignored (the key captured below becomes the pin for this phone).
            if let found, let address = await Bonjour.resolve(found), address.ip == ip {
                connect = Device.Endpoint(ip: address.ip, port: address.port)
            }
        }
        if connect == nil {
            let fields = EndpointPrompt.Fields(code: false, ip: ip)
            if EndpointPrompt.run(title: "Connect", info: "Enter the IP address and port shown under Wireless debugging.", fields: fields) {
                connect = fields.endpoint
            }
        }
        guard let connect, case let .wirelessDebugging(keyHash) = await session.probeKey(ip: connect.ip, port: connect.port) else { return fail() }
        let device = Device(serial: serial, model: "", androidVersion: "", connection: .wireless,
                            pins: Device.Pins(adbKeySHA256: CoreCrypto.hex(keyHash), serial: serial))
        stop()
        session.paired(device, endpoint: connect)
    }

    private func fail() {
        stop()
        phone.show(state: .untrustedDevice)
    }
}

/// Monochrome sheet for an IP address + port (and optionally a 6-digit code) typed from the phone's screen.
@MainActor
enum EndpointPrompt {
    @MainActor
    final class Fields {
        let ip = NSTextField()
        let port = NSTextField()
        let codeField: NSTextField?

        init(code: Bool, ip suggested: String = "") {
            codeField = code ? NSTextField() : nil
            ip.stringValue = suggested
            ip.placeholderString = "192.168.1.20"
            port.placeholderString = "Port"
            codeField?.placeholderString = "6-digit code"
        }

        var all: [NSTextField] { [ip, port] + (codeField.map { [$0] } ?? []) }

        /// Only a private-range address and a valid port (spec 6.2); otherwise nil.
        var endpoint: Device.Endpoint? {
            guard let p = UInt16(port.stringValue.trimmingCharacters(in: .whitespaces)) else { return nil }
            let address = ip.stringValue.trimmingCharacters(in: .whitespaces)
            return WirelessProbe.check(ip: address, port: p) == nil ? Device.Endpoint(ip: address, port: p) : nil
        }

        /// Exactly six ASCII digits.
        var code: String? {
            guard let text = codeField?.stringValue, text.utf8.count == 6, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return text
        }
    }

    static func run(title: String, info: String, fields: Fields) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let stack = NSStackView(views: fields.all)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 220, height: CGFloat(fields.all.count) * 28 - 4)
        for field in stack.arrangedSubviews { field.widthAnchor.constraint(equalToConstant: 220).isActive = true }
        alert.accessoryView = stack
        alert.window.initialFirstResponder = fields.ip.stringValue.isEmpty ? fields.ip : fields.port
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Wireless discovery fallback for the session controller.
    static func ask(suggestedIP: String) -> Device.Endpoint? {
        let fields = Fields(code: false, ip: suggestedIP)
        guard run(title: "Connect to your phone", info: "Enter the IP address and port shown under Wireless debugging on your phone.",
                  fields: fields) else { return nil }
        return fields.endpoint
    }
}
#endif
