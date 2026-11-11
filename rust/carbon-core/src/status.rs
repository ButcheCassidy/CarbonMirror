//! Integer result codes shared by every module and returned across the C ABI.
#![forbid(unsafe_code)]

/// Result code of every carbon-core operation. `Ok` is zero; everything else is a refusal or error.
#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CmStatus {
    Ok = 0,
    NullPointer = 1,
    InvalidUtf8 = 2,
    InvalidArgument = 3,
    BufferTooSmall = 4,
    Panic = 5,
    NeedMoreData = 6,

    IpMalformed = 10,
    IpHostnameRefused = 11,
    IpPublicRefused = 12,
    IpTunnelRangeRefused = 13,
    IpReservedRefused = 14,
    InterfaceTunnelRefused = 15,
    PortInvalid = 16,
    PortLegacyTcpipRefused = 17,

    AdbEmpty = 30,
    AdbUnknownCommand = 31,
    AdbBadArgument = 32,
    AdbInstallNeedsUsb = 33,
    AdbInstallNeedsConfirmation = 34,

    DigestMismatch = 50,

    ParseMalformed = 60,
    ParseTooLarge = 61,

    InputOutside = 70,

    TlsHandshakeFailed = 80,
    TlsPinMismatch = 81,
    TlsPolicyViolation = 82,
    TlsClosed = 83,
    TlsTimeout = 84,
    TlsFailed = 85,

    PairingCodeExpired = 90,
    PairingCodeUsed = 91,
    TrustNotPaired = 92,
    TrustUnknownDevice = 93,
    TrustIdentityChanged = 94,

    AdbProbeMalformed = 100,
}

impl CmStatus {
    /// Value handed to C callers.
    pub const fn code(self) -> i32 {
        self as i32
    }
}

/// Shorthand for results whose error is a [`CmStatus`].
pub type CmResult<T> = Result<T, CmStatus>;
