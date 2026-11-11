# CarbonMirror — HANDOFF (interim, mid-Milestone 1)

**Resume instruction:** Open the GitHub repo `ButcheCassidy/CarbonMirror` (branch `main`), read this file, then continue from **Next steps**. The user will paste the **full spec prompt** (`CarbonMirror_Build_Prompt.md`) and supply the **app logo** (`CarbonMirror-icon.svg`, `CarbonMirror-icon-1024.png` → `Resources/`). Say: *Continue CarbonMirror from the Next steps in HANDOFF.md.*

- Version 0.1.0 · Date 2026-11-11 · Author credit: **ButcheCassidy - The Nomadic Rebel**
- Phase 1: 🟡 in progress · Phase 2: 🟡 started (Theme only) · Phase 3: 🟡 transport done, server fork not started · Phases 4–11: ⬜

## User rules (mandatory, from chat)
- Work and push **directly on `main`**. No branches, no PRs. Git identity per `CLAUDE.md`; no AI attribution trailers.
- Concise, no filler. No sub-agents unless asked. Every line of code has a purpose.
- **Build only this run; no bug-hunt phase. Fix bugs only when strictly necessary to continue.**
- Stop at Milestone 1 (after Phase 3), write the full-spec HANDOFF (template in spec), wait for "continue".
- **UI rule (add to full spec):** test the UI at every stage; every element at the exact spot the spec says; no overflow/clipping at any window size (0.75×–max). Toolbar must collapse extra buttons into an overflow (…) menu when the window is too narrow.
- **Liquid Glass task (add to full spec):** use Liquid Glass (`NSGlassEffectView`, macOS 26+; fallback `NSVisualEffectView` on macOS 15–25) **only** for the Settings window and the not-connected status screens. While a phone is connected/mirroring the UI is the normal, completely opaque UI.
- README must be GitHub-friendly, well formatted, natural feature explanations (per spec).

## Environment
- Cloud env setup fixed: swiftly hit HTTP 403 → `scripts/setup-env.sh` installs Swift 6.4.2 from the swift.org tarball. Env setup script is now a wrapper that runs it. Load with `source ~/carbonmirror-deps/env.sh`.
- Versions: Swift 6.4.2, Rust 1.97.0, cargo-ndk 4.1.2, cbindgen 0.29.4, cargo-audit 0.23.0, NDK 30.0.16248370, platform android-36, build-tools 36.0.0, platform-tools 37.0.1, scrcpy v5.0 (19871982cefb9de4c981c2314dfda2ac81564b48) at `~/carbonmirror-deps/scrcpy`, netns yes, netem no.

