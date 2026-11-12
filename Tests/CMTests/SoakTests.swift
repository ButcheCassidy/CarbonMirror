import CMCore
import CMCoreBridge
import CMInput
@testable import CMTransport
import Foundation
import Synchronization
import Testing

/// Phase 11 Stage 4: high-paced soak against the virtual phone, `CM_SOAK_SECONDS` long (300 for the spec's
/// 5 minutes). Sessions alternate USB (120 fps) and wireless (60 fps) profiles, both with the inner TLS, and
/// are torn down and rebuilt every 15 s (handover / reconnect); halfway the Mac identity is replaced (Create
/// new key + re-pair). Each session gets a 500 events/s input flood. Passes when every event arrives in order,
/// byte-exact, the video keeps up, and file descriptors and memory return to baseline.
@Suite("Soak (Phase 11 Stage 4)", .serialized)
struct SoakTests {
    static var seconds: Double? { ProcessInfo.processInfo.environment["CM_SOAK_SECONDS"].flatMap(Double.init) }

    static func openFDs() -> Int { (try? FileManager.default.contentsOfDirectory(atPath: "/proc/self/fd").count) ?? -1 }

    /// Open descriptors grouped by kind (socket, pipe, file …) for leak reports.
    static func fdKinds() -> [String: Int] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/proc/self/fd")) ?? []
        var kinds: [String: Int] = [:]
        for name in names {
            let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/fd/\(name)")) ?? "?"
            kinds[target.split(separator: ":").first.map(String.init) ?? target, default: 0] += 1
        }
        return kinds
    }

    static func rssMiB() -> Double {
        guard let text = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8),
              let pages = Double(text.split(separator: " ")[1]) else { return -1 }
        return pages * 4096 / 1_048_576
    }

    @Test(.enabled(if: SoakTests.seconds != nil)) func soak() async throws {
        let total = try #require(Self.seconds)
        let cycle = 15.0
        // Baseline after the first session: libdispatch and the runtime allocate their epoll/eventfd and
        // thread pool once; only growth after that is a leak.
        var baselineFDs = 0, baselineRSS = 0.0
        var baselineKinds: [String: Int] = [:]
        var signer = try OpenSSLSigner()
        var rotated = false
        var events = 0, cycles = 0
        let started = Date()
        while Date().timeIntervalSince(started) < total {
            if !rotated, Date().timeIntervalSince(started) >= total / 2 {
                signer = try OpenSSLSigner()
                rotated = true
            }
            let usb = cycles % 2 == 0
            let cycle = cycles == 0 ? 3.0 : cycle
            let fps = usb ? 120 : 60
            let phone = VirtualPhone(loopFPS: fps)
            let sink = RecordingSink()
            let parameters = SessionParameters(serial: "3A091FDJH00ABC", wireless: !usb, serverVersion: "0.1.0", codec: .h264, maxSize: 2992,
                                               maxFPS: fps, bitRate: 32_000_000, clipboardSync: true,
                                               encryption: Encryption(signer: signer, macCA: try InnerTLS.makeIdentityCA(signer: signer)))
            let session = MirrorSession(parameters: parameters, link: VirtualPhoneLink(phone: phone),
                                        connector: { try await POSIXStream.connect(unixPath: $0) }, video: sink)
            let endings = Mutex<[SessionEnd]>([])
            Task { for await case let .ended(reason) in session.events { endings.withLock { $0.append(reason) } } }
            try await session.start()
            let engine = InputTests.engine()
            var expected: [UInt8] = []
            let cycleStart = Date()
            var i = 0
            while Date().timeIntervalSince(cycleStart) < min(cycle, total - Date().timeIntervalSince(started)) {
                for _ in 0..<50 {
                    let x = Double(i % 351), y = Double((i * 7) % 782)
                    let input: PointerInput = i % 3 == 0 ? .down(x: x, y: y) : i % 3 == 1 ? .dragged(x: x, y: y) : .up(x: x, y: y)
                    for m in engine.pointer(input) {
                        session.send(m)
                        expected += m
                    }
                    i += 1
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            try await Task.sleep(for: .milliseconds(500))
            let elapsed = Date().timeIntervalSince(cycleStart)
            #expect(endings.withLock { $0 }.isEmpty, "cycle \(cycles): session stayed up: \(endings.withLock { $0 })")
            let wire = phone.received.withLock { $0.flatMap { $0 } }
            #expect(InputTests.touches(in: wire) == expected, "cycle \(cycles): every event arrived in order, byte-exact")
            let sent = phone.framesSent.withLock { $0 }
            let got = sink.state.withLock { $0.frames }
            #expect(got >= sent - 2, "cycle \(cycles): video kept up (\(got) of \(sent))")
            print("SOAK cycle \(cycles) \(usb ? "USB 120" : "Wi-Fi 60") TLS: \(String(format: "%.1f", Double(got) / elapsed)) fps delivered (\(got)/\(sent) frames), wire \(InputTests.touches(in: wire).count)/\(expected.count) B, "
                + "\(i) events (\(Int(Double(i) / elapsed))/s), fds \(Self.openFDs()), RSS \(String(format: "%.1f", Self.rssMiB())) MiB")
            events += i
            cycles += 1
            await session.stop()
            phone.stop()
            if cycles == 1 {
                try await Task.sleep(for: .seconds(1))
                (baselineFDs, baselineKinds, baselineRSS) = (Self.openFDs(), Self.fdKinds(), Self.rssMiB())
            }
        }
        try await Task.sleep(for: .seconds(2))
        let fds = Self.openFDs(), rss = Self.rssMiB()
        print("SOAK done: \(cycles) sessions, \(events) events, key rotated: \(rotated), fds \(baselineFDs) → \(fds), RSS \(String(format: "%.1f → %.1f", baselineRSS, rss)) MiB")
        #expect(fds <= baselineFDs + 4, "file descriptors return to baseline: \(baselineKinds) → \(Self.fdKinds())")
        #expect(rss - baselineRSS < 64, "no memory growth")
    }
}
