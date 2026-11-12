import CMCoreBridge

/// What a status state looks like inside the phone-shaped window: centred glyph, bold title,
/// one-line subtitle and grey pill buttons (spec 2.4). Text lives here so it is testable on Linux.
public struct StatusContent: Equatable, Sendable {
    /// Button identities; the UI wires each to its action.
    public enum Action: String, Sendable, CaseIterable {
        case openSettings, useUSB, pair, howWirelessDebugging, howLANSharing, reconnect, retry, createNewKey, howInsecure, mirror, connect, howReinstall
    }

    public struct Button: Equatable, Sendable {
        public let title: String
        public let action: Action
    }

    /// Monochrome SF Symbol name.
    public let glyph: String
    public let title: String
    public let subtitle: String
    public let buttons: [Button]
    /// Shows the monochrome spinner instead of a still glyph.
    public let showsSpinner: Bool

    /// Content for a state; nil while mirroring or silently retrying (no overlay shown).
    public static func forState(_ state: UIStateCode) -> StatusContent? {
        switch state {
        case .mirroring, .retryingSilently:
            nil
        case .wifiOff:
            StatusContent(glyph: "wifi.slash", title: "Wi-Fi Off", subtitle: "Turn on Mac Wi-Fi to connect.",
                          buttons: [Button(title: "Settings", action: .openSettings)], showsSpinner: false)
        case .searching:
            StatusContent(glyph: "iphone.radiowaves.left.and.right", title: "Searching", subtitle: "Looking for your Pixel…",
                          buttons: [Button(title: "Use USB instead", action: .useUSB)], showsSpinner: true)
        case .notPaired:
            StatusContent(glyph: "qrcode", title: "Not paired", subtitle: "Pair your phone to get started.",
                          buttons: [Button(title: "Pair", action: .pair)], showsSpinner: false)
        case .wirelessDebuggingOff:
            StatusContent(glyph: "antenna.radiowaves.left.and.right.slash", title: "Wireless debugging off",
                          subtitle: "Turn on Wireless debugging on your phone.",
                          buttons: [Button(title: "How?", action: .howWirelessDebugging)], showsSpinner: false)
        case .lanSharingBlocked:
            StatusContent(glyph: "network.slash", title: "LAN sharing blocked",
                          subtitle: "Allow local network sharing in Mullvad on both devices.",
                          buttons: [Button(title: "How?", action: .howLANSharing)], showsSpinner: false)
        case .disconnected:
            StatusContent(glyph: "bolt.horizontal", title: "Disconnected", subtitle: "Connection lost.",
                          buttons: [Button(title: "Reconnect", action: .reconnect)], showsSpinner: false)
        case .untrustedDevice:
            StatusContent(glyph: "exclamationmark.shield", title: "Untrusted device",
                          subtitle: "This device isn't paired with CarbonMirror.",
                          buttons: [Button(title: "Pair", action: .pair)], showsSpinner: false)
        case .authenticationFailed:
            StatusContent(glyph: "lock.slash", title: "Authentication failed",
                          subtitle: "Your phone couldn't verify this Mac's key.",
                          buttons: [Button(title: "Retry", action: .retry), Button(title: "Create new key", action: .createNewKey)],
                          showsSpinner: false)
        case .identityChanged:
            StatusContent(glyph: "exclamationmark.triangle", title: "This phone's identity changed",
                          subtitle: "Someone may be intercepting the connection.",
                          buttons: [Button(title: "Retry", action: .retry), Button(title: "Create new key", action: .createNewKey)],
                          showsSpinner: false)
        case .phoneReady:
            StatusContent(glyph: "lock.iphone", title: "Ready", subtitle: "Encrypted link to your Pixel is open.",
                          buttons: [Button(title: "Mirror", action: .mirror)], showsSpinner: false)
        case .notConnected:
            StatusContent(glyph: "iphone.slash", title: "Not connected", subtitle: "Plug in USB or connect over Wi-Fi.",
                          buttons: [Button(title: "Connect", action: .connect)], showsSpinner: false)
        case .launchCheckFailed:
            StatusContent(glyph: "xmark.seal", title: "Can't start safely", subtitle: "The bundled adb is missing or its signature is wrong.",
                          buttons: [Button(title: "How?", action: .howReinstall)], showsSpinner: false)
        case .insecureConnectionRefused:
            StatusContent(glyph: "lock.trianglebadge.exclamationmark", title: "Insecure connection refused",
                          subtitle: "Use Wireless debugging, not adb tcpip.",
                          buttons: [Button(title: "How?", action: .howInsecure)], showsSpinner: false)
        }
    }
}
