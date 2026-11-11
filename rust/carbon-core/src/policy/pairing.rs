//! Pairing and trust rules (spec 7.2 / 7.5): QR payload and single-use codes that expire after 120 s, and
//! the pin check that decides whether a phone may be used. A key is only trusted after a completed pairing;
//! after "Create new key" every pin is gone, so nothing is trusted until the next QR pairing.
#![forbid(unsafe_code)]

use crate::crypto;
use crate::status::{CmResult, CmStatus};

/// QR codes are valid this long.
pub const CODE_LIFETIME_SECS: u64 = 120;
/// Random service-name suffix length and password length (base-62 → ≥ 130 bits).
pub const SERVICE_SUFFIX_LEN: usize = 10;
pub const PASSWORD_LEN: usize = 22;
const ALPHABET: &[u8; 62] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

/// Uniform random string over `ALPHABET` (rejection sampling, no modulo bias).
fn random_string(len: usize) -> CmResult<String> {
    let mut out = String::with_capacity(len);
    let mut pool = [0u8; 64];
    while out.len() < len {
        crypto::random(&mut pool)?;
        for &b in &pool {
            if out.len() == len {
                break;
            }
            if b < 248 {
                out.push(char::from(ALPHABET[usize::from(b % 62)]));
            }
        }
    }
    Ok(out)
}

/// One QR pairing offer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairingCode {
    pub service_name: String,
    pub password: String,
    pub created_at: u64,
    used: bool,
}

impl PairingCode {
    /// Fresh random code created at `now` (seconds).
    pub fn generate(now: u64) -> CmResult<Self> {
        Ok(Self {
            service_name: format!("carbonmirror-{}", random_string(SERVICE_SUFFIX_LEN)?),
            password: random_string(PASSWORD_LEN)?,
            created_at: now,
            used: false,
        })
    }

    /// Android's Wireless-debugging QR format.
    pub fn qr_payload(&self) -> String {
        format!("WIFI:T:ADB;S:{};P:{};;", self.service_name, self.password)
    }

    /// Marks the code used; fails if it already was or has expired.
    pub fn consume(&mut self, now: u64) -> CmResult<()> {
        if self.used {
            return Err(CmStatus::PairingCodeUsed);
        }
        if now < self.created_at || now - self.created_at >= CODE_LIFETIME_SECS {
            return Err(CmStatus::PairingCodeExpired);
        }
        self.used = true;
        Ok(())
    }
}

/// Decides whether a phone that presents `serial` and an adb TLS key hash may be used. `pinned` is the
/// stored (serial, key hash) for this Mac's single paired phone, `None` when nothing is paired.
pub fn check_peer(pinned: Option<(&str, &[u8])>, serial: &str, key_hash: Option<&[u8]>) -> CmResult<()> {
    let Some((pinned_serial, pinned_hash)) = pinned else {
        return Err(CmStatus::TrustNotPaired);
    };
    if pinned_serial != serial {
        return Err(CmStatus::TrustUnknownDevice);
    }
    match key_hash {
        None => Ok(()),
        Some(hash) if hash.len() == crypto::SHA256_LEN && crypto::constant_time_eq(hash, pinned_hash) => Ok(()),
        Some(_) => Err(CmStatus::TrustIdentityChanged),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes_are_single_use_and_expire() {
        let mut c = PairingCode::generate(1000).unwrap();
        assert!(c.qr_payload().starts_with("WIFI:T:ADB;S:carbonmirror-"));
        assert_eq!(c.password.len(), PASSWORD_LEN);
        assert_eq!(c.consume(1000 + CODE_LIFETIME_SECS), Err(CmStatus::PairingCodeExpired));
        assert_eq!(c.consume(1119), Ok(()));
        assert_eq!(c.consume(1119), Err(CmStatus::PairingCodeUsed));
        assert_ne!(PairingCode::generate(0).unwrap().password, PairingCode::generate(0).unwrap().password);
    }

    #[test]
    fn trust_requires_matching_pin() {
        let h = [7u8; 32];
        assert_eq!(check_peer(None, "S", Some(&h)), Err(CmStatus::TrustNotPaired));
        assert_eq!(check_peer(Some(("S", &h)), "T", Some(&h)), Err(CmStatus::TrustUnknownDevice));
        assert_eq!(check_peer(Some(("S", &h)), "S", Some(&[8u8; 32])), Err(CmStatus::TrustIdentityChanged));
        assert_eq!(check_peer(Some(("S", &h)), "S", Some(&h)), Ok(()));
        assert_eq!(check_peer(Some(("S", &h)), "S", None), Ok(()));
    }
}
