// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CMCore
import CMCoreBridge
@testable import CMTransport
import Foundation
import Testing

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
private typealias Glibc = Darwin
#endif

extension POSIXStream {
    /// TCP to `ip`:`port` (default loopback) — the fake adbd stands in for a phone on the LAN (tests only; the
    /// app's own sockets are Unix sockets, and its LAN probe uses Network.framework).
    static func connect(port: UInt16, ip: String = "127.0.0.1") async throws -> POSIXStream {
        let fd = socket(AF_INET, streamType, 0)
        var address = loopback(port: port)
        guard inet_pton(AF_INET, ip, &address.sin_addr) == 1 else { throw StreamError.connectFailed }
        let rc = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sysConnect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard fd >= 0, rc == 0 else {
            sysClose(fd)
            throw StreamError.connectFailed
        }
        return POSIXStream(fd: fd)
    }
}

/// A fake adbd: either legacy plaintext (`adb tcpip`) or Wireless debugging (STLS, then TLS).
final class FakeAdbd: @unchecked Sendable {
    enum Mode { case plaintext, tls(TLSIdentity), garbage }

    static func header(_ command: UInt32, _ arg0: UInt32) -> [UInt8] {
        [command, arg0, 0, 0, 0, command ^ 0xFFFF_FFFF].flatMap { withUnsafeBytes(of: $0.littleEndian, Array.init) }
    }

    let port: UInt16
    private let listener: Int32

    init(port: UInt16, mode: Mode) throws {
        self.port = port
        let fd = socket(AF_INET, POSIXStream.streamType, 0)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = POSIXStream.loopback(port: port)
        let rc = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard rc == 0, Glibc.listen(fd, 4) == 0 else { throw StreamError.connectFailed }
        listener = fd
        Thread.detachNewThread {
            let client = Glibc.accept(fd, nil, nil)
            guard client >= 0 else { return }
            let stream = POSIXStream(fd: client)
            Task {
                _ = try? await stream.readExactly(31)
                switch mode {
                case .plaintext:
                    stream.send(Self.header(0x4854_5541, 1) )
                case .garbage:
                    stream.send(Array("HTTP/1.1 400 Bad Request\r\n\r\n".utf8))
                case let .tls(identity):
                    stream.send(Self.header(0x534C_5453, 0x0100_0000))
                    _ = try? await stream.readExactly(24)
                    if let session = try? TLSSession(identity: identity) {
                        try? await SecureStream(inner: stream, session: session).handshake()
                    }
                }
                try? await Task.sleep(for: .milliseconds(200))
                stream.close()
            }
        }
    }

    deinit {
        sysClose(listener)
    }
}

@Suite("Wireless probe (6.1, 7.2)", .serialized)
struct ProbeTests {
    @Test func plaintextAdbTcpipIsRefused() async throws {
        let adbd = try FakeAdbd(port: 28_801, mode: .plaintext)
        let result = await WirelessProbe.run(over: try await POSIXStream.connect(port: adbd.port))
        #expect(result == .plaintextRefused)
    }

    @Test func wirelessDebuggingKeyIsCaptured() async throws {
        let signer = try OpenSSLSigner()
        let identity = try TLSIdentity.server(macCA: try InnerTLS.makeIdentityCA(signer: signer))
        let adbd = try FakeAdbd(port: 28_802, mode: .tls(identity))
        let result = await WirelessProbe.run(over: try await POSIXStream.connect(port: adbd.port))
        #expect(result == .wirelessDebugging(keyHash: try identity.pin()), "the phone's TLS key hash is what gets pinned")
    }

    @Test func nonAdbServiceIsRejected() async throws {
        let adbd = try FakeAdbd(port: 28_803, mode: .garbage)
        #expect(await WirelessProbe.run(over: try await POSIXStream.connect(port: adbd.port)) == .notAdb)
    }

    @Test func addressPolicyRunsBeforeAnyConnection() {
        #expect(WirelessProbe.check(ip: "192.168.1.20", port: 37_099) == nil)
        #expect(WirelessProbe.check(ip: "192.168.1.20", port: 5555) == .plaintextRefused)
        #expect(WirelessProbe.check(ip: "8.8.8.8", port: 37_099) == .refusedAddress(.ipPublicRefused))
        #expect(WirelessProbe.check(ip: "10.64.0.1", port: 37_099) == .refusedAddress(.ipTunnelRangeRefused), "Mullvad tunnel range")
        #expect(WirelessProbe.check(ip: "phone.local", port: 37_099) == .refusedAddress(.ipHostnameRefused))
    }

    @Test func networkIsIdentifiedBySubnetHashNeverSSID() throws {
        #expect(NetworkIdentity.subnet(ip: "192.168.1.37", prefix: 24) == "192.168.1.0/24")
        #expect(NetworkIdentity.subnet(ip: "10.20.30.40", prefix: 12) == "10.16.0.0/12")
        #expect(NetworkIdentity.subnet(ip: "192.168.1", prefix: 24) == nil)
        #expect(NetworkIdentity.subnet(ip: "192.168.1.1", prefix: 33) == nil)
        let key = try NetworkIdentity.key(subnet: "192.168.1.0/24")
        #expect(key.count == 64 && !key.contains("192"))
        #expect(NetworkIdentity.hotspotGateway(subnet: "10.123.45.0/24") == "10.123.45.1")
        #expect(NetworkIdentity.subnet(ofInterface: "lo") == "127.0.0.0/8")
    }

    /// Phase 11 Stage 3.4/3.6 on the virtual LAN (`tools/sectest/virtual_lan.sh` sets `CM_LAN_PHONE`): the
    /// phone namespace offers plaintext adb on 5555 and 37099; a fake `utun` carries Mullvad's 10.64.0.0/10.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CM_LAN_PHONE"] != nil))
    func virtualLANRefusesPlaintextTunnelAndPublicTargets() async throws {
        let phone = try #require(ProcessInfo.processInfo.environment["CM_LAN_PHONE"])
        #expect(WirelessProbe.check(ip: phone, port: 5555) == .plaintextRefused, "legacy port refused before connecting")
        #expect(WirelessProbe.check(ip: phone, port: 37_099) == nil, "the phone's private address is allowed")
        #expect(await WirelessProbe.run(over: try await POSIXStream.connect(port: 37_099, ip: phone)) == .plaintextRefused)
        #expect(WirelessProbe.check(ip: "10.64.0.9", port: 37_099) == .refusedAddress(.ipTunnelRangeRefused), "Mullvad tunnel")
        #expect(WirelessProbe.check(ip: "8.8.8.8", port: 37_099) == .refusedAddress(.ipPublicRefused))
        #expect(WirelessProbe.check(ip: "2001:4860:4860::8888", port: 37_099) == .refusedAddress(.ipPublicRefused))
    }
}
