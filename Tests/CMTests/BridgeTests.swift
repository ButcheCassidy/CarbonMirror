import CarbonCoreC
import CMCore
import CMCoreBridge
import Foundation
import Testing

/// Raw value of a C enum constant (the header declares `CmStatus` both as enum and as int32_t typedef).
private func raw<T: RawRepresentable>(_ value: T) -> Int64 where T.RawValue: BinaryInteger {
    Int64(value.rawValue)
}

@Suite("Swift bridge and C ABI boundary")
struct BridgeTests {
    @Test func swiftStatusCodesMatchHeader() {
        let header: [(CoreStatus, Int64)] = [
            (.ok, raw(CmStatus_Ok)), (.nullPointer, raw(CmStatus_NullPointer)), (.invalidUtf8, raw(CmStatus_InvalidUtf8)),
            (.invalidArgument, raw(CmStatus_InvalidArgument)), (.bufferTooSmall, raw(CmStatus_BufferTooSmall)), (.panic, raw(CmStatus_Panic)),
            (.needMoreData, raw(CmStatus_NeedMoreData)), (.ipMalformed, raw(CmStatus_IpMalformed)), (.ipHostnameRefused, raw(CmStatus_IpHostnameRefused)),
            (.ipPublicRefused, raw(CmStatus_IpPublicRefused)), (.ipTunnelRangeRefused, raw(CmStatus_IpTunnelRangeRefused)),
            (.ipReservedRefused, raw(CmStatus_IpReservedRefused)), (.interfaceTunnelRefused, raw(CmStatus_InterfaceTunnelRefused)),
            (.portInvalid, raw(CmStatus_PortInvalid)), (.portLegacyTcpipRefused, raw(CmStatus_PortLegacyTcpipRefused)),
            (.adbEmpty, raw(CmStatus_AdbEmpty)), (.adbUnknownCommand, raw(CmStatus_AdbUnknownCommand)), (.adbBadArgument, raw(CmStatus_AdbBadArgument)),
            (.adbInstallNeedsUsb, raw(CmStatus_AdbInstallNeedsUsb)), (.adbInstallNeedsConfirmation, raw(CmStatus_AdbInstallNeedsConfirmation)),
            (.digestMismatch, raw(CmStatus_DigestMismatch)), (.parseMalformed, raw(CmStatus_ParseMalformed)), (.parseTooLarge, raw(CmStatus_ParseTooLarge)),
            (.inputOutside, raw(CmStatus_InputOutside)), (.tlsHandshakeFailed, raw(CmStatus_TlsHandshakeFailed)),
            (.tlsPinMismatch, raw(CmStatus_TlsPinMismatch)), (.tlsPolicyViolation, raw(CmStatus_TlsPolicyViolation)),
            (.tlsClosed, raw(CmStatus_TlsClosed)), (.tlsTimeout, raw(CmStatus_TlsTimeout)), (.tlsFailed, raw(CmStatus_TlsFailed)),
            (.pairingCodeExpired, raw(CmStatus_PairingCodeExpired)), (.pairingCodeUsed, raw(CmStatus_PairingCodeUsed)),
            (.trustNotPaired, raw(CmStatus_TrustNotPaired)), (.trustUnknownDevice, raw(CmStatus_TrustUnknownDevice)),
            (.trustIdentityChanged, raw(CmStatus_TrustIdentityChanged)), (.adbProbeMalformed, raw(CmStatus_AdbProbeMalformed)),
        ]
        for (swift, c) in header {
            #expect(Int64(swift.rawValue) == c, "\(swift)")
        }
        #expect(header.count == CoreStatus.allCases.count - 1)
    }

    @Test func nullAndHugeInputsAreRefusedNotCrashed() {
        #expect(cm_net_check_ip(nil, 5) == CoreStatus.nullPointer.rawValue)
        #expect(cm_adb_validate(nil, 0, 0) == CoreStatus.adbEmpty.rawValue)
        #expect(cm_sha256(nil, 0, nil) == CoreStatus.nullPointer.rawValue)
        #expect(cm_random(nil, 4) == CoreStatus.nullPointer.rawValue)
        var byte: UInt8 = 0
        #expect(cm_net_check_ip(&byte, Int.max) == CoreStatus.invalidArgument.rawValue)
        #expect(cm_failure_ui_state(1, 0, nil) == CoreStatus.nullPointer.rawValue)
        var state: UInt32 = 0
        #expect(cm_failure_ui_state(999, 0, &state) == CoreStatus.invalidArgument.rawValue)
    }

    @Test func invalidUTF8IsRefused() {
        let bad: [UInt8] = [0xC3, 0x28]
        let code = bad.withUnsafeBufferPointer { cm_net_check_ip($0.baseAddress, $0.count) }
        #expect(code == CoreStatus.invalidUtf8.rawValue)
    }

    @Test func sha256KnownAnswerAndVerify() throws {
        let hex = try CoreCrypto.sha256Hex(Array("abc".utf8))
        #expect(hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try CoreCrypto.verifySHA256(Array("abc".utf8), expected: try CoreCrypto.bytes(fromHex: hex))
        #expect(throws: CoreStatus.digestMismatch) {
            try CoreCrypto.verifySHA256(Array("abd".utf8), expected: try CoreCrypto.bytes(fromHex: hex))
        }
        #expect(throws: CoreStatus.invalidArgument) { try CoreCrypto.bytes(fromHex: "zz") }
    }

    @Test func randomIsRandomAndInRange() throws {
        let a = try CoreCrypto.randomBytes(32), b = try CoreCrypto.randomBytes(32)
        #expect(a != b)
        for _ in 0..<200 {
            #expect((20_000...59_999).contains(try CoreCrypto.randomInt(in: 20_000...59_999)))
        }
    }

    @Test func ssidIsNeverStoredInPlaintext() throws {
        let key = try Device.ssidKey("Home Wi-Fi")
        #expect(key.count == 64)
        #expect(!key.contains("Home"))
        #expect(key == (try Device.ssidKey("Home Wi-Fi")))
        #expect(key != (try Device.ssidKey("home wi-fi")))
    }

    @Test func deviceRemembersOnlyAllowedEndpoints() throws {
        var device = Device(serial: "SERIAL1", model: "Pixel_10_Pro_XL", androidVersion: "16", connection: .usb)
        try device.remember(.init(ip: "192.168.1.20", port: 37099), onNetwork: "Home")
        #expect(device.lastKnownEndpoints.count == 1)
        #expect(throws: CoreStatus.ipPublicRefused) { try device.remember(.init(ip: "8.8.8.8", port: 37099), onNetwork: "Cafe") }
        #expect(throws: CoreStatus.portLegacyTcpipRefused) { try device.remember(.init(ip: "192.168.1.20", port: 5555), onNetwork: "Home") }
        let decoded = try JSONDecoder().decode(Device.self, from: try JSONEncoder().encode(device))
        #expect(decoded == device)
    }

    @Test func everyFailureStateHasFittingStatusContent() {
        for state in UIStateCode.allCases {
            let content = StatusContent.forState(state)
            if state == .mirroring || state == .retryingSilently {
                #expect(content == nil)
                continue
            }
            guard let c = content else {
                Issue.record("missing status content: \(state)")
                continue
            }
            #expect(c.title.count <= 32, "title too long for 0.75x window: \(state)")
            #expect(c.subtitle.count <= 60, "subtitle should stay one or two short lines: \(state)")
            #expect((1...2).contains(c.buttons.count), "\(state)")
        }
    }
}
