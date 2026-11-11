//! scrcpy wire framing for the two streams the Mac reads from the phone: the video socket (device meta,
//! codec id, session and frame headers) and the control socket's device messages. Every length is bounded
//! before it is trusted; anything unknown or out of range ends the session (`ParseMalformed`/`ParseTooLarge`).
//! Parsers never copy: they return sizes and offsets into the caller's buffer.
#![forbid(unsafe_code)]

use crate::status::{CmResult, CmStatus};

/// Device-name field at the start of the first socket.
pub const DEVICE_NAME_LEN: usize = 64;
/// Codec id "h264" / "h265" (big-endian ASCII).
pub const CODEC_H264: u32 = u32::from_be_bytes(*b"h264");
pub const CODEC_H265: u32 = u32::from_be_bytes(*b"h265");
/// Video packet header: 8-byte PTS + flags, 4-byte size (session packets: flags, width, height).
pub const VIDEO_HEADER_LEN: usize = 12;
/// Largest video packet accepted (a 1344×2992 H.264 keyframe at 32 Mbit/s is far smaller).
pub const MAX_VIDEO_PACKET: u32 = 8 * 1024 * 1024;
/// Largest frame dimension accepted from a session packet.
pub const MAX_DIMENSION: u32 = 8192;
/// Clipboard text cap in both directions (spec A7: 1 MB).
pub const MAX_CLIPBOARD_BYTES: usize = 1024 * 1024;
/// Largest UHID output report accepted from the phone.
pub const MAX_UHID_OUTPUT: usize = 64;

const FLAG_SESSION: u64 = 1 << 63;
const FLAG_CONFIG: u64 = 1 << 62;
const FLAG_KEY_FRAME: u64 = 1 << 61;
const PTS_MASK: u64 = FLAG_KEY_FRAME - 1;

/// Device-message types the Mac accepts (everything else ends the session).
pub const DEVICE_MSG_CLIPBOARD: u8 = 0;
pub const DEVICE_MSG_ACK_CLIPBOARD: u8 = 1;
pub const DEVICE_MSG_UHID_OUTPUT: u8 = 2;
/// CarbonMirror fork: fixed-size battery status (level 0–100, charging 0/1).
pub const DEVICE_MSG_BATTERY: u8 = 0x40;

/// Video codec announced by the server.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum VideoCodec {
    H264 = 1,
    H265 = 2,
}

/// Device name from the 64-byte, NUL-padded meta field (UTF-8; anything after the first NUL is ignored).
pub fn parse_device_name(buf: &[u8]) -> CmResult<&str> {
    let field = buf.get(..DEVICE_NAME_LEN).ok_or(CmStatus::NeedMoreData)?;
    let end = field.iter().position(|&b| b == 0).unwrap_or(DEVICE_NAME_LEN);
    let name = std::str::from_utf8(&field[..end]).map_err(|_| CmStatus::ParseMalformed)?;
    if name.chars().any(char::is_control) {
        return Err(CmStatus::ParseMalformed);
    }
    Ok(name)
}

/// Codec id from the 4 bytes after the device meta. 0/1 mean "stream disabled"/"server error".
pub fn parse_codec(buf: &[u8]) -> CmResult<VideoCodec> {
    let raw = read_u32(buf, 0)?;
    match raw {
        CODEC_H264 => Ok(VideoCodec::H264),
        CODEC_H265 => Ok(VideoCodec::H265),
        _ => Err(CmStatus::ParseMalformed),
    }
}

/// One video header.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VideoHeader {
    /// New capture session: frame size changed (rotation, resize). No payload follows.
    Session { width: u32, height: u32 },
    /// Codec configuration (SPS/PPS/VPS), `size` payload bytes follow.
    Config { size: u32 },
    /// Encoded frame, `size` payload bytes follow.
    Frame { pts: u64, key_frame: bool, size: u32 },
}

/// Parses the 12-byte header at the start of `buf`.
pub fn parse_video_header(buf: &[u8]) -> CmResult<VideoHeader> {
    if buf.len() < VIDEO_HEADER_LEN {
        return Err(CmStatus::NeedMoreData);
    }
    let first = read_u64(buf, 0)?;
    if first & FLAG_SESSION != 0 {
        let flags = read_u32(buf, 0)?;
        if flags & !0x8000_0001 != 0 {
            return Err(CmStatus::ParseMalformed);
        }
        let width = read_u32(buf, 4)?;
        let height = read_u32(buf, 8)?;
        if !(1..=MAX_DIMENSION).contains(&width) || !(1..=MAX_DIMENSION).contains(&height) {
            return Err(CmStatus::ParseMalformed);
        }
        return Ok(VideoHeader::Session { width, height });
    }
    let size = read_u32(buf, 8)?;
    if size == 0 {
        return Err(CmStatus::ParseMalformed);
    }
    if size > MAX_VIDEO_PACKET {
        return Err(CmStatus::ParseTooLarge);
    }
    if first & FLAG_CONFIG != 0 {
        if first != FLAG_CONFIG {
            return Err(CmStatus::ParseMalformed);
        }
        return Ok(VideoHeader::Config { size });
    }
    Ok(VideoHeader::Frame { pts: first & PTS_MASK, key_frame: first & FLAG_KEY_FRAME != 0, size })
}

