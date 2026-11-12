// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CMCore
import CMCoreBridge
import Foundation

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Identifies "this Wi-Fi network" without the SSID. Reading the SSID on macOS needs Location Services
/// permission, which CarbonMirror never asks for (minimal entitlements, spec 1.3/7.7), so the network is
/// identified by the IPv4 subnet of the Mac's Wi-Fi interface (e.g. `192.168.1.0/24`) — stored only as a
/// SHA-256 key (``Device/ssidKey(_:)``), never in plaintext.
public enum NetworkIdentity {
    /// Network address of `ip` under a `prefix`-bit mask, as `a.b.c.d/prefix`; nil for malformed input.
    public static func subnet(ip: String, prefix: Int) -> String? {
        guard (0...32).contains(prefix) else { return nil }
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else { return nil }
            value = value << 8 | UInt32(octet)
        }
        let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << UInt32(32 - prefix)
        let network = value & mask
        return "\(network >> 24).\(network >> 16 & 0xFF).\(network >> 8 & 0xFF).\(network & 0xFF)/\(prefix)"
    }

    /// Storage key for the network `subnet` belongs to.
    public static func key(subnet: String) throws(CoreStatus) -> String {
        try Device.ssidKey("subnet:\(subnet)")
    }

    /// Subnet of the first IPv4 address on interface `name` (e.g. `en0`), from `getifaddrs`.
    public static func subnet(ofInterface name: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard String(cString: entry.pointee.ifa_name) == name, let addr = entry.pointee.ifa_addr, let mask = entry.pointee.ifa_netmask,
                  addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let bits = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let text = "\(ip >> 24).\(ip >> 16 & 0xFF).\(ip >> 8 & 0xFF).\(ip & 0xFF)"
            return subnet(ip: text, prefix: bits.nonzeroBitCount)
        }
        return nil
    }

    /// Default gateway guess for the phone-hotspot case (spec 6.2): the first host of the subnet
    /// (Android's hotspot hands out addresses with the phone at `.1`). Checked against the allowlist by the caller.
    public static func hotspotGateway(subnet: String) -> String? {
        let parts = subnet.split(separator: "/")
        guard parts.count == 2, let prefix = Int(parts[1]), prefix <= 30 else { return nil }
        let octets = parts[0].split(separator: ".").compactMap { UInt32($0) }
        guard octets.count == 4 else { return nil }
        let host = (octets[0] << 24 | octets[1] << 16 | octets[2] << 8 | octets[3]) + 1
        return "\(host >> 24).\(host >> 16 & 0xFF).\(host >> 8 & 0xFF).\(host & 0xFF)"
    }
}
