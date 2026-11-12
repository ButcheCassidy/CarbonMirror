// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CarbonCoreC

/// Private-range allowlist: Mullvad LAN-sharing ranges only; no public, tunnel, hostname or legacy-port targets.
public enum NetPolicy {
    /// Throws unless `ip` is a literal address inside the allowed private ranges.
    public static func checkIP(_ ip: String) throws(CoreStatus) {
        try check(withUTF8Bytes(ip) { cm_net_check_ip($0, $1) })
    }

    /// Throws unless `ip:port` is allowed (also refuses the plaintext `adb tcpip` port 5555).
    public static func checkEndpoint(ip: String, port: UInt32) throws(CoreStatus) {
        try check(withUTF8Bytes(ip) { cm_net_check_endpoint($0, $1, port) })
    }

    /// Throws for VPN/tunnel interfaces (`utun*`, `wg*`, …) or malformed names.
    public static func checkInterface(_ name: String) throws(CoreStatus) {
        try check(withUTF8Bytes(name) { cm_net_check_interface($0, $1) })
    }
}

/// adb command allowlist. Every argv is validated here before any adb process is started.
public enum AdbPolicy {
    /// Throws unless `argv` (without the adb path) matches one allowed template.
    /// - Parameters:
    ///   - usb: the target device is attached over USB (required for `install`).
    ///   - confirmed: the user confirmed this action (required for `install`).
    public static func validate(_ argv: [String], usb: Bool = false, confirmed: Bool = false) throws(CoreStatus) {
        var buffer: [UInt8] = []
        for arg in argv {
            buffer.append(contentsOf: arg.utf8)
            buffer.append(0)
        }
        let flags = (usb ? UInt32(FLAG_TRANSPORT_USB) : 0) | (confirmed ? UInt32(FLAG_USER_CONFIRMED) : 0)
        try check(buffer.withUnsafeBufferPointer { cm_adb_validate($0.baseAddress, $0.count, flags) })
    }
}

/// Failure classes the transport reports (mirrors `CmFailureClass`).
public enum FailureClass: UInt32, Sendable, CaseIterable {
    case macWifiOff = 1
    case deviceNotFound = 2
    case noPairing = 3
    case wirelessDebuggingOff = 4
    case lanUnreachable = 5
    case routeViaTunnel = 6
    case connectionLost = 7
    case unknownDevice = 8
    case pinMismatchKnownDevice = 9
    case adbUnauthorized = 10
    case tlsHandshakeFailed = 11
    case keyFingerprintMismatch = 12
    case keyMissing = 13
    case legacyPlaintextOffered = 14
}

/// What the phone-shaped window shows (mirrors `CmUiState`).
public enum UIStateCode: UInt32, Sendable, CaseIterable {
    case mirroring = 0
    case wifiOff = 1
    case searching = 2
    case notPaired = 3
    case wirelessDebuggingOff = 4
    case lanSharingBlocked = 5
    case disconnected = 6
    case untrustedDevice = 7
    case authenticationFailed = 8
    case identityChanged = 9
    case retryingSilently = 10
    case insecureConnectionRefused = 11
    case phoneReady = 12
    case notConnected = 13
    case launchCheckFailed = 14
}

/// Failure → UI-state mapping from the Rust core.
public enum FailureMap {
    /// State to show after `attempt` consecutive failures of `failure` (first failure = 0).
    public static func uiState(for failure: FailureClass, attempt: UInt32) throws(CoreStatus) -> UIStateCode {
        var raw: UInt32 = 0
        try check(cm_failure_ui_state(failure.rawValue, attempt, &raw))
        guard let state = UIStateCode(rawValue: raw) else { throw CoreStatus.unknown }
        return state
    }
}
