// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CMCore
import CMCoreBridge
import CMInput
@testable import CMTransport
import Foundation
import Testing

@Suite("Input mapping (Phase 5)")
struct InputTests {
    static func engine() -> InputEngine {
        let e = InputEngine()
        e.layout(viewWidth: 351, viewHeight: 782, frameWidth: 1344, frameHeight: 2992)
        return e
    }

    /// The touch messages in a recorded control stream (pings skipped; anything else is recorded as an issue).
    static func touches(in wire: [UInt8]) -> [UInt8] {
        guard let pingLength = try? ControlMessage.ping(0).count, let touchLength = try? touch(.down, 0, 0).count else { return [] }
        var filtered: [UInt8] = []
        var i = 0
        while i < wire.count {
            switch wire[i] {
            case 0x41: i += pingLength
            case 2:
                filtered += wire[i..<min(wire.count, i + touchLength)]
                i += touchLength
            default:
                Issue.record("unexpected control message type \(wire[i])")
                i = wire.count
            }
        }
        return filtered
    }

    static func touch(_ action: ControlMessage.TouchAction, _ x: Int32, _ y: Int32, pointer: Int64 = ControlMessage.fingerPointer) throws -> [UInt8] {
        try ControlMessage.touch(action, pointer: pointer, at: PhonePoint(x: x, y: y, frameWidth: 1344, frameHeight: 2992), pressure: action == .up ? 0 : 1)
    }

    @Test func clickIsATapAtTheRightPixel() throws {
        let e = Self.engine()
        #expect(e.pointer(.down(x: 175.5, y: 391)) == [try Self.touch(.down, 672, 1496)])
        #expect(e.pointer(.up(x: 175.5, y: 391)) == [try Self.touch(.up, 672, 1496)])
    }

    @Test func dragLeavingTheWindowEndsOnTheEdge() throws {
        let e = Self.engine()
        _ = e.pointer(.down(x: 10, y: 10))
        #expect(e.pointer(.dragged(x: 500, y: -50)) == [try Self.touch(.move, 1343, 0)])
        #expect(e.pointer(.up(x: 500, y: -50)) == [try Self.touch(.up, 1343, 0)])
        #expect(e.pointer(.dragged(x: 20, y: 20)).isEmpty, "no move without a touch in progress")
    }

    @Test func clicksOutsideTheVideoAreIgnored() {
        let e = InputEngine()
        e.layout(viewWidth: 351, viewHeight: 782, frameWidth: 2992, frameHeight: 1344)
        #expect(e.pointer(.down(x: 100, y: 5)).isEmpty, "letterbox bar is not the phone")
    }

    @Test func rightClickIsBackOnlyWhenEnabled() throws {
        let e = Self.engine()
        #expect(e.pointer(.secondaryClick) == [try ControlMessage.simple(.backDown), try ControlMessage.simple(.backUp)])
        e.rightClickBack = false
        #expect(e.pointer(.secondaryClick).isEmpty)
    }

    @Test func pinchUsesTwoFingersAroundTheCentre() throws {
        let e = Self.engine()
        let began = e.pointer(.pinchBegan(x: 175.5, y: 391))
        #expect(began == [try Self.touch(.down, 472, 1496), try Self.touch(.down, 872, 1496, pointer: ControlMessage.secondFingerPointer)])
        let grown = e.pointer(.pinchChanged(magnification: 0.5))
        #expect(grown == [try Self.touch(.move, 372, 1496), try Self.touch(.move, 972, 1496, pointer: ControlMessage.secondFingerPointer)])
        #expect(e.pointer(.pinchEnded).count == 2)
    }

    @Test func blurBlocksEverythingAndReleasesHeldInput() throws {
        let e = Self.engine()
        _ = e.pointer(.down(x: 175.5, y: 391))
        let released = e.setBlocked(true)
        #expect(released == [try Self.touch(.up, 672, 1496)])
        #expect(e.pointer(.down(x: 1, y: 1)).isEmpty)
        #expect(e.keyDown(keyCode: 0x00, flags: 0, characters: "a", isRepeat: false).isEmpty)
        #expect(e.action(.home).isEmpty)
        _ = e.setBlocked(false)
        #expect(!e.action(.home).isEmpty)
    }

