//! C ABI — the only module allowed to use `unsafe`. Every function takes `(ptr, len)` byte slices and
//! out-pointers, returns a [`CmStatus`] code, and catches panics so none can cross the boundary.

use std::panic::{AssertUnwindSafe, catch_unwind};

use crate::policy::{adb, failure, net, size};
use crate::protocol::adb_devices;
use crate::status::{CmResult, CmStatus};
use crate::{crypto, ABI_VERSION};

pub use size::{CmInsets, CmSize};

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
