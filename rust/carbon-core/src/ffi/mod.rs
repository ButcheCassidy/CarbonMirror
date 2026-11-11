//! C ABI — the only module allowed to use `unsafe`. Every function takes `(ptr, len)` byte slices and
//! out-pointers, returns a [`CmStatus`] code, and catches panics so none can cross the boundary.

use std::ffi::c_void;
use std::panic::{AssertUnwindSafe, catch_unwind};

use crate::policy::{adb, clipboard, failure, net, pairing, size};
use crate::protocol::{adb_devices, adb_wire, control, display_info, input as pinput, keymap, scrcpy};
use crate::status::{CmResult, CmStatus};
use crate::tls::{self, Identity, IdentitySigner, Session};
use crate::{crypto, ABI_VERSION};

pub use control::CmPosition;
pub use pinput::CmRect;
pub use size::{CmInsets, CmSize};

#[cfg(target_os = "android")]
mod jni;

/// Largest buffer accepted across the C ABI (16 MiB: above any H.265 keyframe at 32 Mbps and the
/// 1 MB clipboard cap). Larger lengths are refused before any pointer is turned into a slice.
const MAX_BUFFER_LEN: usize = 16 * 1024 * 1024;

fn guard(f: impl FnOnce() -> CmResult<()>) -> i32 {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(())) => CmStatus::Ok.code(),
        Ok(Err(e)) => e.code(),
        Err(_) => CmStatus::Panic.code(),
    }
}

/// # Safety
/// `ptr` must be null or point to `len` readable bytes that stay valid for `'a`.
unsafe fn input<'a>(ptr: *const u8, len: usize) -> CmResult<&'a [u8]> {
    if len == 0 {
        return Ok(&[]);
    }
    if ptr.is_null() {
        return Err(CmStatus::NullPointer);
    }
    if len > MAX_BUFFER_LEN {
        return Err(CmStatus::InvalidArgument);
    }
    // SAFETY: non-null, length bounded by MAX_BUFFER_LEN, and the caller guarantees `len` readable bytes.
    Ok(unsafe { std::slice::from_raw_parts(ptr, len) })
}

/// # Safety
/// As [`input`], and the bytes must be UTF-8 text.
unsafe fn input_str<'a>(ptr: *const u8, len: usize) -> CmResult<&'a str> {
    // SAFETY: forwarded caller contract.
    let bytes = unsafe { input(ptr, len) }?;
    std::str::from_utf8(bytes).map_err(|_| CmStatus::InvalidUtf8)
}

/// # Safety
/// `ptr` must be null or point to `len` writable bytes not aliased by any other live reference.
unsafe fn output<'a>(ptr: *mut u8, len: usize) -> CmResult<&'a mut [u8]> {
    if ptr.is_null() {
        return Err(CmStatus::NullPointer);
    }
    if len > MAX_BUFFER_LEN {
        return Err(CmStatus::InvalidArgument);
    }
    // SAFETY: non-null, bounded length, exclusive writable memory guaranteed by the caller.
    Ok(unsafe { std::slice::from_raw_parts_mut(ptr, len) })
}

/// # Safety
/// `out` must be null or a valid, aligned, writable `T`.
unsafe fn write<T>(out: *mut T, value: T) -> CmResult<()> {
    if out.is_null() {
        return Err(CmStatus::NullPointer);
    }
    // SAFETY: non-null and, per the caller contract, valid and aligned for a `T` write.
    unsafe { out.write(value) };
    Ok(())
}

/// Version of this C ABI; the Swift bridge refuses to run against a different one.
#[unsafe(no_mangle)]
pub extern "C" fn cm_abi_version() -> u32 {
    ABI_VERSION
}

/// Mac points per physical inch from the display width in points and in millimetres.
///
/// # Safety
/// `out` must be a valid writable `double`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_mac_points_per_inch(display_width_pt: f64, display_width_mm: f64, out: *mut f64) -> i32 {
    // SAFETY: caller contract on `out`.
    guard(|| unsafe { write(out, size::mac_points_per_inch(display_width_pt, display_width_mm)?) })
}

/// Real-size window (points) for a phone of `phone_px` pixels at `phone_ppi`.
///
/// # Safety
/// `out` must be a valid writable `CmSize`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_size_real(phone_px: CmSize, phone_ppi: f64, mac_pt_per_inch: f64, out: *mut CmSize) -> i32 {
    // SAFETY: caller contract on `out`.
    guard(|| unsafe { write(out, size::real_size(phone_px, phone_ppi, mac_pt_per_inch)?) })
}

/// Screen size for a requested scale, clamped to 0.75×–2.0× and to the visible frame.
///
/// # Safety
/// `out_size` and `out_scale` must be valid writable pointers.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_size_clamp(
    real: CmSize,
    requested_scale: f64,
    insets: CmInsets,
    visible: CmSize,
    out_size: *mut CmSize,
    out_scale: *mut f64,
) -> i32 {
    guard(|| {
        let (s, scale) = size::clamp_scale(real, requested_scale, insets, visible)?;
        // SAFETY: caller contract on both out-pointers.
        unsafe {
            write(out_size, s)?;
            write(out_scale, scale)
        }
    })
}

