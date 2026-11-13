// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
//! adb command allowlist. Every adb invocation the Mac app makes is checked here first: the argv must match
//! one fixed template exactly, every variable slot has a strict grammar, and nothing else is allowed.
//! Values that reach the phone's shell are numbers, hex or fixed words, so shell injection is impossible.
#![forbid(unsafe_code)]

use crate::policy::net;
use crate::status::{CmResult, CmStatus};

/// Caller asserts the target device is connected over USB.
pub const FLAG_TRANSPORT_USB: u32 = 1;
/// Caller asserts the user confirmed this action in a dialog.
pub const FLAG_USER_CONFIRMED: u32 = 1 << 1;

/// Fixed on-device path of the forked scrcpy server.
pub const REMOTE_SERVER_PATH: &str = "/data/local/tmp/carbonmirror-server.jar";
/// Fixed on-device path of the Rust core for the server.
pub const REMOTE_CORE_LIB_PATH: &str = "/data/local/tmp/libcarbon_core.so";
/// The phone server's record of the pinned Mac identity (removed only by "Create new key").
pub const REMOTE_MAC_PIN_PATH: &str = "/data/local/tmp/carbonmirror-mac.pin";
/// Bundled file names; local push/install paths must end in exactly these.
pub const LOCAL_SERVER_NAME: &str = "carbonmirror-server";
pub const LOCAL_CORE_LIB_NAME: &str = "libcarbon_core.so";
pub const LOCAL_COMPANION_NAME: &str = "CarbonMirrorCompanion.apk";
/// Companion package and the one permission the Mac may grant it.
pub const COMPANION_PACKAGE: &str = "com.nomadicrebel.carbonmirror.companion";
pub const COMPANION_PERMISSION: &str = "android.permission.WRITE_SECURE_SETTINGS";
/// Server entry point inside the jar.
pub const SERVER_CLASS: &str = "com.genymobile.scrcpy.Server";

const MAX_ARG_LEN: usize = 1024;
const MAX_ARGS: usize = 40;
const MAX_SERIAL_LEN: usize = 128;

/// Serial: adb USB serials, `ip:port`, `[v6%zone]:port` and mDNS names like
/// `adb-XXXX-yyyy._adb-tls-connect._tcp`. Must not look like an option.
fn check_serial(s: &str) -> CmResult<()> {
    let ok = !s.is_empty()
        && s.len() <= MAX_SERIAL_LEN
        && !s.starts_with('-')
        && s.bytes().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b':' | b'-' | b'[' | b']' | b'%'));
    if ok { Ok(()) } else { Err(CmStatus::AdbBadArgument) }
}

/// True when a serial names a network transport rather than USB.
pub fn serial_is_wireless(s: &str) -> bool {
    s.contains(':') || s.contains("._adb-tls-connect._tcp")
}

fn check_local_path(path: &str, file_name: &str) -> CmResult<()> {
    let ok = path.starts_with('/')
        && path.ends_with(&format!("/{file_name}"))
        && path.split('/').all(|c| c != ".." && c != ".")
        && !path.contains("//")
        && path.chars().all(|c| !c.is_control());
    if ok { Ok(()) } else { Err(CmStatus::AdbBadArgument) }
}

fn check_pairing_secret(s: &str) -> CmResult<()> {
    let six_digit = s.len() == 6 && s.bytes().all(|b| b.is_ascii_digit());
    let qr_password = (16..=64).contains(&s.len()) && s.bytes().all(|b| b.is_ascii_alphanumeric());
    if six_digit || qr_password { Ok(()) } else { Err(CmStatus::AdbBadArgument) }
}

fn parse_uint(v: &str, min: u64, max: u64) -> CmResult<u64> {
    if v.is_empty() || v.len() > 10 || !v.bytes().all(|b| b.is_ascii_digit()) || (v.len() > 1 && v.starts_with('0')) {
        return Err(CmStatus::AdbBadArgument);
    }
    let n: u64 = v.parse().map_err(|_| CmStatus::AdbBadArgument)?;
    if (min..=max).contains(&n) { Ok(n) } else { Err(CmStatus::AdbBadArgument) }
}

/// Longest Unix-socket path macOS accepts (`sun_path` is 104 bytes including the terminator).
pub const MAX_SOCKET_PATH: usize = 103;

