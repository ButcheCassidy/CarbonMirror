//! Encoding of Mac → phone control messages in scrcpy's wire format (big-endian). Only the message types
//! the forked server still accepts exist here; the encoder writes into a caller buffer and never allocates.
#![forbid(unsafe_code)]

use crate::protocol::scrcpy::MAX_CLIPBOARD_BYTES;
use crate::status::{CmResult, CmStatus};

/// scrcpy message type ids.
pub const TYPE_INJECT_KEYCODE: u8 = 0;
pub const TYPE_INJECT_TEXT: u8 = 1;
pub const TYPE_INJECT_TOUCH: u8 = 2;
pub const TYPE_INJECT_SCROLL: u8 = 3;
pub const TYPE_BACK_OR_SCREEN_ON: u8 = 4;
pub const TYPE_EXPAND_NOTIFICATIONS: u8 = 5;
pub const TYPE_EXPAND_SETTINGS: u8 = 6;
pub const TYPE_COLLAPSE_PANELS: u8 = 7;
pub const TYPE_GET_CLIPBOARD: u8 = 8;
pub const TYPE_SET_CLIPBOARD: u8 = 9;
pub const TYPE_SET_DISPLAY_POWER: u8 = 10;
pub const TYPE_ROTATE_DEVICE: u8 = 11;
pub const TYPE_UHID_CREATE: u8 = 12;
pub const TYPE_UHID_INPUT: u8 = 13;
pub const TYPE_UHID_DESTROY: u8 = 14;
pub const TYPE_OPEN_HARD_KEYBOARD_SETTINGS: u8 = 15;
pub const TYPE_START_APP: u8 = 16;
pub const TYPE_RESET_VIDEO: u8 = 17;
/// CarbonMirror fork: ping carrying an opaque value, answered by a pong device message.
pub const TYPE_CARBON_PING: u8 = 0x41;

/// The server's own cap on injected text (scrcpy `INJECT_TEXT_MAX_LENGTH`).
pub const MAX_INJECT_TEXT: usize = 300;
/// Package names for "start app" (scrcpy uses a 1-byte length).
pub const MAX_APP_NAME: usize = 255;
/// UHID descriptor/report caps (scrcpy uses 2-byte lengths; keyboards need far less).
pub const MAX_UHID_DATA: usize = 1024;
pub const MAX_UHID_NAME: usize = 127;

/// Messages without a payload, plus the single-byte ones.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum Simple {
    BackOrScreenOnDown = 1,
    BackOrScreenOnUp = 2,
    ExpandNotifications = 3,
    ExpandSettings = 4,
    CollapsePanels = 5,
    GetClipboardCopy = 6,
    DisplayPowerOff = 7,
    DisplayPowerOn = 8,
    RotateDevice = 9,
    OpenHardKeyboardSettings = 10,
    ResetVideo = 11,
}

impl Simple {
    pub fn from_raw(raw: u32) -> CmResult<Self> {
        Ok(match raw {
            1 => Self::BackOrScreenOnDown,
            2 => Self::BackOrScreenOnUp,
            3 => Self::ExpandNotifications,
            4 => Self::ExpandSettings,
            5 => Self::CollapsePanels,
            6 => Self::GetClipboardCopy,
            7 => Self::DisplayPowerOff,
            8 => Self::DisplayPowerOn,
            9 => Self::RotateDevice,
            10 => Self::OpenHardKeyboardSettings,
            11 => Self::ResetVideo,
            _ => return Err(CmStatus::InvalidArgument),
        })
    }
}

/// A touch/scroll position: phone pixel coordinates plus the frame size they refer to.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(C)]
pub struct CmPosition {
    pub x: i32,
    pub y: i32,
    pub frame_width: u16,
    pub frame_height: u16,
}

/// Little cursor over the output buffer; every write is bounds-checked.
struct Writer<'a> {
    out: &'a mut [u8],
    at: usize,
}

impl<'a> Writer<'a> {
    fn new(out: &'a mut [u8]) -> Self {
        Self { out, at: 0 }
    }

    fn bytes(&mut self, b: &[u8]) -> CmResult<()> {
        let end = self.at.checked_add(b.len()).ok_or(CmStatus::BufferTooSmall)?;
        self.out.get_mut(self.at..end).ok_or(CmStatus::BufferTooSmall)?.copy_from_slice(b);
        self.at = end;
        Ok(())
    }

    fn u8(&mut self, v: u8) -> CmResult<()> {
        self.bytes(&[v])
    }

    fn u16(&mut self, v: u16) -> CmResult<()> {
        self.bytes(&v.to_be_bytes())
    }

    fn i32(&mut self, v: i32) -> CmResult<()> {
        self.bytes(&v.to_be_bytes())
    }

