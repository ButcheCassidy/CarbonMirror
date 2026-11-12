// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CMCore
import CMMedia
import Foundation
import Testing

@Suite("Experience and session policies (8.2, 6.3, 7.6)")
struct PolicyTests {
    @Test func reconnectBackoffAndGiveUp() {
        let delays = (0..<8).map { ReconnectSchedule.delay(attempt: $0, elapsed: 0) }
        #expect(delays == [0.5, 1, 2, 4, 8, 30, 30, 30])
        #expect(ReconnectSchedule.delay(attempt: 9, elapsed: 600) == nil, "stops after 10 minutes")
        #expect(ReconnectSchedule.delay(attempt: 9, elapsed: 590) == nil, "never schedules past the limit")
        #expect(!ReconnectSchedule.allowed(macLocked: true, macAsleep: false, targetIsPinned: true))
        #expect(!ReconnectSchedule.allowed(macLocked: false, macAsleep: true, targetIsPinned: true))
        #expect(!ReconnectSchedule.allowed(macLocked: false, macAsleep: false, targetIsPinned: false), "pinned device only")
        #expect(ReconnectSchedule.allowed(macLocked: false, macAsleep: false, targetIsPinned: true))
    }

    @Test func qualityThresholds() {
        #expect(ConnectionQuality.classify(latencyMs: 6) == .excellent, "10 fps on a quiet adaptive screen is not a slow link")
        #expect(ConnectionQuality.classify(latencyMs: 30) == .good)
        #expect(ConnectionQuality.classify(latencyMs: 80) == .fair)
        #expect(ConnectionQuality.classify(latencyMs: 300) == .poor)
        #expect(ConnectionQuality.classify(latencyMs: nil) == .excellent)
    }

    @Test func statusLineFormatting() {
        let s = StatusLine.Snapshot(batteryLevel: 84, charging: true, transport: .usb, fps: 119.6, latencyMs: 9.2, quality: .excellent)
        #expect(StatusLine.text(s) == "84 % · Charging   ·   USB · 120 fps · 9 ms · Excellent")
        #expect(StatusLine.text(.init(batteryLevel: 50, transport: .wifi, reconnecting: true)) == "50 %   ·   Reconnecting…")
        #expect(StatusLine.text(.init()) == "")
        #expect(StatusLine.batterySymbol(level: 84, charging: false) == "battery.75percent")
        #expect(StatusLine.batterySymbol(level: 10, charging: true) == "battery.100percent.bolt")
    }

    @Test func landscapeSettings() {
        #expect(LandscapeDecision.decide(offerEnabled: true, behaviour: .ask, phoneLandscape: true, windowLandscape: false) == .offer)
        #expect(LandscapeDecision.decide(offerEnabled: true, behaviour: .alwaysRotate, phoneLandscape: true, windowLandscape: false) == .rotateToLandscape)
        #expect(LandscapeDecision.decide(offerEnabled: true, behaviour: .stayPortrait, phoneLandscape: true, windowLandscape: false) == .keep)
        #expect(LandscapeDecision.decide(offerEnabled: false, behaviour: .alwaysRotate, phoneLandscape: true, windowLandscape: false) == .keep)
        #expect(LandscapeDecision.decide(offerEnabled: true, behaviour: .ask, phoneLandscape: false, windowLandscape: true) == .returnToPortrait)
    }

    @Test func privacyBlurRules() {
        var b = PrivacyBlurState()
        let off = b.update(autoBlurSeconds: 0, unfocusedFor: 999, screensaverOrDisplaySleep: false)
        #expect(!off, "auto-blur off by default")
        let auto = b.update(autoBlurSeconds: 10, unfocusedFor: 10, screensaverOrDisplaySleep: false)
        #expect(auto)
        #expect(b.blurred)
        b.reveal()
        let saver = b.update(autoBlurSeconds: 0, unfocusedFor: 0, screensaverOrDisplaySleep: true)
        #expect(saver, "screensaver always blurs")
        b.toggle()
        #expect(!b.blurred)
    }

    @Test func sessionHygiene() {
        for e in [SessionGuard.Event.macLocked, .macSleep, .lidClosed, .userSwitched, .unknownNetwork] {
            #expect(SessionGuard.mustEnd(e, idleTimeoutMinutes: 10))
        }
        #expect(!SessionGuard.mustEnd(.idle(seconds: 599), idleTimeoutMinutes: 10))
        #expect(SessionGuard.mustEnd(.idle(seconds: 600), idleTimeoutMinutes: 10))
    }

    @Test func transportChoiceAndHandover() {
        #expect(TransportChoice.choose(mode: .auto, usbAvailable: true, wirelessReachable: true) == .usb, "plugging USB in hands over to USB")
        #expect(TransportChoice.choose(mode: .auto, usbAvailable: false, wirelessReachable: true) == .wireless, "unplugging falls back to Wi-Fi")
        #expect(TransportChoice.choose(mode: .auto, usbAvailable: false, wirelessReachable: false) == .none)
        #expect(TransportChoice.choose(mode: .usbOnly, usbAvailable: false, wirelessReachable: true) == .none)
        #expect(TransportChoice.choose(mode: .wirelessOnly, usbAvailable: true, wirelessReachable: true) == .wireless)
    }

    @Test func adaptiveFallbackStepsSizeBeforeFPS() {
        var profile: (maxSize: Int, maxFPS: Int)? = (2992, 120)
        var steps: [String] = []
        while let p = profile {
            steps.append("\(p.maxSize)@\(p.maxFPS)")
            profile = AdaptiveProfile.next(maxSize: p.maxSize, maxFPS: p.maxFPS)
        }
        #expect(steps == ["2992@120", "2560@120", "2240@120", "1920@120", "1920@90", "1920@60"])
    }

    @Test func screenshotFileName() {
        let date = Date(timeIntervalSince1970: 1_794_355_200)
        let utc = TimeZone(identifier: "UTC") ?? .current
        #expect(ScreenshotLocation.fileName(for: date, timeZone: utc) == "CarbonMirror-2026-11-11-000000.png")
    }
}

