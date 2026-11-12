// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
//! Keyboard mapping for the two typing modes (spec 8.2.3): macOS virtual key codes → USB HID usages for the
//! UHID "Hardware keyboard", and → Android key codes for "Phone keyboard" (non-text keys and shortcuts).
//! ⌘ is sent as Ctrl so Mac habits (⌘C/⌘V/⌘A/⌘Z) do the same thing on Android.
#![forbid(unsafe_code)]

/// NSEvent.ModifierFlags raw bits.
pub const MAC_SHIFT: u32 = 1 << 17;
pub const MAC_CONTROL: u32 = 1 << 18;
pub const MAC_OPTION: u32 = 1 << 19;
pub const MAC_COMMAND: u32 = 1 << 20;

/// HID modifier byte bits.
const HID_LEFT_CTRL: u8 = 0x01;
const HID_LEFT_SHIFT: u8 = 0x02;
const HID_LEFT_ALT: u8 = 0x04;

/// Android meta-state bits.
const META_SHIFT: i32 = 0x01 | 0x40;
const META_ALT: i32 = 0x02 | 0x10;
const META_CTRL: i32 = 0x1000 | 0x2000;

/// HID boot-keyboard report: 1 modifier byte, 1 reserved, 6 key slots.
pub const HID_REPORT_LEN: usize = 8;
const HID_ERROR_ROLLOVER: u8 = 0x01;

/// Report descriptor of the virtual keyboard (boot keyboard with LED output report).
pub const HID_KEYBOARD_DESCRIPTOR: [u8; 63] = [
    0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95,
    0x08, 0x81, 0x02, 0x75, 0x08, 0x95, 0x01, 0x81, 0x01, 0x05, 0x08, 0x19, 0x01, 0x29, 0x05, 0x75, 0x01, 0x95, 0x05,
    0x91, 0x02, 0x75, 0x03, 0x95, 0x01, 0x91, 0x01, 0x05, 0x07, 0x19, 0x00, 0x29, 0x65, 0x15, 0x00, 0x25, 0x65, 0x75,
    0x08, 0x95, 0x06, 0x81, 0x00, 0xC0,
];

/// macOS key codes of modifier keys (they live in the modifier byte, never in key slots).
fn is_mac_modifier(code: u16) -> bool {
    (0x36..=0x3F).contains(&code)
}

