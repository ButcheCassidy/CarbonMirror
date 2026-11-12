import CMCore
import CMCoreBridge
import Foundation
import Testing

@Suite("Hover chrome layout and settings")
struct UILayoutTests {
    /// Window widths from 0.75× real size to the largest landscape window, in 1 pt steps.
    static let widths: [Double] = {
        let real = try? SizeMath.realSize(phonePixels: CoreSize(width: 1344, height: 2992), phonePPI: 486, macPointsPerInch: 127)
        let minimum = (real?.width ?? 351) * SizeMath.minScale + 2 * ChromeGeometry.margin
        let maximum = (real?.height ?? 782) * SizeMath.maxScale + 2 * ChromeGeometry.margin
        return Array(stride(from: minimum.rounded(.down), through: maximum.rounded(.up), by: 1))
    }()

    @Test func toolbarNeverOverlapsOrOverflowsAtAnyWidth() {
        for width in Self.widths {
            let result = ChromeLayout.layout(width: width)
            let limit = width - ChromeLayout.trailingInset
            var previousEnd = ChromeLayout.trafficLightX(2) + ChromeLayout.trafficLightSize
            for placement in result.visible {
                #expect(placement.x >= previousEnd, "overlap at width \(width): \(placement.item)")
                #expect(placement.x + placement.width <= limit, "clipped at width \(width): \(placement.item)")
                previousEnd = placement.x + placement.width
            }
            if let x = result.overflowX {
                #expect(x >= previousEnd)
                #expect(x + ChromeLayout.buttonSize <= limit, "overflow button clipped at width \(width)")
                #expect(!result.overflow.isEmpty)
            } else {
                #expect(result.overflow.isEmpty)
            }
            #expect(result.visible.map(\.item) + result.overflow == ToolbarItem.allCases, "spec order kept at width \(width)")
        }
    }

    @Test func overflowAppearsOnlyWhenNeeded() {
        let total = ToolbarItem.allCases.reduce(0) { $0 + $1.width } + ChromeLayout.spacing * Double(ToolbarItem.allCases.count - 1)
        let fits = ChromeLayout.trafficLightsWidth + total + ChromeLayout.trailingInset
        #expect(ChromeLayout.layout(width: fits).overflowX == nil)
        #expect(ChromeLayout.layout(width: fits - 1).overflowX != nil)
        let smallest = ChromeLayout.layout(width: Self.widths[0])
        #expect(smallest.visible.first?.item == .back, "Back stays visible at 0.75×")
        #expect(smallest.visible.count >= 6, "core navigation buttons stay visible at 0.75×")
    }

    @Test func screenNeverMovesWhileChromeAnimates() {
        let screen = (w: 351.0, h: 782.0)
        for step in 0...20 {
            let i = ChromeGeometry.insets(progress: Double(step) / 20)
            let origin = ChromeGeometry.screenOrigin(frameWidth: screen.w + i.left + i.right, frameHeight: screen.h + i.top + i.bottom,
                                                     screenWidth: screen.w, screenHeight: screen.h)
            #expect(abs(origin.x - i.left) < 1e-9)
            #expect(abs(origin.y - i.bottom) < 1e-9)
        }
        #expect(ChromeGeometry.top == 58)
    }

    @Test func revealZoneIsTopTwentyEightPoints() {
        #expect(ChromeGeometry.inRevealZone(yFromTop: 0, chromeShown: false))
        #expect(ChromeGeometry.inRevealZone(yFromTop: 28, chromeShown: false))
        #expect(!ChromeGeometry.inRevealZone(yFromTop: 29, chromeShown: false))
        #expect(ChromeGeometry.inRevealZone(yFromTop: 80, chromeShown: true))
        #expect(!ChromeGeometry.inRevealZone(yFromTop: -1, chromeShown: true))
    }

    @MainActor @Test func settingsDefaultsMatchSpec() throws {
        let suite = "cm-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let s = AppSettings(defaults: defaults)
        #expect(s.connectionMode == .auto)
        #expect(s.usbProfile == .init(maxFPS: 120, bitrateMbps: 32, codec: .h264))
        #expect(s.wirelessProfile == .init(maxFPS: 60, bitrateMbps: 12, codec: .h265))
        #expect(s.clipboardSync && s.hideFromCapture && s.statusLine && s.landscapeOffer && s.rememberSize)
        #expect(!s.encryptOverUSB && s.autoConnect)
        #expect(!s.touchIDToReveal && !s.phoneScreenOff && !s.pinOnTop)
        #expect(s.autoBlurSeconds == 0)
        #expect(s.idleTimeoutMinutes == 10)
        #expect(s.rotationReminderDays == 180)
        #expect(s.typingMode == .hardware)
        #expect(s.landscapeBehaviour == .ask)
    }

    @MainActor @Test func settingsClampAndNotify() throws {
        let suite = "cm-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let s = AppSettings(defaults: defaults)
        var changed: [AppSettings.Key] = []
        s.observe { changed.append($0) }
        s.cornerFineTune = 0.9
        #expect(s.cornerFineTune == 0.15)
        s.autoBlurSeconds = 7
        #expect(s.autoBlurSeconds == 0)
        s.idleTimeoutMinutes = 0
        #expect(s.idleTimeoutMinutes == 1)
        defaults.set(999, forKey: AppSettings.Key.usbFPS.rawValue)
        #expect(s.usbProfile.maxFPS == 120, "out-of-range stored value falls back to the default")
        s.clipboardSync = false
        #expect(!AppSettings(defaults: defaults).clipboardSync, "persisted")
        #expect(changed == [.cornerFineTune, .autoBlurSeconds, .idleTimeoutMinutes, .clipboardSync])
    }

    @MainActor @Test func rotationReminder() throws {
        let suite = "cm-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let s = AppSettings(defaults: defaults)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        #expect(!s.rotationReminderDue(now: now))
        s.lastKeyRotation = now.addingTimeInterval(-181 * 86_400)
        #expect(s.rotationReminderDue(now: now))
        s.rotationReminderDays = 0
        #expect(!s.rotationReminderDue(now: now))
    }
}