/// Aspect-locked frame size for one live-resize step.
///
/// # Safety
/// `out` must be a valid writable `CmSize`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_size_locked_resize(
    current_screen: CmSize,
    proposed_frame: CmSize,
    insets: CmInsets,
    real: CmSize,
    visible: CmSize,
    out: *mut CmSize,
) -> i32 {
    // SAFETY: caller contract on `out`.
    guard(|| unsafe { write(out, size::locked_resize(current_screen, proposed_frame, insets, real, visible)?) })
}

/// Corner radius (points); `device_radius_px <= 0` means "unknown, use 9.5 % of width".
///
/// # Safety
/// `out` must be a valid writable `double`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_corner_radius(
    window_width_pt: f64,
    device_radius_px: f64,
    phone_width_px: f64,
    fine_tune: f64,
    out: *mut f64,
) -> i32 {
    // SAFETY: caller contract on `out`.
    guard(|| unsafe { write(out, size::corner_radius(window_width_pt, device_radius_px, phone_width_px, fine_tune)?) })
}

/// Checks a literal IP address against the private-range allowlist.
///
/// # Safety
/// `ip` must point to `ip_len` readable bytes (or be null with `ip_len == 0`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_net_check_ip(ip: *const u8, ip_len: usize) -> i32 {
    // SAFETY: caller contract on `ip`.
    guard(|| net::check_ip(unsafe { input_str(ip, ip_len) }?).map(|_| ()))
}

/// Checks an address + port.
///
/// # Safety
/// As [`cm_net_check_ip`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_net_check_endpoint(ip: *const u8, ip_len: usize, port: u32) -> i32 {
    // SAFETY: caller contract on `ip`.
    guard(|| net::check_endpoint(unsafe { input_str(ip, ip_len) }?, port).map(|_| ()))
}

/// Checks that a route's interface is physical, not a VPN tunnel.
///
/// # Safety
/// `name` must point to `name_len` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_net_check_interface(name: *const u8, name_len: usize) -> i32 {
    // SAFETY: caller contract on `name`.
    guard(|| net::check_interface(unsafe { input_str(name, name_len) }?))
}

/// Validates an adb argv (NUL-separated, without the adb path) against the allowlist.
///
/// # Safety
/// `argv` must point to `argv_len` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_adb_validate(argv: *const u8, argv_len: usize, flags: u32) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `argv`.
        let text = unsafe { input_str(argv, argv_len) }?;
        adb::validate(&adb::split_argv(text), flags)
    })
}

/// Maps a failure class + consecutive attempt count to the UI state to show.
///
/// # Safety
/// `out_state` must be a valid writable `uint32_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_failure_ui_state(failure_class: u32, attempt: u32, out_state: *mut u32) -> i32 {
    guard(|| {
        let state = failure::ui_state(failure::FailureClass::from_u32(failure_class)?, attempt);
        // SAFETY: caller contract on `out_state`.
        unsafe { write(out_state, state as u32) }
    })
}

/// Parses `adb devices -l` text into normalised lines (`serial\tstate\tmodel\ttransport_id\tlink\n`).
/// On `BufferTooSmall`, `out_len` holds the size needed.
///
/// # Safety
/// `text` readable for `text_len`; `out` writable for `out_cap`; `out_len` a valid writable `size_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_adb_parse_devices(
    text: *const u8,
    text_len: usize,
    out: *mut u8,
    out_cap: usize,
    out_len: *mut usize,
) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `text`.
        let entries = adb_devices::parse_devices(unsafe { input(text, text_len) }?)?;
        let normalised = adb_devices::normalise(&entries);
        // SAFETY: caller contract on `out_len`.
        unsafe { write(out_len, normalised.len()) }?;
        if normalised.len() > out_cap {
            return Err(CmStatus::BufferTooSmall);
        }
        // SAFETY: caller contract on `out`.
        let dst = unsafe { output(out, out_cap) }?;
        dst[..normalised.len()].copy_from_slice(normalised.as_bytes());
        Ok(())
    })
}

/// Finds one complete `track-devices` frame at the start of `buf`.
///
/// # Safety
/// `buf` readable for `buf_len`; both out-pointers valid writable `size_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_adb_track_frame(
    buf: *const u8,
    buf_len: usize,
    out_offset: *mut usize,
    out_len: *mut usize,
) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `buf`.
        let (off, len) = adb_devices::track_frame(unsafe { input(buf, buf_len) }?)?;
        // SAFETY: caller contract on the out-pointers.
        unsafe {
            write(out_offset, off)?;
            write(out_len, len)
        }
    })
}

/// SHA-256 of `data` into `out` (32 bytes).
///
/// # Safety
/// `data` readable for `data_len`; `out` writable for 32 bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_sha256(data: *const u8, data_len: usize, out: *mut u8) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `data` and `out`.
        let (src, dst) = unsafe { (input(data, data_len)?, output(out, crypto::SHA256_LEN)?) };
        dst.copy_from_slice(&crypto::sha256(src));
        Ok(())
    })
}

