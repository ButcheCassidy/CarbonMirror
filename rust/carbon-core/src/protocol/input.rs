//! Mac pointer geometry → phone pixel coordinates (spec 5.2/5.5): letterboxing, clamping for drags that
//! leave the screen, trackpad scroll units and two-finger pinch emulation.
#![forbid(unsafe_code)]

use crate::protocol::control::CmPosition;
use crate::status::{CmResult, CmStatus};

/// Rectangle in view points, origin top-left.
#[derive(Debug, Clone, Copy, PartialEq)]
#[repr(C)]
pub struct CmRect {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

/// Points of trackpad scrolling that make one scrcpy scroll unit.
pub const PRECISE_POINTS_PER_UNIT: f64 = 24.0;
/// scrcpy's scroll range per event.
pub const MAX_SCROLL_UNITS: f64 = 16.0;

fn finite_positive(v: f64) -> bool {
    v.is_finite() && v > 0.0
}

/// Where a `frame_w`×`frame_h` video sits inside a `view_w`×`view_h` view (aspect fit, centred).
pub fn letterbox(view_w: f64, view_h: f64, frame_w: u16, frame_h: u16) -> CmResult<CmRect> {
    if !finite_positive(view_w) || !finite_positive(view_h) || frame_w == 0 || frame_h == 0 {
        return Err(CmStatus::InvalidArgument);
    }
    let scale = (view_w / f64::from(frame_w)).min(view_h / f64::from(frame_h));
    let (w, h) = (f64::from(frame_w) * scale, f64::from(frame_h) * scale);
    Ok(CmRect { x: (view_w - w) / 2.0, y: (view_h - h) / 2.0, w, h })
}

/// Maps a view point inside `content` to phone pixels. Outside points are refused unless `clamp`
/// (used while a drag is in progress, so a swipe that leaves the window still ends on the edge).
pub fn map_point(content: CmRect, px: f64, py: f64, frame_w: u16, frame_h: u16, clamp: bool) -> CmResult<CmPosition> {
    if !finite_positive(content.w) || !finite_positive(content.h) || frame_w == 0 || frame_h == 0 {
        return Err(CmStatus::InvalidArgument);
    }
    if !(px.is_finite() && py.is_finite() && content.x.is_finite() && content.y.is_finite()) {
        return Err(CmStatus::InvalidArgument);
    }
    let rx = (px - content.x) / content.w;
    let ry = (py - content.y) / content.h;
    let inside = (0.0..1.0).contains(&rx) && (0.0..1.0).contains(&ry);
    if !inside && !clamp {
        return Err(CmStatus::InputOutside);
    }
    let to_px = |r: f64, size: u16| -> i32 { ((r * f64::from(size)).floor() as i64).clamp(0, i64::from(size) - 1) as i32 };
    Ok(CmPosition { x: to_px(rx, frame_w), y: to_px(ry, frame_h), frame_width: frame_w, frame_height: frame_h })
}

/// Mac scroll delta → scrcpy scroll units. Trackpads report points (`precise`), mouse wheels report lines.
pub fn scroll_units(delta: f64, precise: bool) -> f32 {
    if !delta.is_finite() {
        return 0.0;
    }
    let units = if precise { delta / PRECISE_POINTS_PER_UNIT } else { delta };
    units.clamp(-MAX_SCROLL_UNITS, MAX_SCROLL_UNITS) as f32
}

/// Two virtual fingers `spread` pixels apart, horizontally around `center`, kept inside the frame.
pub fn pinch_points(center: CmPosition, spread: f64) -> CmResult<(CmPosition, CmPosition)> {
    if !spread.is_finite() || spread < 0.0 || center.frame_width == 0 || center.frame_height == 0 {
        return Err(CmStatus::InvalidArgument);
    }
    let max_x = i64::from(center.frame_width) - 1;
    let half = (spread / 2.0).min(f64::from(center.frame_width)) as i64;
    let at = |x: i64| CmPosition { x: x.clamp(0, max_x) as i32, ..center };
    Ok((at(i64::from(center.x) - half), at(i64::from(center.x) + half)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn letterbox_landscape_in_portrait() {
        let r = letterbox(351.0, 782.0, 2992, 1344).unwrap();
        assert!((r.w - 351.0).abs() < 1e-9);
        assert!(r.y > 0.0 && (r.y * 2.0 + r.h - 782.0).abs() < 1e-9);
    }

    #[test]
    fn corners_map_to_first_and_last_pixel() {
        let c = CmRect { x: 0.0, y: 0.0, w: 351.0, h: 782.0 };
        assert_eq!(map_point(c, 0.0, 0.0, 1344, 2992, false).map(|p| (p.x, p.y)), Ok((0, 0)));
        let p = map_point(c, 350.999, 781.999, 1344, 2992, false).unwrap();
        assert_eq!((p.x, p.y), (1343, 2991));
        assert_eq!(map_point(c, 351.0, 10.0, 1344, 2992, false), Err(CmStatus::InputOutside));
        assert_eq!(map_point(c, 400.0, -5.0, 1344, 2992, true).map(|p| (p.x, p.y)), Ok((1343, 0)));
    }
}
