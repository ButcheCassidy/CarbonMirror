import CMCore
import CMCoreBridge
@testable import CMTransport
import Foundation
import Testing

/// Full sessions against the virtual phone over real sockets (spec 11: Swift wrapper + FFI + Rust core).
@Suite("Mirror session against the virtual phone", .serialized)
struct SessionTests {
    static let signer = try? OpenSSLSigner()

    static func parameters(encrypted: Bool, wireless: Bool = false) throws -> SessionParameters {
        var encryption: Encryption?
        if encrypted {
            let signer = try #require(Self.signer)
            encryption = Encryption(signer: signer, macCA: try InnerTLS.makeIdentityCA(signer: signer))
        }
        return SessionParameters(serial: "3A091FDJH00ABC", wireless: wireless, serverVersion: "0.1.0", codec: .h264, maxSize: 2992, maxFPS: 120,
                                 bitRate: 32_000_000, clipboardSync: true, encryption: encryption)
    }

    static func run(_ phone: VirtualPhone, encrypted: Bool, wireless: Bool = false, until stop: @escaping ([SessionEvent]) -> Bool) async throws
        -> (session: MirrorSession, events: [SessionEvent], sink: RecordingSink, link: VirtualPhoneLink) {
        let link = VirtualPhoneLink(phone: phone)
        let sink = RecordingSink()
        let session = MirrorSession(parameters: try parameters(encrypted: encrypted, wireless: wireless), link: link,
                                    connector: { try await TapStream.wrap(POSIXStream.connect(unixPath: $0)) }, video: sink)
        try await session.start()
        var collected: [SessionEvent] = []
        let deadline = ContinuousClock.now + .seconds(10)
        for await event in session.events {
            collected.append(event)
            if stop(collected) || ContinuousClock.now > deadline { break }
        }
        return (session, collected, sink, link)
    }

    static func ended(_ events: [SessionEvent]) -> SessionEnd? {
        for case let .ended(reason) in events { return reason }
        return nil
    }

    @Test func encryptedSessionStreamsVideoAndControl() async throws {
        let phone = VirtualPhone()
        let (session, events, sink, link) = try await Self.run(phone, encrypted: true, wireless: true) { events in
            events.contains { if case .latency = $0 { true } else { false } } && events.contains { if case .clipboard = $0 { true } else { false } }
        }
        var tls: (UInt16?, UInt16?) = (nil, nil)
        for case let .connected(name, codec, suite, group) in events {
            #expect(name == "Pixel 10 Pro XL")
            #expect(codec == .h264)
            tls = (suite, group)
        }
        #expect(tls.0 == InnerTLS.suiteAES256GCM, "TLS_AES_256_GCM_SHA384")
        #expect(tls.1 == InnerTLS.groupX25519MLKEM768, "hybrid post-quantum key exchange")
        #expect(events.contains { if case .cornerRadius(104) = $0 { true } else { false } })
        #expect(events.contains { if case .battery(84, true) = $0 { true } else { false } })
        #expect(events.contains { if case .clipboard("hello") = $0 { true } else { false } })

        let point = PhonePoint(x: 672, y: 1496, frameWidth: 1344, frameHeight: 2992)
        session.send(try ControlMessage.touch(.down, at: point, pressure: 1))
        session.send(try ControlMessage.touch(.up, at: point, pressure: 0))
        try await Task.sleep(for: .milliseconds(300))
        let wire = phone.received.withLock { $0.flatMap { $0 } }
        let touch = try ControlMessage.touch(.down, at: point, pressure: 1)
        #expect(wire.firstRange(of: touch) != nil, "touch arrived byte-exact with the right coordinates")

        let state = sink.state.withLock { $0 }
        #expect(state.codec == .h264)
        #expect(state.sizes.first == "1344x2992")
        #expect(state.configs >= 1)
        #expect(state.frames > 0)
        await session.stop()
        #expect(link.calls.withLock { $0 } == ["prepare", "forward", "startServer", "removeForward", "cleanup"])
    }

