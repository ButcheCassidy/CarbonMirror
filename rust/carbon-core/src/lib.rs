//! CarbonMirror core: memory-safe parsing of untrusted phone data, connection policy and (Phase 7) TLS,
//! shared by the Mac app (static library) and the phone server (`libcarbon_core.so` via JNI).
#![deny(unsafe_code)]

pub mod crypto;
#[allow(unsafe_code)]
pub mod ffi;
pub mod policy;
pub mod protocol;
pub mod status;

/// Version of the C ABI in `rust/include/carbon_core.h`; bump on any signature change.
pub const ABI_VERSION: u32 = 1;
