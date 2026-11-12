// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
//! Window size maths: real-size scaling, 0.75×–2.0× clamping, aspect-locked live resize and corner radius.
#![forbid(unsafe_code)]

use crate::status::{CmResult, CmStatus};

/// Smallest window relative to the real phone.
pub const MIN_SCALE: f64 = 0.75;
/// Largest window relative to the real phone (before clamping to the visible screen).
pub const MAX_SCALE: f64 = 2.0;
/// Corner radius before the phone reports its own: 9.5 % of the window width.
pub const DEFAULT_CORNER_FRACTION: f64 = 0.095;
/// Settings slider range for corner fine-tuning (±15 %).
pub const CORNER_FINE_TUNE_LIMIT: f64 = 0.15;
const MM_PER_INCH: f64 = 25.4;

/// Width/height pair in points or pixels.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CmSize {
    pub w: f64,
    pub h: f64,
}

/// Space the chrome adds around the mirrored screen (points).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CmInsets {
    pub top: f64,
    pub left: f64,
    pub bottom: f64,
    pub right: f64,
}

fn positive(v: f64) -> CmResult<f64> {
    if v.is_finite() && v > 0.0 { Ok(v) } else { Err(CmStatus::InvalidArgument) }
}

fn valid_size(s: CmSize) -> CmResult<CmSize> {
    Ok(CmSize { w: positive(s.w)?, h: positive(s.h)? })
}

fn valid_insets(i: CmInsets) -> CmResult<CmInsets> {
    let ok = |v: f64| v.is_finite() && v >= 0.0;
    if ok(i.top) && ok(i.left) && ok(i.bottom) && ok(i.right) { Ok(i) } else { Err(CmStatus::InvalidArgument) }
}

/// Mac points per physical inch, from the display's width in points and its physical width in mm
/// (`CGDisplayScreenSize`). Points already include the backing scale factor, so this is correct at any
/// "Looks like" resolution.
pub fn mac_points_per_inch(display_width_pt: f64, display_width_mm: f64) -> CmResult<f64> {
    Ok(positive(display_width_pt)? / (positive(display_width_mm)? / MM_PER_INCH))
}

/// Size in Mac points at which the phone's screen appears at its real physical size.
pub fn real_size(phone_px: CmSize, phone_ppi: f64, mac_pt_per_inch: f64) -> CmResult<CmSize> {
    let px = valid_size(phone_px)?;
    let factor = positive(mac_pt_per_inch)? / positive(phone_ppi)?;
    Ok(CmSize { w: px.w * factor, h: px.h * factor })
}

/// Clamps a requested scale to 0.75×–2.0× of real size, then shrinks it until the window (screen plus
/// `insets`) fits the visible screen frame. Fitting the screen wins over the 0.75× minimum.
/// Returns the mirrored-screen size and the scale actually used.
pub fn clamp_scale(real: CmSize, requested_scale: f64, insets: CmInsets, visible: CmSize) -> CmResult<(CmSize, f64)> {
    let real = valid_size(real)?;
    let visible = valid_size(visible)?;
    let insets = valid_insets(insets)?;
    let scale = positive(requested_scale)?.clamp(MIN_SCALE, MAX_SCALE);
    let room_w = visible.w - insets.left - insets.right;
    let room_h = visible.h - insets.top - insets.bottom;
    if room_w <= 0.0 || room_h <= 0.0 {
        return Err(CmStatus::InvalidArgument);
    }
    let fit = (room_w / real.w).min(room_h / real.h);
    let used = scale.min(fit);
    Ok((CmSize { w: real.w * used, h: real.h * used }, used))
}

/// Live-resize step: given the current screen size and the frame size AppKit proposes, returns the frame
/// size that keeps the screen at the phone's aspect ratio and within the scale limits. The axis that changed
/// more (relative to the current size) drives the other.
pub fn locked_resize(
    current_screen: CmSize,
    proposed_frame: CmSize,
    insets: CmInsets,
    real: CmSize,
    visible: CmSize,
) -> CmResult<CmSize> {
    let cur = valid_size(current_screen)?;
    let real = valid_size(real)?;
    let insets = valid_insets(insets)?;
    if !(proposed_frame.w.is_finite() && proposed_frame.h.is_finite()) {
        return Err(CmStatus::InvalidArgument);
    }
    let want_w = proposed_frame.w - insets.left - insets.right;
    let want_h = proposed_frame.h - insets.top - insets.bottom;
    let dw = ((want_w - cur.w) / cur.w).abs();
    let dh = ((want_h - cur.h) / cur.h).abs();
    let requested_scale = if dw >= dh { want_w / real.w } else { want_h / real.h };
    let requested_scale = if requested_scale.is_finite() && requested_scale > 0.0 { requested_scale } else { MIN_SCALE };
    let (screen, _) = clamp_scale(real, requested_scale, insets, visible)?;
    Ok(CmSize { w: screen.w + insets.left + insets.right, h: screen.h + insets.top + insets.bottom })
}

/// Corner radius in points for a window `window_width_pt` wide. Uses the phone's own radius (pixels, read
/// at connect time) scaled to the window when known (`device_radius_px > 0`), else 9.5 % of the width.
/// `fine_tune` is the Settings slider, clamped to ±15 %.
pub fn corner_radius(window_width_pt: f64, device_radius_px: f64, phone_width_px: f64, fine_tune: f64) -> CmResult<f64> {
    let w = positive(window_width_pt)?;
    if !fine_tune.is_finite() || !device_radius_px.is_finite() {
        return Err(CmStatus::InvalidArgument);
    }
    let base = if device_radius_px > 0.0 {
        device_radius_px * w / positive(phone_width_px)?
    } else {
        w * DEFAULT_CORNER_FRACTION
    };
    let radius = base * (1.0 + fine_tune.clamp(-CORNER_FINE_TUNE_LIMIT, CORNER_FINE_TUNE_LIMIT));
    Ok(radius.min(w / 2.0))
}

#[cfg(test)]
mod tests {
    use super::*;

    const PIXEL: CmSize = CmSize { w: 1344.0, h: 2992.0 };
    const NONE: CmInsets = CmInsets { top: 0.0, left: 0.0, bottom: 0.0, right: 0.0 };

    #[test]
    fn reference_mac_matches_spec() {
        let ptpi = mac_points_per_inch(1728.0, 3456.0 / 254.0 * 25.4).unwrap();
        assert!((ptpi - 127.0).abs() < 1e-9);
        let real = real_size(PIXEL, 486.0, ptpi).unwrap();
        assert_eq!((real.w.round(), real.h.round()), (351.0, 782.0));
    }

    #[test]
    fn rejects_nonsense() {
        assert_eq!(real_size(PIXEL, 0.0, 127.0), Err(CmStatus::InvalidArgument));
        assert_eq!(real_size(CmSize { w: f64::NAN, h: 1.0 }, 486.0, 127.0), Err(CmStatus::InvalidArgument));
        assert_eq!(corner_radius(100.0, f64::INFINITY, 1344.0, 0.0), Err(CmStatus::InvalidArgument));
    }

    #[test]
    fn locked_resize_keeps_aspect() {
        let real = CmSize { w: 351.0, h: 782.0 };
        let vis = CmSize { w: 1728.0, h: 1080.0 };
        let f = locked_resize(real, CmSize { w: 400.0, h: 790.0 }, NONE, real, vis).unwrap();
        assert!((f.w / f.h - real.w / real.h).abs() < 1e-9);
    }
}