    fn i64(&mut self, v: i64) -> CmResult<()> {
        self.bytes(&v.to_be_bytes())
    }

    fn position(&mut self, p: CmPosition) -> CmResult<()> {
        if p.frame_width == 0 || p.frame_height == 0 {
            return Err(CmStatus::InvalidArgument);
        }
        self.i32(p.x)?;
        self.i32(p.y)?;
        self.u16(p.frame_width)?;
        self.u16(p.frame_height)
    }

    fn done(self) -> usize {
        self.at
    }
}

/// Float in [0, 1] → scrcpy unsigned 16-bit fixed point.
fn u16_fixed(v: f32) -> u16 {
    if !v.is_finite() || v <= 0.0 {
        return 0;
    }
    if v >= 1.0 {
        return 0xffff;
    }
    (v * 65536.0) as u16
}

/// Float in [-1, 1] → scrcpy signed 16-bit fixed point.
fn i16_fixed(v: f32) -> i16 {
    if !v.is_finite() {
        return 0;
    }
    let c = v.clamp(-1.0, 1.0);
    if c >= 1.0 {
        return 0x7fff;
    }
    (c * 32768.0) as i16
}

pub fn simple(kind: Simple, out: &mut [u8]) -> CmResult<usize> {
    let mut w = Writer::new(out);
    match kind {
        Simple::BackOrScreenOnDown | Simple::BackOrScreenOnUp => {
            w.u8(TYPE_BACK_OR_SCREEN_ON)?;
            w.u8(u8::from(kind == Simple::BackOrScreenOnUp))?;
        }
        Simple::ExpandNotifications => w.u8(TYPE_EXPAND_NOTIFICATIONS)?,
        Simple::ExpandSettings => w.u8(TYPE_EXPAND_SETTINGS)?,
        Simple::CollapsePanels => w.u8(TYPE_COLLAPSE_PANELS)?,
        Simple::GetClipboardCopy => {
            w.u8(TYPE_GET_CLIPBOARD)?;
            w.u8(1)?;
        }
        Simple::DisplayPowerOff | Simple::DisplayPowerOn => {
            w.u8(TYPE_SET_DISPLAY_POWER)?;
            w.u8(u8::from(kind == Simple::DisplayPowerOn))?;
        }
        Simple::RotateDevice => w.u8(TYPE_ROTATE_DEVICE)?,
        Simple::OpenHardKeyboardSettings => w.u8(TYPE_OPEN_HARD_KEYBOARD_SETTINGS)?,
        Simple::ResetVideo => w.u8(TYPE_RESET_VIDEO)?,
    }
    Ok(w.done())
}

/// Android key event (`action` 0 down / 1 up).
pub fn keycode(action: u8, keycode: i32, repeat: i32, meta_state: i32, out: &mut [u8]) -> CmResult<usize> {
    if action > 1 || keycode <= 0 || repeat < 0 {
        return Err(CmStatus::InvalidArgument);
    }
    let mut w = Writer::new(out);
    w.u8(TYPE_INJECT_KEYCODE)?;
    w.u8(action)?;
    w.i32(keycode)?;
    w.i32(repeat)?;
    w.i32(meta_state)?;
    Ok(w.done())
}

/// Text typed in "Phone keyboard" mode (≤ 300 bytes, no control characters except tab/newline).
pub fn text(text: &str, out: &mut [u8]) -> CmResult<usize> {
    if text.is_empty() || text.len() > MAX_INJECT_TEXT || text.chars().any(|c| c.is_control() && c != '\n' && c != '\t') {
        return Err(CmStatus::InvalidArgument);
    }
    let mut w = Writer::new(out);
    w.u8(TYPE_INJECT_TEXT)?;
    w.i32(text.len() as i32)?;
    w.bytes(text.as_bytes())?;
    Ok(w.done())
}

/// Touch event (`action` = Android MotionEvent action: 0 down, 1 up, 2 move).
pub fn touch(action: u8, pointer_id: i64, pos: CmPosition, pressure: f32, action_button: i32, buttons: i32, out: &mut [u8]) -> CmResult<usize> {
    if action > 2 {
        return Err(CmStatus::InvalidArgument);
    }
    let mut w = Writer::new(out);
    w.u8(TYPE_INJECT_TOUCH)?;
    w.u8(action)?;
    w.i64(pointer_id)?;
    w.position(pos)?;
    w.u16(u16_fixed(pressure))?;
    w.i32(action_button)?;
    w.i32(buttons)?;
    Ok(w.done())
}