/// Local end of `adb forward`: only a Unix-domain socket file CarbonMirror owns
/// (`localfilesystem:<absolute dir>/cm-f<16 lower-case hex>`). TCP is refused, so no forwarded port is ever
/// reachable over the network or by other local users.
fn check_local_forward(spec: &str) -> CmResult<()> {
    let path = spec.strip_prefix("localfilesystem:").ok_or(CmStatus::AdbBadArgument)?;
    let (dir, name) = path.rsplit_once('/').ok_or(CmStatus::AdbBadArgument)?;
    let name_ok = name.len() == 20
        && name.starts_with("cm-f")
        && name.bytes().skip(4).all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b));
    let dir_ok = dir.starts_with('/')
        && dir.bytes().all(|b| b.is_ascii_alphanumeric() || b"/._-".contains(&b))
        && !dir.split('/').any(|c| c == "." || c == "..");
    if name_ok && dir_ok && path.len() <= MAX_SOCKET_PATH { Ok(()) } else { Err(CmStatus::AdbBadArgument) }
}

fn check_scid(v: &str) -> CmResult<()> {
    let ok = v.len() == 8 && v.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) && v.as_bytes()[0] < b'8';
    if ok { Ok(()) } else { Err(CmStatus::AdbBadArgument) }
}

fn check_remote_forward(spec: &str) -> CmResult<()> {
    check_scid(spec.strip_prefix("localabstract:scrcpy_").ok_or(CmStatus::AdbBadArgument)?)
}

fn one_of(v: &str, allowed: &[&str]) -> CmResult<()> {
    if allowed.contains(&v) { Ok(()) } else { Err(CmStatus::AdbBadArgument) }
}

/// One `key=value` server parameter. Only these keys, only these value grammars.
fn check_server_param(param: &str) -> CmResult<&str> {
    let (key, value) = param.split_once('=').ok_or(CmStatus::AdbBadArgument)?;
    let bools = ["true", "false"];
    match key {
        "scid" => check_scid(value)?,
        "log_level" => one_of(value, &["verbose", "debug", "info", "warn", "error"])?,
        "audio" => one_of(value, &["false"])?,
        "video" | "control" | "tunnel_forward" | "send_device_meta" | "send_frame_meta" | "send_dummy_byte"
        | "send_stream_meta" | "cleanup" | "power_on" => one_of(value, &["true"])?,
        "clipboard_autosync" | "stay_awake" => one_of(value, &bools)?,
        "video_codec" => one_of(value, &["h264", "h265"])?,
        "video_source" => one_of(value, &["display"])?,
        "display_id" => one_of(value, &["0"])?,
        "max_size" => parse_uint(value, 0, 4096).map(|_| ())?,
        "max_fps" => parse_uint(value, 1, 240).map(|_| ())?,
        "video_bit_rate" => parse_uint(value, 100_000, 100_000_000).map(|_| ())?,
        _ => return Err(CmStatus::AdbBadArgument),
    }
    Ok(key)
}

fn check_version(v: &str) -> CmResult<()> {
    let parts: Vec<&str> = v.split('.').collect();
    let ok = (2..=3).contains(&parts.len()) && parts.iter().all(|p| parse_uint(p, 0, 999).is_ok());
    if ok { Ok(()) } else { Err(CmStatus::AdbBadArgument) }
}

fn check_start_server(rest: &[&str]) -> CmResult<()> {
    let [classpath, app_process, root, class, version, params @ ..] = rest else {
        return Err(CmStatus::AdbBadArgument);
    };
    if *classpath != format!("CLASSPATH={REMOTE_SERVER_PATH}") || *app_process != "app_process" || *root != "/" || *class != SERVER_CLASS {
        return Err(CmStatus::AdbBadArgument);
    }
    check_version(version)?;
    let mut seen: Vec<&str> = Vec::with_capacity(params.len());
    for p in params {
        let key = check_server_param(p)?;
        if seen.contains(&key) {
            return Err(CmStatus::AdbBadArgument);
        }
        seen.push(key);
    }
    if !seen.contains(&"scid") || !seen.contains(&"audio") {
        return Err(CmStatus::AdbBadArgument);
    }
    Ok(())
}