/// Constant-time check of `data` against an expected 32-byte SHA-256.
///
/// # Safety
/// `data` readable for `data_len`; `expected` readable for `expected_len`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_sha256_verify(
    data: *const u8,
    data_len: usize,
    expected: *const u8,
    expected_len: usize,
) -> i32 {
    // SAFETY: caller contract on both inputs.
    guard(|| unsafe { crypto::sha256_verify(input(data, data_len)?, input(expected, expected_len)?) })
}

/// Fills `out` with `len` bytes from the system CSPRNG.
///
/// # Safety
/// `out` writable for `len` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_random(out: *mut u8, len: usize) -> i32 {
    // SAFETY: caller contract on `out`.
    guard(|| crypto::random(unsafe { output(out, len) }?))
}

// MARK: Shared out-buffer helper

/// Copies `bytes` into the caller's buffer and reports the length (needed size on `BufferTooSmall`).
///
/// # Safety
/// `out` writable for `cap` bytes; `out_len` a valid writable `size_t`.
unsafe fn emit(bytes: &[u8], out: *mut u8, cap: usize, out_len: *mut usize) -> CmResult<()> {
    // SAFETY: caller contract on `out_len`.
    unsafe { write(out_len, bytes.len()) }?;
    if bytes.len() > cap {
        return Err(CmStatus::BufferTooSmall);
    }
    // SAFETY: caller contract on `out`.
    let dst = unsafe { output(out, cap) }?;
    dst[..bytes.len()].copy_from_slice(bytes);
    Ok(())
}

/// Runs an encoder over the caller's buffer and reports how many bytes it wrote.
///
/// # Safety
/// `out` writable for `cap` bytes; `written` a valid writable `size_t`.
unsafe fn encode(out: *mut u8, cap: usize, written: *mut usize, f: impl FnOnce(&mut [u8]) -> CmResult<usize>) -> CmResult<()> {
    // SAFETY: caller contract on `out`.
    let n = f(unsafe { output(out, cap) }?)?;
    // SAFETY: caller contract on `written`.
    unsafe { write(written, n) }
}

// MARK: Video and device messages (phone → Mac)

/// Video header as seen by C: `kind` 1 session, 2 config, 3 frame.
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct CmVideoHeader {
    pub kind: u32,
    pub key_frame: u32,
    pub pts: u64,
    pub size: u32,
    pub width: u32,
    pub height: u32,
}

/// Device message as seen by C: `kind` is the scrcpy type byte; payload at `offset`/`len` in the input.
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct CmDeviceMessage {
    pub kind: u32,
    pub consumed: usize,
    pub offset: usize,
    pub len: usize,
    pub sequence: u64,
    pub id: u16,
    pub level: u8,
    pub charging: u8,
}

/// Length of the UTF-8 device name at the start of the 64-byte meta field.
///
/// # Safety
/// `buf` readable for `buf_len`; `out_len` a valid writable `size_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_proto_device_name(buf: *const u8, buf_len: usize, out_len: *mut usize) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `buf`.
        let name = scrcpy::parse_device_name(unsafe { input(buf, buf_len) }?)?;
        // SAFETY: caller contract on `out_len`.
        unsafe { write(out_len, name.len()) }
    })
}

/// Codec id after the device meta: 1 H.264, 2 H.265.
///
/// # Safety
/// `buf` readable for `buf_len`; `out_codec` a valid writable `uint32_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_proto_codec(buf: *const u8, buf_len: usize, out_codec: *mut u32) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `buf`.
        let codec = scrcpy::parse_codec(unsafe { input(buf, buf_len) }?)?;
        // SAFETY: caller contract on `out_codec`.
        unsafe { write(out_codec, codec as u32) }
    })
}

/// Parses one 12-byte video header.
///
/// # Safety
/// `buf` readable for `buf_len`; `out` a valid writable `CmVideoHeader`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_proto_video_header(buf: *const u8, buf_len: usize, out: *mut CmVideoHeader) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `buf`.
        let header = scrcpy::parse_video_header(unsafe { input(buf, buf_len) }?)?;
        let c = match header {
            scrcpy::VideoHeader::Session { width, height } => CmVideoHeader { kind: 1, width, height, ..Default::default() },
            scrcpy::VideoHeader::Config { size } => CmVideoHeader { kind: 2, size, ..Default::default() },
            scrcpy::VideoHeader::Frame { pts, key_frame, size } => {
                CmVideoHeader { kind: 3, key_frame: u32::from(key_frame), pts, size, ..Default::default() }
            }
        };
        // SAFETY: caller contract on `out`.
        unsafe { write(out, c) }
    })
}

