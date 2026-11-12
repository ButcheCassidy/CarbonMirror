//! Hashing, randomness and constant-time comparison (aws-lc-rs) for artifact verification and secrets.
#![forbid(unsafe_code)]

use aws_lc_rs::{constant_time, digest, hmac, rand};

use crate::status::{CmResult, CmStatus};

/// SHA-256 output length.
pub const SHA256_LEN: usize = 32;

/// SHA-256 of `data`.
pub fn sha256(data: &[u8]) -> [u8; SHA256_LEN] {
    let d = digest::digest(&digest::SHA256, data);
    let mut out = [0u8; SHA256_LEN];
    out.copy_from_slice(d.as_ref());
    out
}

/// Checks `data` against an expected SHA-256 in constant time.
pub fn sha256_verify(data: &[u8], expected: &[u8]) -> CmResult<()> {
    if expected.len() != SHA256_LEN {
        return Err(CmStatus::InvalidArgument);
    }
    constant_time::verify_slices_are_equal(&sha256(data), expected).map_err(|_| CmStatus::DigestMismatch)
}

/// Constant-time equality of two byte strings (false when lengths differ).
pub fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    constant_time::verify_slices_are_equal(a, b).is_ok()
}

/// Fills `out` from the operating system's CSPRNG.
pub fn random(out: &mut [u8]) -> CmResult<()> {
    rand::fill(out).map_err(|_| CmStatus::InvalidArgument)
}

/// HMAC-SHA-256 of `data` under `key`.
pub fn hmac_sha256(key: &[u8], data: &[u8]) -> [u8; SHA256_LEN] {
    let tag = hmac::sign(&hmac::Key::new(hmac::HMAC_SHA256, key), data);
    let mut out = [0u8; SHA256_LEN];
    out.copy_from_slice(tag.as_ref());
    out
}

/// Checks an HMAC-SHA-256 tag in constant time.
pub fn hmac_sha256_verify(key: &[u8], data: &[u8], tag: &[u8]) -> CmResult<()> {
    hmac::verify(&hmac::Key::new(hmac::HMAC_SHA256, key), data, tag).map_err(|_| CmStatus::DigestMismatch)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// RFC 4231 test case 2.
    #[test]
    fn hmac_matches_rfc4231() {
        let tag = hmac_sha256(b"Jefe", b"what do ya want for nothing?");
        assert_eq!(tag[..4], [0x5b, 0xdc, 0xc1, 0x46]);
        assert!(hmac_sha256_verify(b"Jefe", b"what do ya want for nothing?", &tag).is_ok());
        assert_eq!(hmac_sha256_verify(b"Jefe", b"what do ya want for nothing!", &tag), Err(CmStatus::DigestMismatch));
        assert_eq!(hmac_sha256_verify(b"Jefe", b"what do ya want for nothing?", &tag[..31]), Err(CmStatus::DigestMismatch));
    }
}
