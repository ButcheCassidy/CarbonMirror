//! Network allowlist: Mullvad "Local network sharing" ranges only, never public or VPN-tunnel addresses,
//! never hostnames, never the plaintext legacy `adb tcpip` port, never a tunnel interface.
#![forbid(unsafe_code)]

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

use crate::status::{CmResult, CmStatus};

/// Legacy plaintext `adb tcpip` port — refused outright (Wireless debugging uses TLS on random ports).
pub const LEGACY_TCPIP_PORT: u16 = 5555;
const MAX_ADDRESS_LEN: usize = 64;
const MAX_ZONE_LEN: usize = 15;
const TUNNEL_PREFIXES: [&str; 8] = ["utun", "ipsec", "ppp", "tun", "tap", "wg", "gif", "stf"];

/// A destination accepted by the allowlist; IPv6 link-local addresses carry their interface (zone).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Destination {
    pub ip: IpAddr,
    pub zone: Option<String>,
}

fn v4_in(ip: Ipv4Addr, net: [u8; 4], prefix: u32) -> bool {
    let mask = u32::MAX.checked_shl(32 - prefix).unwrap_or(0);
    u32::from(ip) & mask == u32::from(Ipv4Addr::from(net)) & mask
}

fn v6_in(ip: Ipv6Addr, net: [u16; 8], prefix: u32) -> bool {
    let mask = u128::MAX.checked_shl(128 - prefix).unwrap_or(0);
    u128::from(ip) & mask == u128::from(Ipv6Addr::from(net)) & mask
}

fn check_v4(ip: Ipv4Addr) -> CmResult<()> {
    if ip.is_unspecified() || ip.is_loopback() || ip.is_multicast() || ip.is_broadcast() {
        return Err(CmStatus::IpReservedRefused);
    }
    // Mullvad's in-tunnel addresses (10.64.0.0/10) sit inside 10/8 but are never a phone on the LAN.
    if v4_in(ip, [10, 64, 0, 0], 10) {
        return Err(CmStatus::IpTunnelRangeRefused);
    }
    let allowed = v4_in(ip, [10, 0, 0, 0], 8)
        || v4_in(ip, [172, 16, 0, 0], 12)
        || v4_in(ip, [192, 168, 0, 0], 16)
        || v4_in(ip, [169, 254, 0, 0], 16);
    if allowed { Ok(()) } else { Err(CmStatus::IpPublicRefused) }
}

fn check_v6(ip: Ipv6Addr, zone: Option<&str>) -> CmResult<()> {
    if ip.is_unspecified() || ip.is_loopback() || ip.is_multicast() || ip.to_ipv4_mapped().is_some() {
        return Err(CmStatus::IpReservedRefused);
    }
    // Mullvad's in-tunnel IPv6 network is a ULA (fc00:bbbb:bbbb:bb01::/64).
    if v6_in(ip, [0xfc00, 0xbbbb, 0xbbbb, 0xbb01, 0, 0, 0, 0], 64) {
        return Err(CmStatus::IpTunnelRangeRefused);
    }
    if v6_in(ip, [0xfe80, 0, 0, 0, 0, 0, 0, 0], 10) {
        // Link-local is ambiguous without the interface it lives on.
        return if zone.is_some() { Ok(()) } else { Err(CmStatus::IpMalformed) };
    }
    if zone.is_some() {
        return Err(CmStatus::IpMalformed);
    }
    if v6_in(ip, [0xfc00, 0, 0, 0, 0, 0, 0, 0], 7) { Ok(()) } else { Err(CmStatus::IpPublicRefused) }
}

/// True for interface names that belong to VPNs or other tunnels (`utun3`, `wg0`, `ipsec0`, …).
pub fn is_tunnel_interface(name: &str) -> bool {
    TUNNEL_PREFIXES.iter().any(|p| name.starts_with(p))
}

/// Accepts a physical interface name for routing (`en0`, `bridge100`); refuses tunnels and junk.
pub fn check_interface(name: &str) -> CmResult<()> {
    let well_formed = !name.is_empty()
        && name.len() <= MAX_ZONE_LEN
        && name.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit());
    if !well_formed {
        return Err(CmStatus::InvalidArgument);
    }
    if is_tunnel_interface(name) { Err(CmStatus::InterfaceTunnelRefused) } else { Ok(()) }
}