    @Test func hardwareKeyboardSendsHIDReports() throws {
        let e = Self.engine()
        let first = e.keyDown(keyCode: 0x00, flags: 1 << 17, characters: "A", isRepeat: false)
        #expect(first.count == 2, "UHID keyboard created on first key, then the report")
        #expect(first[0].first == 12)
        #expect(first[1] == (try ControlMessage.uhidInput(id: 1, report: [0x02, 0, 0x04, 0, 0, 0, 0, 0])))
        #expect(e.keyUp(keyCode: 0x00, flags: 0) == [try ControlMessage.uhidInput(id: 1, report: [0, 0, 0, 0, 0, 0, 0, 0])])
    }

    @Test func everySessionCreatesItsKeyboardBeforeTheFirstKey() throws {
        let e = Self.engine()
        for _ in 0..<2 {
            let start = e.sessionStarted(typingMode: .hardware)
            #expect(start.count == 1 && start[0].first == 12, "UHID create at session start")
            #expect(e.keyDown(keyCode: 0x00, flags: 0, characters: "a", isRepeat: false).count == 1, "first key is only the report")
        }
        #expect(e.sessionStarted(typingMode: .phone).isEmpty)
    }

    @Test func phoneKeyboardTypesTextAndSendsKeysForEditing() throws {
        let e = Self.engine()
        let switched = e.setTypingMode(.phone)
        #expect(switched.isEmpty)
        #expect(e.keyDown(keyCode: 0x00, flags: 0, characters: "é", isRepeat: false) == [try ControlMessage.text("é")])
        #expect(e.keyDown(keyCode: 0x33, flags: 0, characters: "\u{7f}", isRepeat: false) == [try ControlMessage.keycode(down: true, keycode: 67, meta: 0)])
        #expect(e.keyUp(keyCode: 0x33, flags: 0) == [try ControlMessage.keycode(down: false, keycode: 67, meta: 0)])
        let copy = e.keyDown(keyCode: 0x08, flags: 1 << 20, characters: "c", isRepeat: false)
        #expect(copy == [try ControlMessage.keycode(down: true, keycode: 31, meta: 0x3000)], "⌘C becomes Ctrl+C on the phone")
        let long = String(repeating: "ab", count: 200)
        #expect(e.keyDown(keyCode: 0x00, flags: 0, characters: long, isRepeat: false).count == 2, "long text split under 300 bytes")
    }

    @Test func toolbarShortcutsSendTheRightKeys() throws {
        let e = Self.engine()
        func keys(_ item: ToolbarItem) -> [[UInt8]] { e.action(item) }
        #expect(keys(.home) == [try ControlMessage.keycode(down: true, keycode: 3, meta: 0), try ControlMessage.keycode(down: false, keycode: 3, meta: 0)])
        #expect(keys(.back).first == (try ControlMessage.keycode(down: true, keycode: 4, meta: 0)))
        #expect(keys(.recents).first == (try ControlMessage.keycode(down: true, keycode: 187, meta: 0)))
        #expect(keys(.appDrawer).first == (try ControlMessage.keycode(down: true, keycode: 284, meta: 0)))
        #expect(keys(.lock).first == (try ControlMessage.keycode(down: true, keycode: 26, meta: 0)))
        #expect(keys(.notifications) == [try ControlMessage.simple(.expandNotifications)])
        #expect(keys(.quickSettings) == [try ControlMessage.simple(.expandSettings)])
        #expect(keys(.rotate) == [try ControlMessage.simple(.rotateDevice)])
        #expect(e.phoneScreenshot().first == (try ControlMessage.keycode(down: true, keycode: 120, meta: 0)))
        #expect(keys(.screenshot).isEmpty, "Mac screenshot is taken on the Mac")
    }

    @Test func inputFloodArrivesInOrderAtTheVirtualPhone() async throws {
        let phone = VirtualPhone()
        let link = VirtualPhoneLink(phone: phone)
        let session = MirrorSession(parameters: try SessionTests.parameters(encrypted: true, wireless: true), link: link,
                                    connector: { try await TapStream.wrap(POSIXStream.connect(unixPath: $0)) }, video: RecordingSink())
        try await session.start()
        let e = Self.engine()
        var expected: [UInt8] = []
        for i in 0..<500 {
            let x = Double(i % 351), y = Double((i * 7) % 782)
            let messages = i % 3 == 0 ? e.pointer(.down(x: x, y: y)) : i % 3 == 1 ? e.pointer(.dragged(x: x, y: y)) : e.pointer(.up(x: x, y: y))
            for m in messages {
                session.send(m)
                expected += m
            }
        }
        try await Task.sleep(for: .milliseconds(800))
        #expect(Self.touches(in: phone.received.withLock { $0.flatMap { $0 } }) == expected, "every event arrived, in order, byte-exact")
        await session.stop()
    }
}
