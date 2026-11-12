// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
//! Failure class → UI state mapping (the status states shown inside the phone-shaped window).
#![forbid(unsafe_code)]

use crate::status::{CmResult, CmStatus};

/// Something that went wrong while finding, pairing with or talking to the phone.
#[repr(u32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FailureClass {
    MacWifiOff = 1,
    DeviceNotFound = 2,
    NoPairing = 3,
    WirelessDebuggingOff = 4,
    LanUnreachable = 5,
    RouteViaTunnel = 6,
    ConnectionLost = 7,
    UnknownDevice = 8,
    PinMismatchKnownDevice = 9,
    AdbUnauthorized = 10,
    TlsHandshakeFailed = 11,
    KeyFingerprintMismatch = 12,
    KeyMissing = 13,
    LegacyPlaintextOffered = 14,
}

impl FailureClass {
    /// Decodes the C ABI value.
    pub fn from_u32(v: u32) -> CmResult<Self> {
        use FailureClass::*;
        Ok(match v {
            1 => MacWifiOff,
            2 => DeviceNotFound,
            3 => NoPairing,
            4 => WirelessDebuggingOff,
            5 => LanUnreachable,
            6 => RouteViaTunnel,
            7 => ConnectionLost,
            8 => UnknownDevice,
            9 => PinMismatchKnownDevice,
            10 => AdbUnauthorized,
            11 => TlsHandshakeFailed,
            12 => KeyFingerprintMismatch,
            13 => KeyMissing,
            14 => LegacyPlaintextOffered,
            _ => return Err(CmStatus::InvalidArgument),
        })
    }
}

/// What the window shows.
#[repr(u32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UiState {
    Mirroring = 0,
    WifiOff = 1,
    Searching = 2,
    NotPaired = 3,
    WirelessDebuggingOff = 4,
    LanSharingBlocked = 5,
    Disconnected = 6,
    UntrustedDevice = 7,
    AuthenticationFailed = 8,
    IdentityChanged = 9,
    RetryingSilently = 10,
    InsecureConnectionRefused = 11,
    /// Auto-connect verified the pinned phone and holds an encrypted link; one button starts mirroring.
    PhoneReady = 12,
    /// Paired, auto-connect off: waits for USB or the Connect button.
    NotConnected = 13,
    /// The bundled adb is missing or failed its code-signature check; nothing was started.
    LaunchCheckFailed = 14,
}

/// Automatic retries allowed for failures that may be network blips rather than key problems.
pub const AUTO_RETRIES: u32 = 1;

/// Maps a failure to the state to show. `attempt` counts failures of this class in a row (first = 0):
/// adb/TLS authentication failures get one silent retry; local key corruption never does.
pub fn ui_state(failure: FailureClass, attempt: u32) -> UiState {
    use FailureClass as F;
    match failure {
        F::MacWifiOff => UiState::WifiOff,
        F::DeviceNotFound => UiState::Searching,
        F::NoPairing => UiState::NotPaired,
        F::WirelessDebuggingOff => UiState::WirelessDebuggingOff,
        F::LanUnreachable | F::RouteViaTunnel => UiState::LanSharingBlocked,
        F::ConnectionLost => UiState::Disconnected,
        F::UnknownDevice => UiState::UntrustedDevice,
        F::PinMismatchKnownDevice => UiState::IdentityChanged,
        F::AdbUnauthorized | F::TlsHandshakeFailed if attempt < AUTO_RETRIES => UiState::RetryingSilently,
        F::AdbUnauthorized | F::TlsHandshakeFailed | F::KeyFingerprintMismatch | F::KeyMissing => {
            UiState::AuthenticationFailed
        }
        F::LegacyPlaintextOffered => UiState::InsecureConnectionRefused,
    }
}
