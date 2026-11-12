# Release check (Phase 11) — in progress

Status: **not passed — release blocked.** Stages run on Linux so far; Mac/phone parts are in `REAL_DEVICE_CHECKS.md` (all NOT RUN).

## Findings

| # | Finding | Severity | File | Fix | Re-test |
|---|---|---|---|---|---|
| 1 | Children inherit the app's `SIG_IGN` for SIGTERM, so stopping adb's `track-devices` and the server shell waited for them to exit (60 s in tests; quit could hang) | Medium | `Sources/CMTransport/ChildProcesses.swift`, `AdbSupervisor.swift`, `PhoneLink.swift` | `ChildProcesses.stop(_:)`: SIGTERM, then SIGKILL after 0.5 s | `supervisorLifecycle` 60.020 s → 0.558 s; `supervisorRestartsAfterCrash` 60.520 s → 1.081 s; full suite 65/65 |
| 2 | RUSTSEC-2026-0009 `time` 0.3.45 stack exhaustion (DoS) | Medium | `rust/Cargo.lock` | `time` 0.3.55, crate MSRV 1.85 → 1.88 | `cargo audit` exit 0; `cargo test` 39/39; clippy clean (host + Android) |
| 3 | Renderer released `CVMetalTexture`s before the GPU read them (possible corrupted frames) | High | `Sources/CMMedia/MetalScreenView.swift` | Textures kept alive until the command buffer completes | NOT RUN — needs my Mac (macOS-only) |
| 4 | Decoder's zero-copy block buffer could be read after `scratch` was reused | High | `Sources/CMMedia/VideoDecoder.swift` | `VTDecompressionSessionWaitForAsynchronousFrames` after each decode | NOT RUN — needs my Mac |
| 5 | `MetalScreenView.enqueue` was main-actor isolated but called from the decode thread (Swift 6 error / data race) | High | `Sources/CMMedia/MetalScreenView.swift` | Lock-protected `FrameSlot`, `nonisolated enqueue` | NOT RUN — needs my Mac |
| 6 | Landscape frames were stretched into a portrait window | Medium | `Sources/CMMedia/MetalScreenView.swift` | Aspect-fit viewport (same letterbox as input mapping) | NOT RUN — needs my Mac |
| 7 | A session that failed during `start()` never finished its event stream (leaked listener task) | Low | `Sources/CMTransport/MirrorSession.swift` | Finish the stream on every start failure | full suite 65/65 |

## Stage 3 evidence so far

**3.1/3.2 TLS downgrade and impersonation** — `tools/sectest/tls_downgrade.sh` (OpenSSL 3.0.13 against the phone-side policy):
```
PASS  TLS 1.0                                            server: REFUSED TlsHandshakeFailed
PASS  TLS 1.1                                            server: REFUSED TlsHandshakeFailed
PASS  TLS 1.2 strong suite                               server: REFUSED TlsPolicyViolation
PASS  TLS 1.2 any suite                                  server: REFUSED TlsPolicyViolation
PASS  TLS 1.3 AES-128-GCM only                           server: REFUSED TlsPolicyViolation
PASS  TLS 1.3 P-256 group only                           server: REFUSED TlsPolicyViolation
PASS  TLS 1.3 allowed suite, no ALPN, no client cert     server: REFUSED TlsPinMismatch
PASS  TLS 1.3 allowed suite + ALPN, no client cert       server: REFUSED TlsPinMismatch
```
Negotiated on success (`encryptedSessionStreamsVideoAndControl`): suite `0x1302` TLS_AES_256_GCM_SHA384, group `0x11EC` X25519MLKEM768. Wrong pins, wrong session secret and hostile device messages: `SessionTests` (4 attack cases) pass.

**3.3 Plaintext and leakage** — `tools/sectest/capture_session.sh` (tcpdump on loopback + `capture_scan.py`):
```
ok       127.0.0.1:28201 -> 127.0.0.1:43012                  102395 B  entropy 8.00  start codes    0  markers []
ok       127.0.0.1:28201 -> 127.0.0.1:43022                    1890 B  entropy 7.88  start codes    0  markers []
ok       127.0.0.1:43012 -> 127.0.0.1:28201                    2042 B  entropy 7.84  start codes    0  markers []
ok       127.0.0.1:43022 -> 127.0.0.1:28201                    2157 B  entropy 7.83  start codes    0  markers []
RESULT: nothing readable
```
Control (plain session, encryption off) — the scanner must catch it, and does:
```
READABLE 127.0.0.1:27202 -> 127.0.0.1:58826                     130 B  entropy 3.02  start codes    2  markers ['Pixel 10 Pro XL']
READABLE 127.0.0.1:27202 -> 127.0.0.1:58834                      22 B  entropy 3.19  start codes    1  markers ['hello']
RESULT: plaintext found
```

**Stage 1 dependency audit** — `cargo audit`: exit 0 (1458 advisories, 126 crates) after finding 2.

## Still to run before release
- Stage 1: line-by-line review of every file; macOS build with zero warnings (needs Mac); `aapt2 dump badging` + entitlement verification on the signed app.
- Stage 2: edge cases against the virtual phone (reboot mid-session, Wi-Fi drop 5 s / 60 s, two phones, rotate during resize, long/fast typing, non-English layout).
- Stage 3: 3.4 legacy 5555 on a virtual LAN (`ip netns`), 3.5 exposure scan from an attacker namespace, 3.6 routing with a fake `utun` route, 3.7 pairing reuse/expiry against the flow, 3.8 Python `hypothesis` fuzzing ≥ 2 min per entry point, 3.9 replay, 3.12–3.14 on device.
- Stage 4: 5-minute soak (120 fps then 60 fps, 500 events/s, handovers every 15 s).
- Release gate: signed DMG + APK checksums, evidence table, `INSTALL.md` final.
