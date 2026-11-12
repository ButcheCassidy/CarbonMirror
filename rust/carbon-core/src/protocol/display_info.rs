// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
//! Reads the panel's rounded-corner radius from `adb shell dumpsys display` output (spec 4.2), e.g.
//! `RoundedCorner{position=TopLeft, radius=104, center=Point(104, 104)}`. Text from the phone: size-capped,
//! numbers range-checked; when nothing valid is found the window keeps its 9.5 % fallback.
#![forbid(unsafe_code)]

use crate::status::{CmResult, CmStatus};

/// `dumpsys display` is a few hundred KB at most.
pub const MAX_DUMPSYS_BYTES: usize = 4 * 1024 * 1024;
/// Plausible corner radius range, pixels.
pub const MAX_RADIUS_PX: u32 = 1000;

/// Largest top corner radius reported for the built-in display, in pixels.
pub fn corner_radius_px(text: &[u8]) -> CmResult<u32> {
    if text.len() > MAX_DUMPSYS_BYTES {
        return Err(CmStatus::ParseTooLarge);
    }
    let text = String::from_utf8_lossy(text);
    let mut best: Option<u32> = None;
    for block in text.split("RoundedCorner{").skip(1) {
        let block = block.split('}').next().unwrap_or("");
        let top = block.contains("position=TopLeft") || block.contains("position=TopRight");
        let Some(value) = block.split("radius=").nth(1) else { continue };
        let digits: String = value.chars().take_while(char::is_ascii_digit).take(5).collect();
        let Ok(radius) = digits.parse::<u32>() else { continue };
        if top && (1..=MAX_RADIUS_PX).contains(&radius) {
            best = Some(best.map_or(radius, |b| b.max(radius)));
        }
    }
    best.ok_or(CmStatus::ParseMalformed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_top_corner() {
        let s = b"mRoundedCorners=RoundedCorners{[RoundedCorner{position=TopLeft, radius=104, center=Point(104, 104)}, \
RoundedCorner{position=TopRight, radius=104, center=Point(1240, 104)}, RoundedCorner{position=BottomRight, radius=0}]}";
        assert_eq!(corner_radius_px(s), Ok(104));
        assert_eq!(corner_radius_px(b"no corners here"), Err(CmStatus::ParseMalformed));
        assert_eq!(corner_radius_px(b"RoundedCorner{position=TopLeft, radius=999999}"), Err(CmStatus::ParseMalformed));
    }
}