/// One message from the phone's control socket. Payloads are offsets into the parsed buffer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeviceMessage {
    /// Plain-text clipboard (already checked to be UTF-8 and ≤ 1 MB).
    Clipboard { offset: usize, len: usize },
    AckClipboard { sequence: u64 },
    UhidOutput { id: u16, offset: usize, len: usize },
    Battery { level: u8, charging: bool },
}

/// Parses one device message at the start of `buf`; returns it and the bytes it used.
pub fn parse_device_message(buf: &[u8]) -> CmResult<(DeviceMessage, usize)> {
    let kind = *buf.first().ok_or(CmStatus::NeedMoreData)?;
    match kind {
        DEVICE_MSG_CLIPBOARD => {
            let len = read_u32(buf, 1)? as usize;
            if len > MAX_CLIPBOARD_BYTES {
                return Err(CmStatus::ParseTooLarge);
            }
            let text = buf.get(5..5 + len).ok_or(CmStatus::NeedMoreData)?;
            std::str::from_utf8(text).map_err(|_| CmStatus::ParseMalformed)?;
            Ok((DeviceMessage::Clipboard { offset: 5, len }, 5 + len))
        }
        DEVICE_MSG_ACK_CLIPBOARD => Ok((DeviceMessage::AckClipboard { sequence: read_u64(buf, 1)? }, 9)),
        DEVICE_MSG_UHID_OUTPUT => {
            let id = read_u16(buf, 1)?;
            let len = read_u16(buf, 3)? as usize;
            if len > MAX_UHID_OUTPUT {
                return Err(CmStatus::ParseTooLarge);
            }
            buf.get(5..5 + len).ok_or(CmStatus::NeedMoreData)?;
            Ok((DeviceMessage::UhidOutput { id, offset: 5, len }, 5 + len))
        }
        DEVICE_MSG_BATTERY => {
            let fields = buf.get(1..3).ok_or(CmStatus::NeedMoreData)?;
            let (level, charging) = (fields[0], fields[1]);
            if level > 100 || charging > 1 {
                return Err(CmStatus::ParseMalformed);
            }
            Ok((DeviceMessage::Battery { level, charging: charging == 1 }, 3))
        }
        _ => Err(CmStatus::ParseMalformed),
    }
}

fn read_u16(buf: &[u8], at: usize) -> CmResult<u16> {
    let b = buf.get(at..at + 2).ok_or(CmStatus::NeedMoreData)?;
    Ok(u16::from_be_bytes([b[0], b[1]]))
}

fn read_u32(buf: &[u8], at: usize) -> CmResult<u32> {
    let b = buf.get(at..at + 4).ok_or(CmStatus::NeedMoreData)?;
    Ok(u32::from_be_bytes([b[0], b[1], b[2], b[3]]))
}

fn read_u64(buf: &[u8], at: usize) -> CmResult<u64> {
    let b = buf.get(at..at + 8).ok_or(CmStatus::NeedMoreData)?;
    let mut a = [0u8; 8];
    a.copy_from_slice(b);
    Ok(u64::from_be_bytes(a))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_header_round_trip() {
        let mut h = [0u8; 12];
        h[..8].copy_from_slice(&(FLAG_KEY_FRAME | 1234).to_be_bytes());
        h[8..].copy_from_slice(&5000u32.to_be_bytes());
        assert_eq!(parse_video_header(&h), Ok(VideoHeader::Frame { pts: 1234, key_frame: true, size: 5000 }));
    }

    #[test]
    fn session_header() {
        let mut h = [0u8; 12];
        h[..4].copy_from_slice(&0x8000_0000u32.to_be_bytes());
        h[4..8].copy_from_slice(&1344u32.to_be_bytes());
        h[8..].copy_from_slice(&2992u32.to_be_bytes());
        assert_eq!(parse_video_header(&h), Ok(VideoHeader::Session { width: 1344, height: 2992 }));
    }

    #[test]
    fn battery_bounds() {
        assert_eq!(parse_device_message(&[0x40, 84, 1]), Ok((DeviceMessage::Battery { level: 84, charging: true }, 3)));
        assert_eq!(parse_device_message(&[0x40, 101, 0]), Err(CmStatus::ParseMalformed));
        assert_eq!(parse_device_message(&[0x40, 50, 2]), Err(CmStatus::ParseMalformed));
        assert_eq!(parse_device_message(&[0x40, 50]), Err(CmStatus::NeedMoreData));
    }
}
