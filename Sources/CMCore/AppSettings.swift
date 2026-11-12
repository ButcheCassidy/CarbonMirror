// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import Foundation

/// Every user setting (spec 8.3), persisted in the app's own (sandboxed) defaults. Changes are applied live:
/// observers registered with `observe` run on every change with the key that changed.
@MainActor
public final class AppSettings {
    public enum ConnectionMode: String, CaseIterable, Sendable { case auto, usbOnly, wirelessOnly }
    public enum Codec: String, CaseIterable, Sendable { case h264, h265 }
    public enum TypingMode: String, CaseIterable, Sendable { case hardware, phone }
    public enum LandscapeBehaviour: String, CaseIterable, Sendable { case ask, alwaysRotate, stayPortrait }

    /// Video profile for one transport.
    public struct Profile: Equatable, Sendable {
        public var maxFPS: Int
        public var bitrateMbps: Int
        public var codec: Codec

        public init(maxFPS: Int, bitrateMbps: Int, codec: Codec) {
            self.maxFPS = maxFPS
            self.bitrateMbps = bitrateMbps
            self.codec = codec
        }
    }

    public enum Key: String, CaseIterable, Sendable {
        case connectionMode, autoConnect, usbFPS, usbBitrate, usbCodec, wifiFPS, wifiBitrate, wifiCodec
        case cornerFineTune, rememberSize
        case autoBlurSeconds, touchIDToReveal, typingMode, landscapeOffer, landscapeBehaviour, powerSavingWhenHidden
        case statusLine, pinAcrossSpaces, pinOnTop, phoneScreenOff, rightClickBack
        case encryptOverUSB, idleTimeoutMinutes, hideFromCapture, clipboardSync, rotationReminderDays, lastKeyRotation
        case showDebugHUD, macPinResetPending, companionInstalled
    }

    /// Allowed values offered in Settings.
    public static let autoBlurChoices = [0, 5, 10, 30, 60]
    public static let usbFPSChoices = [60, 90, 120]
    public static let wifiFPSChoices = [30, 60, 90, 120]
    public static let idleTimeoutRange = 1...120
    public static let fineTuneRange = -0.15...0.15

    private let defaults: UserDefaults
    private var observers: [(Key) -> Void] = []

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Runs `body` after every change.
    public func observe(_ body: @escaping (Key) -> Void) {
        observers.append(body)
    }

    private func set<T: Sendable>(_ value: T?, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
        for observer in observers { observer(key) }
    }

