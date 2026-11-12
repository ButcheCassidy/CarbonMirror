// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CMCore
import CMCoreBridge

/// Auto-connect to the pinned phone (owner addition to 6.3). At launch, and whenever the conditions allow, it
/// browses mDNS for the pinned serial's Wireless debugging service, accepts only a private address inside the
/// Mac's current, already known Wi-Fi subnet (no port scan, no public IP), has the controller verify the phone's
/// pinned adb TLS key and open the adb link, then locks that endpoint and waits for one "Mirror" press. The
/// session itself runs the full inner-TLS handshake with the device-key proof. Never runs while the Mac is locked
/// or asleep; an identity failure halts it until the user retries.
public struct AutoConnect: Equatable, Sendable {
    public struct Conditions: Equatable, Sendable {
        public var enabled: Bool
        /// The phone's adb TLS key is pinned and a device key from a USB session exists (proof possible).
        public var paired: Bool
        public var macLocked: Bool
        public var macAsleep: Bool
        /// The Mac's Wi-Fi subnet (`a.b.c.d/n`); nil when Wi-Fi is down.
        public var subnet: String?
        /// The phone was seen on this subnet before (its key is in the pinned device's endpoints).
        public var knownNetwork: Bool
        /// A USB or user-started session is running.
        public var busy: Bool

        public init(enabled: Bool, paired: Bool, macLocked: Bool, macAsleep: Bool, subnet: String?, knownNetwork: Bool, busy: Bool) {
            self.enabled = enabled
            self.paired = paired
            self.macLocked = macLocked
            self.macAsleep = macAsleep
            self.subnet = subnet
            self.knownNetwork = knownNetwork
            self.busy = busy
        }

        var eligible: Bool {
            enabled && paired && !macLocked && !macAsleep && subnet != nil && knownNetwork && !busy
        }
    }

    public enum Phase: Equatable, Sendable {
        case off, waiting, searching, verifying(Device.Endpoint), ready(Device.Endpoint), mirroring(Device.Endpoint), halted
    }

    /// What the controller does next.
    public enum Step: Equatable, Sendable {
        case none
        /// Browse mDNS once for the pinned serial and report with ``found(_:)``.
        case browse
        /// Call ``retry()`` after this many seconds.
        case wait(seconds: Double)
        /// Probe, check the pinned adb key, `adb connect`; report with ``verified(_:)``.
        case verify(Device.Endpoint)
        /// Start the wireless session on this endpoint.
        case mirror(Device.Endpoint)
        /// Disconnect the idle adb link to this endpoint.
        case drop(Device.Endpoint)
    }

    public enum Verification: Equatable, Sendable {
        case linked
        /// Not reachable or no adb answer: search again later.
        case unreachable
        /// Wrong key, plaintext adb, tunnel route or failed device proof: stop until the user retries.
        case refused
    }

    /// Seconds between searches: 5, 10, 20, then every 30.
    public static let searchDelays: [Double] = [5, 10, 20, 30]

    public private(set) var phase: Phase = .off
    /// The verified endpoint; only this one is used until it fails or the network changes.
    public private(set) var locked: Device.Endpoint?
    private var subnet: String?
    private var misses = 0

    public init() {}

    /// A private address (allowlist) inside `subnet`; never a public address, tunnel range or port 5555.
    public static func accept(_ endpoint: Device.Endpoint, subnet: String) -> Bool {
        guard (try? NetPolicy.checkEndpoint(ip: endpoint.ip, port: UInt32(endpoint.port))) != nil,
              let prefix = subnet.split(separator: "/").last.flatMap({ Int($0) }) else { return false }
        return NetworkIdentity.subnet(ip: endpoint.ip, prefix: prefix) == subnet
    }

    private var linkedEndpoint: Device.Endpoint? {
        switch phase {
        case let .verifying(e), let .ready(e): e
        default: nil
        }
    }

    /// Re-evaluates after any change of settings, lock, sleep, network, pairing or session.
    public mutating func update(_ c: Conditions) -> Step {
        if c.subnet != subnet {
            // A new network: forget the lock and start over (a running session is ended by the controller's network guard).
            subnet = c.subnet
            locked = nil
            if case .mirroring = phase {} else if phase != .off { phase = .waiting }
        }
        let linked = linkedEndpoint
        guard c.eligible else {
            if case .mirroring = phase, c.enabled, c.busy, !c.macLocked, !c.macAsleep { return .none }
            phase = c.enabled ? (phase == .halted ? .halted : .waiting) : .off
            if !c.enabled { locked = nil }
            return linked.map(Step.drop) ?? .none
        }
        switch phase {
        case .off, .waiting:
            phase = .searching
            misses = 0
            return .browse
        case let .mirroring(e):
            // The session ended (busy cleared): check the locked link again, or search on a new network.
            guard locked == e else {
                phase = .searching
                misses = 0
                return .browse
            }
            phase = .verifying(e)
            return .verify(e)
        case .searching, .verifying, .ready, .halted:
            return .none
        }
    }

    /// mDNS answers for the pinned serial.
    public mutating func found(_ candidates: [Device.Endpoint]) -> Step {
        guard phase == .searching, let subnet else { return .none }
        let usable = candidates.filter { Self.accept($0, subnet: subnet) }
        guard let pick = usable.first(where: { $0 == locked }) ?? usable.first else { return miss() }
        phase = .verifying(pick)
        return .verify(pick)
    }

    /// Result of the controller's checks for the endpoint being verified.
    public mutating func verified(_ result: Verification, for endpoint: Device.Endpoint) -> Step {
        guard case let .verifying(e) = phase, e == endpoint else { return .none }
        switch result {
        case .linked:
            phase = .ready(e)
            locked = e
            misses = 0
            return .none
        case .unreachable:
            locked = nil
            phase = .searching
            return miss()
        case .refused:
            locked = nil
            phase = .halted
            return .none
        }
    }

    /// The "Mirror" button.
    public mutating func openMirror() -> Step {
        guard case let .ready(e) = phase else { return .none }
        phase = .mirroring(e)
        return .mirror(e)
    }

    /// The idle link went away (device left adb's list).
    public mutating func linkLost() -> Step {
        guard case let .ready(e) = phase else { return .none }
        phase = .verifying(e)
        return .verify(e)
    }

    /// The wait from ``Step/wait(seconds:)`` is over.
    public mutating func retry() -> Step {
        phase == .searching ? .browse : .none
    }

    /// The user pressed Retry or Connect: a refusal no longer blocks the next ``update(_:)``.
    public mutating func resume() {
        if phase == .halted { phase = .waiting }
    }

    private mutating func miss() -> Step {
        let delay = Self.searchDelays[min(misses, Self.searchDelays.count - 1)]
        misses += 1
        return .wait(seconds: delay)
    }
}