/// Parses one device message (allowlist: clipboard text, clipboard ack, UHID output, battery).
///
/// # Safety
/// `buf` readable for `buf_len`; `out` a valid writable `CmDeviceMessage`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_proto_device_message(buf: *const u8, buf_len: usize, out: *mut CmDeviceMessage) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `buf`.
        let (msg, consumed) = scrcpy::parse_device_message(unsafe { input(buf, buf_len) }?)?;
        let c = match msg {
            scrcpy::DeviceMessage::Clipboard { offset, len } => {
                CmDeviceMessage { kind: u32::from(scrcpy::DEVICE_MSG_CLIPBOARD), consumed, offset, len, ..Default::default() }
            }
            scrcpy::DeviceMessage::AckClipboard { sequence } => {
                CmDeviceMessage { kind: u32::from(scrcpy::DEVICE_MSG_ACK_CLIPBOARD), consumed, sequence, ..Default::default() }
            }
            scrcpy::DeviceMessage::UhidOutput { id, offset, len } => {
                CmDeviceMessage { kind: u32::from(scrcpy::DEVICE_MSG_UHID_OUTPUT), consumed, offset, len, id, ..Default::default() }
            }
            scrcpy::DeviceMessage::Battery { level, charging } => CmDeviceMessage {
                kind: u32::from(scrcpy::DEVICE_MSG_BATTERY),
                consumed,
                level,
                charging: u8::from(charging),
                ..Default::default()
            },
        };
        // SAFETY: caller contract on `out`.
        unsafe { write(out, c) }
    })
}

/// Rounded-corner radius (pixels) from `dumpsys display` text.
///
/// # Safety
/// `text` readable for `text_len`; `out` a valid writable `uint32_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_display_corner_radius(text: *const u8, text_len: usize, out: *mut u32) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `text`.
        let radius = display_info::corner_radius_px(unsafe { input(text, text_len) }?)?;
        // SAFETY: caller contract on `out`.
        unsafe { write(out, radius) }
    })
}

/// Clipboard filter: plain UTF-8 text, no NUL, ≤ 1 MB.
///
/// # Safety
/// `text` readable for `text_len`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_clipboard_check(text: *const u8, text_len: usize) -> i32 {
    // SAFETY: caller contract on `text`.
    guard(|| clipboard::filter(unsafe { input(text, text_len) }?).map(|_| ()))
}

// MARK: Control messages (Mac → phone)

/// Payload-free or single-byte control message (`kind` = `Simple` value).
///
/// # Safety
/// `out` writable for `cap`; `written` a valid writable `size_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_ctrl_simple(kind: u32, out: *mut u8, cap: usize, written: *mut usize) -> i32 {
    // SAFETY: caller contract on `out` and `written`.
    guard(|| unsafe { encode(out, cap, written, |b| control::simple(control::Simple::from_raw(kind)?, b)) })
}

/// Android key event.
///
/// # Safety
/// As [`cm_ctrl_simple`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_ctrl_keycode(action: u8, keycode: i32, repeat: i32, meta: i32, out: *mut u8, cap: usize, written: *mut usize) -> i32 {
    // SAFETY: caller contract on `out` and `written`.
    guard(|| unsafe { encode(out, cap, written, |b| control::keycode(action, keycode, repeat, meta, b)) })
}

/// Injected text (≤ 300 bytes).
///
/// # Safety
/// `text` readable for `text_len`; otherwise as [`cm_ctrl_simple`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_ctrl_text(text: *const u8, text_len: usize, out: *mut u8, cap: usize, written: *mut usize) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `text`.
        let t = unsafe { input_str(text, text_len) }?;
        // SAFETY: caller contract on `out` and `written`.
        unsafe { encode(out, cap, written, |b| control::text(t, b)) }
    })
}

/// Touch event.
///
/// # Safety
/// As [`cm_ctrl_simple`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_ctrl_touch(
    action: u8,
    pointer_id: i64,
    position: CmPosition,
    pressure: f32,
    action_button: i32,
    buttons: i32,
    out: *mut u8,
    cap: usize,
    written: *mut usize,
) -> i32 {
    // SAFETY: caller contract on `out` and `written`.
    guard(|| unsafe { encode(out, cap, written, |b| control::touch(action, pointer_id, position, pressure, action_button, buttons, b)) })
}

/// Scroll event (`h`/`v` in scrcpy units).
///
/// # Safety
/// As [`cm_ctrl_simple`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_ctrl_scroll(position: CmPosition, h: f32, v: f32, buttons: i32, out: *mut u8, cap: usize, written: *mut usize) -> i32 {
    // SAFETY: caller contract on `out` and `written`.
    guard(|| unsafe { encode(out, cap, written, |b| control::scroll(position, h, v, buttons, b)) })
}

/// Sets the phone clipboard (filtered: plain text ≤ 1 MB).
///
/// # Safety
/// `text` readable for `text_len`; otherwise as [`cm_ctrl_simple`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_ctrl_set_clipboard(
    sequence: i64,
    paste: u8,
    text: *const u8,
    text_len: usize,
    out: *mut u8,
    cap: usize,
    written: *mut usize,
) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `text`.
        let t = clipboard::filter(unsafe { input(text, text_len) }?)?;
        // SAFETY: caller contract on `out` and `written`.
        unsafe { encode(out, cap, written, |b| control::set_clipboard(sequence, paste != 0, t, b)) }
    })
}

