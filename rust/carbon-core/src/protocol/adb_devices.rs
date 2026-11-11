//! Parser for `adb devices -l` / `adb track-devices -l` output. Model names come from the phone, so every
//! field is checked against a strict grammar; lines that fail are dropped, oversize input is refused.
#![forbid(unsafe_code)]

use crate::status::{CmResult, CmStatus};

/// Largest device-list payload accepted (adb's own limit is far smaller in practice).
pub const MAX_LIST_BYTES: usize = 64 * 1024;
/// Most devices reported in one list.
pub const MAX_DEVICES: usize = 32;
const MAX_FIELD_LEN: usize = 128;
const STATES: [&str; 9] =
    ["device", "offline", "unauthorized", "authorizing", "connecting", "recovery", "sideload", "bootloader", "host"];

/// How the device is attached.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Link {
    Usb,
    Wireless,
}

/// One validated device line.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceEntry {
    pub serial: String,
    pub state: String,
    pub model: String,
    pub transport_id: u32,
    pub link: Link,
}

fn token_ok(s: &str, extra: &[u8]) -> bool {
    !s.is_empty() && s.len() <= MAX_FIELD_LEN && s.bytes().all(|b| b.is_ascii_alphanumeric() || extra.contains(&b))
}

fn parse_line(line: &str) -> Option<DeviceEntry> {
    let mut fields = line.split_ascii_whitespace();
    let serial = fields.next()?;
    let state = fields.next()?;
    if !token_ok(serial, b"._:-[]%") || serial.starts_with('-') || !STATES.contains(&state) {
        return None;
    }
    let mut model = String::new();
    let mut transport_id = 0u32;
    let mut usb = false;
    for kv in fields {
        let (k, v) = kv.split_once(':')?;
        match k {
            "model" if token_ok(v, b"_-.") => model = v.to_owned(),
            "transport_id" => transport_id = v.parse().ok().filter(|_| v.len() <= 10)?,
            "usb" if token_ok(v, b"-.") => usb = true,
            "product" | "device" | "features" if token_ok(v, b"_-.,") => {}
            _ => return None,
        }
    }
    let wireless = serial.contains(':') || serial.contains("._adb-tls-connect._tcp");
    let link = if usb && !wireless { Link::Usb } else { Link::Wireless };
    Some(DeviceEntry { serial: serial.to_owned(), state: state.to_owned(), model, transport_id, link })
}

/// Parses the text of a device list. The `List of devices attached` header and blank lines are skipped.
pub fn parse_devices(bytes: &[u8]) -> CmResult<Vec<DeviceEntry>> {
    if bytes.len() > MAX_LIST_BYTES {
        return Err(CmStatus::ParseTooLarge);
    }
    let text = std::str::from_utf8(bytes).map_err(|_| CmStatus::InvalidUtf8)?;
    let mut out = Vec::new();
    for line in text.lines() {
        if line.trim().is_empty() || line.starts_with("List of devices") || line.starts_with("* daemon") {
            continue;
        }
        if let Some(entry) = parse_line(line) {
            if out.len() == MAX_DEVICES {
                return Err(CmStatus::ParseTooLarge);
            }
            out.push(entry);
        }
    }
    Ok(out)
}

/// Normalised, trusted form handed to Swift: one `serial\tstate\tmodel\ttransport_id\tusb|wireless` per line.
pub fn normalise(entries: &[DeviceEntry]) -> String {
    let mut s = String::new();
    for e in entries {
        let link = if e.link == Link::Usb { "usb" } else { "wireless" };
        s.push_str(&format!("{}\t{}\t{}\t{}\t{}\n", e.serial, e.state, e.model, e.transport_id, link));
    }
    s
}

/// `track-devices` framing: four ASCII hex digits of length, then the payload.
/// Returns `(payload_offset, payload_len)` once the whole frame is buffered.
pub fn track_frame(buf: &[u8]) -> CmResult<(usize, usize)> {
    let Some(header) = buf.get(..4) else { return Err(CmStatus::NeedMoreData) };
    if !header.iter().all(u8::is_ascii_hexdigit) {
        return Err(CmStatus::ParseMalformed);
    }
    let hex = std::str::from_utf8(header).map_err(|_| CmStatus::ParseMalformed)?;
    let len = usize::from_str_radix(hex, 16).map_err(|_| CmStatus::ParseMalformed)?;
    if len > MAX_LIST_BYTES {
        return Err(CmStatus::ParseTooLarge);
    }
    if buf.len() - 4 < len { Err(CmStatus::NeedMoreData) } else { Ok((4, len)) }
}