fn check_shell(rest: &[&str]) -> CmResult<()> {
    match rest {
        ["settings", "put", "global", "adb_wifi_enabled", "0"] => Ok(()),
        ["pm", "grant", pkg, perm] if *pkg == COMPANION_PACKAGE && *perm == COMPANION_PERMISSION => Ok(()),
        ["dumpsys", "display"] => Ok(()),
        ["rm", "-f", a, b] if *a == REMOTE_SERVER_PATH && *b == REMOTE_CORE_LIB_PATH => Ok(()),
        ["rm", "-f", a] if *a == REMOTE_MAC_PIN_PATH => Ok(()),
        [first, ..] if first.starts_with("CLASSPATH=") => check_start_server(rest),
        _ => Err(CmStatus::AdbUnknownCommand),
    }
}

fn check_device_command(serial: &str, rest: &[&str], flags: u32) -> CmResult<()> {
    check_serial(serial)?;
    match rest {
        ["forward", "--remove", local] => check_local_forward(local),
        ["forward", local, remote] => {
            check_local_forward(local)?;
            check_remote_forward(remote)
        }
        ["push", local, remote] if *remote == REMOTE_SERVER_PATH => check_local_path(local, LOCAL_SERVER_NAME),
        ["push", local, remote] if *remote == REMOTE_CORE_LIB_PATH => check_local_path(local, LOCAL_CORE_LIB_NAME),
        ["shell", cmd @ ..] => check_shell(cmd),
        ["install", "-r", path] => {
            check_local_path(path, LOCAL_COMPANION_NAME)?;
            check_usb_confirmed(serial, flags)
        }
        // Replacing a companion signed with another key (no in-place update possible): same rules as install.
        ["uninstall", pkg] if *pkg == COMPANION_PACKAGE => check_usb_confirmed(serial, flags),
        _ => Err(CmStatus::AdbUnknownCommand),
    }
}

/// Package changes on the phone: USB only (never over the network) and only after the user confirmed.
fn check_usb_confirmed(serial: &str, flags: u32) -> CmResult<()> {
    if flags & FLAG_TRANSPORT_USB == 0 || serial_is_wireless(serial) {
        return Err(CmStatus::AdbInstallNeedsUsb);
    }
    if flags & FLAG_USER_CONFIRMED == 0 {
        return Err(CmStatus::AdbInstallNeedsConfirmation);
    }
    Ok(())
}

/// Validates one adb argv (without the adb binary itself) against the allowlist.
pub fn validate(argv: &[&str], flags: u32) -> CmResult<()> {
    if argv.is_empty() {
        return Err(CmStatus::AdbEmpty);
    }
    if argv.len() > MAX_ARGS || argv.iter().any(|a| a.len() > MAX_ARG_LEN || a.contains('\0')) {
        return Err(CmStatus::AdbBadArgument);
    }
    match argv {
        ["start-server"] | ["kill-server"] | ["devices", "-l"] | ["track-devices", "-l"] => Ok(()),
        ["connect", hp] | ["disconnect", hp] => net::parse_host_port(hp).map(|_| ()),
        ["pair", hp, secret] => {
            net::parse_host_port(hp)?;
            check_pairing_secret(secret)
        }
        ["-s", serial, rest @ ..] => check_device_command(serial, rest, flags),
        _ => Err(CmStatus::AdbUnknownCommand),
    }
}

/// Splits a NUL-separated argv buffer (as passed over the C ABI; a trailing NUL is optional).
pub fn split_argv(buf: &str) -> Vec<&str> {
    let trimmed = buf.strip_suffix('\0').unwrap_or(buf);
    if trimmed.is_empty() { Vec::new() } else { trimmed.split('\0').collect() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn duplicate_server_params_refused() {
        let argv = [
            "-s", "SERIAL1", "shell", "CLASSPATH=/data/local/tmp/carbonmirror-server.jar", "app_process", "/",
            SERVER_CLASS, "3.3", "scid=0badcafe", "audio=false", "audio=false",
        ];
        assert_eq!(validate(&argv, 0), Err(CmStatus::AdbBadArgument));
    }

    #[test]
    fn split_handles_trailing_nul() {
        assert_eq!(split_argv("devices\0-l\0"), vec!["devices", "-l"]);
        assert!(split_argv("").is_empty());
    }
}