/// Creates the virtual UHID keyboard.
///
/// # Safety
/// `name`/`descriptor` readable for their lengths; otherwise as [`cm_ctrl_simple`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_ctrl_uhid_create(
    id: u16,
    vendor: u16,
    product: u16,
    name: *const u8,
    name_len: usize,
    descriptor: *const u8,
    descriptor_len: usize,
    out: *mut u8,
    cap: usize,
    written: *mut usize,
) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `name` and `descriptor`.
        let (n, d) = unsafe { (input_str(name, name_len)?, input(descriptor, descriptor_len)?) };
        // SAFETY: caller contract on `out` and `written`.
        unsafe { encode(out, cap, written, |b| control::uhid_create(id, vendor, product, n, d, b)) }
    })
}

/// Sends one UHID input report.
///
/// # Safety
/// `report` readable for `report_len`; otherwise as [`cm_ctrl_simple`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_ctrl_uhid_input(id: u16, report: *const u8, report_len: usize, out: *mut u8, cap: usize, written: *mut usize) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `report`.
        let r = unsafe { input(report, report_len) }?;
        // SAFETY: caller contract on `out` and `written`.
        unsafe { encode(out, cap, written, |b| control::uhid_input(id, r, b)) }
    })
}

/// Removes the virtual UHID keyboard.
///
/// # Safety
/// As [`cm_ctrl_simple`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_ctrl_uhid_destroy(id: u16, out: *mut u8, cap: usize, written: *mut usize) -> i32 {
    // SAFETY: caller contract on `out` and `written`.
    guard(|| unsafe { encode(out, cap, written, |b| control::uhid_destroy(id, b)) })
}

/// Launches an app by package name.
///
/// # Safety
/// `package` readable for `package_len`; otherwise as [`cm_ctrl_simple`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_ctrl_start_app(package: *const u8, package_len: usize, out: *mut u8, cap: usize, written: *mut usize) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `package`.
        let p = unsafe { input_str(package, package_len) }?;
        // SAFETY: caller contract on `out` and `written`.
        unsafe { encode(out, cap, written, |b| control::start_app(p, b)) }
    })
}

// MARK: Input mapping and keyboard

/// Where the video sits inside the view (aspect fit).
///
/// # Safety
/// `out` a valid writable `CmRect`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_input_letterbox(view_w: f64, view_h: f64, frame_w: u16, frame_h: u16, out: *mut CmRect) -> i32 {
    // SAFETY: caller contract on `out`.
    guard(|| unsafe { write(out, pinput::letterbox(view_w, view_h, frame_w, frame_h)?) })
}

/// View point → phone pixels (`clamp` non-zero while dragging).
///
/// # Safety
/// `out` a valid writable `CmPosition`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_input_map_point(content: CmRect, x: f64, y: f64, frame_w: u16, frame_h: u16, clamp: u8, out: *mut CmPosition) -> i32 {
    // SAFETY: caller contract on `out`.
    guard(|| unsafe { write(out, pinput::map_point(content, x, y, frame_w, frame_h, clamp != 0)?) })
}

/// Mac scroll delta → scrcpy scroll units.
///
/// # Safety
/// `out` a valid writable `float`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_input_scroll_units(delta: f64, precise: u8, out: *mut f32) -> i32 {
    // SAFETY: caller contract on `out`.
    guard(|| unsafe { write(out, pinput::scroll_units(delta, precise != 0)) })
}

/// Two-finger pinch positions around `center`.
///
/// # Safety
/// `out_a`/`out_b` valid writable `CmPosition`s.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_input_pinch(center: CmPosition, spread: f64, out_a: *mut CmPosition, out_b: *mut CmPosition) -> i32 {
    guard(|| {
        let (a, b) = pinput::pinch_points(center, spread)?;
        // SAFETY: caller contract on both out-pointers.
        unsafe {
            write(out_a, a)?;
            write(out_b, b)
        }
    })
}

/// 8-byte HID keyboard report for modifier flags + held macOS key codes (≤ 64).
///
/// # Safety
/// `held` null or readable, aligned for `held_count` `uint16_t`; `out` writable for 8 bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_key_hid_report(mac_flags: u32, held: *const u16, held_count: usize, out: *mut u8) -> i32 {
    guard(|| {
        if held_count > 64 || (held_count > 0 && (held.is_null() || held.align_offset(std::mem::align_of::<u16>()) != 0)) {
            return Err(CmStatus::InvalidArgument);
        }
        let keys: &[u16] = if held_count == 0 {
            &[]
        } else {
            // SAFETY: non-null, aligned, bounded count, caller guarantees readability.
            unsafe { std::slice::from_raw_parts(held, held_count) }
        };
        // SAFETY: caller contract on `out`.
        let dst = unsafe { output(out, keymap::HID_REPORT_LEN) }?;
        dst.copy_from_slice(&keymap::hid_report(mac_flags, keys));
        Ok(())
    })
}

/// The virtual keyboard's HID report descriptor.
///
/// # Safety
/// `out` writable for `cap`; `out_len` a valid writable `size_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_key_hid_descriptor(out: *mut u8, cap: usize, out_len: *mut usize) -> i32 {
    // SAFETY: caller contract on the out-pointers.
    guard(|| unsafe { emit(&keymap::HID_KEYBOARD_DESCRIPTOR, out, cap, out_len) })
}

