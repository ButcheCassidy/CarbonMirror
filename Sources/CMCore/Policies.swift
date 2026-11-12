// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import Foundation

/// Silent auto-reconnect (spec 8.2.2): 0.5, 1, 2, 4, 8 s, then every 30 s; stop after 10 minutes.
/// Only the pinned device, never while the Mac is locked or asleep.
public enum ReconnectSchedule {
    public static let steps: [TimeInterval] = [0.5, 1, 2, 4, 8]
    public static let steadyInterval: TimeInterval = 30
    public static let giveUpAfter: TimeInterval = 600

    /// Delay before attempt `attempt` (0-based), or nil when `elapsed` has reached the 10-minute limit.
    public static func delay(attempt: Int, elapsed: TimeInterval) -> TimeInterval? {
        guard attempt >= 0, elapsed < giveUpAfter else { return nil }
        let d = attempt < steps.count ? steps[attempt] : steadyInterval
        return elapsed + d <= giveUpAfter ? d : nil
    }

    /// Whether a reconnect may run now.
    public static func allowed(macLocked: Bool, macAsleep: Bool, targetIsPinned: Bool) -> Bool {
        !macLocked && !macAsleep && targetIsPinned
    }
}

/// Connection quality word for the status line (spec 8.2.5), from fixed thresholds:
/// Excellent — ≥ 95 % of the target frame rate and ≤ 20 ms round trip;
/// Good — ≥ 80 % and ≤ 50 ms; Fair — ≥ 50 % and ≤ 120 ms; Poor — anything worse.
public enum ConnectionQuality: String, CaseIterable, Sendable {
    case excellent = "Excellent", good = "Good", fair = "Fair", poor = "Poor"

    /// Frame rate is judged only when the screen is changing (Android sends no frames for a still screen).
    public static func classify(fps: Double?, targetFPS: Double, latencyMs: Double?) -> ConnectionQuality {
        let ratio = fps.map { targetFPS > 0 ? $0 / targetFPS : 1 } ?? 1
        let rtt = latencyMs ?? 0
        if ratio >= 0.95 && rtt <= 20 { return .excellent }
        if ratio >= 0.80 && rtt <= 50 { return .good }
        if ratio >= 0.50 && rtt <= 120 { return .fair }
        return .poor
    }
}

/// Text of the status line (spec 8.2.5), e.g. `84 % · Charging   ·   USB · 120 fps · 9 ms · Excellent`.
public enum StatusLine {
    public enum Transport: Sendable { case usb, wifi }

    public struct Snapshot: Equatable, Sendable {
        public var batteryLevel: Int?
        public var charging: Bool
        public var transport: Transport?
        public var fps: Double?
        public var latencyMs: Double?
        public var quality: ConnectionQuality?
        public var reconnecting: Bool

        public init(batteryLevel: Int? = nil, charging: Bool = false, transport: Transport? = nil, fps: Double? = nil,
                    latencyMs: Double? = nil, quality: ConnectionQuality? = nil, reconnecting: Bool = false) {
            self.batteryLevel = batteryLevel
            self.charging = charging
            self.transport = transport
            self.fps = fps
            self.latencyMs = latencyMs
            self.quality = quality
            self.reconnecting = reconnecting
        }
    }

    public static func text(_ s: Snapshot) -> String {
        var left: [String] = []
        if let level = s.batteryLevel {
            left.append("\(level) %")
            if s.charging { left.append("Charging") }
        }
        var right: [String] = []
        if s.reconnecting {
            right.append("Reconnecting…")
        } else if let transport = s.transport {
            right.append(transport == .usb ? "USB" : "Wi-Fi")
            if let fps = s.fps { right.append("\(Int(fps.rounded())) fps") }
            if let ms = s.latencyMs { right.append("\(Int(ms.rounded())) ms") }
            if let q = s.quality { right.append(q.rawValue) }
        }
        let parts = [left.joined(separator: " · "), right.joined(separator: " · ")].filter { !$0.isEmpty }
        return parts.joined(separator: "   ·   ")
    }

    /// Monochrome SF Symbol for the battery glyph at the start of the line.
    public static func batterySymbol(level: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// Landscape behaviour (spec 8.2.6).
public enum LandscapeDecision: Equatable, Sendable {
    case keep
    case offer
    case rotateToLandscape
    case returnToPortrait

    public static func decide(offerEnabled: Bool, behaviour: AppSettings.LandscapeBehaviour, phoneLandscape: Bool, windowLandscape: Bool) -> LandscapeDecision {
        if !phoneLandscape { return windowLandscape ? .returnToPortrait : .keep }
        if windowLandscape || !offerEnabled { return .keep }
        switch behaviour {
        case .stayPortrait: return .keep
        case .alwaysRotate: return .rotateToLandscape
        case .ask: return .offer
        }
    }
}

/// Privacy blur (spec 8.2.4): manual toggle, optional auto-blur after N seconds without focus, always on
/// screensaver/display sleep. While blurred, input to the phone is blocked.
public struct PrivacyBlurState: Equatable, Sendable {
    public private(set) var blurred = false

    public init() {}

    public mutating func toggle() { blurred.toggle() }
    public mutating func reveal() { blurred = false }

    /// Applies auto-blur rules; returns true when the state changed.
    public mutating func update(autoBlurSeconds: Int, unfocusedFor seconds: TimeInterval, screensaverOrDisplaySleep: Bool) -> Bool {
        let should = screensaverOrDisplaySleep || (autoBlurSeconds > 0 && seconds >= TimeInterval(autoBlurSeconds))
        guard should, !blurred else { return false }
        blurred = true
        return true
    }
}

/// When a session must end and its keys be wiped (spec 7.6).
public enum SessionGuard {
    public enum Event: Sendable { case macLocked, macSleep, lidClosed, userSwitched, unknownNetwork, idle(seconds: TimeInterval) }

    public static func mustEnd(_ event: Event, idleTimeoutMinutes: Int) -> Bool {
        switch event {
        case .macLocked, .macSleep, .lidClosed, .userSwitched, .unknownNetwork: true
        case let .idle(seconds): seconds >= TimeInterval(idleTimeoutMinutes * 60)
        }
    }
}

/// Which transport to use (spec 6.3): Auto prefers USB, falls back to a reachable paired wireless endpoint.
public enum TransportChoice: Equatable, Sendable {
    case usb, wireless, none

    public static func choose(mode: AppSettings.ConnectionMode, usbAvailable: Bool, wirelessReachable: Bool) -> TransportChoice {
        switch mode {
        case .usbOnly: usbAvailable ? .usb : .none
        case .wirelessOnly: wirelessReachable ? .wireless : .none
        case .auto: usbAvailable ? .usb : wirelessReachable ? .wireless : .none
        }
    }
}

/// Adaptive USB fallback (spec 4.5): if fewer than 110 fps arrive over 3 s, step the size down before the fps.
public enum AdaptiveProfile {
    public static let sizeSteps = [2992, 2560, 2240, 1920]
    public static let fpsSteps = [120, 90, 60]
    public static let threshold = 110.0
    public static let window: TimeInterval = 3

    /// Next (maxSize, maxFPS) after a slow window, or nil when already at the floor.
    public static func next(maxSize: Int, maxFPS: Int) -> (maxSize: Int, maxFPS: Int)? {
        if let i = sizeSteps.firstIndex(of: maxSize), i + 1 < sizeSteps.count { return (sizeSteps[i + 1], maxFPS) }
        if let i = fpsSteps.firstIndex(of: maxFPS), i + 1 < fpsSteps.count { return (maxSize, fpsSteps[i + 1]) }
        return nil
    }
}