    @Test func plainUSBSessionWorksWithoutTLS() async throws {
        let phone = VirtualPhone()
        let (session, events, _, _) = try await Self.run(phone, encrypted: false) { events in
            events.contains { if case .battery = $0 { true } else { false } }
        }
        for case let .connected(_, _, suite, _) in events { #expect(suite == nil) }
        await session.stop()
    }

    @Test func wirelessWithoutEncryptionIsRefused() async throws {
        let session = MirrorSession(parameters: try Self.parameters(encrypted: false, wireless: true), link: VirtualPhoneLink(phone: VirtualPhone()),
                                    connector: { try await TapStream.wrap(POSIXStream.connect(unixPath: $0)) }, video: RecordingSink())
        await #expect(throws: SessionEnd.tlsFailed(.tlsPolicyViolation)) { try await session.start() }
    }

    @Test func wrongPhonePinIsRefusedAsIdentityChange() async throws {
        let phone = VirtualPhone(attack: .wrongPin)
        let session = MirrorSession(parameters: try Self.parameters(encrypted: true, wireless: true), link: VirtualPhoneLink(phone: phone),
                                    connector: { try await TapStream.wrap(POSIXStream.connect(unixPath: $0)) }, video: RecordingSink())
        await #expect(throws: SessionEnd.identityChanged) { try await session.start() }
        phone.stop()
    }

    @Test(arguments: [VirtualPhone.Attack.unknownMessage, .oversizedClipboard, .nonTextClipboard, .forgedBattery])
    func hostileDeviceMessagesEndTheSession(attack: VirtualPhone.Attack) async throws {
        let phone = VirtualPhone(attack: attack)
        let (_, events, _, _) = try await Self.run(phone, encrypted: true, wireless: true) { Self.ended($0) != nil }
        guard case .protocolViolation = Self.ended(events) else {
            Issue.record("expected a protocol violation, got \(String(describing: Self.ended(events)))")
            return
        }
        #expect(!events.contains { if case .clipboard(let t) = $0 { t.count > 1000 } else { false } }, "nothing oversized reached the clipboard")
    }

    @Test func wrongSessionSecretIsRefusedByThePhone() async throws {
        let phone = VirtualPhone()
        let path = FileManager.default.temporaryDirectory.path + "/cm-f" + CoreCrypto.hex(try CoreCrypto.randomBytes(8))
        defer { try? FileManager.default.removeItem(atPath: path) }
        try phone.listen(unixPath: path)
        phone.start(setupLine: "CM1 plain \(String(repeating: "ab", count: 32)) -\n")
        let intruder = try await POSIXStream.connect(unixPath: path)
        intruder.send([UInt8](repeating: 0, count: 32))
        let reply = try await intruder.read(max: 16)
        #expect(reply.isEmpty, "connection dropped without sending anything")
        #expect(phone.rejectedSecrets.withLock { $0 } == 1)
        phone.stop()
    }

    /// Stage 2: the phone reboots / its server dies mid-session → the session ends promptly (no hang),
    /// forwards are removed and phone files cleaned up, so the reconnect logic can take over.
    @Test func phoneDyingMidSessionEndsTheSessionCleanly() async throws {
        let phone = VirtualPhone(loopFPS: 60)
        let link = VirtualPhoneLink(phone: phone)
        let session = MirrorSession(parameters: try Self.parameters(encrypted: true, wireless: true), link: link,
                                    connector: { try await POSIXStream.connect(unixPath: $0) }, video: RecordingSink())
        try await session.start()
        try await Task.sleep(for: .milliseconds(300))
        let killed = ContinuousClock.now
        phone.stop()
        var reason: SessionEnd?
        for await case let .ended(r) in session.events {
            reason = r
            break
        }
        #expect(reason != nil && reason != .stopped)
        #expect(ContinuousClock.now - killed < .seconds(3), "ended within 3 s")
        #expect(link.calls.withLock { $0 }.suffix(2) == ["removeForward", "cleanup"])
    }
}