/// macOS key code → Android key code and meta state ("Phone keyboard" mode).
///
/// # Safety
/// `out_keycode`/`out_meta` valid writable `int32_t`s.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_key_android(mac_code: u16, mac_flags: u32, out_keycode: *mut i32, out_meta: *mut i32) -> i32 {
    guard(|| {
        let code = keymap::mac_to_android(mac_code).ok_or(CmStatus::InvalidArgument)?;
        // SAFETY: caller contract on both out-pointers.
        unsafe {
            write(out_keycode, code)?;
            write(out_meta, keymap::android_meta(mac_flags))
        }
    })
}

// MARK: Wireless probe, pairing and trust

/// adb `CNXN` hello for the plaintext/TLS probe.
///
/// # Safety
/// `out` writable for `cap`; `written` a valid writable `size_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_adb_probe_hello(out: *mut u8, cap: usize, written: *mut usize) -> i32 {
    // SAFETY: caller contract on `out` and `written`.
    guard(|| unsafe { encode(out, cap, written, adb_wire::hello) })
}

/// adb `STLS` reply that starts TLS (fingerprint probe only).
///
/// # Safety
/// As [`cm_adb_probe_hello`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_adb_probe_stls(out: *mut u8, cap: usize, written: *mut usize) -> i32 {
    // SAFETY: caller contract on `out` and `written`.
    guard(|| unsafe { encode(out, cap, written, adb_wire::stls_reply) })
}

/// Classifies the phone's first adb packet: 1 TLS required (allowed), 2 plaintext (refused).
///
/// # Safety
/// `buf` readable for `buf_len`; `out_answer` a valid writable `uint32_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_adb_probe_classify(buf: *const u8, buf_len: usize, out_answer: *mut u32) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `buf`.
        let answer = adb_wire::classify(unsafe { input(buf, buf_len) }?)?;
        // SAFETY: caller contract on `out_answer`.
        unsafe { write(out_answer, answer as u32) }
    })
}

/// A single-use QR pairing code (opaque).
pub struct CmPairing(pairing::PairingCode);

/// New random pairing code created at `now` (Unix seconds).
///
/// # Safety
/// `out` a valid writable pointer; free the result with [`cm_pairing_free`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_pairing_new(now: u64, out: *mut *mut CmPairing) -> i32 {
    guard(|| {
        let code = Box::new(CmPairing(pairing::PairingCode::generate(now)?));
        // SAFETY: caller contract on `out`.
        unsafe { write(out, Box::into_raw(code)) }
    })
}

/// `field`: 0 QR payload, 1 service name, 2 password.
///
/// # Safety
/// `code` from [`cm_pairing_new`]; `out` writable for `cap`; `out_len` a valid writable `size_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_pairing_field(code: *const CmPairing, field: u32, out: *mut u8, cap: usize, out_len: *mut usize) -> i32 {
    guard(|| {
        // SAFETY: caller contract: null or a live handle from `cm_pairing_new`.
        let c = unsafe { code.as_ref() }.ok_or(CmStatus::NullPointer)?;
        let value = match field {
            0 => c.0.qr_payload(),
            1 => c.0.service_name.clone(),
            2 => c.0.password.clone(),
            _ => return Err(CmStatus::InvalidArgument),
        };
        // SAFETY: caller contract on the out-pointers.
        unsafe { emit(value.as_bytes(), out, cap, out_len) }
    })
}

/// Uses the code once; fails when used before or older than 120 s.
///
/// # Safety
/// `code` null or a live handle from [`cm_pairing_new`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_pairing_consume(code: *mut CmPairing, now: u64) -> i32 {
    // SAFETY: caller contract on `code`.
    guard(|| unsafe { code.as_mut() }.ok_or(CmStatus::NullPointer)?.0.consume(now))
}

/// Frees a pairing code.
///
/// # Safety
/// `code` null or a handle from [`cm_pairing_new`] not used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_pairing_free(code: *mut CmPairing) {
    if !code.is_null() {
        // SAFETY: caller contract: the pointer came from `Box::into_raw` and is freed once.
        drop(unsafe { Box::from_raw(code) });
    }
}

/// Pin check: a zero `pinned_serial_len` means nothing is paired; a zero `key_hash_len` means USB (no key).
///
/// # Safety
/// Every pointer readable for its length.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_trust_check(
    pinned_serial: *const u8,
    pinned_serial_len: usize,
    pinned_hash: *const u8,
    pinned_hash_len: usize,
    serial: *const u8,
    serial_len: usize,
    key_hash: *const u8,
    key_hash_len: usize,
) -> i32 {
    guard(|| {
        // SAFETY: caller contract on every input.
        let (ps, ph, s, kh) = unsafe {
            (input_str(pinned_serial, pinned_serial_len)?, input(pinned_hash, pinned_hash_len)?, input_str(serial, serial_len)?, input(key_hash, key_hash_len)?)
        };
        let pinned = if ps.is_empty() { None } else { Some((ps, ph)) };
        pairing::check_peer(pinned, s, if kh.is_empty() { None } else { Some(kh) })
    })
}

// MARK: Inner TLS