/// macOS virtual key code → HID usage (keyboard page). `None` for keys the virtual keyboard lacks.
pub fn mac_to_hid(code: u16) -> Option<u8> {
    Some(match code {
        0x00 => 0x04, // A
        0x0B => 0x05, // B
        0x08 => 0x06, // C
        0x02 => 0x07, // D
        0x0E => 0x08, // E
        0x03 => 0x09, // F
        0x05 => 0x0A, // G
        0x04 => 0x0B, // H
        0x22 => 0x0C, // I
        0x26 => 0x0D, // J
        0x28 => 0x0E, // K
        0x25 => 0x0F, // L
        0x2E => 0x10, // M
        0x2D => 0x11, // N
        0x1F => 0x12, // O
        0x23 => 0x13, // P
        0x0C => 0x14, // Q
        0x0F => 0x15, // R
        0x01 => 0x16, // S
        0x11 => 0x17, // T
        0x20 => 0x18, // U
        0x09 => 0x19, // V
        0x0D => 0x1A, // W
        0x07 => 0x1B, // X
        0x10 => 0x1C, // Y
        0x06 => 0x1D, // Z
        0x12 => 0x1E, // 1
        0x13 => 0x1F, // 2
        0x14 => 0x20, // 3
        0x15 => 0x21, // 4
        0x17 => 0x22, // 5
        0x16 => 0x23, // 6
        0x1A => 0x24, // 7
        0x1C => 0x25, // 8
        0x19 => 0x26, // 9
        0x1D => 0x27, // 0
        0x24 => 0x28, // Return
        0x35 => 0x29, // Escape
        0x33 => 0x2A, // Delete (backspace)
        0x30 => 0x2B, // Tab
        0x31 => 0x2C, // Space
        0x1B => 0x2D, // -
        0x18 => 0x2E, // =
        0x21 => 0x2F, // [
        0x1E => 0x30, // ]
        0x2A => 0x31, // \
        0x29 => 0x33, // ;
        0x27 => 0x34, // '
        0x32 => 0x35, // `
        0x2B => 0x36, // ,
        0x2F => 0x37, // .
        0x2C => 0x38, // /
        0x39 => 0x39, // Caps Lock
        0x7A => 0x3A, // F1
        0x78 => 0x3B, // F2
        0x63 => 0x3C, // F3
        0x76 => 0x3D, // F4
        0x60 => 0x3E, // F5
        0x61 => 0x3F, // F6
        0x62 => 0x40, // F7
        0x64 => 0x41, // F8
        0x65 => 0x42, // F9
        0x6D => 0x43, // F10
        0x67 => 0x44, // F11
        0x6F => 0x45, // F12
        0x73 => 0x4A, // Home
        0x74 => 0x4B, // Page Up
        0x75 => 0x4C, // Forward Delete
        0x77 => 0x4D, // End
        0x79 => 0x4E, // Page Down
        0x7C => 0x4F, // Right
        0x7B => 0x50, // Left
        0x7D => 0x51, // Down
        0x7E => 0x52, // Up
        0x47 => 0x53, // Keypad Clear → Num Lock
        0x4B => 0x54, // Keypad /
        0x43 => 0x55, // Keypad *
        0x4E => 0x56, // Keypad -
        0x45 => 0x57, // Keypad +
        0x4C => 0x58, // Keypad Enter
        0x53 => 0x59, // Keypad 1
        0x54 => 0x5A, // Keypad 2
        0x55 => 0x5B, // Keypad 3
        0x56 => 0x5C, // Keypad 4
        0x57 => 0x5D, // Keypad 5
        0x58 => 0x5E, // Keypad 6
        0x59 => 0x5F, // Keypad 7
        0x5B => 0x60, // Keypad 8
        0x5C => 0x61, // Keypad 9
        0x52 => 0x62, // Keypad 0
        0x41 => 0x63, // Keypad .
        0x0A => 0x64, // ISO § key (non-US \)
        _ => return None,
    })
}

/// HID modifier byte for NSEvent modifier flags (⌘ and ⌃ both → Ctrl).
pub fn hid_modifiers(mac_flags: u32) -> u8 {
    let mut m = 0;
    if mac_flags & (MAC_CONTROL | MAC_COMMAND) != 0 {
        m |= HID_LEFT_CTRL;
    }
    if mac_flags & MAC_SHIFT != 0 {
        m |= HID_LEFT_SHIFT;
    }
    if mac_flags & MAC_OPTION != 0 {
        m |= HID_LEFT_ALT;
    }
    m
}

/// Builds the 8-byte report for the modifier flags and the currently held macOS key codes.
/// More than six held keys report "error roll-over", as a real keyboard does.
pub fn hid_report(mac_flags: u32, held: &[u16]) -> [u8; HID_REPORT_LEN] {
    let mut report = [0u8; HID_REPORT_LEN];
    report[0] = hid_modifiers(mac_flags);
    let usages = held.iter().filter(|&&c| !is_mac_modifier(c)).filter_map(|&c| mac_to_hid(c));
    let mut count = 0;
    for usage in usages {
        if report[2..2 + count].contains(&usage) {
            continue;
        }
        if count == 6 {
            report[2..].fill(HID_ERROR_ROLLOVER);
            return report;
        }
        report[2 + count] = usage;
        count += 1;
    }
    report
}

