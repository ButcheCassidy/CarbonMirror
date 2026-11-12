// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CarbonCoreC

/// Result codes of the Rust core (mirrors `CmStatus` in `carbon_core.h`; a test checks every value).
public enum CoreStatus: Int32, Error, Sendable, CaseIterable {
    case ok = 0
    case nullPointer = 1
    case invalidUtf8 = 2
    case invalidArgument = 3
    case bufferTooSmall = 4
    case panic = 5
    case needMoreData = 6
    case ipMalformed = 10
    case ipHostnameRefused = 11
    case ipPublicRefused = 12
    case ipTunnelRangeRefused = 13
    case ipReservedRefused = 14
    case interfaceTunnelRefused = 15
    case portInvalid = 16
    case portLegacyTcpipRefused = 17
    case adbEmpty = 30
    case adbUnknownCommand = 31
    case adbBadArgument = 32
    case adbInstallNeedsUsb = 33
    case adbInstallNeedsConfirmation = 34
    case digestMismatch = 50
    case parseMalformed = 60
    case parseTooLarge = 61
    case inputOutside = 70
    case tlsHandshakeFailed = 80
    case tlsPinMismatch = 81
    case tlsPolicyViolation = 82
    case tlsClosed = 83
    case tlsTimeout = 84
    case tlsFailed = 85
    case pairingCodeExpired = 90
    case pairingCodeUsed = 91
    case trustNotPaired = 92
    case trustUnknownDevice = 93
    case trustIdentityChanged = 94
    case adbProbeMalformed = 100
    /// A code this build of the bridge does not know — treated as a refusal.
    case unknown = -1

    /// The Rust variant name (`IpPublicRefused`), used by the shared test vectors.
    public var name: String {
        let s = String(describing: self)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    init(code: Int32) {
        self = CoreStatus(rawValue: code) ?? .unknown
    }
}

/// Converts a C ABI return code into a Swift error.
@inline(__always)
func check(_ code: Int32) throws(CoreStatus) {
    if code != CoreStatus.ok.rawValue { throw CoreStatus(code: code) }
}

/// Calls `body` with a pointer to the UTF-8 bytes of `text` (null pointer for an empty string).
@inline(__always)
func withUTF8Bytes<R>(_ text: String, _ body: (UnsafePointer<UInt8>?, Int) -> R) -> R {
    let bytes = Array(text.utf8)
    return bytes.withUnsafeBufferPointer { body($0.baseAddress, $0.count) }
}

/// Core library identity checks.
public enum CarbonCore {
    /// ABI version the bridge was written against.
    public static let expectedABIVersion: UInt32 = 3

    /// True when the linked Rust core speaks the ABI this bridge expects.
    public static var abiMatches: Bool {
        cm_abi_version() == expectedABIVersion
    }
}
