// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
//! Parsers for every byte that originates on the phone.
#![forbid(unsafe_code)]

pub mod adb_devices;
pub mod adb_wire;
pub mod annexb;
pub mod control;
pub mod display_info;
pub mod input;
pub mod keymap;
pub mod scrcpy;
