# CarbonMirror — HANDOFF (full spec: Phases 1–10 built, Phase 11 Linux stages done; Mac + phone checks NOT RUN)

> **Resume instruction:** Paste this file plus the latest source bundle (repo `ButcheCassidy/CarbonMirror`, branch `main`) into a new chat and say: *Continue CarbonMirror from the Next steps in HANDOFF.md.*
> Then: `source ~/carbonmirror-deps/env.sh` (Linux build env, see §4) and start at **§10 Next steps, step 1**.

## 1. Header

| Item | Value |
|---|---|
| Project | CarbonMirror — native macOS ⇄ Google Pixel 10 Pro XL mirroring & control |
| Version | 0.1.0 (`CFBundleShortVersionString`; server `VERSION_NAME` and APK versionName/versionCode 100 derive from it) |
| Milestone | Past Milestone 2 (user waived milestone stops); Phase 11 release check in progress |
| Date | 2026-11-12 (Phase 11 pass) |
| Author credit | **ButcheCassidy - The Nomadic Rebel** |
| Last commit before this handoff | `019f354` (plus this HANDOFF commit) |
| Phases 1–3 | ✅ (Mac steps NOT RUN — needs Mac; device steps in `REAL_DEVICE_CHECKS.md`) |
| Phase 4 | ✅ code — decoder + renderer reviewed and fixed, still **uncompiled** (macOS-only); HUD ✅; adaptive wiring ✅ |
| Phase 5 | ✅ code — `MirrorView` event glue + Mac→phone clipboard polling written (uncompiled) |
| Phase 6 | ✅ code — mDNS (NWBrowser + dns_sd resolve, no connect before allowlist), IP+port prompt, hotspot gateway guess, auto-handover; netns virtual LAN ⬜ (Phase 11) |
| Phase 7 | ✅ code — QR pairing UI/flow, 6-digit fallback, session-end triggers, `SECURITY_NOTES.md` ✅ |
| Phase 8 | ✅ code — Settings window (Liquid Glass), full menu-bar menu, blur + Touch ID, status line, landscape pill, launch at login |
| Phase 9 | ✅ companion APK builds/signs on Linux (test key), v2+v3 verified |
| Phase 10 | ✅ docs (README, INSTALL, SECURITY_NOTES, REAL_DEVICE_CHECKS, THIRD_PARTY_NOTICES, CHANGELOG, LICENSE); Mac build NOT RUN |
| Phase 11 | 🟡 Stages 1–4 done on Linux with evidence (`RELEASE_CHECK.md`, 17 findings, all High fixed); release gate open (Mac build + device checks) |

## 2. Where the build stands

Everything in the spec has code except the Phase 11 harnesses still listed in §10. The macOS-only Swift (`Sources/CMUI/*`, `Sources/CMMedia/{VideoDecoder,MetalScreenView}.swift`, `CMSecurity/{HelperSignature,KeychainKeyStore,OwnerCheck}.swift`, `CMTransport/{NWByteStream,Bonjour}.swift`) has **never been compiled** — Linux has no AppKit. The first Mac build (`scripts/build.sh`) will very likely surface compile errors; fix them first (§10 step 1).

## 3. User rules (mandatory, from chat — keep obeying)
- Commit and push **directly to `main`**, under `ButcheCassidy <354005634+ButcheCassidy@users.noreply.github.com>` (run the two `git config` lines from `CLAUDE.md` first). **No** branches, PRs, `Co-Authored-By`, "Generated with Claude", session links. (The harness proposes a branch `dimitri/adoring-goodall-ejzoqv`; the user explicitly overrode it: main only.)
- Responses: structured, concise, no filler. While working, say in < 2 sentences what you are doing. Detail only in execution steps.
- No agents/sub-agents unless the user asks. No research tangents.
- Every line of code must have a purpose. Build everything; **bug fixes and bug hunts at the end** (Phase 11), fix earlier only when strictly necessary to continue.
- **Do not stop at milestones** (user: "Skip handoff at phase two… move through coding as efficiently as possible"). Write the full-spec HANDOFF at the end (and whenever the user asks, as now).
- UI rule: test the UI at every stage; every element exactly where the spec puts it; no overflow/clipping at any window size 0.75×–max; toolbar collapses extra buttons into an overflow (…) menu when narrow. (Implemented as pure geometry `ChromeLayout`, tested at every 1 pt width.)
- Liquid Glass (`NSGlassEffectView`, macOS 26+; fallback `NSVisualEffectView` .hudWindow behind-window on 15–25) **only** for the Settings window and the not-connected status screens. While connected/mirroring: normal, fully opaque UI.
- README must be GitHub-friendly, well formatted, subtitles, natural feature explanations (refer to the spec).
- App icon: the user attached the 1024 PNG only (no SVG). Decision (user): **raster from PNG** — Android adaptive-icon foreground = PNG cut per density; monochrome layer = hand-drawn white phone outlines (vector). Same icon for the Mac (`.icns` via build.sh). PNG committed at `Resources/CarbonMirror-icon-1024.png` (sha256 `0252738ba477448d5e6bd3c1057ef15ba567f23e659fb5ffcb34a6e37201cf03`).
- Licence (user): **PolyForm Noncommercial 1.0.0** → create `LICENSE` (not yet done).
- Device scope (user): **Pixel 10 Pro XL defaults, keep the spec's fallbacks** (adaptive size steps etc.); other Android 11+ phones still connect.
- Encryption focus (user preference + CLAUDE.md): all mirroring/control traffic encrypted+authenticated on wireless; no plaintext transport on LAN.
- (2026-11-12) **All commits authored and committed as ButcheCassidy** (git config from `CLAUDE.md`); no AI trailers.
- (2026-11-12) **Inner TLS over USB ON by default** (owner decision; spec said off).
- (2026-11-12) The SVG is now supplied (`Resources/CarbonMirror-icon.svg`): **companion icon = VectorDrawable converted from the SVG** (gradients kept, SVG blur shadows dropped). Mac `.icns` still from the 1024 PNG.
- (2026-11-12) **No bloat:** every line must have a purpose. Responses: one-line progress notes, no conversational filler.
- (2026-11-12) Must be **GrapheneOS-compatible** (see SECURITY_NOTES §6.6, README phone setup).

## 4. Environment (Linux build box)
- `source ~/carbonmirror-deps/env.sh` sets `JAVA_HOME` (OpenJDK 21), `ANDROID_HOME=/root/carbonmirror-deps/android-sdk`, `ANDROID_NDK_HOME=…/ndk/30.0.16248370`, `CM_TEST_VIDEO_DIR=/root/carbonmirror-deps/test-video`, PATH with Swift 6.4.2, build-tools 36.0.0, platform-tools, cargo.
- Versions (`~/carbonmirror-deps/VERSIONS.txt`): Swift 6.4.2, Rust 1.97.0, cargo-ndk 4.1.2, cbindgen 0.29.4, cargo-audit 0.23.0, NDK 30.0.16248370, platform android-36, build-tools 36.0.0, platform-tools 37.0.1, scrcpy v5.0 (`19871982cefb9de4c981c2314dfda2ac81564b48`) at `~/carbonmirror-deps/scrcpy`, Python 3.13 venv, ffmpeg 6.1.1, netns available **yes**, netem **no**, openssl at `/usr/bin/openssl`.
- Test streams: `pixel10proxl-60fps.h264` (34 MB), `pixel10proxl-120fps.h264` (58 MB), `pixel10proxl-60fps.h265` (21 MB).
- If the container is fresh: `scripts/setup-env.sh` (installs Swift from the swift.org tarball because swiftly hit HTTP 403; downloads sequentially, cached, sha-recorded in `~/carbonmirror-deps/deps.lock`).
- Gotcha: SwiftPM does **not** relink when `rust/target/release/libcarbon_core.a` changes → after any Rust change run `touch Sources/CMCoreBridge/*.swift` before `swift test`.
- Gotcha: `swift test` output is buffered when redirected; a hanging test shows nothing — run single tests with `--filter` and `timeout`.