/// macOS key code → Android key code for "Phone keyboard" mode.
pub fn mac_to_android(code: u16) -> Option<i32> {
    let hid = mac_to_hid(code)?;
    Some(match hid {
        0x04..=0x1D => 29 + i32::from(hid - 0x04), // KEYCODE_A … KEYCODE_Z
        0x1E..=0x26 => 8 + i32::from(hid - 0x1E),  // KEYCODE_1 … KEYCODE_9
        0x27 => 7,                                 // KEYCODE_0
        0x28 => 66,                                // ENTER
        0x29 => 111,                               // ESCAPE
        0x2A => 67,                                // DEL (backspace)
        0x2B => 61,                                // TAB
        0x2C => 62,                                // SPACE
        0x2D => 69,                                // MINUS
        0x2E => 70,                                // EQUALS
        0x2F => 71,                                // LEFT_BRACKET
        0x30 => 72,                                // RIGHT_BRACKET
        0x31 | 0x64 => 73,                         // BACKSLASH
        0x33 => 74,                                // SEMICOLON
        0x34 => 75,                                // APOSTROPHE
        0x35 => 68,                                // GRAVE
        0x36 => 55,                                // COMMA
        0x37 => 56,                                // PERIOD
        0x38 => 76,                                // SLASH
        0x39 => 115,                               // CAPS_LOCK
        0x3A..=0x45 => 131 + i32::from(hid - 0x3A), // F1 … F12
        0x4A => 122,                               // MOVE_HOME
        0x4B => 92,                                // PAGE_UP
        0x4C => 112,                               // FORWARD_DEL
        0x4D => 123,                               // MOVE_END
        0x4E => 93,                                // PAGE_DOWN
        0x4F => 22,                                // DPAD_RIGHT
        0x50 => 21,                                // DPAD_LEFT
        0x51 => 20,                                // DPAD_DOWN
        0x52 => 19,                                // DPAD_UP
        0x53 => 143,                               // NUM_LOCK
        0x54 => 154,                               // NUMPAD_DIVIDE
        0x55 => 155,                               // NUMPAD_MULTIPLY
        0x56 => 156,                               // NUMPAD_SUBTRACT
        0x57 => 157,                               // NUMPAD_ADD
        0x58 => 160,                               // NUMPAD_ENTER
        0x59..=0x61 => 145 + i32::from(hid - 0x59), // NUMPAD_1 … NUMPAD_9
        0x62 => 144,                               // NUMPAD_0
        0x63 => 158,                               // NUMPAD_DOT
        _ => return None,
    })
}

/// Android meta state for NSEvent modifier flags.
pub fn android_meta(mac_flags: u32) -> i32 {
    let mut m = 0;
    if mac_flags & MAC_SHIFT != 0 {
        m |= META_SHIFT;
    }
    if mac_flags & MAC_OPTION != 0 {
        m |= META_ALT;
    }
    if mac_flags & (MAC_CONTROL | MAC_COMMAND) != 0 {
        m |= META_CTRL;
    }
    m
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn letters_and_digits() {
        assert_eq!(mac_to_hid(0x00), Some(0x04));
        assert_eq!(mac_to_android(0x00), Some(29));
        assert_eq!(mac_to_android(0x06), Some(54));
        assert_eq!(mac_to_android(0x1D), Some(7));
        assert_eq!(mac_to_android(0x19), Some(16));
    }

    #[test]
    fn report_rolls_over_after_six_keys() {
        let r = hid_report(MAC_SHIFT, &[0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03]);
        assert_eq!(r, [0x02, 0, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09]);
        let r = hid_report(0, &[0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05]);
        assert_eq!(&r[2..], &[1; 6]);
        assert_eq!(hid_report(MAC_COMMAND, &[0x37, 0x08]), [0x01, 0, 0x06, 0, 0, 0, 0, 0]);
    }

    #[test]
    fn every_hid_usage_is_inside_the_descriptor_range() {
        for code in 0u16..=0x7F {
            if let Some(u) = mac_to_hid(code) {
                assert!(u <= 0x65, "usage {u:#x} outside logical maximum");
            }
        }
    }
}