    private func bool(_ key: Key, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key.rawValue) == nil ? fallback : defaults.bool(forKey: key.rawValue)
    }

    private func int(_ key: Key, _ fallback: Int, allowed: (Int) -> Bool) -> Int {
        guard defaults.object(forKey: key.rawValue) != nil else { return fallback }
        let value = defaults.integer(forKey: key.rawValue)
        return allowed(value) ? value : fallback
    }

    private func choice<T: RawRepresentable>(_ key: Key, _ fallback: T) -> T where T.RawValue == String {
        defaults.string(forKey: key.rawValue).flatMap { T(rawValue: $0) } ?? fallback
    }

    // MARK: Connection

    public var connectionMode: ConnectionMode {
        get { choice(.connectionMode, .auto) }
        set { set(newValue.rawValue, .connectionMode) }
    }

    /// At launch, find the pinned phone on a known Wi-Fi network and hold a verified link (owner addition to 6.3).
    public var autoConnect: Bool {
        get { bool(.autoConnect, true) }
        set { set(newValue, .autoConnect) }
    }

    /// USB "Performance" profile (spec 4.5): 120 fps, H.264, 32 Mbps.
    public var usbProfile: Profile {
        get {
            Profile(maxFPS: int(.usbFPS, 120) { Self.usbFPSChoices.contains($0) },
                    bitrateMbps: int(.usbBitrate, 32) { (4...64).contains($0) },
                    codec: choice(.usbCodec, .h264))
        }
        set {
            let old = usbProfile
            if newValue.maxFPS != old.maxFPS { set(newValue.maxFPS, .usbFPS) }
            if newValue.bitrateMbps != old.bitrateMbps { set(newValue.bitrateMbps, .usbBitrate) }
            if newValue.codec != old.codec { set(newValue.codec.rawValue, .usbCodec) }
        }
    }

    /// Wireless "Secure" profile (spec 6.1): 60 fps, H.265, 12 Mbps; 90/120 fps are "Experimental".
    public var wirelessProfile: Profile {
        get {
            Profile(maxFPS: int(.wifiFPS, 60) { Self.wifiFPSChoices.contains($0) },
                    bitrateMbps: int(.wifiBitrate, 12) { (2...40).contains($0) },
                    codec: choice(.wifiCodec, .h265))
        }
        set {
            let old = wirelessProfile
            if newValue.maxFPS != old.maxFPS { set(newValue.maxFPS, .wifiFPS) }
            if newValue.bitrateMbps != old.bitrateMbps { set(newValue.bitrateMbps, .wifiBitrate) }
            if newValue.codec != old.codec { set(newValue.codec.rawValue, .wifiCodec) }
        }
    }

    // MARK: Display

    /// Corner radius fine-tune, −0.15…+0.15.
    public var cornerFineTune: Double {
        get { min(Self.fineTuneRange.upperBound, max(Self.fineTuneRange.lowerBound, defaults.double(forKey: Key.cornerFineTune.rawValue))) }
        set { set(min(Self.fineTuneRange.upperBound, max(Self.fineTuneRange.lowerBound, newValue)), .cornerFineTune) }
    }

    public var rememberSize: Bool {
        get { bool(.rememberSize, true) }
        set { set(newValue, .rememberSize) }
    }

    // MARK: Experience

    /// Seconds without focus before auto-blur; 0 = off (default).
    public var autoBlurSeconds: Int {
        get { int(.autoBlurSeconds, 0) { Self.autoBlurChoices.contains($0) } }
        set { set(Self.autoBlurChoices.contains(newValue) ? newValue : 0, .autoBlurSeconds) }
    }

    public var touchIDToReveal: Bool {
        get { bool(.touchIDToReveal, false) }
        set { set(newValue, .touchIDToReveal) }
    }

    public var typingMode: TypingMode {
        get { choice(.typingMode, .hardware) }
        set { set(newValue.rawValue, .typingMode) }
    }

    public var landscapeOffer: Bool {
        get { bool(.landscapeOffer, true) }
        set { set(newValue, .landscapeOffer) }
    }

    public var landscapeBehaviour: LandscapeBehaviour {
        get { choice(.landscapeBehaviour, .ask) }
        set { set(newValue.rawValue, .landscapeBehaviour) }
    }

    /// Pause decoding after 5 s fully hidden (spec 8.2.1).
    public var powerSavingWhenHidden: Bool {
        get { bool(.powerSavingWhenHidden, true) }
        set { set(newValue, .powerSavingWhenHidden) }
    }

    public var statusLine: Bool {
        get { bool(.statusLine, true) }
        set { set(newValue, .statusLine) }
    }

    public var pinAcrossSpaces: Bool {
        get { bool(.pinAcrossSpaces, false) }
        set { set(newValue, .pinAcrossSpaces) }
    }

    public var pinOnTop: Bool {
        get { bool(.pinOnTop, false) }
        set { set(newValue, .pinOnTop) }
    }

    /// "Turn phone screen off while mirroring" (spec 5.1), off by default.
    public var phoneScreenOff: Bool {
        get { bool(.phoneScreenOff, false) }
        set { set(newValue, .phoneScreenOff) }
    }

    /// Right-click sends Back (spec 5.2).
    public var rightClickBack: Bool {
        get { bool(.rightClickBack, true) }
        set { set(newValue, .rightClickBack) }
    }

    public var showDebugHUD: Bool {
        get { bool(.showDebugHUD, false) }
        set { set(newValue, .showDebugHUD) }
    }

    // MARK: Security

    /// Inner TLS over USB too (spec 7.3): off by default; the cable is a physical link and adb USB needs the phone's approval.
    public var encryptOverUSB: Bool {
        get { bool(.encryptOverUSB, false) }
        set { set(newValue, .encryptOverUSB) }
    }

    public var idleTimeoutMinutes: Int {
        get { int(.idleTimeoutMinutes, 10) { Self.idleTimeoutRange.contains($0) } }
        set { set(min(Self.idleTimeoutRange.upperBound, max(Self.idleTimeoutRange.lowerBound, newValue)), .idleTimeoutMinutes) }
    }

    /// Window `sharingType = .none` (spec 7.6).
    public var hideFromCapture: Bool {
        get { bool(.hideFromCapture, true) }
        set { set(newValue, .hideFromCapture) }
    }

    public var clipboardSync: Bool {
        get { bool(.clipboardSync, true) }
        set { set(newValue, .clipboardSync) }
    }

    /// Days between "Create new key" reminders; 0 = off.
    public var rotationReminderDays: Int {
        get { int(.rotationReminderDays, 180) { (0...3650).contains($0) } }
        set { set(min(3650, max(0, newValue)), .rotationReminderDays) }
    }

    /// When the keys were last created (for the rotation reminder).
    public var lastKeyRotation: Date? {
        get { defaults.object(forKey: Key.lastKeyRotation.rawValue) as? Date }
        set { set(newValue, .lastKeyRotation) }
    }

    /// After "Create new key": the phone still pins the old Mac identity until the next session removes it.
    public var macPinResetPending: Bool {
        get { bool(.macPinResetPending, false) }
        set { set(newValue, .macPinResetPending) }
    }

    /// The companion APK was installed from this Mac (its permission is re-granted on every USB connect).
    public var companionInstalled: Bool {
        get { bool(.companionInstalled, false) }
        set { set(newValue, .companionInstalled) }
    }

    /// True when the rotation reminder is due at `now`.
    public func rotationReminderDue(now: Date) -> Bool {
        guard rotationReminderDays > 0, let last = lastKeyRotation else { return false }
        return now.timeIntervalSince(last) >= Double(rotationReminderDays) * 86_400
    }
}