/// Signs `msg` with the Mac identity key; writes a DER ECDSA signature. Returns 0 on success.
pub type CmSignCallback =
    Option<unsafe extern "C" fn(ctx: *mut c_void, msg: *const u8, msg_len: usize, out: *mut u8, out_cap: usize, out_len: *mut usize) -> i32>;

/// Largest DER ECDSA P-384 signature.
const MAX_SIGNATURE: usize = 112;

struct CallbackSigner {
    public_key: Vec<u8>,
    callback: unsafe extern "C" fn(*mut c_void, *const u8, usize, *mut u8, usize, *mut usize) -> i32,
    ctx: *mut c_void,
}

impl IdentitySigner for CallbackSigner {
    fn public_key(&self) -> &[u8] {
        &self.public_key
    }

    fn sign(&self, message: &[u8]) -> CmResult<Vec<u8>> {
        let mut sig = vec![0u8; MAX_SIGNATURE];
        let mut len = 0usize;
        // SAFETY: the Swift side guarantees `callback`/`ctx` are valid for the duration of the call that
        // created this signer; buffers are live Rust allocations of the stated sizes.
        let rc = unsafe { (self.callback)(self.ctx, message.as_ptr(), message.len(), sig.as_mut_ptr(), sig.len(), &mut len) };
        if rc != 0 || len == 0 || len > sig.len() {
            return Err(CmStatus::TlsFailed);
        }
        sig.truncate(len);
        Ok(sig)
    }
}

/// # Safety
/// `public_key` readable for `public_key_len`; `callback`/`ctx` valid for this call.
unsafe fn signer(public_key: *const u8, public_key_len: usize, callback: CmSignCallback, ctx: *mut c_void) -> CmResult<CallbackSigner> {
    let callback = callback.ok_or(CmStatus::NullPointer)?;
    // SAFETY: caller contract on `public_key`.
    let pk = unsafe { input(public_key, public_key_len) }?;
    if pk.len() != 97 || pk[0] != 0x04 {
        return Err(CmStatus::InvalidArgument);
    }
    Ok(CallbackSigner { public_key: pk.to_vec(), callback, ctx })
}

/// Self-signed CA certificate for the Mac identity key (made once per key).
///
/// # Safety
/// As [`signer`]; `out` writable for `cap`; `out_len` a valid writable `size_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_make_identity_ca(
    public_key: *const u8,
    public_key_len: usize,
    callback: CmSignCallback,
    ctx: *mut c_void,
    out: *mut u8,
    cap: usize,
    out_len: *mut usize,
) -> i32 {
    guard(|| {
        // SAFETY: caller contract.
        let s = unsafe { signer(public_key, public_key_len, callback, ctx) }?;
        let der = tls::make_identity_ca(&s)?;
        // SAFETY: caller contract on the out-pointers.
        unsafe { emit(&der, out, cap, out_len) }
    })
}

/// One side's TLS configuration (opaque).
pub struct CmTlsIdentity(Identity);

/// One TLS connection (opaque). Not thread-safe: use from one thread at a time.
pub struct CmTlsSession(Session);

/// Mac: per-session client identity, pinning the phone's session key hash (32 bytes).
///
/// # Safety
/// As [`signer`]; `phone_pin` readable for 32 bytes; `out` a valid writable pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_client_identity_new(
    public_key: *const u8,
    public_key_len: usize,
    callback: CmSignCallback,
    ctx: *mut c_void,
    phone_pin: *const u8,
    out: *mut *mut CmTlsIdentity,
) -> i32 {
    guard(|| {
        // SAFETY: caller contract.
        let (s, pin) = unsafe { (signer(public_key, public_key_len, callback, ctx)?, input(phone_pin, crypto::SHA256_LEN)?) };
        let id = Box::new(CmTlsIdentity(Identity::client(&s, pin)?));
        // SAFETY: caller contract on `out`.
        unsafe { write(out, Box::into_raw(id)) }
    })
}

/// Phone (and test peer): per-start server identity that trusts only the pinned Mac CA.
///
/// # Safety
/// `mac_ca` readable for `mac_ca_len`; `out` a valid writable pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_server_identity_new(mac_ca: *const u8, mac_ca_len: usize, out: *mut *mut CmTlsIdentity) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `mac_ca`.
        let id = Box::new(CmTlsIdentity(Identity::server(unsafe { input(mac_ca, mac_ca_len) }?)?));
        // SAFETY: caller contract on `out`.
        unsafe { write(out, Box::into_raw(id)) }
    })
}

/// Server identity's public-key hash (32 bytes) for the Mac to pin.
///
/// # Safety
/// `identity` null or live; `out` writable for 32 bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_identity_pin(identity: *const CmTlsIdentity, out: *mut u8) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `identity`.
        let hash = unsafe { identity.as_ref() }.ok_or(CmStatus::NullPointer)?.0.spki_hash().ok_or(CmStatus::InvalidArgument)?;
        // SAFETY: caller contract on `out`.
        unsafe { output(out, crypto::SHA256_LEN) }?.copy_from_slice(&hash);
        Ok(())
    })
}