## Decisions / deviations
- Layout follows the spec (root `Package.swift`, `rust/`, `Resources/`, `scripts/`), not `android/`/`macos/` from CLAUDE.md (CI jobs for those stay skipped). Planned: `server/` (forked scrcpy-server), `companion/` (APK), `tools/`.
- Cargo workspace at `rust/` so outputs are `rust/target/...` as the spec's linker paths expect.
- `CarbonCoreC` is `.systemLibrary(path: "rust/include")` (header-only `.target` produced no `.o` with Swift 6.4's build system).
- Static archive linked **by full path** (`rust/target/.../libcarbon_core.a`) — with `-l`, the linker picks the cdylib `.so/.dylib` built beside it.
- adb server port: random per launch in 20000–59999 (never 5037), persisted to `adb-server.port` (0600) only for launch-time stale cleanup (`kill-server`).
- Helper adb signature check: requirement `identifier "adb" and certificate leaf = H"<SHA-1 of app's own leaf cert>"` (app DR has a different identifier).
- Pushed artifacts are hash-verified, copied to a private 0600 staging file, and the copy is pushed (closes check/push race).
- Expected artifact hashes live in Info.plist keys `CMServerSHA256`, `CMCoreLibSHA256` (written by build.sh; sealed by codesign).
- IP policy also refuses Mullvad tunnel ranges `10.64.0.0/10` and `fc00:bbbb:bbbb:bb01::/64`, IPv4-mapped IPv6, link-local without zone, port 5555.
- Extra UI states: `IdentityChanged` (7.5.4), `InsecureConnectionRefused` (6.1/11.4), `RetryingSilently` (no overlay).

## Exact values
- Bundle id `com.nomadicrebel.carbonmirror`; companion `com.nomadicrebel.carbonmirror.companion`; cert "CarbonMirror Dev".
- Remote paths: `/data/local/tmp/carbonmirror-server.jar`, `/data/local/tmp/libcarbon_core.so`; server class `com.genymobile.scrcpy.Server`.
- USB profile: h264, max_size 2992, max_fps 120, 32 Mbps. Size: min 0.75×, max 2.0×, corner fallback 9.5 % width, fine-tune ±15 %. Pixel 10 Pro XL 1344×2992 @ 486 ppi.
- Chrome: toolbar 44 pt + status line 14 pt, margins 10 pt, hover zone 28 pt, reveal 0.2 s, hide 1.2 s.
- C ABI v1 (`rust/include/carbon_core.h`): `cm_abi_version, cm_mac_points_per_inch, cm_size_real, cm_size_clamp, cm_size_locked_resize, cm_corner_radius, cm_net_check_ip, cm_net_check_endpoint, cm_net_check_interface, cm_adb_validate, cm_failure_ui_state, cm_adb_parse_devices, cm_adb_track_frame, cm_sha256, cm_sha256_verify, cm_random`.
- Rust deps: aws-lc-rs 1 (dev: serde, serde_json, proptest). rustls not added yet (Phase 7).

## File tree (done)
- `scripts/setup-env.sh` — Linux build/test environment.
- `rust/Cargo.toml` — workspace + release profile. `rust/carbon-core/` — `status.rs` (codes), `policy/{size,net,adb,failure}.rs`, `protocol/adb_devices.rs`, `crypto.rs`, `ffi.rs` (only `unsafe`), `tests/vectors.rs`, `tests/fuzz.rs`, `cbindgen.toml`.
- `rust/include/carbon_core.h` (generated) + `module.modulemap`.
- `tests/vectors/{net,adb,size,failure,adb_devices}.json` — shared vectors (Rust + Swift).
- `Package.swift` — all targets from spec.
- `Sources/CMCoreBridge/` — safe Swift wrappers (CoreStatus, SizeMath, Policy, AdbDeviceList, Crypto).
- `Sources/CMCore/` — Log (metadata only), PhoneProfile, Device (SSID-hash keys), StatusContent (2.4 table text).
- `Sources/CMSecurity/HelperSignature.swift` (macOS). `Sources/CMMedia`, `Sources/CMInput` — placeholders (Phases 4/5).
- `Sources/CMTransport/` — AdbCommand (typed commands), AdbEnvironment, ChildProcesses, AdbRunner, AdbSupervisor, ServerDeployer.
- `Sources/CMUI/Theme.swift` (tokens). `Sources/CarbonMirrorApp/main.swift` (expects `CMUI.AppDelegate` — **not written yet; macOS build will fail until it is**).
- `Tests/CMTests/` — VectorTests, BridgeTests, TransportTests, `Fixtures/fake-adb.sh`.

## Test status (evidence)
- `cargo test` (rust/carbon-core): unit 7 ✅, fuzz 5 ✅ (4096 cases each), vectors 5 ✅ — run before the workspace move.
- `cargo clippy --all-targets -- -D warnings`: clean.
- `swift build` (Linux): **Build complete**, zero warnings (before tests were added).
- `swift test`: **NOT RUN — tests written right before pause.** Run first: `source ~/carbonmirror-deps/env.sh && cargo build --release --manifest-path rust/Cargo.toml && swift test`.
- Everything macOS-only: NOT RUN — needs the Mac.

## Next steps (in order)
1. `cargo test` + clippy in workspace layout; `swift test`; fix only blocking failures.
2. Phase 1 remainder: `Resources/Info.plist`, `Resources/CarbonMirror.entitlements`, `Resources/adb-helper.entitlements`, `scripts/build.sh` (10.4 B–F, writes CM*SHA256 into Info.plist), `scripts/make-cert.sh` (10.4 A), `.gitignore` (`rust/target/`, `build/`, `dist/`, `deps/`).
3. Phase 2 (CMUI, macOS): `AppDelegate` (main menu, `--demo`), `PhoneWindow` (borderless, continuous corners, black, hairline, shadow, `sharingType = .none`), `StatusView` (glyph/title/subtitle/pill buttons, Liquid Glass when not connected), hover `ChromeView` (traffic lights via `standardWindowButton`, toolbar buttons in spec order with overflow menu, status line), `WindowSizer` (CGDisplayScreenSize → Rust math, ⌘0, per-orientation frame memory, live aspect lock via `windowWillResize`), `MenuBarController` (code-drawn template icon, Quit), `DemoDriver`.
4. Phase 3: fork scrcpy v5.0 server into `server/` (strip audio/file paths), `scripts/build-server.sh` (javac → d8, no Gradle) + `cargo ndk -t arm64-v8a` for `libcarbon_core.so` (API 30); show build output.
5. Write `REAL_DEVICE_CHECKS.md`, `SECURITY_NOTES.md`, `THIRD_PARTY_NOTICES.md`, README; then the full-spec HANDOFF.md (spec template, verbatim spec + ✅/🟡/⬜) and stop for "continue".
