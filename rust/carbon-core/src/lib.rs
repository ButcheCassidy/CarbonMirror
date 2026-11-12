// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
//! CarbonMirror core: memory-safe parsing of untrusted phone data, connection policy and TLS,
//! shared by the Mac app (static library) and the phone server (`libcarbon_core.so` via JNI).
#![deny(unsafe_code)]

pub mod crypto;
#[allow(unsafe_code)]
pub mod ffi;
pub mod policy;
pub mod protocol;
pub mod status;
pub mod tls;

/// Version of the C ABI in `rust/include/carbon_core.h`; bump on any signature change.
pub const ABI_VERSION: u32 = 3;