/// Parses and checks a literal IP address (optionally `fe80::…%en0`). Hostnames are refused: Mullvad's DNS
/// cannot resolve local names and DNS answers are attacker-controlled.
pub fn check_ip(text: &str) -> CmResult<Destination> {
    if text.is_empty() || text.len() > MAX_ADDRESS_LEN {
        return Err(CmStatus::IpMalformed);
    }
    if !text.bytes().all(|b| b.is_ascii_hexdigit() || matches!(b, b'.' | b':' | b'%') || b.is_ascii_lowercase()) {
        return Err(if text.bytes().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.')) {
            CmStatus::IpHostnameRefused
        } else {
            CmStatus::IpMalformed
        });
    }
    let (addr, zone) = match text.split_once('%') {
        Some((a, z)) => {
            check_interface(z).map_err(|e| if e == CmStatus::InterfaceTunnelRefused { e } else { CmStatus::IpMalformed })?;
            (a, Some(z))
        }
        None => (text, None),
    };
    let ip: IpAddr = match addr.parse() {
        Ok(ip) => ip,
        Err(_) if addr.bytes().any(|b| b.is_ascii_alphabetic() && !b.is_ascii_hexdigit()) => {
            return Err(CmStatus::IpHostnameRefused);
        }
        Err(_) => return Err(CmStatus::IpMalformed),
    };
    match ip {
        IpAddr::V4(v4) => {
            if zone.is_some() {
                return Err(CmStatus::IpMalformed);
            }
            check_v4(v4)?
        }
        IpAddr::V6(v6) => check_v6(v6, zone)?,
    }
    Ok(Destination { ip, zone: zone.map(str::to_owned) })
}

/// Checks a TCP port: 1–65535 and never the legacy plaintext `adb tcpip` port.
pub fn check_port(port: u32) -> CmResult<u16> {
    let p = u16::try_from(port).map_err(|_| CmStatus::PortInvalid)?;
    match p {
        0 => Err(CmStatus::PortInvalid),
        LEGACY_TCPIP_PORT => Err(CmStatus::PortLegacyTcpipRefused),
        _ => Ok(p),
    }
}

/// Checks a full endpoint (address + port).
pub fn check_endpoint(ip: &str, port: u32) -> CmResult<(Destination, u16)> {
    Ok((check_ip(ip)?, check_port(port)?))
}

/// Parses `ip:port` or `[ipv6%zone]:port` as written in adb `connect`/`pair` arguments.
pub fn parse_host_port(text: &str) -> CmResult<(Destination, u16)> {
    let (host, port) = if let Some(rest) = text.strip_prefix('[') {
        let (h, p) = rest.split_once("]:").ok_or(CmStatus::IpMalformed)?;
        (h, p)
    } else {
        let (h, p) = text.rsplit_once(':').ok_or(CmStatus::IpMalformed)?;
        if h.contains(':') {
            return Err(CmStatus::IpMalformed);
        }
        (h, p)
    };
    if port.is_empty() || port.len() > 5 || !port.bytes().all(|b| b.is_ascii_digit()) {
        return Err(CmStatus::PortInvalid);
    }
    let port: u32 = port.parse().map_err(|_| CmStatus::PortInvalid)?;
    check_endpoint(host, port)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn link_local_needs_zone() {
        assert_eq!(check_ip("fe80::1").err(), Some(CmStatus::IpMalformed));
        assert!(check_ip("fe80::1%en0").is_ok());
        assert_eq!(check_ip("fe80::1%utun4").err(), Some(CmStatus::InterfaceTunnelRefused));
    }

    #[test]
    fn host_port_forms() {
        assert!(parse_host_port("192.168.1.20:37099").is_ok());
        assert!(parse_host_port("[fe80::1%en0]:40001").is_ok());
        assert_eq!(parse_host_port("192.168.1.20:5555").err(), Some(CmStatus::PortLegacyTcpipRefused));
        assert_eq!(parse_host_port("fe80::1:4000").err(), Some(CmStatus::IpMalformed));
    }
}