/// Frees an identity (sessions made from it stay valid).
///
/// # Safety
/// `identity` null or a handle not used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_identity_free(identity: *mut CmTlsIdentity) {
    if !identity.is_null() {
        // SAFETY: pointer from `Box::into_raw`, freed once.
        drop(unsafe { Box::from_raw(identity) });
    }
}

/// New TLS connection for an identity.
///
/// # Safety
/// `identity` null or live; `out` a valid writable pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_session_new(identity: *const CmTlsIdentity, out: *mut *mut CmTlsSession) -> i32 {
    guard(|| {
        // SAFETY: caller contract on `identity`.
        let id = unsafe { identity.as_ref() }.ok_or(CmStatus::NullPointer)?;
        let s = Box::new(CmTlsSession(Session::new(&id.0)?));
        // SAFETY: caller contract on `out`.
        unsafe { write(out, Box::into_raw(s)) }
    })
}

/// Capture-only client for the adb TLS key probe.
///
/// # Safety
/// `out` a valid writable pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_capture_new(out: *mut *mut CmTlsSession) -> i32 {
    guard(|| {
        let s = Box::new(CmTlsSession(Session::capture()?));
        // SAFETY: caller contract on `out`.
        unsafe { write(out, Box::into_raw(s)) }
    })
}

/// # Safety
/// `session` null or a live handle.
unsafe fn session<'a>(session: *mut CmTlsSession) -> CmResult<&'a mut Session> {
    // SAFETY: caller contract.
    Ok(&mut unsafe { session.as_mut() }.ok_or(CmStatus::NullPointer)?.0)
}

/// Feeds received ciphertext.
///
/// # Safety
/// `s` live; `data` readable for `len`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_read_tls(s: *mut CmTlsSession, data: *const u8, len: usize) -> i32 {
    // SAFETY: caller contract.
    guard(|| unsafe { session(s)?.read_tls(input(data, len)?) })
}

/// Takes ciphertext to send.
///
/// # Safety
/// `s` live; `out` writable for `cap`; `written` a valid writable `size_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_write_tls(s: *mut CmTlsSession, out: *mut u8, cap: usize, written: *mut usize) -> i32 {
    // SAFETY: caller contract.
    guard(|| unsafe { encode(out, cap, written, |b| session(s)?.write_tls(b)) })
}

/// Takes decrypted application data (0 bytes when none is pending).
///
/// # Safety
/// As [`cm_tls_write_tls`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_read_plain(s: *mut CmTlsSession, out: *mut u8, cap: usize, read: *mut usize) -> i32 {
    // SAFETY: caller contract.
    guard(|| unsafe { encode(out, cap, read, |b| session(s)?.read_plain(b)) })
}

/// Queues application data for encryption.
///
/// # Safety
/// `s` live; `data` readable for `len`; `consumed` a valid writable `size_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_write_plain(s: *mut CmTlsSession, data: *const u8, len: usize, consumed: *mut usize) -> i32 {
    guard(|| {
        // SAFETY: caller contract.
        let n = unsafe { session(s)?.write_plain(input(data, len)?) }?;
        // SAFETY: caller contract on `consumed`.
        unsafe { write(consumed, n) }
    })
}

/// Status flags: 1 handshaking, 2 wants write.
///
/// # Safety
/// `s` live; `out` a valid writable `uint32_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_status(s: *mut CmTlsSession, out: *mut u32) -> i32 {
    // SAFETY: caller contract.
    guard(|| unsafe { write(out, session(s)?.status()) })
}

/// Negotiated suite and group (IANA ids).
///
/// # Safety
/// `s` live; out-pointers valid writable `uint16_t`s.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_negotiated(s: *mut CmTlsSession, suite: *mut u16, group: *mut u16) -> i32 {
    guard(|| {
        // SAFETY: caller contract.
        let (a, b) = unsafe { session(s) }?.negotiated()?;
        // SAFETY: caller contract on the out-pointers.
        unsafe {
            write(suite, a)?;
            write(group, b)
        }
    })
}

/// Public-key hash captured by a probe session (32 bytes).
///
/// # Safety
/// `s` live; `out` writable for 32 bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_captured_pin(s: *mut CmTlsSession, out: *mut u8) -> i32 {
    guard(|| {
        // SAFETY: caller contract.
        let hash = unsafe { session(s) }?.captured().ok_or(CmStatus::NeedMoreData)?;
        // SAFETY: caller contract on `out`.
        unsafe { output(out, crypto::SHA256_LEN) }?.copy_from_slice(&hash);
        Ok(())
    })
}

/// Queues close_notify.
///
/// # Safety
/// `s` live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_close(s: *mut CmTlsSession) -> i32 {
    guard(|| {
        // SAFETY: caller contract.
        unsafe { session(s) }?.close();
        Ok(())
    })
}

/// Frees a session and wipes its keys.
///
/// # Safety
/// `s` null or a handle not used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cm_tls_session_free(s: *mut CmTlsSession) {
    if !s.is_null() {
        // SAFETY: pointer from `Box::into_raw`, freed once.
        drop(unsafe { Box::from_raw(s) });
    }
}
