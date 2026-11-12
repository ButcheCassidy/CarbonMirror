# Third-party notices

CarbonMirror is © 2026 **ButcheCassidy - The Nomadic Rebel**, licensed under the PolyForm Noncommercial License 1.0.0 (`LICENSE`).
It contains or links the third-party software below, each under its own licence.

## Bundled or forked code

| Component | Where | Licence | Notes |
|---|---|---|---|
| scrcpy server v5.0 (Genymobile, commit `19871982cefb9de4c981c2314dfda2ac81564b48`) | `server/` → `Contents/Resources/carbonmirror-server` | Apache-2.0 (`server/LICENSE-scrcpy`) | Forked: audio, camera, virtual displays, file paths and reverse tunnel removed; session setup, inner TLS (JNI), battery and ping messages added. Modified files carry their original copyright. |
| Android SDK Platform-Tools `adb` (Google LLC) | `Contents/Helpers/adb` | Android SDK licence terms (downloaded by you, step 10.4 A-2) | Not redistributed in this repository; re-signed with your local certificate. |

## Rust crates linked into `libcarbon_core` (Mac app and phone)

| Crate | Version | Licence |
|---|---|---|
| rustls | 0.23.46 | Apache-2.0 OR ISC OR MIT |
| rustls-webpki | 0.103.16 | ISC |
| rustls-pki-types | 1.16.0 | MIT OR Apache-2.0 |
| aws-lc-rs | 1.19.0 | ISC AND (Apache-2.0 OR ISC) |
| aws-lc-sys (AWS-LC, includes BoringSSL/OpenSSL-derived code) | 0.47.0 | ISC AND (Apache-2.0 OR ISC) AND Apache-2.0 AND MIT AND BSD-3-Clause AND (Apache-2.0 OR ISC OR MIT) AND (Apache-2.0 OR ISC OR MIT-0) |
| rcgen | 0.14.7 | MIT OR Apache-2.0 |
| yasna | 0.5.2 | MIT OR Apache-2.0 |
| time / time-core | 0.3.55 / 0.1.9 | MIT OR Apache-2.0 |
| deranged, num-conv, powerfmt | 0.5.9, 0.2.2, 0.2.1 | MIT OR Apache-2.0 |
| zeroize / zeroize_derive | 1.9.1 / 1.5.0 | Apache-2.0 OR MIT |
| subtle | 2.6.1 | BSD-3-Clause |
| untrusted | 0.7.1, 0.9.0 | ISC |
| once_cell | 1.21.4 | MIT OR Apache-2.0 |
| jni / jni-sys (phone build only) | 0.21.1 / 0.3.1, 0.4.1 | MIT OR Apache-2.0 |
| proc-macro2, quote, syn, unicode-ident (build time only) | 1.0.107, 1.0.47, 2.0.119, 1.0.27 | MIT OR Apache-2.0 (unicode-ident also Unicode-3.0) |

The list is generated from `cargo tree -p carbon-core -e normal` (Mac/Linux and `--target aarch64-linux-android`); versions are pinned in `rust/Cargo.lock`.

## Reference projects (studied, not copied)

| Project | Licence | What was learned |
|---|---|---|
| [scrcpy](https://github.com/Genymobile/scrcpy) | Apache-2.0 | Wire protocol, on-device server (forked, see above) |
| [QtScrcpy](https://github.com/barry-ran/QtScrcpy) | Apache-2.0 | VideoToolbox → Metal zero-copy pipeline |
| [Droid Mirroring](https://droidmirroring.pages.dev) | Apache-2.0 | Native Swift client, phone-shaped window |
| [device-hub-pro](https://github.com/gitemre/device-hub-pro) | MIT | QR wireless-pairing flow |

## Platform frameworks

Apple frameworks (AppKit, Metal, MetalPerformanceShaders, VideoToolbox, Network, Security, LocalAuthentication, ServiceManagement) and SF Symbols are used through the macOS SDK under Apple's licence; no Apple binaries or assets are included. The Android companion uses only framework APIs.
