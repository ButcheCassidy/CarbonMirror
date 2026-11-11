//! H.264/H.265 Annex B (start-code delimited, as MediaCodec emits) → 4-byte length-prefixed NAL units, the
//! format VideoToolbox decodes. Runs on every frame from the phone, writes into a caller buffer, never
//! allocates; empty or oversized NAL units end the session.
#![forbid(unsafe_code)]

use crate::status::{CmResult, CmStatus};

/// Finds the next start code (`00 00 01`, optionally preceded by `00`) at or after `from`.
/// Returns (start of the code, first byte after it).
fn next_start_code(buf: &[u8], from: usize) -> Option<(usize, usize)> {
    let mut i = from;
    while i + 3 <= buf.len() {
        if buf[i] == 0 && buf[i + 1] == 0 && buf[i + 2] == 1 {
            let begin = if i > from && buf[i - 1] == 0 { i - 1 } else { i };
            return Some((begin, i + 3));
        }
        i += 1;
    }
    None
}

/// Converts `input` into `out`; returns bytes written. Input must begin with a start code.
pub fn to_length_prefixed(input: &[u8], out: &mut [u8]) -> CmResult<usize> {
    let (_, mut payload) = next_start_code(input, 0).filter(|(s, _)| *s == 0).ok_or(CmStatus::ParseMalformed)?;
    let mut written = 0usize;
    loop {
        let (end, next) = match next_start_code(input, payload) {
            Some((s, n)) => (s, Some(n)),
            None => (input.len(), None),
        };
        let nal = input.get(payload..end).ok_or(CmStatus::ParseMalformed)?;
        if nal.is_empty() {
            return Err(CmStatus::ParseMalformed);
        }
        let len = u32::try_from(nal.len()).map_err(|_| CmStatus::ParseTooLarge)?;
        let dst = out.get_mut(written..written + 4 + nal.len()).ok_or(CmStatus::BufferTooSmall)?;
        dst[..4].copy_from_slice(&len.to_be_bytes());
        dst[4..].copy_from_slice(nal);
        written += 4 + nal.len();
        match next {
            Some(n) => payload = n,
            None => return Ok(written),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn three_and_four_byte_start_codes() {
        let input = [0, 0, 0, 1, 0x67, 1, 2, 0, 0, 1, 0x68, 3];
        let mut out = [0u8; 32];
        let n = to_length_prefixed(&input, &mut out).unwrap();
        assert_eq!(&out[..n], &[0, 0, 0, 3, 0x67, 1, 2, 0, 0, 0, 2, 0x68, 3]);
    }

    #[test]
    fn malformed_inputs() {
        let mut out = [0u8; 8];
        assert_eq!(to_length_prefixed(&[1, 2, 3], &mut out), Err(CmStatus::ParseMalformed));
        assert_eq!(to_length_prefixed(&[0, 0, 1, 0, 0, 1, 5], &mut out), Err(CmStatus::ParseMalformed), "empty NAL");
        assert_eq!(to_length_prefixed(&[0, 0, 1, 5, 6, 7, 8, 9], &mut out), Err(CmStatus::BufferTooSmall));
    }
}
