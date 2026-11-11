import CarbonCoreC
import CMCore
import CMCoreBridge
import Foundation
import Testing

@Suite("Swift bridge and C ABI boundary")
struct BridgeTests {
    @Test func swiftStatusCodesMatchHeader() {
        let header: [(CoreStatus, CmStatus)] = [
            (.ok, CmStatus_Ok), (.nullPointer, CmStatus_NullPointer), (.invalidUtf8, CmStatus_InvalidUtf8),
            (.invalidArgument, CmStatus_InvalidArgument), (.bufferTooSmall, CmStatus_BufferTooSmall), (.panic, CmStatus_Panic),
            (.needMoreData, CmStatus_NeedMoreData), (.ipMalformed, CmStatus_IpMalformed), (.ipHostnameRefused, CmStatus_IpHostnameRefused),
            (.ipPublicRefused, CmStatus_IpPublicRefused), (.ipTunnelRangeRefused, CmStatus_IpTunnelRangeRefused),
            (.ipReservedRefused, CmStatus_IpReservedRefused), (.interfaceTunnelRefused, CmStatus_InterfaceTunnelRefused),
            (.portInvalid, CmStatus_PortInvalid), (.portLegacyTcpipRefused, CmStatus_PortLegacyTcpipRefused),
            (.adbEmpty, CmStatus_AdbEmpty), (.adbUnknownCommand, CmStatus_AdbUnknownCommand), (.adbBadArgument, CmStatus_AdbBadArgument),
            (.adbInstallNeedsUsb, CmStatus_AdbInstallNeedsUsb), (.adbInstallNeedsConfirmation, CmStatus_AdbInstallNeedsConfirmation),
            (.digestMismatch, CmStatus_DigestMismatch), (.parseMalformed, CmStatus_ParseMalformed), (.parseTooLarge, CmStatus_ParseTooLarge),
        ]
        for (swift, c) in header {
            #expect(Int64(swift.rawValue) == Int64(c.rawValue), "\(swift)")
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
            let c = try? #require(content)
            #expect((c?.title.count ?? 99) <= 32, "title too long for 0.75x window: \(state)")
            #expect((c?.subtitle.count ?? 99) <= 60, "subtitle should stay one or two short lines: \(state)")
            #expect((1...2).contains(c?.buttons.count ?? 0), "\(state)")
        }
    }
}
