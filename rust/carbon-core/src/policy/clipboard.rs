//! Clipboard filter (spec A7 / 7.6): plain text only, at most 1 MB, valid UTF-8, no NUL bytes. Applied to
//! text in both directions before it touches either clipboard.
#![forbid(unsafe_code)]

use crate::protocol::scrcpy::MAX_CLIPBOARD_BYTES;
use crate::status::{CmResult, CmStatus};

/// Checks clipboard bytes; returns the text on success.
pub fn filter(bytes: &[u8]) -> CmResult<&str> {
    if bytes.is_empty() {
        return Err(CmStatus::InvalidArgument);
    }
    if bytes.len() > MAX_CLIPBOARD_BYTES {
        return Err(CmStatus::ParseTooLarge);
    }
    let text = std::str::from_utf8(bytes).map_err(|_| CmStatus::InvalidUtf8)?;
    if text.contains('\0') {
        return Err(CmStatus::ParseMalformed);
    }
    Ok(text)
}