## 5. Decisions made and deviations from the spec (with reasons)
1. **Layout** follows the spec (root `Package.swift`, `rust/`, `Resources/`, `scripts/`, `server/`), not `android/`/`macos/` from CLAUDE.md (CI jobs for those stay skipped). Planned still: `companion/` (APK), `tools/` (virtual phone, sectest).
2. Cargo workspace at `rust/` (outputs in `rust/target/...` as the spec's linker paths expect).
3. `CarbonCoreC` is `.systemLibrary(path: "rust/include")` (header-only `.target` produced no `.o` with Swift 6.4).
4. Static archive linked **by full path** (`rust/target/{aarch64-apple-darwin/,}release/libcarbon_core.a`): with `-l` the linker picks the cdylib beside it.
5. adb server port random per launch in 20000–59999 (never 5037), persisted to `adb-server.port` (0600) only for launch-time stale cleanup.
6. Helper adb signature requirement: `identifier "adb" and certificate leaf = H"<SHA-1 of the app's own leaf cert>"` (`Sources/CMSecurity/HelperSignature.swift`). **Not yet called at launch** (§10 step 3).
7. Pushed artifacts are hash-verified, copied to a private 0600 staging file, and the copy is pushed (closes check/push race). Expected hashes in Info.plist `CMServerSHA256`, `CMCoreLibSHA256` (written into the bundle copy by `scripts/build.sh`, sealed by codesign).
8. IP policy also refuses Mullvad tunnel ranges `10.64.0.0/10`, `fc00:bbbb:bbbb:bb01::/64`, IPv4-mapped IPv6, link-local without zone, hostnames, port 5555.
9. Extra UI states: `IdentityChanged` (7.5.4), `InsecureConnectionRefused` (6.1), `RetryingSilently` (no overlay).
10. **C ABI buffer cap 16 MiB** (`MAX_BUFFER_LEN`): lengths up to `isize::MAX` previously reached `from_raw_parts` (UB) — fixed (test `nullAndHugeInputsAreRefusedNotCrashed`).
11. **TLS:** rustls 0.23.46 built **without** the `tls12` feature (TLS 1.2 code is not even compiled), provider = aws-lc-rs with suites `[TLS13_AES_256_GCM_SHA384, TLS13_CHACHA20_POLY1305_SHA256]`, groups `[X25519MLKEM768, X25519]`. **Deviation:** rustls 0.23's unbuffered API does *not* yet decrypt in place (`ReadTraffic::next_record` pops a Vec), so the buffered `Connection` API is used; plaintext is copied once into the caller's buffer and rustls allocates per record internally. Protocol parsing itself is offset-based, zero-copy. → record in SECURITY_NOTES.
12. **Pin format = SHA-256 of the certificate's SubjectPublicKeyInfo** (not the whole DER) — stable if adbd regenerates its certificate from the same key. Used for the phone's adb TLS key (pairing pin) and the phone server's per-session key.
13. **Identity design:** Mac identity = Keychain P-384 key (non-extractable, permanent, login keychain, tag `com.nomadicrebel.carbonmirror.identity`, label `CarbonMirror identity`). It signs (via Swift callback, `ecdsaSignatureMessageX962SHA384`) a self-made CA cert `CN=CarbonMirror Mac identity` (CA, pathlen 0, keyCertSign) once, and per session a fresh **Ed25519** client cert `CN=CarbonMirror Mac session` (EKU clientAuth, valid now−1 h … now+24 h). Phone server creates a fresh Ed25519 self-signed cert `CN=CarbonMirror phone session` per start; trusts only client certs chaining to the pinned Mac CA (`WebPkiClientVerifier`, mandatory client auth).
14. **Phone pins the Mac CA TOFU** in `/data/local/tmp/carbonmirror-mac.pin` (hex SHA-256 of the CA DER, mode 0600). Mismatch → server prints `CM-ERROR identity-changed` and exits → Mac shows "This phone's identity changed". "Create new key" must run the allowlisted `adb shell rm -f /data/local/tmp/carbonmirror-mac.pin` after re-pairing. Honest limit: anyone with adb shell access can delete that file; adb's SPAKE2 pairing is the root of trust (SECURITY_NOTES).
15. **Session setup goes over the adb shell's stdin**, never argv or files: line `CM1 <plain|tls> <secret:64 hex> <mac-ca: base64 DER | ->\n`. In TLS mode the server prints `CM-PIN <64 hex>` on stdout (authenticated adb channel). No key files on the phone at all; `libcarbon_core.so` is deleted right after `System.load`; the jar unlinks itself (scrcpy `CleanUp`).
16. **Session secret:** 32 random bytes; each socket (video, control) must present it first (after TLS when TLS is on); server compares with `MessageDigest.isEqual` and closes on mismatch; dummy byte / data only afterwards.
17. Connect retry: `adb forward` accepts TCP even before the server listens, then closes → client retries on `StreamError.closed` (60 × 100 ms). TLS/pin errors are not retried.
18. **Wireless transport reality:** the phone↔Mac TCP connection in Wireless debugging is made by **adb** itself (adb over TLS), and CarbonMirror's sockets go to 127.0.0.1 through `adb forward`. Network.framework interface binding (`requiredInterfaceType .wifi/.wiredEthernet`, `prohibitedInterfaceTypes [.other, .cellular]`) and the `utun` rejection are applied by CarbonMirror's own **pre-connect probe** (`WirelessProbe.probe`), which also refuses plaintext `adb tcpip` (adb `CNXN` answered by `AUTH`/`CNXN` instead of `STLS`) and captures the phone's adb TLS key hash for pinning. adb's own socket follows system routing (cannot be bound from outside) → SECURITY_NOTES.
19. Spec 7.2 says the Mac "advertises the pairing service": in Android's QR flow the **phone** advertises `_adb-tls-pairing._tcp` under the QR's service name and the Mac browses for it and runs `adb pair ip:port password`. Implement that way.
20. **Server fork** (from scrcpy v5.0): removed audio package, camera capture, virtual/new display, `list_*` modes, media-scan of file paths (`TYPE_SCAN_FILE`), camera torch/zoom, display resize, reverse tunnel. `Options` is a strict allowlist: unknown keys throw; `audio=false`, `video/control/tunnel_forward=true`, `video_source=display`, `display_id=0` accepted only with those values; `max_size` 0–4096, `video_bit_rate` 1–100 M, `max_fps` 0–240, `scid` required. Rust adb allowlist aligned (key `send_stream_meta` — the old Swift `send_codec_meta` was wrong; removed `show_touches`, `power_off_on_close`, `downsize_on_error`).
21. Added device messages: `0x40` battery (level u8 0–100, charging u8 0/1; every 30 s and on change, polled every 5 s from the sticky `ACTION_BATTERY_CHANGED` intent in-process) and `0x41` pong (u64); control message `0x41` ping (u64) → round-trip latency for the status line (Mac pings every 2 s).
22. Clipboard: server raised `MESSAGE_MAX_SIZE` to 1 MiB(+header) both ways, bounds every length in the reader, and only reads clips whose description has `text/plain` or `text/html` (returns plain text); Mac validates UTF-8, no NUL, ≤ 1 MiB in Rust; phone→Mac text is dropped while sync is off.
23. ⌘ is sent to the phone as **Ctrl** (⌘C/⌘V/⌘A/⌘Z work as on a Mac) in both typing modes. App shortcuts in the menu take precedence.
24. Pointer ids: finger `-2`, second pinch finger `-3`; pinch start spread 400 px, clamped 40 px … frame width. Scroll: precise deltas ÷ 24 pt per unit, clamp ±16; horizontal sign `-dx` (**unverified → REAL_DEVICE_CHECKS**).
25. App drawer uses `KEYCODE_ALL_APPS` (284) (works on Android 12+, i.e. Pixel 10); the spec's swipe-up fallback is **not implemented** (no reliable failure signal) → note in README/HANDOFF.
26. `swift test` Linux-only test signer uses `/usr/bin/openssl` (P-384) — tests only.
27. `KeyManager` stores CA DER, adb-key fingerprint and the paired `Device` JSON as generic-password items (service `com.nomadicrebel.carbonmirror`, accounts `CarbonMirror identity certificate`, `CarbonMirror adb key fingerprint`, `CarbonMirror paired device`). Data-protection keychain / Secure Enclave need a Team ID → future upgrade (SECURITY_NOTES).
28. Logging: `os.Logger` subsystem `com.nomadicrebel.carbonmirror`, categories app/ui/transport/adb/security/media/input; metadata only (compile-time messages + app-generated values). On Linux, `CM_LOG=1` prints to stderr. The app writes no log files (unified logging rotates) → the "rotate at 1 MB" requirement is met by not writing files; state in SECURITY_NOTES.
29. `MirrorSession.connect` uses local forward ports 27000–29999 (random).
30. Toolbar ⌘-shortcuts list lives in `ToolbarItem.shortcut` (AppDelegate.swift). Traffic lights are system `standardWindowButton`s (coloured — they are system controls; everything else monochrome).
31. **Network identity without SSID:** SSID needs Location permission (not allowed). "This network" = IPv4 subnet of the Wi-Fi interface (`NetworkIdentity.subnet(ofInterface:)`), stored as `Device.ssidKey("subnet:<a.b.c.d/n>")`. Subnet change during a wireless session = unknown network → session ends.
32. **mDNS resolve without connecting:** `Bonjour.resolve` uses `DNSServiceResolve` + `DNSServiceGetAddrInfo` (IPv4) so the allowlist runs before any packet goes to the phone; browsing via `NWBrowser` with `.other`/`.cellular` prohibited.
33. **USB without pairing** is allowed while nothing is paired (Android's USB authorisation is the trust root); once paired, another USB serial → Untrusted device.
34. **Mirroring state for the tile:** server `CleanUp` writes Global setting `carbonmirror_session` 1 at start / 0 after the server dies. Verified from AOSP source: unknown Global keys aren't gated by the S+ `@Readable` check, and `adb_wifi_enabled` is `@Readable`. 1-bit leak to other apps documented.
35. **Signals:** children inherit `SIG_IGN` for SIGTERM (needed by the app's dispatch signal sources) → `ChildProcesses.stop(pid)` = SIGTERM, 0.5 s, SIGKILL.
36. **Wireless debugging off** only after a *final* end (Disconnect, quit, idle). Lock/sleep keep it on so silent reconnect works.
37. Display sleep / screensaver → blur (8.2.4); system sleep, lock, user switch, network change, idle → end session (7.6). Lid close = system sleep.
38. Adaptive USB profile judges only seconds with ≥ 30 fps (Android sends no frames for still screens); `requestedMaxSize` decides whether a frame size is the native panel size.
39. Wireless H.265 → H.264 fallback: if the server fails before the first connect with H.265, retry with H.264 (`h265Failed`).
40. The companion has no launcher activity (tile only). Tile fallback = `ACTION_APPLICATION_DEVELOPMENT_SETTINGS` (PendingIntent on API 34+).
41. ⌘-combinations that aren't app shortcuts go to the phone from `performKeyEquivalent` with an immediate key-up (AppKit sends no key-up while ⌘ is held). App shortcuts: `AppShortcuts` in `MirrorView.swift`.
42. Pairing: `adb pair` output `[guid=adb-<serial>-<suffix>]` gives the serial and the `_adb-tls-connect._tcp` name to resolve.
44. **adb server + forwards on Unix sockets** (`ADB_SERVER_SOCKET=localfilesystem:<container tmp>/cm/cm-adb`, forwards `localfilesystem:…/cm-f<16 hex>`), folder 0700, path ≤ 103 bytes or launch fails closed. Rust allowlist refuses `tcp:` forwards. `StreamConnector` takes a socket path; the app connects with `POSIXStream.connect(unixPath:)`; `NWByteStream` is only the LAN probe now.
45. rustls caps unread plaintext at 16 KiB → `Session` drains into its own buffer (`PLAIN_LIMIT` 16 MiB, zeroed on drop).
46. Clipboard privacy: concealed/transient Mac items skipped; Android `EXTRA_IS_SENSITIVE` skipped in the server; phone text written `currentHostOnly`.
47. Windows `isRestorable = false`; Keychain items `kSecAttrSynchronizable false`; adb folders excluded from backup; unlock notification verified with `CGSessionCopyCurrentDictionary`.
48. Scripts locate the repo via `BASH_SOURCE`/git (user's Mac run failed with `dirname: illegal option -- z`). Run as `bash scripts/build.sh` from the repo folder.
49. Phase 11 harnesses: `tools/sectest/{tls_downgrade.sh, capture_session.sh+capture_scan.py, virtual_lan.sh+fake_adbd.py+port_scan.py, ffi_fuzz.sh+ffi_fuzz.py}`, `rust/carbon-core/examples/tls_endpoint.rs`, `Tests/CMTests/SoakTests.swift` (`CM_SOAK_SECONDS`), `TapStream` (`CM_CAPTURE_DIR`), virtual phone `loopFPS`. The LAN must be outside 10.64.0.0/10 (Mullvad range is refused by design).
43. Rust crate licence field = `PolyForm-Noncommercial-1.0.0`; crate MSRV 1.88 (time 0.3.55, RUSTSEC-2026-0009).

## 6. Exact values in use
- Bundle id `com.nomadicrebel.carbonmirror`; companion `com.nomadicrebel.carbonmirror.companion`; signing cert "CarbonMirror Dev" (P-384/SHA-384, 5 y, `-x -T /usr/bin/codesign`; RSA-4096 fallback in `scripts/make-cert.sh`).
- Remote paths: `/data/local/tmp/carbonmirror-server.jar`, `/data/local/tmp/libcarbon_core.so`, `/data/local/tmp/carbonmirror-mac.pin`; server class `com.genymobile.scrcpy.Server`; abstract socket `scrcpy_<scid 8 hex>`.
- Current artifact SHA-256 (Linux build `scripts/build-server.sh`, change with code): server jar `448e49ea83172f872240a15458965bfbf4cc6580a47d09b53c17c593b48bbd9c` (before the `time` bump the .so was `fa8f9cb1…`; rebuild for the current hash). Companion APK (test key) `f036e83dc92a412f9def72cbda4807b3cd3703057093b6c12d55c8c9d17c330c`. All are **gitignored** build outputs.
- Global setting `carbonmirror_session` (0/1). Network key: `Device.ssidKey("subnet:<subnet>")`. Defaults keys added: `macPinResetPending`, `companionInstalled`.
- USB profile: H.264, max_size 2992, max_fps 120, 32 Mbps; adaptive steps 2992→2560→2240→1920 then fps 120→90→60 when < 110 fps over 3 s. Wireless "Secure": 60 fps, H.265, 12 Mbps; experimental 90/120.
- Size: min 0.75×, max 2.0×, fallback real-size 127 pt/inch, corner fallback 9.5 % width, fine-tune ±15 %. Pixel 10 Pro XL 1344×2992 @ 486 ppi.
- Chrome: toolbar 44 pt + status line 14 pt (top inset 58), margins 10 pt, hover zone 28 pt, reveal 0.2 s ease-out, hide 1.2 s; toolbar buttons 22 pt, spacing 2, badge 66 pt, traffic lights at x 8/28/48 (14 pt), leading area 72 pt, trailing 8 pt.
- Fonts: title 17 bold, subtitle 13, pill 13 semibold, status line SF Pro 11 tabular digits; secondary text white 60 %; hairline white 10 %; pill fill white 16 % (pressed 28 %); chrome fill grey 0.08.
- TLS: ALPN `carbonmirror/1`; handshake timeout 10 s; key update every 15 min or 4 GiB; no resumption (`Resumption::disabled`, `NoServerSessionStorage`, 0 tickets), no 0-RTT; buffer limit 4 MiB. IANA ids: suite 0x1302/0x1303, group 0x11EC/0x001D.
- Pairing: QR `WIFI:T:ADB;S:carbonmirror-<10 base62>;P:<22 base62 ≥130 bit>;;`, lifetime 120 s, single use; 6-digit fallback accepted by the allowlist.
- Reconnect: 0.5, 1, 2, 4, 8 s, then 30 s; give up after 600 s. Quality: Excellent ≥95 % fps & ≤20 ms; Good ≥80 % & ≤50 ms; Fair ≥50 % & ≤120 ms; else Poor. Idle timeout default 10 min (1–120). Rotation reminder 180 days. Auto-blur choices 0/5/10/30/60 s.
- Limits: video packet ≤ 8 MiB, frame dimension ≤ 8192, clipboard ≤ 1 MiB, UHID output ≤ 64 B, inject text ≤ 300 B (split), app name ≤ 255, adb output ≤ 1 MiB, dumpsys ≤ 4 MiB, adb line ≤ 4096 B, setup line ≤ 8192 B.
- UHID keyboard id 1, name "CarbonMirror Keyboard", vendor 0x18D1, product 0x4EE7, 63-byte boot-keyboard descriptor with LED output (`keymap.rs`).
- Android keys: HOME 3, BACK 4, VOL_UP 24, VOL_DOWN 25, POWER 26, SYSRQ 120, MUTE 164, APP_SWITCH 187, ALL_APPS 284.
- Rust crates: aws-lc-rs 1, rustls 0.23.46 (aws_lc_rs, prefer-post-quantum, std; no tls12), rustls-webpki 0.103.16, rcgen 0.14.7 (aws_lc_rs, crypto), time 0.3.55, zeroize 1.9.1, jni 0.21 (Android only); dev: serde, serde_json, proptest. `Cargo.lock` committed. `cargo audit` clean (2026-11-12).
- C ABI version **2** (`rust/include/carbon_core.h`, 65 functions):
  `cm_abi_version`, `cm_mac_points_per_inch`, `cm_size_real`, `cm_size_clamp`, `cm_size_locked_resize`, `cm_corner_radius`, `cm_net_check_ip`, `cm_net_check_endpoint`, `cm_net_check_interface`, `cm_adb_validate`, `cm_failure_ui_state`, `cm_adb_parse_devices`, `cm_adb_track_frame`, `cm_sha256`, `cm_sha256_verify`, `cm_random`, `cm_proto_device_name`, `cm_proto_codec`, `cm_proto_video_header`, `cm_proto_device_message`, `cm_annexb_to_avcc`, `cm_display_corner_radius`, `cm_clipboard_check`, `cm_ctrl_simple`, `cm_ctrl_keycode`, `cm_ctrl_text`, `cm_ctrl_touch`, `cm_ctrl_scroll`, `cm_ctrl_set_clipboard`, `cm_ctrl_uhid_create`, `cm_ctrl_uhid_input`, `cm_ctrl_uhid_destroy`, `cm_ctrl_ping`, `cm_ctrl_start_app`, `cm_input_letterbox`, `cm_input_map_point`, `cm_input_scroll_units`, `cm_input_pinch`, `cm_key_hid_report`, `cm_key_hid_descriptor`, `cm_key_android`, `cm_adb_probe_hello`, `cm_adb_probe_stls`, `cm_adb_probe_classify`, `cm_pairing_new`, `cm_pairing_field`, `cm_pairing_consume`, `cm_pairing_free`, `cm_trust_check`, `cm_tls_make_identity_ca`, `cm_tls_client_identity_new`, `cm_tls_server_identity_new`, `cm_tls_identity_pin`, `cm_tls_identity_free`, `cm_tls_session_new`, `cm_tls_capture_new`, `cm_tls_read_tls`, `cm_tls_write_tls`, `cm_tls_read_plain`, `cm_tls_write_plain`, `cm_tls_status`, `cm_tls_negotiated`, `cm_tls_captured_pin`, `cm_tls_close`, `cm_tls_session_free`
- Status codes: Ok 0, NullPointer 1, InvalidUtf8 2, InvalidArgument 3, BufferTooSmall 4, Panic 5, NeedMoreData 6, IpMalformed 10, IpHostnameRefused 11, IpPublicRefused 12, IpTunnelRangeRefused 13, IpReservedRefused 14, InterfaceTunnelRefused 15, PortInvalid 16, PortLegacyTcpipRefused 17, AdbEmpty 30, AdbUnknownCommand 31, AdbBadArgument 32, AdbInstallNeedsUsb 33, AdbInstallNeedsConfirmation 34, DigestMismatch 50, ParseMalformed 60, ParseTooLarge 61, InputOutside 70, TlsHandshakeFailed 80, TlsPinMismatch 81, TlsPolicyViolation 82, TlsClosed 83, TlsTimeout 84, TlsFailed 85, PairingCodeExpired 90, PairingCodeUsed 91, TrustNotPaired 92, TrustUnknownDevice 93, TrustIdentityChanged 94, AdbProbeMalformed 100.
- Keychain items: key tag `com.nomadicrebel.carbonmirror.identity` / label `CarbonMirror identity`; generic passwords listed in §5.27.

## 7. File tree (one-line purpose each)
**Root:** `Package.swift` SwiftPM manifest (targets below, Rust archive by path) · `CLAUDE.md` project rules · `HANDOFF.md` this file · `README.md` placeholder (to be written) · `.gitignore` · `.github/workflows/{ci,release}.yml`, `.github/dependabot.yml` CI from project setup · `docs/RELEASING.md` release notes process.
**Resources/:** `Info.plist` (bundle keys, local-network text, Bonjour types, CM*SHA256 placeholders) · `CarbonMirror.entitlements` (sandbox, network client/server, USB, Pictures rw) · `adb-helper.entitlements` (sandbox + inherit) · `CarbonMirror-icon-1024.png` app icon. Build outputs (gitignored): `adb`, `carbonmirror-server`, `libcarbon_core.so`, `CarbonMirrorCompanion.apk`.
**scripts/:** `setup-env.sh` Linux env · `build.sh` Mac build/sign/DMG (10.4 B–F, `--install`) · `make-cert.sh` P-384 cert with RSA fallback (10.4 A) · `build-server.sh` javac→d8 server jar + cargo-ndk core lib, prints SHA-256.
**rust/carbon-core/src/:** `lib.rs` modules + ABI_VERSION · `status.rs` codes · `crypto.rs` SHA-256, constant-time eq, CSPRNG · `tls.rs` inner TLS (identities, verifiers, sessions, capture) · `ffi/mod.rs` C ABI (only `unsafe`) · `ffi/jni.rs` JNI bridge for the server (Android only) · `policy/{adb,net,size,failure,clipboard,pairing}.rs` adb allowlist, IP/interface allowlist, size maths, failure→UI state, clipboard filter, QR codes + trust pins · `protocol/{adb_devices,adb_wire,annexb,control,display_info,input,keymap,scrcpy}.rs` device list parser, CNXN/STLS probe, Annex B→AVCC, control encoder, corner-radius parser, pointer mapping, key maps + HID report, video/device-message parsers. **tests/:** `vectors.rs` shared JSON vectors, `fuzz.rs` proptest (4096 cases each), `tls.rs` end-to-end TLS. `cbindgen.toml`. **rust/include/:** `carbon_core.h` (generated), `module.modulemap`.
**tests/vectors/:** `adb.json net.json size.json failure.json adb_devices.json` shared Rust/Swift vectors.
**Sources/CMCoreBridge/:** `CoreStatus.swift` status enum + ABI check · `Crypto.swift` · `Policy.swift` net/adb/failure · `SizeMath.swift` · `AdbDeviceList.swift` · `Protocol.swift` scrcpy parsers, control encoder, Annex B · `Input.swift` pointer + keyboard mapping · `Security.swift` adb probe, PairingCode, TrustPolicy, IdentitySigning, InnerTLS, TLSIdentity, TLSSession.
**Sources/CMCore/:** `Log.swift` metadata-only logging · `PhoneProfile.swift` Pixel panel facts · `Device.swift` paired device + SSID-hash endpoints · `StatusContent.swift` 2.4 status texts · `AppSettings.swift` every 8.3 setting (UserDefaults, live observers) · `ChromeLayout.swift` toolbar items/geometry + overflow + reveal maths · `Policies.swift` reconnect, quality, status line, landscape, blur, session guard, transport choice, adaptive profile · `VideoSink.swift` decoder protocol · `Encryption.swift` signer + CA bundle.
**Sources/CMTransport/:** `AdbCommand.swift` typed adb commands + ServerOptions · `AdbEnvironment.swift` private adb HOME/port · `AdbRunner.swift` allowlisted process runner · `AdbSupervisor.swift` server lifecycle + track-devices · `ChildProcesses.swift` kill-all + signal handlers · `ServerDeployer.swift` hash-verified staging + push · `ByteStream.swift` stream protocol + POSIX loopback stream · `NWByteStream.swift` Network.framework stream (loopback; LAN for probe) · `SecureStream.swift` inner TLS over a stream · `PhoneLink.swift` adb-facing protocol + `AdbPhoneLink` + server process (stdin/stdout) · `MirrorSession.swift` the session actor · `WirelessProbe.swift` STLS/plaintext probe, key capture, utun check.
**Sources/CMSecurity/:** `HelperSignature.swift` adb helper code-signature check · `KeyManager.swift` KeyStore protocol, identity/CA, pins, adb-key health, Create new key · `KeychainKeyStore.swift` login-Keychain implementation (macOS).
**Sources/CMInput/:** `InputEngine.swift` pointer/keyboard/toolbar → control messages, blur blocking.
**Sources/CMMedia/:** `Screenshot.swift` folder + file naming · `VideoDecoder.swift` VideoToolbox (WIP, uncompiled) · `MetalScreenView.swift` Metal renderer, blur, screenshot (WIP, uncompiled).
**Sources/CMUI/ (macOS):** `Theme.swift` tokens · `PhoneWindow.swift` borderless window · `PhoneContentView.swift` screen + chrome container, hover tracking · `StatusView.swift` glass status screens + pill buttons · `ChromeView.swift` toolbar, traffic lights, overflow menu, status line · `WindowSizer.swift` real-size maths, clamp, aspect lock, per-orientation memory · `PhoneWindowController.swift` states, reveal/hide, sizing, pin, rotation · `MenuBarController.swift` template icon + menu · `DemoDriver.swift` `--demo` · `AppDelegate.swift` app entry, main menu, shortcuts.
**New (2026-11-12):** `Sources/CMUI/{MirrorView,SessionController,PairingController,SettingsWindow}.swift` (input glue + HUD + lock glyph; the whole session lifecycle; QR pairing + IP/port/code prompts; Settings) · `Sources/CMTransport/{NetworkIdentity,Bonjour}.swift` · `Sources/CMSecurity/OwnerCheck.swift` (Touch ID/password) · `companion/` (`AndroidManifest.xml`, `src/…/WirelessDebuggingTile.java`, `res/` adaptive icon + tile icon + strings) · `scripts/build-apk.sh` · `rust/carbon-core/examples/tls_endpoint.rs` + `tools/sectest/{tls_downgrade.sh,capture_session.sh,capture_scan.py}` · `Resources/CarbonMirror-icon.svg` · docs `README.md INSTALL.md SECURITY_NOTES.md REAL_DEVICE_CHECKS.md THIRD_PARTY_NOTICES.md CHANGELOG.md RELEASE_CHECK.md LICENSE`.
**Sources/CarbonMirrorApp/main.swift** entry (Linux prints a message and exits 64).
**Tests/CMTests/:** `VectorTests` shared vectors · `BridgeTests` C ABI boundary · `TransportTests` adb allowlist/runner/supervisor/deployer (+ `Fixtures/fake-adb.sh`) · `UILayoutTests` chrome geometry + settings · `SessionTests` full sessions vs virtual phone · `VirtualPhone.swift` virtual phone, recording sink, openssl test signer, virtual link · `InputTests` mapping + input flood · `PolicyTests` 8.2/6.3/7.6 rules · `KeyTests` keys/pins/Create new key/pairing codes · `ProbeTests` wireless probe vs fake adbd.
**server/:** `LICENSE-scrcpy` (Apache-2.0) · `src/main/aidl/...` · `src/main/java/android/content/IContentProvider.java` · `src/main/java/com/genymobile/scrcpy/...` forked server; new `carbon/CarbonCore.java` (JNI), `carbon/SessionSetup.java` (stdin setup, Mac pin, CM-PIN), `carbon/SecureChannel.java` (TLS or plain socket wrapper), `carbon/BatteryMonitor.java`; modified `Server.java`, `Options.java`, `Workarounds.java`, `device/{DesktopConnection,Streamer}.java`, `control/{ControlChannel,ControlMessage,ControlMessageReader,Controller,DeviceMessage,DeviceMessageWriter}.java`, `wrappers/{ClipboardManager,ServiceManager}.java`, `util/LogUtils.java`; deleted `audio/`, camera/new-display/video-source classes, `model/NewDisplay.java`, `AndroidManifest.xml`, upstream tests.

## 8. Build, sign, package & install commands (as they currently work)
**Linux (verified):**
```bash
source ~/carbonmirror-deps/env.sh
```
```bash
cargo test --release --manifest-path rust/Cargo.toml
```
```bash
(cd rust && cargo clippy --all-targets -- -D warnings)
```
```bash
(cd rust/carbon-core && cargo ndk -t arm64-v8a -P 30 clippy --release -- -D warnings)
```
```bash
cbindgen --config rust/carbon-core/cbindgen.toml --crate carbon-core --output rust/include/carbon_core.h rust/carbon-core
```
```bash
cargo build --release --manifest-path rust/Cargo.toml && touch Sources/CMCoreBridge/*.swift && swift build --build-tests && swift test
```
```bash
scripts/build-server.sh
```
**Mac (NOT RUN — needs the Mac):** Step A `scripts/make-cert.sh` (or the README's manual 10.4 A commands); Step A-2 platform-tools download + `deps.lock` + `cp deps/platform-tools/adb Resources/adb`; Step A-3 rustup + `aarch64-apple-darwin` + cbindgen; JDK + Android SDK (platform 36, build-tools 36.0.0, NDK) for `scripts/build-server.sh`; APK via `scripts/build-apk.sh` (release keystore, password typed); then `scripts/build.sh` (Steps B–F; `--install` copies to /Applications). The exact 10.4 commands are in the README and implemented 1:1 in `scripts/build.sh` / `scripts/make-cert.sh`. Full Mac setup (JDK, SDK without Homebrew, keystore) in `INSTALL.md` §8.4.
**Linux extras (verified):** `scripts/build-apk.sh --test-key` · `tools/sectest/tls_downgrade.sh` · `tools/sectest/capture_session.sh encryptedSessionStreamsVideoAndControl` (root, tcpdump) · `(cd rust && cargo audit)`.

## 9. Test status (evidence) — Linux, 2026-11-12, after Phase 11

- `cargo test --release`: 43 passed; clippy clean (host + Android); `cargo audit` exit 0.
- `swift build --build-tests`: 0 warnings; `swift test`: 68 tests in 10 suites passed.
- Phase 11 (full evidence in `RELEASE_CHECK.md`): TLS downgrade 8/8 refused; capture scan clean (control flagged); virtual LAN PASS (0 TCP/UDP listeners, 65 535-port scan none open, plaintext/tunnel/public refused, fake utun TX 0); hypothesis C-ABI fuzz 13 × 120 s no crash; replay/tamper refused; 5-min soak PASS (23 sessions, 142 900 events byte-exact, 111/56 fps, fds/RSS plateau).
- The user's first Mac run of `scripts/build.sh` stopped before compiling (script-location bug, fixed in `502ad5e`). **macOS-only Swift still never compiled.**

**NOT RUN — needs my Mac / real device:** everything in `REAL_DEVICE_CHECKS.md` (now incl. 6a–6c: socket folder perms, no Resume snapshots, try removing `network.server`).

**Known open issues:** macOS code uncompiled; horizontal scroll sign; `ALL_APPS` swipe fallback; companion fallback test only on device; `tc netem` unavailable (no loss/latency simulation); `network.server` entitlement possibly removable.

## 10. Next steps (ordered; start at 1)
1. On the Mac: `bash scripts/build.sh` (after Step A-2 adb, `bash scripts/build-server.sh`, `bash scripts/build-apk.sh`). Fix compile errors in the macOS-only files (Swift 6 strict concurrency, zero warnings).
2. `REAL_DEVICE_CHECKS.md` A–E; record results in `RELEASE_CHECK.md`; fix findings (re-run the affected stage).
3. User will attach the full prompt again: second pass adding all detail requirement by requirement (§12 table).
4. Release gate: version bump, CHANGELOG, signed DMG + APK, checksums, evidence table.

## 11. Rules to keep obeying
- **A3 rules 1–10**, especially **rule 9 (honesty & evidence)**: show the exact command + real output for every "done/tested"; write `NOT RUN — <reason>` otherwise and add to `REAL_DEVICE_CHECKS.md`; never weaken/skip/hard-code tests or special-case test inputs; every fix shows its diff + re-run.
- A7 scope: display out, input in, clipboard text ≤ 1 MB both ways (toggle, never logged, wiped on disconnect), screenshots only to `~/Pictures/CarbonMirror/`; no files, drag-and-drop, audio, recording, APK drops, storage browsing, free-form shell; notifications never reach macOS.
- Monochrome UI only (black/white/greys; app icon is the only colour); always dark appearance.
- No Xcode-only tools, no Homebrew, command-line build only; Swift 6 strict concurrency with zero warnings.
- Network etiquette (A3.8): download once, sequentially, ≤ 1 req/s, cache + SHA-256, backoff 2→4→8→16→32 s, max 5, then print the manual command.
- Author credit "ButcheCassidy - The Nomadic Rebel" (About, README, notices).
- Terminal instructions for the user: one command per line, a plain sentence before each, no comment lines.

## 12. The full spec (verbatim; PART A + all phases), with requirement status
Legend: ✅ done · 🟡 partial · ⬜ not started. Status for each numbered requirement is given in the table directly after this legend; the spec text follows unchanged.

| Req | Status | Evidence / note |
|---|---|---|
| A3.1 native only | ✅ | Swift/AppKit/Metal + Rust; no web views |
| A3.2 no Apple binaries/assets | ✅ | original code; system SF Symbols only |
| A3.3 CLT-only build | ✅ | scripts use swift/sips/iconutil/plutil/codesign/hdiutil; Metal shader compiled at runtime |
| A3.4 signed .app in .dmg | 🟡 | scripts/build.sh written, NOT RUN |
| A3.5 monochrome | ✅ | Theme tokens; traffic lights are system buttons |
| A3.6 security rules | 🟡 | see Phase 7 rows |
| A3.7 files complete, README/terminal style | 🟡 | no TODO/stubs in code; README not written |
| A3.8 network etiquette | ✅ | setup-env.sh; nothing downloaded in this session except crates via cargo (cached) |
| A3.9 evidence | ✅ | §9 |
| A3.10 Linux vs Mac | ✅ | macOS parts guarded; NOT RUN list §9 |
| A9 Rust core split/C ABI/no Tokio/no unsafe outside ffi/release profile/zeroize/cbindgen/vectors twice/JNI | ✅ (🟡 in-place decrypt deviation §5.11; cargo audit ⬜) | rust/, tests |
| 1.1 package targets + Linux split | ✅ | swift build Linux 0 warnings |
| 1.2 Info.plist | ✅ | Resources/Info.plist |
| 1.3 entitlements | ✅ | Resources/*.entitlements |
| 1.4 packaging 10.4 + build.sh | 🟡 | written; NOT RUN (needs Mac); APK now builds |
| 1.5 borderless window + Not paired + menu-bar Quit | ✅ code / NOT RUN | CMUI |
| 1.6 logging | ✅ | Log.swift |
| Checkpoint 1 | ✅ Linux / Mac NOT RUN | §9 |
| 2.1 visual language | ✅ | Theme |
| 2.2 resting state, continuous corners, hairline, shadow | ✅ | device corner radius wired (SessionController) |
| 2.3 hover chrome, toolbar order, overflow, status line, hide 1.2 s | ✅ | status line live data + battery glyph |
| 2.4 status states (+ glass) | ✅ | StatusContent, StatusView |
| 2.5 sizing, aspect lock, ⌘0, memory, rotate animation | ✅ | WindowSizer, size vectors |
| Checkpoint 2 | 🟡 | --demo written NOT RUN; math tests ✅ |
| 3.1 bundled adb, deps.lock, Google check, signature check at runtime | ✅ code | `HelperSignature.verify` at launch; NOT RUN |
| 3.2 private adb env 127.0.0.1 | ✅ | AdbEnvironment |
| 3.3 forked server (no Gradle), hash verify, libcarbon_core.so | ✅ | build-server.sh output §9 |
| 3.4 supervisor | ✅ (bug §9.1) | TransportTests |
| 3.5 device model | ✅ | Device.swift |
| Checkpoint 3 | ✅ Linux | REAL_DEVICE_CHECKS.md written |
| 4.1 protocol client + allowlist + battery | ✅ | SessionTests |
| 4.2 corner radius | ✅ | read + window wiring |
| 4.3 decode | 🟡 | reviewed + fixed; uncompiled (needs Mac) |
| 4.4 render | 🟡 | reviewed + fixed (texture lifetime, letterbox, BT.601); uncompiled |
| 4.5 USB profile + adaptive fallback | ✅ code | wiring in SessionController; device check |
| 4.6 debug HUD | ✅ code | ⌥⌘D, MirrorView |
| Checkpoint 4 | 🟡 | framing/config/key frames ✅ on real test stream; rotation-change test ⬜ |
| 5.1 main display, screen-off toggle | ✅ code | toggle live |
| 5.2 mapping | ✅ | InputTests |
| 5.3 typing modes | ✅ | InputTests |
| 5.4 shortcuts | ✅ engine+menu / Mac screenshot 🟡 | |
| 5.5 dedicated queue, rotation/scale mapping | ✅ | ordered non-blocking send |
| 5.6 clipboard | ✅ code | Mac→phone polling 0.5 s while key + sync on |
| Checkpoint 5 | ✅ Linux | InputTests incl. flood |
| 6.1 Wireless debugging only, tcpip refused, Secure profile | ✅ | H.265→H.264 fallback |
| 6.2 allowlist, interface binding, IP only, discovery, hotspot, self-check, README tile | ✅ code | mDNS + IP/port prompt + hotspot gateway; netns test ⬜ |
| 6.3 auto switching + mode setting | ✅ code | switchSession handover |
| Checkpoint 6 | 🟡 | netns LAN + captures ⬜ |
| 7.1 threat model doc | ✅ | SECURITY_NOTES.md |
| 7.2 QR pairing, 120 s single use, pins, 6-digit fallback | ✅ code | PairingController; NOT RUN |
| 7.3 inner TLS (all bullets) | ✅ | rust tests/tls.rs, SessionTests |
| 7.4 identity key + adb key fingerprint | ✅ code / Keychain NOT RUN | |
| 7.5 key regeneration & recovery | ✅ code | dialogs, retry, reminder |
| 7.6 hardening | ✅ code | session-end triggers wired |
| 7.7 segregation | ✅ code / sandbox checks NOT RUN | |
| Checkpoint 7.7 | ✅ Linux | vectors + hostile message tests |
| Checkpoint 7 | ✅ Linux | + OpenSSL TLS 1.0–1.2/weak-suite/group/no-cert attacks refused (RELEASE_CHECK) |
| 8.1 icon | ✅ | SVG + PNG in Resources; companion adaptive vector icon |
| 8.2.1–8.2.6 | ✅ code | UI wired; visual checks NOT RUN |
| 8.3 settings & menu bar | ✅ code | Settings (glass), menu bar, SMAppService |
| Checkpoint 8.2 / 8 | ✅ Linux / NOT RUN | live settings apply; codec change restarts stream |
| Phase 9 | ✅ | APK built + verified on Linux (test key); device checks NOT RUN |
| Phase 10 | 🟡 | docs ✅; Mac build/sign NOT RUN; perf targets unmeasured |
| Phase 11 | 🟡 | Linux stages 1–4 ✅ (RELEASE_CHECK.md); release gate ⬜ |

---

# CarbonMirror — Step-by-Step Build Prompt
### Native macOS ⇄ Google Pixel 10 Pro XL screen mirroring & control
Author credit: **ButcheCassidy - The Nomadic Rebel**

> **How to use this prompt:** give the whole file to the model. It builds the app **phase by phase, in order**. Each phase ends with a **Checkpoint**: the model must confirm the checkpoint passes (and list any problem) before starting the next phase. Never skip a phase, never leave placeholders.

---

## PART A — CONTEXT (read fully before Phase 1)

### A1. Your role
You are a senior macOS systems engineer (Swift 6, AppKit, Metal, VideoToolbox, Network.framework, Security.framework), a Rust systems engineer (FFI, rustls, no-`unsafe` parsing, Android NDK cross-compiling) and an Android platform engineer (Java, MediaCodec, adb, scrcpy internals). You write complete, working, production-quality code.

### A2. What we are building
A lightweight native Mac app that mirrors and controls an Android phone (Pixel 10 Pro XL) with the feel of Apple's iPhone Mirroring:
- **Full duplex:** the Mac and the phone show the *same live screen*. I can use the phone on the Mac, or pick up the phone, open an app by hand, and see every movement on the Mac instantly.
- **Wired (USB-C, up to 120 fps)** and **wireless (encrypted, locked down)**, switching automatically.
- **Android UI is never altered** — frames are shown pixel-for-pixel; only the window's rounded mask is applied.
- **Works with Mullvad VPN always on**, using Mullvad's *Local network sharing*.

### A3. Hard rules
1. **No Electron, web views, Flutter, Qt or SDL.** Native only: Swift 6 + AppKit + Metal for everything Apple-specific, Rust for the security-critical core (A9).
2. **Do not reverse-engineer or copy Apple's iPhone Mirroring binary or assets.** Only the interaction feel is a reference; all code and icons are original.
3. **Command-line build only** — Apple Command Line Tools (`swift build`/`swiftc`, `sips`, `iconutil`, `plutil`, `codesign`, `hdiutil`). Xcode is **not installed**: never use Xcode-only tools (`xcodebuild` — so no `.xcframework`, `actool`, `ibtool`, `xcstringstool`) or `#Preview` macros. Rust via `rustup`/`cargo` only. No Homebrew at build or run time.
4. Output: signed `.app` inside a `.dmg`, signed with a **local self-signed certificate** (name configurable, default "CarbonMirror Dev"), hardened runtime on.
5. **Monochrome UI only** — black, white and greys. No accent colours anywhere.
6. Security rules (Phase 7) are non-negotiable. If a requirement is impossible, say so and implement the closest secure alternative; record it in `SECURITY_NOTES.md`.
7. Every file written in full. No "TODO", no stubs. Non-coder-friendly `README.md`. Terminal instructions for me: one command per line, no comment lines, plain-English sentence before each command (I paste them one at a time).
8. **Network etiquette — do not trip rate limits.** Download every external artifact (Android SDK command-line tools, platform-tools, build-tools, platform jar, scrcpy source, any Google Maven artifact) **once, sequentially, never in parallel, at most 1 request per second**. Cache it locally and verify its SHA-256. On HTTP 429/5xx: honour `Retry-After`, otherwise back off 2 s → 4 s → 8 s → 16 s → 32 s, max 5 tries, then **stop** and print the exact manual download command for me instead of retrying in a loop. Never re-download what is already cached.
9. **Honesty & evidence — no cheating.** Never say something is done, built, tested, fixed or passing unless you show proof: the exact command you ran and its real, unedited output (or an excerpt with the total line/test count). If you could not run something, write **`NOT RUN — <reason>`** and add it to the real-device checks; never write "should work", "would pass" or "verified" without output. Never weaken, skip, delete, comment out or hard-code a test to make it pass; never special-case test inputs in production code; never stub or bypass a security check. Every fix must show its diff plus the re-run output of the test that caught it. An honest "partly done, here's what's missing" is always better than a complete-looking fake. I will check.
10. **Your environment is Linux; mine is a Mac.** You cannot run macOS-only steps (AppKit/Metal/VideoToolbox code, `codesign`, `iconutil`, `sips`, `hdiutil`, Keychain) or touch my phone. For those: write the code and the exact commands, mark them `NOT RUN — needs my Mac` / `NOT RUN — needs real device`, and add them to `REAL_DEVICE_CHECKS.md`. Every checkpoint below is verified as far as your environment allows, by this rule.

### A4. Hardware & environment
| Item | Value |
|---|---|
| Mac | MacBook Pro 16" M4 Pro, 24 GB, arm64 only, ProMotion 120 Hz, panel 3456×2234 px @ 254 ppi |
| macOS | macOS 27 (deployment target macOS 15) |
| Phone | Google Pixel 10 Pro XL, Android 16, may run **GrapheneOS** |
| Phone panel | 1344 × 2992 px, ~486 ppi, 20:9, LTPO 1–120 Hz |
| Phone active area (derived) | 70.2 × 156.4 mm, diagonal ≈ 171.4 mm (6.75"; marketed 6.8") |
| VPN | Mullvad on Mac **and** phone, *Local network sharing* ON on both |

Must also work on any Android 11+ phone; defaults are tuned for the Pixel 10 Pro XL.

### A5. Reference projects (study, don't copy blindly; credit in `THIRD_PARTY_NOTICES.md`)
- github.com/Genymobile/scrcpy (Apache-2.0, latest 5.x) — protocol and on-device server
- github.com/barry-ran/QtScrcpy — VideoToolbox + Metal zero-copy pipeline
- droidmirroring.pages.dev — Droid Mirroring (Apache-2.0): native Swift scrcpy client, phone-shaped window
- github.com/gitemre/device-hub-pro (MIT) — QR wireless pairing flow

### A6. Architecture overview
```
[Pixel]                                          [Mac — CarbonMirror.app]
forked scrcpy-server (pinned, hash-verified)     Transport manager (USB | Wireless, auto handover)
 + libcarbon_core.so (Rust, via JNI)              + libcarbon_core.a (Rust, linked statically)
 ├─ video  MediaCodec H.264/H.265   ───────►      ├─ Inner TLS 1.3 session (always on wireless)
 ├─ clipboard text (opt) ◄──────►               ├─ scrcpy protocol client (native Swift)
 │  (no audio, no files)                        │
 └─ control socket                  ◄──────►      ├─ VideoToolbox decode → IOSurface → Metal (zero copy)
        ▲                                         ├─ CAMetalLayer, ProMotion-paced
  adb tunnel: USB, or Wireless Debugging (TLS)    ├─ Input engine (mouse/trackpad/keyboard → control msgs)
                                                  ├─ Key & pairing manager (Keychain)
                                                  └─ Menu-bar agent (no listening network ports)
```
Plus a tiny **phone-side companion APK** (Phase 9) — Quick Settings tile only, no network permission.

### A8. Your build environment (already prepared)
My environment script (`setup-env.sh`) has already installed, on Linux: Swift toolchain (via swiftly), Rust (stable via rustup, with `clippy`, `rustfmt`, the `aarch64-linux-android` target, `cargo-ndk`, `cbindgen`, `cargo-audit`), the Android NDK, `cmake`/`clang` (for aws-lc), JDK, Android SDK (cmdline-tools, platform-tools, `platforms;android-36`, `build-tools;36.0.0`), the pinned scrcpy source, a Python venv (`cryptography`, `pytest`, `hypothesis`, `dpkt` for capture analysis), `ffmpeg` with pre-generated synthetic H.264/H.265 test streams, a verified Swift↔Rust static-link smoke test, and network test tools (`iproute2` incl. `tc netem` for latency/packet-loss simulation, `iperf3`, `ping`, `tcpdump`, `netcat`, `openssl`, `lsof`). Load it with `source ~/carbonmirror-deps/env.sh`; versions, checksums and whether network namespaces work are in `~/carbonmirror-deps/VERSIONS.txt`. **Do not re-download any of it** (A3.8). If something is missing, tell me the exact package/command instead of fetching it in a loop.

### A7. Scope & segregation (core principle)
The phone link is a **partial sandbox: display out, input in, plus two narrow, controlled extras**. It must be walled off from the rest of my Mac:
- **Allowed:** the phone's screen shown on the Mac; taps, swipes, scrolls, pinches and keyboard typing sent to the phone; navigation shortcuts (Back, Home, Recents, App drawer, Notifications, Quick Settings, Volume, Rotate, Lock); opening and using apps exactly as a person would on the phone.
- **Allowed extra 1 — clipboard (plain text only, both ways):** copy on the Mac → paste on the phone and vice versa. Text only (no images, files or rich content), max 1 MB, never logged, toggle in the toolbar and Settings (on by default), cleared from memory on disconnect, travels only inside the encrypted session.
- **Allowed extra 2 — screenshots to the Mac:** a toolbar button saves the current mirrored frame as a PNG into `~/Pictures/CarbonMirror/` (the only folder the app may write outside its container). Built from the decoded frame on the Mac — nothing is pulled from phone storage.
- **Notifications** appear only on the phone screen (and therefore in the mirrored window). They are **never** passed into macOS Notification Centre, and the app never posts macOS notifications containing phone content.
- **Not allowed (do not build):** file transfer in either direction, drag-and-drop, audio forwarding, screen recording to the Mac, installing apps by dropping APKs, browsing phone storage, any free-form adb shell.
- If the phone or the wireless link were ever compromised, nothing coming from it may reach my Mac's files (beyond writing PNGs into `~/Pictures/CarbonMirror/` when *I* press Screenshot), keychain or other apps; incoming clipboard text is plain text only and size-capped. Details in Phase 7.7.

### A9. Swift + Rust split (one Rust core, used on both ends)
**Why Rust here:** not to save memory — Swift and Rust are both native with no garbage collector, and the footprint is decided by the video pipeline (zero-copy, newest-frame-only), not the language. Rust is used because it gives **memory-safe parsing of untrusted data**, **one identical TLS implementation on the Mac and the phone** (rustls + aws-lc-rs: TLS 1.3, AES-256-GCM, hybrid post-quantum `X25519MLKEM768`), and code you can **build, test and fuzz on Linux**. State this honestly in `SECURITY_NOTES.md`.

**Crate `rust/carbon-core`** (`crate-type = ["lib", "staticlib", "cdylib"]`, edition 2024):
- `protocol` — scrcpy wire framing/parsing with strict bounds checks (all bytes from the phone pass through here first), and encoding of input/control messages (taps, swipes, keys, clipboard) with coordinate mapping through rotation and scale.
- `policy` — private-range IP allowlist + `utun` rule data, adb command allowlist + argument validation, size/aspect maths, clipboard filter (text only, ≤ 1 MB), key/pairing state machine, failure → UI-state mapping.
- `tls` — rustls (0.23.x or newer) with the **aws-lc-rs** provider and `prefer-post-quantum`: TLS 1.3 only; cipher suites restricted to `TLS13_AES_256_GCM_SHA384` then `TLS13_CHACHA20_POLY1305_SHA256`; key exchange `X25519MLKEM768` then `X25519`; custom certificate verifiers that do **pinning only** (no CA trust); session secret check. rustls only does the TLS state machine over bytes — the actual sockets stay in Swift (Network.framework, so interface binding and `utun` rules keep working) and in Java on the phone.
- `ffi` — the **only** module allowed to use `unsafe`; every other module has `#![forbid(unsafe_code)]`.

**Rules for the Rust side:**
- Small, hand-written **C ABI** (`extern "C"`, opaque handles, `(ptr, len)` byte slices, integer error codes), header generated with **cbindgen** → `rust/include/carbon_core.h` + `module.modulemap`. No UniFFI/swift-bridge runtime layers, no XCFramework.
- No async runtime (no Tokio). No allocations per video frame: Rust decrypts/parses in place and returns offsets into the caller's buffer; Swift hands frame bytes straight to VideoToolbox.
- Release profile: `opt-level = 3`, `lto = "fat"`, `codegen-units = 1`, `panic = "abort"`, `strip = true`. Never let a panic cross the FFI boundary.
- Secrets in Rust use `zeroize`. Dependencies kept minimal and pinned in `Cargo.lock`; `cargo audit` must be clean.

**Linking into the Mac app (SwiftPM, no Xcode):** a C target `CarbonCoreC` containing the cbindgen header + modulemap, and in `Package.swift`:
```swift
.target(name: "CarbonCoreC", path: "rust/include"),
.target(
  name: "CMCoreBridge",
  dependencies: ["CarbonCoreC"],
  linkerSettings: [
    .unsafeFlags(["-L", "rust/target/aarch64-apple-darwin/release"], .when(platforms: [.macOS])),
    .unsafeFlags(["-L", "rust/target/release"], .when(platforms: [.linux])),
    .linkedLibrary("carbon_core"),
    .linkedFramework("Security", .when(platforms: [.macOS])),
    .linkedLibrary("m", .when(platforms: [.linux])),
    .linkedLibrary("dl", .when(platforms: [.linux])),
    .linkedLibrary("pthread", .when(platforms: [.linux]))
  ]
),
```
(On Linux, take the exact extra system libraries from `cargo rustc --release -- --print native-static-libs` and list them here.) The Rust core is linked **statically** — no `.dylib` — so hardened-runtime library validation never has to load third-party code. `CMCoreBridge` wraps the C ABI in safe Swift types; nothing else in Swift calls the C functions directly.

**Testing on both sides (Linux):** the same security, protocol and input tests run **twice** — once in Rust (`cargo test`) and once from Swift (`swift test` linking the Linux build of `carbon-core` through `CMCoreBridge`) — using shared test vectors in `tests/vectors/*.json` (packets, malformed inputs, IP lists, adb commands, TLS policy cases, input-mapping cases with expected outputs). A Swift-only POSIX-socket test transport (Linux) drives a full session against the virtual phone (Phase 11), so the Swift wrapper, the FFI boundary and the Rust core are all exercised end-to-end. Both suites must pass; any disagreement between them is a bug.

**On the phone:** the same crate is built for `aarch64-linux-android` with `cargo ndk` into `libcarbon_core.so`, pushed next to the server, SHA-256-verified like the server, and loaded via JNI (`System.load`) by the forked scrcpy-server for the inner TLS and protocol checks. If loading ever fails on a device, the server refuses to start a wireless session (no silent fallback to a weaker stack) and the Mac shows why.

---

## PART B — BUILD PHASES

## Phase 1 — Base project & packaging

Goal: an app that builds, signs, packages and launches, showing an empty phone-shaped window.

1. Create a Swift Package with targets:
   - `CarbonMirrorApp` (executable, AppKit app entry)
   - `CMCore` (shared models, settings, logging)
   - `CMUI` (window, chrome, views)
   - `CMTransport` (adb, sockets, TLS) — empty for now
   - `CMMedia` (decode, render) — empty for now
   - `CMInput` (input mapping) — empty for now
   - `CMSecurity` (keys, pairing, pins) — empty for now
   - `CMTests` (unit tests)
   - `CarbonCoreC` + `CMCoreBridge` (Rust core link + safe Swift wrapper — A9)
   - `rust/carbon-core` (Rust crate — protocol, policy, TLS; A9)
   Split so the **core logic builds and tests on Linux** (A3.10): the Rust crate (`cargo build`, `cargo test`, `cargo clippy -- -D warnings`) plus the Swift targets `CMCore` and `CMCoreBridge` with their `swift test` suite running the shared test vectors (A9). Mac-only targets (`CMUI`, `CMMedia`, Mac parts of `CMTransport`/`CMSecurity`, `CarbonMirrorApp`) are guarded with `#if os(macOS)` so `swift build` and `swift test` also succeed on Linux.
2. `Info.plist`: bundle id `com.nomadicrebel.carbonmirror`, `LSUIElement = false`, menu-bar extra enabled, `NSLocalNetworkUsageDescription` ("CarbonMirror connects to your phone on your local network."), `NSBonjourServices` = `_adb-tls-connect._tcp`, `_adb-tls-pairing._tcp`, camera/mic keys **absent**.
3. Entitlements: hardened runtime + **App Sandbox ON** with only `com.apple.security.network.client`, `com.apple.security.network.server` (needed only for adb's **127.0.0.1-only** server — enforced in code and tested in Phase 11) `com.apple.security.device.usb` and `com.apple.security.assets.pictures.read-write` (only so screenshots can be saved to `~/Pictures/CarbonMirror/`). **No** other file-access entitlements (no user-selected files, Downloads, Documents), no Apple Events, camera, microphone, contacts, calendars or JIT. A separate `Resources/adb-helper.entitlements` (`com.apple.security.app-sandbox` + `com.apple.security.inherit` only) is used to sign the bundled adb so it runs inside the app's sandbox. See Phase 7.7.
4. Packaging follows **Phase 10.4 exactly** (local "CarbonMirror Dev" certificate, `.icns` via `iconutil`, inside-out signing, DMG via `hdiutil`). Also provide `scripts/build.sh` that runs the same commands, but the README must show them by hand too.
5. App launches a **borderless, phone-shaped, black window** with continuous corners (detail in Phase 2) showing the "Not paired" state, plus a monochrome menu-bar icon with Quit.
6. Logging: `os.Logger` subsystem `com.nomadicrebel.carbonmirror`, metadata only, never content.

**Checkpoint 1:** `cargo test` + `cargo clippy -- -D warnings` for `carbon-core`, and `swift build` + `swift test` for the Linux-buildable Swift targets, pass on Linux (show output); the Mac build/sign/DMG commands (10.4) are written out and marked `NOT RUN — needs my Mac`.

---

## Phase 2 — Window & UI system (monochrome)

### 2.1 Visual language
- Black, white, greys only. SF Symbols in monochrome. Always dark appearance. Neutral-grey vibrancy allowed.
- System font: bold titles, secondary text at ~60 % white, grey pill buttons.

### 2.2 Resting state (while using the phone)
- Borderless window that is **only the mirrored screen**: no title bar, no bezel, no frame.
- **Continuous ("squircle") corners**: `CALayer.cornerCurve = .continuous`. Radius = the phone's real corner radius read at connect time (Phase 4), scaled to window size. Default before connect: 9.5 % of window width. Settings slider ±15 % fine-tune.
- 1 px outer hairline (white @ 10 %), standard soft macOS shadow, black fill behind content (no corner bleed during resize).
- No camera hole-punch: it is physical glass and is not in captured frames — never draw one, never add fake padding.

### 2.3 Hover state (top reveal)
- Pointer enters the **top 28 pt** (or window becomes key via ⌘-Tab) → 200 ms ease-out: chrome frame grows **around** the screen — ~44 pt toolbar on top and 10 pt margin on other sides. The mirrored screen is **not rescaled** (no video jump) and gains a 1 px inner hairline; continuous corners stay.
- Toolbar (left → right): traffic lights (close / minimise / zoom), then monochrome icon buttons with tooltips: Back · Home · **Recents** (Android's own overview — swipe away/remove app cards natively) · **App drawer** · Notifications · Quick Settings · Screenshot (saves the current frame to `~/Pictures/CarbonMirror/` on the Mac) · Clipboard sync on/off · Privacy blur · Typing mode · Rotate · Volume −/+ · Mute · Lock (power) · Connection badge (`USB · 120` / `Wi-Fi · 🔒`) · Pin on top · Settings.
- Under the buttons: the one-line **status line** (battery, charging, connection quality — 8.2.5).
- Chrome hides 1.2 s after pointer leaves the zone.

### 2.4 Status states (inside the phone-shaped window)
Centred glyph + bold title + one-line subtitle + grey pill button:
| State | Subtitle | Button |
|---|---|---|
| Wi-Fi Off | Turn on Mac Wi-Fi to connect. | Settings |
| Searching | Looking for your Pixel… (monochrome spinner) | Use USB instead |
| Not paired | Pair your phone to get started. | Pair |
| Wireless debugging off | Turn on Wireless debugging on your phone. | How? |
| LAN sharing blocked | Allow local network sharing in Mullvad on both devices. | How? |
| Disconnected | Connection lost. | Reconnect |
| Untrusted device | This device isn't paired with CarbonMirror. | Pair |
| Authentication failed | Your phone couldn't verify this Mac's key. | Retry · **Create new key** |

### 2.5 Sizing (locked aspect ratio, smooth)
- Locked to the phone aspect (1344:2992 portrait; inverse landscape) during live resize from any edge/corner. Resizing only changes the Metal drawable size — no frame drops.
- Sizes are **relative to the real phone**, computed at runtime from `CGDisplayScreenSize()` and `backingScaleFactor` (correct at any scaled resolution):
  - Min **0.75×** real size, max **2.0×**, clamped to the visible screen frame.
  - Reference at default "Looks like 1728×1117" (127 pt/inch): 1:1 ≈ **351 × 782 pt**; 0.75× ≈ **263 × 586 pt**; 2.0× ≈ **702 × 1564 pt** → in portrait clamped to visible height (~1.38×); 2.0× fits in landscape.
- ⌘0 snaps to real size. Remember size/position per orientation. Rotation behaviour is set by the *Landscape* setting (8.2.6); whenever the window does rotate, it animates around its centre.

**Checkpoint 2:** UI demo mode (`--demo` flag) cycles all states, shows hover chrome, resizes between limits with the aspect locked; unit tests for size/clamp math pass.

---

## Phase 3 — Infrastructure (adb, server, process management)

1. **Bundled adb**: official Google platform-tools for macOS, placed in `Contents/Helpers/`. Google does not publish checksums for the platform-tools zip, so: I download it on my Mac (step 10.4 A-2), its SHA-256 is recorded in `deps.lock` on first download and checked on every later build, and before re-signing the build checks Google's original signature (`codesign -dv` must show *Google LLC*). Re-signing changes the file, so at runtime verify the helper's **code signature** against CarbonMirror's designated requirement (`SecStaticCodeCheckValidity`) instead of a hash; refuse to run on mismatch.
2. **App-private adb environment**: `HOME` / `ANDROID_USER_HOME` = `~/Library/Application Support/CarbonMirror/adb/` (dir 0700, files 0600). Never touch `~/.android`. adb server on a **non-default port**, bound to **127.0.0.1** only (`ADB_SERVER_SOCKET=tcp:127.0.0.1:<port>`).
3. **Forked scrcpy-server**: pinned upstream version; the fork only adds the JNI bridge to `libcarbon_core.so` (inner TLS + protocol checks, Phase 7) and removes the features banned in A7 (Phase 7.7). Build it **without Gradle**, following scrcpy's own `server/build_without_gradle.sh` approach (`javac` → `d8` from SDK build-tools, against the platform `android.jar`). `scripts/build-server.sh` does this; SDK components are fetched once per rule A3.8. Bundle the result, store its SHA-256, verify before every push to the phone. It runs as `shell` via `app_process`, so GrapheneOS app optimisation never touches it. Also build `libcarbon_core.so` for `aarch64-linux-android` (`cargo ndk -t arm64-v8a -o … build --release`, API level 30) and treat it exactly like the server: bundled, hash-verified, pushed only to the server's fixed path.
4. **Process supervisor** (`CMTransport.AdbSupervisor`): start/stop adb server, watch device list (USB attach/detach events), restart on crash, kill all child processes on quit/crash (also via a signal handler and launch-time stale-process cleanup).
5. **Device model** (`CMCore.Device`): serial, model, Android version, connection type, pinned fingerprints, last known IP per Wi-Fi network (SSID hash only, never plaintext SSID in logs).

**Checkpoint 3:** the server builds on Linux with the SDK from A8 (show output); supervisor/allowlist logic passes unit tests on Linux; the real USB flow (list Pixel, push + verify server, clean up on quit) is written up in `REAL_DEVICE_CHECKS.md`.

---

## 🔶 MILESTONE 1 — one third done (after Phase 3) (stop here and deliver)
Before starting the next phase, **stop and output**:
1. **The complete source code so far** — every file in full, each preceded by its path, nothing truncated, no "unchanged" placeholders. Unfinished parts are allowed but must compile; clearly mark unfinished functions with `// MILESTONE 1: not yet implemented — see HANDOFF.md`. If it is too long for one reply, split it into numbered parts ("Part 1 of N") and finish with a file list so I can check nothing is missing.
2. **`HANDOFF.md`** (full spec — template below) covering everything up to the end of Phase 3.
3. A short status line: what works now, what I can test now, and the exact commands to build what exists.
Then **wait for me to say "continue"**.

### HANDOFF.md — required contents (full spec, every detail)
Write it so a **fresh model with no other context** can continue the build perfectly. Never summarise vaguely; include exact values.
1. **Header:** project name, version, milestone number, date, which phases are complete / in progress / not started.
2. **The full spec:** paste PART A (A1–A9) and every phase section (Phases 1–11) of this prompt **verbatim**, so no requirement is lost. Mark each requirement ✅ done · 🟡 partial · ⬜ not started.
3. **Decisions made so far** and why (library/API choices, deviations from this prompt, anything I approved).
4. **Exact values in use:** bundle ids, certificate name, adb server port, scrcpy version + SHA-256s, Rust toolchain/crate versions (rustls, aws-lc-rs), the C ABI function list, SDK/build-tools/NDK versions, ciphers/groups, timeouts, fps/bitrate defaults, window size constants, corner-radius fallback, file paths, Keychain item labels.
5. **File tree** with a one-line purpose for every file.
6. **Full build, sign, package & install commands** (Phase 10.4 + APK + server) as they currently work.
7. **Test status:** every checkpoint result, failing tests, known bugs with steps to reproduce, open security findings.
8. **Next steps:** an ordered to-do list, starting with the exact next file/function to write.
9. **Rules to keep obeying:** A3 rules 1–10 (especially 9 — honesty & evidence), A7 scope, monochrome UI, no Xcode/Homebrew, rate limits, author credit "ButcheCassidy - The Nomadic Rebel", my Terminal-instruction style.
10. **Resume instruction** at the top: "Paste this file plus the latest source bundle into a new chat and say: *Continue CarbonMirror from the Next steps in HANDOFF.md.*"

---

## Phase 4 — Backend: mirroring pipeline (USB first)

1. **scrcpy protocol client** in Swift: device meta, video stream and control stream **only** (`audio=false`; `clipboard_autosync` follows the clipboard toggle). Accept only an allowlist of device messages (clipboard **text** ≤ 1 MB, UHID keyboard output, and a small fixed-size **battery status** message — level 0–100 + charging yes/no — sent by the server every 30 s and on change); drop and log (metadata only) anything else. Tunnel via `adb forward` to 127.0.0.1.
2. **Corner radius**: on connect read the device's rounded-corner radius (`adb shell dumpsys display` → `RoundedCorner … radius=`); if unavailable, use the fallback. Feed it to the window mask.
3. **Decode**: `VTDecompressionSession` (hardware), low-latency real-time settings; H.264 and H.265.
4. **Render**: `CVMetalTextureCache` from IOSurface-backed `CVPixelBuffer` (zero CPU copies) → Metal shader (correct BT.709/BT.2020 colour) → `CAMetalLayer`, ProMotion-paced. Always draw the **newest** frame; drop stale ones; zero display buffer.
5. **USB "Performance" profile**: 120 fps (`max_fps=120`), H.264, 32 Mbps, native resolution. **Adaptive fallback**: measure delivered fps over 3 s; if < 110, step max size 2992 → 2560 → 2240 → 1920 before lowering fps. Phone is charging, so no power throttling.
6. Debug HUD (⌥⌘D, hidden by default): fps, decode time, end-to-end latency estimate, bitrate, codec, transport, TLS suite.

**Checkpoint 4:** protocol client decodes the synthetic test streams from A8 in Linux tests (framing, keyframes, config packets, rotation changes); real 120 fps USB mirroring, CPU, colours and corner mask go into `REAL_DEVICE_CHECKS.md`.

---

## Phase 5 — Backend: input & control (full duplex)

1. Mirror the **main display** (not a virtual display) so phone and Mac stay identical. Phone screen stays **on** by default (toggle: "Turn phone screen off while mirroring").
2. Mapping: click = tap; drag = swipe; long press = hold; two-finger trackpad scroll = smooth scroll events; trackpad pinch = two-finger pinch; right-click = Back (setting).
3. Keyboard: two typing modes (details in 8.2.3) — **Hardware keyboard** (UHID, default) and **Phone keyboard** (SDK key injection with the phone's on-screen keyboard kept available).
4. Toolbar actions & shortcuts: ⌘1 Home, ⌘[ Back, ⌘2 Recents, ⌘3 App drawer (KEYCODE_ALL_APPS, fallback swipe-up), ⌘4 Notifications, ⌘5 Quick Settings, ⌘S Screenshot to Mac (PNG of the current frame, full native resolution, into `~/Pictures/CarbonMirror/`, filename `CarbonMirror-YYYY-MM-DD-HHmmss.png`), ⌘⇧S Screenshot on the phone only, ⌘⇧C toggle clipboard sync, ⌘R Rotate, ⌘L Lock, ⌘↑/⌘↓ Volume, ⌘0 Real size, ⌘P Pin on top.
5. Input events go out on a dedicated high-priority queue; coordinates mapped through the current rotation and scale.
6. Clipboard (A7): when on, Mac → phone sends the Mac's plain-text clipboard when it changes while the window is focused; phone → Mac sets the Mac clipboard when the phone copies text. Rich content, images and files are ignored. No audio forwarding — phone sound stays on the phone.

**Checkpoint 5:** input-mapping, shortcut and clipboard-filter tests pass on Linux against the virtual phone (Phase 11) — every event arrives with correct coordinates/keycodes; real-device behaviour (typing in a password field, hand use mirrored within one frame, screenshot saved) goes into `REAL_DEVICE_CHECKS.md`.

---

## Phase 6 — Wireless & Mullvad LAN-sharing compatibility

### 6.1 Transport
- **Android Wireless Debugging only** (adb over TLS, Android 11+). **Legacy `adb tcpip 5555` (plaintext) is forbidden** — detect and refuse it in code.
- "Secure" profile defaults: 60 fps, H.265 (fallback H.264), 12 Mbps, adaptive bitrate on loss/latency. Option: 90/120 fps "Experimental" on Wi-Fi 6E/7.

### 6.2 Mullvad LAN-sharing compatibility (must pass)
- Mullvad's *Local network sharing* allows traffic both ways only to: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`, `fe80::/10`, `fc00::/7`. Multicast is **outgoing only**. There are **no port restrictions**.
- Enforce an allowlist in code: connect **only** to those ranges; **reject any public IP**.
- **Bind to the physical interface**: Mullvad's tunnel (`utun*`) itself uses addresses inside `10.0.0.0/8` (e.g. `10.64.0.0/10`). Use `NWParameters.requiredInterfaceType = .wifi` (or the hotspot/Ethernet interface) and `prohibitedInterfaceTypes = [.other]` so phone traffic **never** goes into the VPN tunnel, and reject any destination whose route resolves to a `utun` interface.
- Connect by **IP address**, never hostnames (Mullvad DNS cannot resolve local names).
- **Discovery**: try mDNS (`_adb-tls-connect._tcp`) first. Because incoming multicast replies may be blocked, fall back to: last known IP for this network + ask for the **port** shown in the phone's Wireless debugging screen (type it, or scan a QR of `IP:port` if the user provides one). **No port scanning.**
- **Phone hotspot mode**: if the Mac is on the Pixel's hotspot, use the gateway IP — works within the same allowed ranges.
- **LAN-sharing self-check** on wireless start: probe reachability of the phone's IP over the physical interface and confirm the route is not via `utun` (the sandboxed app can't call the Mullvad CLI, so don't try). On failure show the "LAN sharing blocked" state with steps for Mac **and** phone Mullvad apps.
- README: add the native **Wireless debugging Quick Settings developer tile** on the phone to toggle it per session.

### 6.3 Auto switching
- Plug USB in mid-session → hand over to USB within ~1 s without closing the window. Unplug → hand over to wireless if a paired endpoint is reachable, else "Disconnected".
- Mode setting: Auto (default) / USB only / Wireless only.

**Checkpoint 6:** on the virtual LAN (Phase 11): allowlist, `utun` rejection, handover logic and encrypted-only traffic pass with captures shown; Mullvad + real Wi-Fi + hotspot checks go into `REAL_DEVICE_CHECKS.md`.

---

## Phase 7 — Security: pairing, encryption, key management

### 7.1 Threat model (write into `SECURITY_NOTES.md`)
Hostile devices on the LAN or hotspot; passive sniffing; active MITM; a different phone trying to pair; malware on the Mac capturing the window; a stolen Mac; stale or corrupted keys.

### 7.2 First-time pairing — QR (like Mochi)
- Use Android's native **Wireless debugging → "Pair device with QR code"**. Mac shows a full-window monochrome QR encoding `WIFI:T:ADB;S:<random service name>;P:<random ≥128-bit password>;;` and advertises the pairing service; the phone scans it. This runs adb's SPAKE2-authenticated key exchange and establishes mutual TLS trust.
- Codes are single-use, expire after **120 s**, generated with `SecRandomCopyBytes`.
- After pairing, **pin** the device: adb TLS certificate fingerprint (SHA-256) + serial. Any other device or changed fingerprint → "Untrusted device".
- Fallback: 6-digit pairing code entry.

### 7.3 Inner encryption layer (always on wireless)
- **TLS 1.3 only** (there is no TLS 1.4). Mutual authentication with pinned certificates.
- Cipher suite: **`TLS_AES_256_GCM_SHA384`** (AES-256-GCM). Only if unavailable: `TLS_CHACHA20_POLY1305_SHA256`. Refuse everything else; log the negotiated suite.
- Key exchange: prefer hybrid post-quantum **`X25519MLKEM768`** where both stacks support it, else X25519. Show the negotiated group in the debug HUD.
- Implementation: **the same Rust `carbon-core::tls` module on both ends** (A9). Mac: Swift owns the Network.framework TCP connection (interface binding, `utun` rules) and feeds bytes through rustls via `CMCoreBridge`. Phone: the forked server feeds its socket bytes through `libcarbon_core.so` via JNI. Do **not** use Network.framework's own TLS or Conscrypt for the inner layer — one implementation, one policy, testable on Linux.
- Per session: Mac generates a fresh ephemeral **Ed25519** certificate, signed by its long-term identity key (7.4); the phone server generates its own ephemeral Ed25519 certificate at start and sends the fingerprint over the already-authenticated adb channel → pinned for that session. The phone also pins the Mac identity public key at first pairing and checks that every session certificate is signed by it — so even a compromised adb channel can't substitute a Mac. Temporary key files on the phone (`/data/local/tmp`) are deleted right after the server reads them.
- Extra hardening: **no session resumption, no 0-RTT/early data** (every session is a full, fresh handshake — no replay window); ALPN `carbonmirror/1` required; **traffic keys refreshed** (TLS KeyUpdate) every 15 minutes or 4 GiB, whichever comes first; certificate verifiers accept **only** the pinned keys (no CA trust, no hostname logic); handshake timeout 10 s; any alert or decrypt error ends the session.
- USB: inner TLS off by default; Settings toggle "Encrypt over USB too".

### 7.4 Long-term keys & storage
- **Mac identity key**: **ECDSA P-384** key created with `SecKeyCreateRandomKey` in the login Keychain, `kSecAttrIsExtractable = false`, access-control list limited to CarbonMirror's code signature. It never leaves the Keychain: rustls signs with it through a custom `SigningKey` that calls back into Swift (`SecKeyCreateSignature`, `ecdsaSignatureMessageX962SHA384`), so the private key never enters Rust or app memory. (The data-protection keychain and Secure Enclave require an Apple Developer Team ID, which a self-signed local certificate doesn't have — note this in `SECURITY_NOTES.md` as a future upgrade, don't fake it.)
- **adb key pair** (needed by adb): in the app-private adb dir, 0600; its fingerprint is mirrored into the Keychain so tampering is detected (fingerprint mismatch at launch → treat as corrupted).

### 7.5 Key regeneration & recovery ("Create new key")
Wireless authentication can fail for odd reasons (phone revoked authorisations, Android reset adb trust, corrupted key file, Keychain item lost, OS update). The app must recover cleanly **without ever silently trusting a new or unknown key**:
1. **Detect**: classify failures — adb `unauthorized`/`failed to authenticate`, TLS handshake failure, pin mismatch, key file/Keychain fingerprint mismatch, missing key.
2. **Retry first**: one automatic retry with backoff (network blips are not key problems). Then show the **"Authentication failed"** state with **Retry** and **Create new key**.
3. **Create new key** (also in Settings → Security, and in the menu bar):
   - Confirm dialog (monochrome) explaining: "This replaces this Mac's key and forgets the paired phone. You'll scan a new QR code."
   - Securely delete old Keychain items and the old adb key files (overwrite then remove), clear all device pins and cached endpoints.
   - Generate a **new** Mac identity key (Keychain) and a **new** adb key pair.
   - Restart the adb server with the new key and immediately launch the QR pairing flow (7.2).
   - Tell the user to tap **Revoke USB debugging authorizations** on the phone and remove the old entry under *Wireless debugging → Paired devices*.
   - Write a metadata-only event to the log ("key rotated", timestamp) — never key material.
4. **Pin mismatch from a known device** is shown as a possible MITM warning first ("This phone's identity changed"), with Create new key only after explicit confirmation.
5. **Optional scheduled rotation**: reminder every N days (default 180, configurable or off) to run Create new key.
6. **Unit tests**: each failure class maps to the right state; old keys are gone after regeneration; a new key is never trusted without a completed QR pairing.

### 7.6 Hardening
- The Mac app **never listens on a network interface** (adb server on 127.0.0.1 only; all connections outbound).
- **Local socket protection:** the localhost ports created by `adb forward` could be reached by other processes on the Mac, so every session uses a random 256-bit session secret that the server must receive first (and the inner TLS pins) before any video or control data flows. Wrong or missing secret → connection dropped.
- End session and wipe session keys from memory on: Mac lock, sleep, lid close, user switch, change to an unknown network, or **10 min idle** (configurable).
- Window `sharingType = .none` by default to keep the phone out of screen recordings/screen sharing. Toggle in Settings. Newer macOS versions may not honour this for every capture method — test it and report honestly what it does and doesn't block.
- Clipboard: plain text only, ≤ 1 MB, never logged or written to disk, wiped from memory on disconnect; the app reads `NSPasteboard` only while sync is on and the window is focused.
- Nothing written to disk except screenshots I explicitly take (to `~/Pictures/CarbonMirror/`). No frame caches, thumbnails or input logs. Logs: metadata only, rotate at 1 MB.
- "Forget device" removes pins, endpoints and cached data.
- GrapheneOS notes in README: keep Wireless/USB debugging off when not mirroring.

### 7.7 Segregation from the rest of the Mac (A7 in practice)
- **App Sandbox ON** with the minimal entitlements from Phase 1 — the app's own container plus `~/Pictures/CarbonMirror/` (screenshots) are the only places it can write. adb runs inside the sandbox (child processes inherit it). If adb truly cannot work sandboxed, move adb + transport into a **separate sandboxed XPC helper** with only USB + network entitlements and keep the UI app sandboxed — never just turn the sandbox off; document what you did.
- **adb command allowlist:** all adb calls go through one wrapper that permits only fixed templates — `devices`, `pair`, `connect`/`disconnect` (private-range IPs only), `forward` to 127.0.0.1, `push` of the hash-verified server and `libcarbon_core.so` to their fixed paths, `shell` with fixed templates (start server via `app_process`, `settings put global adb_wifi_enabled 0`, `pm grant` for the companion, `dumpsys display` for the corner radius, `rm` of the server's own temp files), and `install` of the companion over **USB only** after my confirmation. Everything else is refused and logged. No user-supplied strings are ever passed into shell commands.
- **Server fork stripped down:** remove audio capture, file push/install and any app-data paths from the forked scrcpy-server so they cannot be re-enabled by a message. Keep video capture, input injection, app launch by package name, **plain-text** clipboard get/set (≤ 1 MB, non-text clip types ignored) and the battery status message (read in-process from the system battery service — no extra adb shell commands).
- **Minimal attack surface on the Mac:** the only data the Mac parses from the phone is the video stream and allowlisted device messages; every length field is bounds-checked; malformed data ends the session.
- **No inbound anything:** no listening network ports (A7/7.6), no URL schemes, no Services menu items, no Apple Events, no shared app-group containers.

**Checkpoint 7.7:** on Linux, tests prove the adb wrapper refuses non-allowlisted commands and injection strings, and that file/audio/unknown messages and oversized or non-text clipboard data from the phone side are dropped. The sandbox checks (can't read `~/Documents`, can write only container + `~/Pictures/CarbonMirror/`) go into `REAL_DEVICE_CHECKS.md`.

**Checkpoint 7:** against the virtual phone: inner TLS negotiates TLS 1.3 + AES-256-GCM (show output), TLS 1.2/other ciphers and wrong pins are rejected, and the Create-new-key state machine replaces keys and forces re-pairing. Real QR pairing and Keychain behaviour go into `REAL_DEVICE_CHECKS.md`.

---

## 🔶 MILESTONE 2 — two thirds done (after Phase 7) (stop here and deliver)
Before starting the next phase, **stop and output**:
1. **The complete source code so far** — every file in full, each preceded by its path, nothing truncated, no "unchanged" placeholders. Unfinished parts are allowed but must compile; clearly mark unfinished functions with `// MILESTONE 2: not yet implemented — see HANDOFF.md`. If it is too long for one reply, split it into numbered parts ("Part 1 of N") and finish with a file list so I can check nothing is missing.
2. **`HANDOFF.md`** (full spec — template below) covering everything up to the end of Phase 7.
3. A short status line: what works now, what I can test now, and the exact commands to build what exists.
Then **wait for me to say "continue"**.
Use the same `HANDOFF.md` template as Milestone 1, fully rewritten (not a diff) so it stands alone.

---

## Phase 8 — Settings, menu bar, app icon & extras

### 8.1 App icon (provided — use as-is)
- I supply `CarbonMirror-icon.svg` (source) and `CarbonMirror-icon-1024.png` (1024 × 1024, macOS icon grid: 824 × 824 continuous-corner body centred, with its shadow). Put both in `Resources/`. **Do not redraw or restyle it.**
- Design (for reference only): black continuous-corner body with a subtle top-to-bottom grey-to-black gradient; two continuous-corner phone shapes — a solid **yellow** one behind (offset up-right) and a translucent **white glass** one in front (offset down-left, white outline) containing a **4 × 4 grid of small coloured squircle app tiles** in its lower half. It is the only coloured element in the whole app; the UI itself stays monochrome.
- Build `CarbonMirror.icns` from the 1024 PNG with `sips` + `iconutil` (commands in Phase 10.4). Set `CFBundleIconFile` = `CarbonMirror` in `Info.plist` (no asset catalog — `actool` needs Xcode).
- Menu-bar icon: a separate **monochrome template image** (two overlapping phone outlines, no colour, no grid), drawn in code at 18 pt so it adapts to light/dark menu bars.
- Companion APK icon (Phase 9): Android adaptive icon — background layer solid black, foreground layer = the two phones + grid from the SVG, scaled into the 66 dp safe zone; monochrome layer = white phone outlines (for themed icons).

### 8.2 Experience upgrades (beat Apple's iPhone Mirroring on its known weak spots)
Reviewers' common complaints about iPhone Mirroring are sessions pausing when switching desktops, having to click Connect again, no autocorrect control, privacy in public places, and no at-a-glance phone status. Fix each one:

**8.2.1 Never pause across Spaces or when hidden**
- Switching desktops (Spaces), minimising, covering the window or going full-screen in another app must **never** end or pause the session.
- When the window is fully hidden (`NSWindow.occlusionState`), stop **rendering** but keep the session and control channel alive. Keep decoding for up to 5 s; after that, also pause decoding to save power, and on return send scrcpy's reset-video request so a fresh keyframe arrives — the current screen should appear within ~150 ms.
- Window collection behaviour: works on any Space, and with "Pin on top" it can follow me across Spaces (`.canJoinAllSpaces`, toggle).

**8.2.2 Silent auto-reconnect**
- After Wi-Fi blips, Mac wake, USB↔Wi-Fi switches or the phone's network changing, reconnect automatically with backoff (0.5 s, 1, 2, 4, 8, then every 30 s) — no button to click. Show "Reconnecting…" in the status line (8.2.5) with the last frame dimmed, not an error screen.
- Only ever reconnect to the **pinned** device with the full security handshake (Phase 7); never while the Mac is locked or asleep; stop after 10 minutes and show the "Disconnected" state.

**8.2.3 Typing modes (autocorrect choice)**
- Toolbar toggle + Settings default + shortcut ⌥⌘K:
  - **Hardware keyboard** (UHID): behaves like a real physical keyboard — exact keys, no autocorrect, works in password fields.
  - **Phone keyboard** (SDK key injection): the phone's on-screen keyboard stays available so its suggestions/autocorrect can be used where the keyboard app supports it.
- Test on the GrapheneOS keyboard and Gboard and **report honestly** what autocorrect actually does in each mode (Android keyboards treat hardware-key input differently) — don't promise behaviour you haven't confirmed.

**8.2.4 Privacy blur**
- **Instant hide:** ⌘⇧H (and a toolbar button) blurs the mirrored screen immediately and pauses rendering of real content; press again or click the window to reveal.
- **Auto-blur:** optional, off by default — blur after N seconds without focus (5 / 10 / 30 / 60 s), and always when the Mac's screensaver starts or the display sleeps.
- **Reveal protection:** optional "Require Touch ID to reveal" (LocalAuthentication, falls back to my Mac password).
- The blur is a heavy Gaussian blur plus dark tint done in Metal on a downscaled frame, so text is unreadable; a small monochrome lock glyph sits in the centre. While blurred, input to the phone is blocked.
- The session stays connected while blurred (no reconnect delay when revealing).

**8.2.5 Status line (in the toolbar)**
- A single thin line under the toolbar buttons, in the system font (**SF Pro**, 11 pt, tabular digits; secondary white ~60 %), monochrome SF Symbols only. Example: `􀛨 84 % · Charging   ·   USB · 120 fps · 9 ms · Excellent`.
- **Battery:** level + charging glyph (`battery.100percent.bolt` etc.) from the battery status message (Phase 4); updates every 30 s or on change.
- **Connection quality:** transport (USB / Wi-Fi 🔒), delivered fps, round-trip latency (measured on the control channel), and a word — Excellent / Good / Fair / Poor — from fixed, documented thresholds. Shows "Reconnecting…" during 8.2.2.
- Updates at most once per second; no extra network traffic beyond the existing streams. Toggle in Settings.

**8.2.6 Landscape (optional)**
- Setting **"Offer landscape window when the phone rotates"** (on by default), plus a choice of *Ask* (default) / *Always rotate* / *Stay portrait*.
- *Ask*: when the phone turns landscape, keep the window as it is (landscape content letterboxed inside) and show a small monochrome pill at the top — "Switch to landscape" · "Not now". Accepting rotates the window to the landscape aspect ratio (same size rules as 2.5); turning the phone back to portrait returns automatically.
- *Stay portrait*: never rotates the window. *Always rotate*: rotates straight away.

**Checkpoint 8.2:** Linux tests for the reconnect state machine (backoff timings, pinned-only, locked-Mac refusal), privacy-blur state (input blocked while blurred), quality thresholds and status-line formatting, battery-message parsing (including fuzzing), and the landscape setting logic. Visual checks (blur unreadable, status line look, Spaces behaviour, Touch ID reveal) go into `REAL_DEVICE_CHECKS.md`.

### 8.3 Settings & menu bar
- **Settings window** (monochrome): Connection (Auto/USB/Wireless, fps/bitrate/codec per profile) · Display (corner fine-tune, real-size reference, remember size) · Experience (privacy blur: auto-blur delay, Touch ID to reveal; typing mode default; landscape behaviour; power saving when hidden; status line on/off; pin across Spaces) · Security (USB encryption, idle timeout, hide from capture, clipboard sync, Create new key, Forget device, rotation reminder) · Screenshots (open folder) · General (launch at login via `SMAppService`, shortcuts list) · About (version, **ButcheCassidy - The Nomadic Rebel**, licences).
- **Menu-bar extra**: Connect/Disconnect, Mode, Pair new device, Create new key, Forget device, Settings, Quit.
- Background agent (launch at login) only watches USB attach and paired endpoints; opens **no** ports.

**Checkpoint 8:** every setting persists and takes effect live without restarting the session (except codec, which restarts the stream seamlessly).

---

## Phase 9 — Android companion APK (GrapheneOS-first)

### 9.1 Purpose (keep it tiny)
"CarbonMirror Companion" exists only to make wireless sessions easy and safe to start. It does **not** stream, store or send anything.
1. **Quick Settings tile "CarbonMirror"**: tap → turns **Wireless debugging** on (`Settings.Global` `adb_wifi_enabled`), tile shows Off / Ready / Mirroring. The Mac turns Wireless debugging **off** itself over adb when a session ends (`settings put global adb_wifi_enabled 0`), so it is never left on.
2. Writing that setting needs `WRITE_SECURE_SETTINGS`, which apps can't request — the Mac app grants it once over USB during setup (`adb shell pm grant com.nomadicrebel.carbonmirror.companion android.permission.WRITE_SECURE_SETTINGS`), only after I confirm. If the grant is missing, the tile opens *Developer options → Wireless debugging* instead of failing.
3. Installed by the Mac app over USB (`adb install`) with my confirmation; also available as a plain signed APK file.

### 9.2 Permissions (minimum possible)
- **No `INTERNET`**, no network, location, notification, storage, camera, microphone, contacts or boot permissions. Only `WRITE_SECURE_SETTINGS` (dev-granted) and `BIND_QUICK_SETTINGS_TILE` on the tile service.
- No exported components except the tile service (protected by the system permission). `android:allowBackup="false"`, `android:usesCleartextTraffic="false"`, no `debuggable`.

### 9.3 GrapheneOS compatibility & update resilience
GrapheneOS **fully AOT-compiles apps at install and after every OS update ("Optimizing apps")**, has no JIT, may restrict dynamic code loading per app, uses hardened_malloc, and after an update may show "Restart apps" or reset special permissions. Therefore:
- Plain **Java, framework APIs only** — no Kotlin stdlib, no AndroidX, no Google Play Services, no Firebase, no native code (`.so`), no reflection on hidden APIs, **no dynamic code loading**, no runtime code generation. Nothing that depends on JIT profiles.
- **Stateless**: the tile reads the real state from `Settings.Global` every time it is shown or tapped; nothing is cached across process death. It works immediately after "Optimizing apps" / "Restart apps" without the user reopening anything. No background service, no foreground service, no alarms, no boot receiver to "restore" state.
- Check `WRITE_SECURE_SETTINGS` on every tap (`checkSelfPermission`); if an update reset it, fall back as in 9.1.2, and the Mac app silently re-grants it the next time USB is connected (and tells me it did).
- `minSdk 30`, `targetSdk` = latest stable (36). Works in the Owner profile (adb/Developer options are Owner-only on GrapheneOS — say so in the README).
- Test on GrapheneOS: install, tap tile, OS update + "Optimizing apps", tap tile again → must still work.

### 9.4 Build & signing (no Gradle, no network at sign time)
- Build with Android SDK command-line build-tools only: `aapt2 compile` / `aapt2 link` → `javac --release 17` against `android.jar` → `d8` → `zipalign -p 4` → `apksigner`. Script: `scripts/build-apk.sh`. SDK pieces are downloaded once per rule **A3.8** (sequential, ≤ 1 request/s, cached, backoff).
- **Signing is local.** Google Maven (`maven.google.com`) only hosts libraries and the Android Gradle Plugin — it does **not** issue signing certificates, so never try to fetch one. Create my own release key once with `keytool`:
  - keystore at `~/Library/Application Support/CarbonMirror/signing/carbonmirror-release.p12` (PKCS12, folder 0700), alias `carbonmirror`, **EC P-384** (`keytool -genkeypair -keyalg EC -groupname secp384r1 -sigalg SHA384withECDSA`; fall back to RSA 4096 only if a tool rejects it, and say so), validity 10 000 days, strong password I type in (never stored in scripts or the repo).
  - Sign with `apksigner sign --v2-signing-enabled true --v3-signing-enabled true`; verify with `apksigner verify --verbose --print-certs`.
  - README: back the keystore up — Android only accepts updates signed with the **same** key.
- If you ever choose Gradle instead: `org.gradle.parallel=false`, `--max-workers=1`, `org.gradle.internal.repository.max.retries=5`, `org.gradle.internal.repository.initial.backoff=2000`, and `--offline` after the first successful sync. Still sign locally as above.

**Checkpoint 9:** the APK builds and signs on Linux with a throwaway test key; `apksigner verify` and `aapt2 dump permissions` output shown (no permissions beyond 9.2). Install, tile and OS-update checks go into `REAL_DEVICE_CHECKS.md`; the release build is signed with my real key on my machine.

---

## Phase 10 — Testing, performance verification & delivery

### 10.1 Performance targets (measure and report)
| Metric | USB | Wireless (Wi-Fi 6E/7) |
|---|---|---|
| Glass-to-glass latency | ≤ 45 ms | ≤ 70 ms |
| Frame rate | 120 fps (adaptive) | 60 fps (90/120 experimental) |
| Mac CPU while mirroring | < 8 % | < 10 % |
| Idle memory (no session) | < 40 MB | — |

### 10.2 Automated tests
Protocol parsing · companion permission fallback · private-range allowlist + `utun` rejection · TLS policy · pinning · key-regeneration flow · aspect/size clamp math · failure-class → UI-state mapping.

### 10.3 Manual test checklist (include in README)
1. First pair via QR. 2. Reconnect after Mac and phone reboot. 3. USB → Wi-Fi → USB handover mid-session. 4. Mullvad on, LAN sharing on (both). 5. Mullvad LAN sharing off → correct "blocked" state. 6. Phone hotspot mode. 7. 120 fps over USB. 8. Use phone by hand while mirrored. 9. Rotate. 10. Resize 0.75× → max. 11. Lock Mac → session ends. 12. Revoke authorisations on phone → "Authentication failed" → Create new key → re-pair works. 13. Screen recording of the Mac doesn't show the phone window. 13a. Clipboard both ways (text only); toggle off stops it. 13b. Screenshot lands in `~/Pictures/CarbonMirror/`. 13c. Phone notifications show only in the mirrored screen, never in macOS Notification Centre. 13d. Switch Spaces and minimise for 2 minutes → session still live on return. 13e. Privacy blur (⌘⇧H, auto-blur, Touch ID reveal). 13f. Status line shows correct battery/charging and connection quality. 13g. Rotate phone → landscape offer appears; each Landscape setting behaves as described. 13h. Both typing modes, autocorrect behaviour noted. 14. Companion tile turns Wireless debugging on; session end turns it off. 15. GrapheneOS update → "Optimizing apps" → tile still works.

### 10.4 Build, sign & package the DMG (exact commands — same method as my Mochi Lite / Coucou Lite builds)
Write these into the README **exactly like this**, one command per line, each with a plain sentence before it. Local testing only: no Developer ID, **no notarisation**. On macOS 27 `hdiutil` prints a deprecation warning but still works.

**Step A. One-time: create the local "CarbonMirror Dev" signing certificate — strongest settings available without an Apple Developer account** (use the same one for its whole life so macOS keeps the app's permissions):
- **ECDSA P-384 key with SHA-384** (stronger than the RSA-2048 used for Mochi Lite), code-signing use only, valid 5 years.
- Imported as **non-extractable** (`-x`): the private key can't be exported from the Keychain again, and only `codesign` is allowed to use it (`-T`).
- The temporary file is protected by a **random one-time password** and deleted straight away.
```
printf '[req]\ndistinguished_name=dn\nprompt=no\n[dn]\nCN=CarbonMirror Dev\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' > cm-cert.cnf
/usr/bin/openssl ecparam -name secp384r1 -genkey -noout -out cm-key.pem
/usr/bin/openssl req -x509 -new -key cm-key.pem -sha384 -days 1825 -config cm-cert.cnf -extensions ext -out cm-cert.pem
export CM_P12_PASS="$(/usr/bin/openssl rand -hex 32)"
/usr/bin/openssl pkcs12 -export -inkey cm-key.pem -in cm-cert.pem -name "CarbonMirror Dev" -passout env:CM_P12_PASS -out cm-cert.p12
security import cm-cert.p12 -k ~/Library/Keychains/login.keychain-db -P "$CM_P12_PASS" -x -T /usr/bin/codesign
unset CM_P12_PASS
rm -f cm-key.pem cm-cert.pem cm-cert.p12 cm-cert.cnf
security find-identity -p codesigning
```
(`CSSMERR_TP_NOT_TRUSTED` next to it is normal for a self-made certificate.) Then test that `codesign` accepts the P-384 key:
```
cp /usr/bin/true /tmp/cm-sign-test
codesign --force --sign "CarbonMirror Dev" /tmp/cm-sign-test
codesign --verify --verbose=2 /tmp/cm-sign-test
rm /tmp/cm-sign-test
```
If that test fails, give me the fallback: the same commands with `/usr/bin/openssl req -x509 -newkey rsa:4096 -nodes -sha384 …` instead of the two P-384 lines, after deleting the failed identity with `security delete-identity -c "CarbonMirror Dev"`.

**Step A-2. One-time per adb update: download Google's platform-tools for macOS and record its checksum** (Google doesn't publish one):
```
mkdir -p deps
curl -fL --retry 5 -o deps/platform-tools-latest-darwin.zip https://dl.google.com/android/repository/platform-tools-latest-darwin.zip
shasum -a 256 deps/platform-tools-latest-darwin.zip | tee -a deps.lock
ditto -x -k deps/platform-tools-latest-darwin.zip deps/
codesign -dv deps/platform-tools/adb 2>&1 | grep Authority
cp deps/platform-tools/adb Resources/adb
```
(The Authority line should mention Google LLC.)

**Step A-3. One-time: install Rust on the Mac (official installer, no Homebrew):**
```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
source "$HOME/.cargo/env"
rustup target add aarch64-apple-darwin
cargo install cbindgen --locked
```
(If the aws-lc build ever asks for CMake, give me the official CMake download steps — not Homebrew.)

**Step B. Build the Rust core, then the app binary:**
```
cargo build --release --target aarch64-apple-darwin --manifest-path rust/carbon-core/Cargo.toml
cbindgen --config rust/carbon-core/cbindgen.toml --crate carbon-core --output rust/include/carbon_core.h rust/carbon-core
swift build -c release --arch arm64 2>&1 | tee build.log
grep -E ": error:|^ld:|Undefined symbols" build.log | sort -u | head -60
```

**Step C. Assemble the .app bundle:**
```
rm -rf build/CarbonMirror.app
mkdir -p build/CarbonMirror.app/Contents/MacOS build/CarbonMirror.app/Contents/Resources build/CarbonMirror.app/Contents/Helpers
cp .build/release/CarbonMirror build/CarbonMirror.app/Contents/MacOS/CarbonMirror
cp Resources/Info.plist build/CarbonMirror.app/Contents/Info.plist
cp Resources/adb build/CarbonMirror.app/Contents/Helpers/adb
cp Resources/carbonmirror-server build/CarbonMirror.app/Contents/Resources/carbonmirror-server
cp Resources/libcarbon_core.so build/CarbonMirror.app/Contents/Resources/libcarbon_core.so
cp Resources/CarbonMirrorCompanion.apk build/CarbonMirror.app/Contents/Resources/CarbonMirrorCompanion.apk
plutil -lint build/CarbonMirror.app/Contents/Info.plist
```

**Step D. Make the app icon (.icns) from the 1024 PNG:**
```
mkdir -p build/CarbonMirror.iconset
sips -z 16 16 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_16x16.png
sips -z 32 32 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_16x16@2x.png
sips -z 32 32 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_32x32.png
sips -z 64 64 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_32x32@2x.png
sips -z 128 128 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_128x128.png
sips -z 256 256 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_128x128@2x.png
sips -z 256 256 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_256x256.png
sips -z 512 512 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_256x256@2x.png
sips -z 512 512 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_512x512.png
cp Resources/CarbonMirror-icon-1024.png build/CarbonMirror.iconset/icon_512x512@2x.png
iconutil -c icns build/CarbonMirror.iconset -o build/CarbonMirror.app/Contents/Resources/CarbonMirror.icns
rm -rf build/CarbonMirror.iconset
```

**Step E. Sign inside-out (helper first, then the app) and verify:**
```
codesign --force --options runtime --timestamp=none --entitlements Resources/adb-helper.entitlements --sign "CarbonMirror Dev" build/CarbonMirror.app/Contents/Helpers/adb
codesign --force --options runtime --timestamp=none --entitlements Resources/CarbonMirror.entitlements --sign "CarbonMirror Dev" build/CarbonMirror.app
codesign --verify --deep --strict --verbose=2 build/CarbonMirror.app
```
(Should say "valid on disk" and "satisfies its Designated Requirement".)

**Step F. Make and sign the DMG:**
```
mkdir -p dist build/dmg
ditto build/CarbonMirror.app build/dmg/CarbonMirror.app
ln -s /Applications build/dmg/Applications
hdiutil create -volname "CarbonMirror 0.1.0" -srcfolder build/dmg -ov -format UDZO dist/CarbonMirror-0.1.0.dmg
rm -rf build/dmg
codesign --force --timestamp=none --sign "CarbonMirror Dev" dist/CarbonMirror-0.1.0.dmg
open dist/CarbonMirror-0.1.0.dmg
```
Then drag CarbonMirror onto Applications (choose Replace when updating). Or install straight away without the DMG:
```
osascript -e 'tell application id "com.nomadicrebel.carbonmirror" to quit'
rm -rf /Applications/CarbonMirror.app
ditto build/CarbonMirror.app /Applications/CarbonMirror.app
open /Applications/CarbonMirror.app
```

### 10.5 Final install guide for me — `INSTALL.md` (written last, after everything is built)
I'm not a coder. Write `INSTALL.md` as numbered steps, one command per line, a plain sentence before each, and what I should see after it. It must cover:
1. **What adb is and where it lives:** adb is **bundled inside CarbonMirror.app** (`Contents/Helpers/adb`) and runs only while CarbonMirror needs it. I do **not** install adb system-wide, add anything to my PATH, or keep a separate copy installed for the app to work. Say clearly whether anything adb-related stays on my Mac after quitting (its private folder in `~/Library/Containers/…` / Application Support and its key files) and why.
2. **Sizes, measured not guessed:** give me `du -sh` commands for: the installed app, the bundled adb, the `deps/` folder from Step A-2 (platform-tools download), the Rust toolchain (`~/.rustup`, `~/.cargo`), the build folders (`build/`, `.build/`, `rust/target/`), and the app's data folder — and tell me which ones I can delete after building and which I need to keep for future rebuilds.
3. **Cleanup commands** for each deletable item, and how to remove the Rust toolchain entirely (`rustup self uninstall`) if I stop rebuilding.
4. **Installing the Mac app:** opening the DMG, dragging to Applications, first-launch prompts (Local Network, USB) and what to allow.
5. **Phone setup (GrapheneOS and stock Android):** turning on Developer options (tap *Build number* 7 times), USB debugging, Wireless debugging, the Quick Settings developer tile, Mullvad *Local network sharing* on the phone **and** the Mac, installing the companion APK via the app, adding the CarbonMirror tile.
6. **First connection:** USB first, then QR pairing for wireless — with what each screen should look like.
7. **Full uninstall:** delete the app, its data folders, its Keychain items and the "CarbonMirror Dev" certificate (`security delete-identity -c "CarbonMirror Dev"`), and on the phone: uninstall the companion, *Revoke USB debugging authorizations*, remove the Mac under *Wireless debugging → Paired devices*, turn Developer options off.
8. **Signing everything on my Mac, with the strongest settings (exact commands):**
   - Creating the P-384 "CarbonMirror Dev" certificate (Step A, including the `codesign` test and the RSA-4096 fallback).
   - Signing the bundled adb, the app and the DMG (Steps E–F), in the right order.
   - **Checking the signatures**, with what I should see: `codesign -dvvv` on the app must show `Authority=CarbonMirror Dev`, `Runtime Version` (hardened runtime on) and a SHA-256 CodeDirectory hash; `codesign -d --entitlements - ` must list exactly the Phase 1 entitlements; `codesign --verify --deep --strict --verbose=2` must say "valid on disk" and "satisfies its Designated Requirement"; the same verify on the DMG. Be honest that `codesign` always uses SHA-256 for code hashes — the P-384/SHA-384 strength is in the certificate's signature, which is the part I control.
   - Why macOS Gatekeeper will still warn (self-signed, not notarised) and the exact safe way to open it the first time (System Settings → Privacy & Security → *Open Anyway*), without turning Gatekeeper off.
   - **Signing the release APK on my Mac** with my own P-384 key, so the key never leaves my machine: installing a JDK and the Android build-tools for macOS **without Homebrew** (official installers/zips only), creating the keystore with `keytool` (9.4), signing with `apksigner` (v2 + v3), verifying with `apksigner verify --verbose --print-certs` (what the output should show), and backing up the keystore.
   - Re-signing after every rebuild, and what to do if the certificate expires in 5 years (make a new one; macOS will ask for permissions once more).
9. **Troubleshooting** for the 10 most likely problems, each with a symptom and a fix.

### 10.6 Deliverables
1. Full Swift Package source + forked scrcpy-server source + companion APK source, with `CarbonMirror-icon.svg` and `CarbonMirror-icon-1024.png` in `Resources/`.
2. `scripts/build.sh` (runs 10.4 B–F), `scripts/build-server.sh`, `scripts/build-apk.sh`, `scripts/make-cert.sh` (runs 10.4 A) → `dist/CarbonMirror-<version>.dmg` and `dist/CarbonMirrorCompanion-<version>.apk`. No Xcode, no Homebrew.
3. `INSTALL.md` (10.5), `README.md` (overview + build commands), `SECURITY_NOTES.md`, `THIRD_PARTY_NOTICES.md`, `CHANGELOG.md`.

---

## Phase 11 — Four-stage release bug check (mandatory before publishing)

**You cannot access my Mac or my phone — test virtually, and be honest about what that covers.**
- All core logic (protocol parsing, TLS policy, IP allowlist + `utun` rejection, adb allowlist, key/pairing state machine, failure → UI-state mapping, size/aspect maths, input mapping) lives in the Rust core and is tested **from both Rust and Swift** on Linux with the shared test vectors (A9). Keep AppKit/Metal/VideoToolbox/Keychain wrappers thin.
- Build a **virtual phone** in `tools/virtualphone/`: a fake device that speaks the real protocol (handshake, session secret, inner TLS 1.3 with the same constraints, synthetic H.264 test-pattern video at 60 and 120 fps), records every input message it receives, and can be switched into **attacker mode** (wrong certs, downgrades, fuzzing, replay, oversized/non-text clipboard, file/audio messages, plaintext `adb tcpip`-style endpoint).
- Build a **virtual LAN**: separate network namespaces (`ip netns`) or loopback aliases on a private subnet for "Mac", "phone" and "attacker", plus a fake `utun` route, so routing and allowlist rules are exercised for real.
- Run the forked server's Java TLS/session code on a desktop JVM against the Swift client logic where possible. Use an Android emulator only if your environment supports it — don't depend on it.
- Anything that genuinely needs my hardware goes into **`REAL_DEVICE_CHECKS.md`**: numbered steps I can finish in **about 5 minutes**, each with the exact action and expected result. Those items stay marked `NOT RUN — needs real device` until I report back; never mark them passed yourself.

Do **not** produce a release DMG/APK until all four stages pass. Run them **in order**; any fix restarts the stage it was found in and re-runs every earlier stage it could affect. Record everything in `RELEASE_CHECK.md` (finding · severity Critical/High/Medium/Low · file:line · fix · re-test result). In your Linux environment use the tools from A8 plus harnesses you write in `tools/`. Any command you give me to run on my Mac must use only built-in macOS tools (`tcpdump`, `lsof`, `nettop`, `nc`, `/usr/bin/openssl`, `log`, `leaks`, `python3`) — no Homebrew.

### Stage 1 — Static review & build hygiene
- Read every source file line by line for: force unwraps/`try!` on untrusted data, integer overflow in length fields, unchecked buffer sizes, data races (Swift 6 strict concurrency must compile with **zero warnings**), retain cycles, unclosed sockets/processes, main-thread blocking, missing error paths.
- Search for secrets/content in logs, hard-coded passwords, debug flags, leftover test endpoints, `print` of key material.
- Verify Info.plist, entitlements (exactly the Phase 1 list — sandbox on, network.server used only for adb on 127.0.0.1, nothing else), hardened runtime, `codesign --verify --deep --strict`, APK manifest (`aapt2 dump badging`, `apksigner verify --print-certs`), no extra permissions.
- Dependency audit: scrcpy/adb/build-tools/NDK versions pinned and hash-verified; `Cargo.lock` committed; `cargo audit` clean; licences listed.
- Rust: `cargo clippy --all-targets -- -D warnings` clean; `unsafe` appears only in the `ffi` module and every block has a `// SAFETY:` comment; no `unwrap`/`expect`/indexing panics on data from the phone; no panic can cross the FFI boundary.

### Stage 2 — Functional & regression
- Full unit test suite green on Linux (show output). Everything from the manual checklist (10.3) that can be simulated runs against the virtual phone/LAN; the rest is listed in `REAL_DEVICE_CHECKS.md` as `NOT RUN`.
- Edge cases: phone locked when connecting, phone reboots mid-session, Wi-Fi drops for 5 s / 60 s, Mac sleeps mid-session, two phones plugged in, unplug during pairing, rotate during resize, window at min/max size, very fast typing and long typed text, non-English keyboard layout, Do Not Disturb, Mullvad reconnecting mid-session.
- GrapheneOS (real device → `REAL_DEVICE_CHECKS.md`): OS update → "Optimizing apps" → companion tile + reconnect still work.

### Stage 3 — Security stress test & attack simulation (most important)
Write harnesses in `tools/sectest/` and attack the app as a hostile LAN device would. Every test must **fail safely** (connection refused, session ended, clear UI state) — never fall back to weaker security.
1. **TLS downgrade:** try TLS 1.0/1.1/1.2 and weak suites against the inner TLS endpoint (`openssl s_client -tls1_2 …`, custom cipher lists, a rustls client configured with TLS 1.2 / AES-128 / non-PQ-only groups) → all must be rejected. Confirm the negotiated suite is `TLS_AES_256_GCM_SHA384` (or the allowed fallback) and log the group (X25519MLKEM768/X25519).
2. **MITM / impersonation:** present a self-signed cert with the right subject but wrong key; a session cert **not** signed by the pinned Mac identity key; attempt session resumption and 0-RTT early data (must be refused); a valid cert from a different pairing; an expired cert; a swapped phone fingerprint → all refused with "Untrusted device"/"Identity changed". Verify nothing is auto-trusted.
3. **Plaintext & leakage check:** `sudo tcpdump -i en0 -w capture.pcap host <phone-ip>` during a wireless session; scan the capture for any readable strings, frame data or typed text (entropy check with a Python script). Must find nothing readable beyond TLS handshakes.
4. **Legacy path refusal:** the virtual phone offers a plaintext `adb tcpip`-style endpoint (port 5555) → the client must refuse it and show the warning. (Real-device repeat in `REAL_DEVICE_CHECKS.md`.)
5. **Exposure scan:** `lsof -nP -iTCP -sTCP:LISTEN` and `lsof -nP -iUDP` on the Mac → only 127.0.0.1 listeners. From the attacker namespace on the virtual LAN, scan the "Mac" address (rate-limited Python scanner or `nc -zv`) → no CarbonMirror/adb port reachable. Give me the Mac `lsof` commands for the real check.
6. **Routing:** confirm with `nettop`/`lsof` that phone traffic never uses a `utun` interface with Mullvad connected; feed the allowlist public IPs, Mullvad tunnel IPs (10.64.x.x), IPv6 global addresses, malformed addresses → all rejected.
7. **Pairing attacks:** reuse an old QR/pairing code, use one after 120 s, pair a second unknown virtual phone → all fail safely. Android itself rate-limits 6-digit code guessing — verify our client never falls back to anything weaker, and list the real brute-force check in `REAL_DEVICE_CHECKS.md`.
8. **Protocol fuzzing:** property/fuzz tests on the Rust `protocol`, `policy` and `tls` entry points (`proptest` in `cargo test`, plus Python `hypothesis` through the virtual phone) with malformed, truncated, oversized (length fields up to 2³²−1) and random input for at least 2 minutes each → no panic, no hang, no memory growth; session ends cleanly. Also fuzz the C ABI from Swift tests (null/zero-length/huge pointers-and-lengths).
9. **Replay & injection:** replay captured encrypted records; inject control messages on the forwarded local port from another local user/process → rejected (per-session auth on local sockets).
10. **Key handling:** after "Create new key", confirm (virtually: the key-store abstraction; on my Mac: `security find-generic-password`/`find-key` commands in `REAL_DEVICE_CHECKS.md`) that old Keychain items and old adb key files are gone; new key never trusted before QR pairing. Corrupt the key file and Keychain fingerprint → correct "Authentication failed" path.
11. **Session hygiene:** lock Mac / sleep / idle timeout / network change → session ends, keys wiped; screen recording (`screencapture`) of the desktop doesn't show the phone window; logs (`log show --predicate 'subsystem == "com.nomadicrebel.carbonmirror"'`) contain no content or secrets.
11a. **Privacy blur & reconnect:** while blurred, injected input from the Mac is dropped; auto-reconnect only ever targets the pinned device and never runs while the Mac is locked; a forged battery message with out-of-range values or wrong size is rejected.
12. **Companion APK:** `adb shell dumpsys package com.nomadicrebel.carbonmirror.companion` → only the expected permission and the tile service exported; try launching its components from another app/`am` → refused.
13. **On-device server:** temp key files in `/data/local/tmp` deleted after start; server refuses connections without the session secret; server binary hash check rejects a tampered jar.
14. **Segregation:** virtual phone sends file-push, audio, unknown device messages, clipboard > 1 MB, non-text clipboard, and clipboard while sync is off → all dropped, nothing written anywhere, session stays isolated; clipboard text never appears in logs; adb wrapper refuses non-allowlisted commands and shell-injection strings (`; rm -rf`, backticks, `$(…)`); sandboxed app process cannot read `~/Documents` or write outside its container.

**Critical/High findings must be patched before release — no exceptions.** Fix the root cause (not the symptom, not the test), show the diff, re-run the exact attack that found it plus the full Stage 3 suite, and show the output. You may not downgrade a finding's severity or mark it "accepted risk" without my explicit written approval. Medium/Low findings are fixed too unless I agree to defer them.

### Stage 4 — Performance, soak & stability
**5-minute high-paced stress session** against the virtual phone (record resource usage before, during and after):
- Synthetic stream at 120 fps (USB profile) then 60 fps (wireless profile) with the inner TLS on.
- Input flood: ~500 mixed events/s (taps, swipes, scrolls, pinches, key presses, fast typing) — the virtual phone must receive every event, in order, with correct coordinates.
- Forced USB↔wireless handover every 15 s, full disconnect/reconnect every 30 s, one Create-new-key + re-pair cycle, random packet loss/latency spikes on the virtual LAN.
- Pass criteria: no crash or hang, no dropped or reordered input, memory and file-descriptor/socket/process counts return to baseline afterwards (`lsof`, `ps`, heap stats), decode/render keeps up (no growing frame backlog).
- Report measured numbers (fps, per-frame decode/render time, CPU, memory) and clearly mark which 10.1 targets could only be estimated virtually.
- Add the same 5-minute session to `REAL_DEVICE_CHECKS.md` for me to run on the Pixel (USB then Wi-Fi), with what to watch for.

### Release gate
Only when Stages 1–4 pass **with evidence** (A3.9) and every Critical/High finding is patched and re-tested: bump version, update `CHANGELOG.md`, build the final signed DMG (10.4) and signed APK (9.4), print their SHA-256 checksums, and deliver `INSTALL.md` (10.5), `RELEASE_CHECK.md` with every finding and its re-test result, plus an **evidence table** (each claim → the command output that proves it; any row without proof counts as not done) and `REAL_DEVICE_CHECKS.md`. Then publish.

---

## PART C — Before you write any code
1. Restate the phases you will follow, including Milestone 1 (after Phase 3), Milestone 2 (after Phase 7) and the Phase 11 release check.
2. List every assumption you made.
3. List anything technically impossible as specified, with the closest secure alternative.
Then start Phase 1.
