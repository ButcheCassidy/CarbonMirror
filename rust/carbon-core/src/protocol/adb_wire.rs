//! Minimal adb wire probe (spec 6.1 / 11 stage 3.4): before `adb connect`, CarbonMirror opens its own TCP
//! connection to the phone's port and sends an adb `CNXN`. Android Wireless debugging answers `STLS` (the
//! connection must switch to TLS); legacy `adb tcpip` answers `CNXN` or `AUTH` in plaintext and is refused.
#![forbid(unsafe_code)]

use crate::status::{CmResult, CmStatus};

/// adb packet header length.
pub const HEADER_LEN: usize = 24;
pub const A_CNXN: u32 = 0x4e58_4e43;
pub const A_AUTH: u32 = 0x4854_5541;
pub const A_STLS: u32 = 0x534c_5453;
/// adb protocol version that understands STLS.
pub const A_VERSION: u32 = 0x0100_0001;
pub const A_STLS_VERSION: u32 = 0x0100_0000;
const MAX_PAYLOAD: u32 = 256 * 1024;
const BANNER: &[u8] = b"host::\0";

/// What the port answered.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum ProbeAnswer {
    /// Wireless debugging (TLS required) — allowed.
    TlsRequired = 1,
    /// Plaintext adb (`adb tcpip`) — refused.
    Plaintext = 2,
}

fn header(command: u32, arg0: u32, arg1: u32, payload: &[u8]) -> [u8; HEADER_LEN] {
    let mut h = [0u8; HEADER_LEN];
    let checksum: u32 = payload.iter().map(|&b| u32::from(b)).sum();
    for (i, v) in [command, arg0, arg1, payload.len() as u32, checksum, command ^ 0xffff_ffff].iter().enumerate() {
        h[i * 4..i * 4 + 4].copy_from_slice(&v.to_le_bytes());
    }
    h
}

/// The `CNXN` packet to send first (header + banner).
pub fn hello(out: &mut [u8]) -> CmResult<usize> {
    let total = HEADER_LEN + BANNER.len();
    let dst = out.get_mut(..total).ok_or(CmStatus::BufferTooSmall)?;
    dst[..HEADER_LEN].copy_from_slice(&header(A_CNXN, A_VERSION, MAX_PAYLOAD, BANNER));
    dst[HEADER_LEN..].copy_from_slice(BANNER);
    Ok(total)
}

/// The `STLS` reply that switches the connection to TLS (used only to read the phone's certificate).
pub fn stls_reply(out: &mut [u8]) -> CmResult<usize> {
    let dst = out.get_mut(..HEADER_LEN).ok_or(CmStatus::BufferTooSmall)?;
    dst.copy_from_slice(&header(A_STLS, A_STLS_VERSION, 0, &[]));
    Ok(HEADER_LEN)
}

/// Classifies the first packet header the phone sent back.
pub fn classify(buf: &[u8]) -> CmResult<ProbeAnswer> {
    let h = buf.get(..HEADER_LEN).ok_or(CmStatus::NeedMoreData)?;
    let word = |i: usize| u32::from_le_bytes([h[i * 4], h[i * 4 + 1], h[i * 4 + 2], h[i * 4 + 3]]);
    let command = word(0);
    if word(5) != command ^ 0xffff_ffff || word(3) > MAX_PAYLOAD {
        return Err(CmStatus::AdbProbeMalformed);
    }
    match command {
        A_STLS => Ok(ProbeAnswer::TlsRequired),
        A_CNXN | A_AUTH => Ok(ProbeAnswer::Plaintext),
        _ => Err(CmStatus::AdbProbeMalformed),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classify_answers() {
        assert_eq!(classify(&header(A_STLS, A_STLS_VERSION, 0, &[])), Ok(ProbeAnswer::TlsRequired));
        assert_eq!(classify(&header(A_AUTH, 1, 0, &[0; 20])), Ok(ProbeAnswer::Plaintext));
        assert_eq!(classify(&header(A_CNXN, A_VERSION, MAX_PAYLOAD, b"device::")), Ok(ProbeAnswer::Plaintext));
        let mut bad = header(A_STLS, 0, 0, &[]);
        bad[20] ^= 1;
        assert_eq!(classify(&bad), Err(CmStatus::AdbProbeMalformed));
        let mut out = [0u8; 64];
        assert_eq!(hello(&mut out), Ok(31));
    }
}