/// Scroll event; `h`/`v` in scrcpy units, clamped to [-16, 16].
pub fn scroll(pos: CmPosition, h: f32, v: f32, buttons: i32, out: &mut [u8]) -> CmResult<usize> {
    let mut w = Writer::new(out);
    w.u8(TYPE_INJECT_SCROLL)?;
    w.position(pos)?;
    w.bytes(&i16_fixed(h / 16.0).to_be_bytes())?;
    w.bytes(&i16_fixed(v / 16.0).to_be_bytes())?;
    w.i32(buttons)?;
    Ok(w.done())
}

/// Sets the phone clipboard (plain text ≤ 1 MB), optionally pasting it.
pub fn set_clipboard(sequence: i64, paste: bool, text: &str, out: &mut [u8]) -> CmResult<usize> {
    if text.len() > MAX_CLIPBOARD_BYTES {
        return Err(CmStatus::ParseTooLarge);
    }
    let mut w = Writer::new(out);
    w.u8(TYPE_SET_CLIPBOARD)?;
    w.i64(sequence)?;
    w.u8(u8::from(paste))?;
    w.i32(text.len() as i32)?;
    w.bytes(text.as_bytes())?;
    Ok(w.done())
}

pub fn uhid_create(id: u16, vendor: u16, product: u16, name: &str, descriptor: &[u8], out: &mut [u8]) -> CmResult<usize> {
    if name.len() > MAX_UHID_NAME || descriptor.is_empty() || descriptor.len() > MAX_UHID_DATA {
        return Err(CmStatus::InvalidArgument);
    }
    let mut w = Writer::new(out);
    w.u8(TYPE_UHID_CREATE)?;
    w.u16(id)?;
    w.u16(vendor)?;
    w.u16(product)?;
    w.u8(name.len() as u8)?;
    w.bytes(name.as_bytes())?;
    w.u16(descriptor.len() as u16)?;
    w.bytes(descriptor)?;
    Ok(w.done())
}

pub fn uhid_input(id: u16, report: &[u8], out: &mut [u8]) -> CmResult<usize> {
    if report.is_empty() || report.len() > MAX_UHID_DATA {
        return Err(CmStatus::InvalidArgument);
    }
    let mut w = Writer::new(out);
    w.u8(TYPE_UHID_INPUT)?;
    w.u16(id)?;
    w.u16(report.len() as u16)?;
    w.bytes(report)?;
    Ok(w.done())
}

pub fn uhid_destroy(id: u16, out: &mut [u8]) -> CmResult<usize> {
    let mut w = Writer::new(out);
    w.u8(TYPE_UHID_DESTROY)?;
    w.u16(id)?;
    Ok(w.done())
}

/// Round-trip probe for the status line's latency figure.
pub fn ping(value: u64, out: &mut [u8]) -> CmResult<usize> {
    let mut w = Writer::new(out);
    w.u8(TYPE_CARBON_PING)?;
    w.bytes(&value.to_be_bytes())?;
    Ok(w.done())
}

/// Launches an app by Android package name (letters, digits, `_` and `.` only).
pub fn start_app(package: &str, out: &mut [u8]) -> CmResult<usize> {
    let valid = !package.is_empty()
        && package.len() <= MAX_APP_NAME
        && package.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'.')
        && !package.starts_with('.');
    if !valid {
        return Err(CmStatus::InvalidArgument);
    }
    let mut w = Writer::new(out);
    w.u8(TYPE_START_APP)?;
    w.u8(package.len() as u8)?;
    w.bytes(package.as_bytes())?;
    Ok(w.done())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn touch_layout_is_32_bytes() {
        let mut out = [0u8; 64];
        let pos = CmPosition { x: 100, y: 200, frame_width: 1344, frame_height: 2992 };
        let n = touch(0, -2, pos, 1.0, 0, 0, &mut out).unwrap();
        assert_eq!(n, 32);
        assert_eq!(out[0], TYPE_INJECT_TOUCH);
        assert_eq!(&out[22..24], &[0xff, 0xff]);
    }

    #[test]
    fn buffer_too_small_is_refused() {
        let mut out = [0u8; 10];
        let pos = CmPosition { x: 0, y: 0, frame_width: 1, frame_height: 1 };
        assert_eq!(touch(0, -2, pos, 1.0, 0, 0, &mut out), Err(CmStatus::BufferTooSmall));
    }

    #[test]
    fn scroll_fixed_point() {
        let mut out = [0u8; 32];
        let pos = CmPosition { x: 1, y: 1, frame_width: 10, frame_height: 10 };
        assert_eq!(scroll(pos, 0.0, 16.0, 0, &mut out), Ok(21));
        assert_eq!(&out[15..17], &[0x7f, 0xff]);
        scroll(pos, 0.0, -100.0, 0, &mut out).unwrap();
        assert_eq!(&out[15..17], &[0x80, 0x00]);
    }
}
