//! Hashing, randomness and constant-time comparison (aws-lc-rs) for artifact verification and secrets.
#![forbid(unsafe_code)]

use aws_lc_rs::{constant_time, digest, rand};

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

/// Fills `out` from the operating system's CSPRNG.
pub fn random(out: &mut [u8]) -> CmResult<()> {
    rand::fill(out).map_err(|_| CmStatus::InvalidArgument)
}
