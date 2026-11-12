import CMCore
import CMTransport
import Testing

@Suite("auto-connect")
struct AutoConnectTests {
    static let home = Device.Endpoint(ip: "192.168.1.20", port: 37_099)

    static func ready(_ change: (inout AutoConnect.Conditions) -> Void = { _ in }) -> AutoConnect.Conditions {
        var c = AutoConnect.Conditions(enabled: true, paired: true, macLocked: false, macAsleep: false,
                                       subnet: "192.168.1.0/24", knownNetwork: true, busy: false)
        change(&c)
        return c
    }

    /// Runs launch → mDNS → verify → ready on the home endpoint.
    static func linked() -> AutoConnect {
        var a = AutoConnect()
        _ = a.update(ready())
        _ = a.found([home])
        _ = a.verified(.linked, for: home)
        return a
    }

    @Test func launchSearchesVerifiesLocksAndMirrorsOnOnePress() {
        var a = AutoConnect()
        #expect(a.update(Self.ready()) == .browse)
        #expect(a.found([Self.home]) == .verify(Self.home))
        #expect(a.verified(.linked, for: Self.home) == .none)
        #expect(a.phase == .ready(Self.home) && a.locked == Self.home)
        #expect(a.openMirror() == .mirror(Self.home))
        #expect(a.openMirror() == .none, "one press, one session")
    }

    @Test func neverRunsWhileLockedAsleepOffUnpairedOrOnUnknownNetwork() {
        let blocked: [(inout AutoConnect.Conditions) -> Void] = [
            { $0.macLocked = true }, { $0.macAsleep = true }, { $0.enabled = false }, { $0.paired = false },
            { $0.subnet = nil }, { $0.knownNetwork = false }, { $0.busy = true },
        ]
        for change in blocked {
            var a = AutoConnect()
            #expect(a.update(Self.ready(change)) == .none)
            #expect(a.found([Self.home]) == .none)
            #expect(a.phase != .searching)
        }
    }

    @Test func lockOrSleepDropsTheIdleLinkAndResumesAfterUnlock() {
        var a = Self.linked()
        #expect(a.update(Self.ready { $0.macLocked = true }) == .drop(Self.home))
        #expect(a.phase == .waiting)
        #expect(a.openMirror() == .none)
        #expect(a.update(Self.ready()) == .browse)
    }

    @Test func refusesPublicTunnelLegacyAndOtherSubnetAddresses() {
        let bad = [Device.Endpoint(ip: "8.8.8.8", port: 37_099), Device.Endpoint(ip: "10.64.0.2", port: 37_099),
                   Device.Endpoint(ip: "192.168.1.20", port: 5555), Device.Endpoint(ip: "192.168.2.20", port: 37_099),
                   Device.Endpoint(ip: "fe80::1", port: 37_099), Device.Endpoint(ip: "pixel.local", port: 37_099)]
        for endpoint in bad { #expect(!AutoConnect.accept(endpoint, subnet: "192.168.1.0/24"), "\(endpoint)") }
        #expect(AutoConnect.accept(Self.home, subnet: "192.168.1.0/24"))
        var a = AutoConnect()
        _ = a.update(Self.ready())
        #expect(a.found(bad) == .wait(seconds: 5), "no usable answer: wait, never scan")
    }

    @Test func searchBacksOffWithoutScanning() {
        var a = AutoConnect()
        _ = a.update(Self.ready())
        var delays: [Double] = []
        for _ in 0..<6 {
            guard case let .wait(seconds) = a.found([]) else { Issue.record("expected wait"); return }
            delays.append(seconds)
            #expect(a.retry() == .browse)
        }
        #expect(delays == [5, 10, 20, 30, 30, 30])
    }

    @Test func lockedEndpointWinsOverOtherAnswers() {
        var a = Self.linked()
        #expect(a.linkLost() == .verify(Self.home))
        #expect(a.verified(.unreachable, for: Self.home) == .wait(seconds: 5))
        #expect(a.locked == nil, "a failed lock is released")
        var b = Self.linked()
        #expect(b.update(Self.ready { $0.busy = true }) == .drop(Self.home), "a USB session takes over")
        #expect(b.update(Self.ready()) == .browse)
        let other = Device.Endpoint(ip: "192.168.1.21", port: 40_001)
        #expect(b.found([other, Self.home]) == .verify(Self.home), "the locked endpoint is preferred")
    }

    @Test func identityFailureHaltsUntilTheUserRetries() {
        var a = AutoConnect()
        _ = a.update(Self.ready())
        _ = a.found([Self.home])
        #expect(a.verified(.refused, for: Self.home) == .none)
        #expect(a.phase == .halted)
        #expect(a.update(Self.ready()) == .none)
        #expect(a.retry() == .none)
        #expect(a.reset(Self.ready()) == .browse)
    }

    @Test func staleVerificationIsIgnored() {
        var a = AutoConnect()
        _ = a.update(Self.ready())
        _ = a.found([Self.home])
        _ = a.update(Self.ready { $0.subnet = "10.0.0.0/24" })
        #expect(a.verified(.linked, for: Self.home) == .none)
        #expect(a.phase != .ready(Self.home))
    }

    @Test func sessionEndRechecksLockOrSearchesOnNewNetwork() {
        var a = Self.linked()
        _ = a.openMirror()
        #expect(a.update(Self.ready { $0.busy = true }) == .none)
        #expect(a.update(Self.ready()) == .verify(Self.home))
        var b = Self.linked()
        _ = b.openMirror()
        _ = b.update(Self.ready { $0.busy = true; $0.subnet = "10.0.0.0/24" })
        #expect(b.update(Self.ready { $0.subnet = "10.0.0.0/24" }) == .browse)
    }

    @Test func turningOffForgetsTheLock() {
        var a = Self.linked()
        #expect(a.update(Self.ready { $0.enabled = false }) == .drop(Self.home))
        #expect(a.phase == .off && a.locked == nil)
    }
}
