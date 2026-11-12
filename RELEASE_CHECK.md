# Release check (Phase 11)

**Status: Linux stages complete. Release gate NOT passed** — the macOS-only code has never been compiled, and every Mac/phone item in `REAL_DEVICE_CHECKS.md` is NOT RUN. No release DMG/APK until those pass.

## Findings

| # | Finding | Severity | Where | Fix | Re-test |
|---|---|---|---|---|---|
| 1 | **adb server reachable by any local process.** It listened on `127.0.0.1:<random port>`; adb's server protocol has no authentication, so any other user or any sandboxed app with network access could find the port and run `adb shell`/`pull` against the phone. Same exposure for the `adb forward` TCP ports. | **High** | `AdbEnvironment`, `AdbCommand`, `PhoneLink`, `MirrorSession`, `policy/adb.rs` | adb server and all forwards are Unix-domain sockets in a 0700 folder in the sandbox container; the Rust allowlist refuses any `tcp:` forward; socket names carry 64 random bits | Vectors (6 new forward cases) Rust + Swift; `environmentIsPrivateAndLocalOnly`; virtual LAN: 0 TCP / 0 UDP listeners, 65 535-port scan → none open |
| 2 | **Inner TLS broke under load:** a socket read carrying > 16 KiB of plaintext (any large key frame) exceeded rustls's own unread-plaintext cap → `TlsFailed`, session dropped after a few frames (Mac and phone, same Rust code) | **High** | `rust/carbon-core/src/tls.rs` | Decrypted data moves into a bounded (16 MiB), zeroed session buffer after every batch | `large_burst_in_one_read_is_delivered` fails on the old code, passes on the fix; 5-min soak passes |
| 3 | Mac clipboard items from password managers (concealed/transient) would be sent to the phone | Medium | `SessionController.pollPasteboard` | nspasteboard.org concealed/transient/auto-generated types are never sent | NOT RUN — needs Mac (check 14) |
| 4 | Android clips marked sensitive (passwords) would be sent to the Mac | Medium | server `ClipboardManager.getText` | `ClipDescription.EXTRA_IS_SENSITIVE` clips are never read | server builds; NOT RUN — needs device |
| 5 | Phone clipboard text would sync to the user's other Apple devices via Universal Clipboard | Medium | `SessionController` | `prepareForNewContents(with: .currentHostOnly)` | NOT RUN — needs Mac |
| 6 | macOS "Resume" could save a snapshot of the phone window to disk | Medium | `PhoneWindow`, `SettingsWindow` | `isRestorable = false` | NOT RUN — needs Mac (check 6b) |
| 7 | A forged `com.apple.screenIsUnlocked` notification (any process can post it) could trigger a reconnect while the Mac is locked | Medium | `SessionController.observeSystem` | Trusted only if `CGSessionCopyCurrentDictionary` says unlocked; initial lock state read at launch | NOT RUN — needs Mac |
| 8 | adb's private key would be included in Time Machine backups | Low | `AdbEnvironment.prepare` | `isExcludedFromBackup` on the adb and socket folders | NOT RUN — needs Mac |
| 9 | `adb pair` output (phone-controlled `guid`) used without a character check | Low | `SessionController.pair` | Only `[A-Za-z0-9._-]`, ≤ 128 bytes, `adb-` prefix | Linux build |
| 10 | Children inherit the app's `SIG_IGN` for SIGTERM, so stopping adb waited for it to exit (quit could hang 60 s) | Medium | `ChildProcesses`, `AdbSupervisor`, `PhoneLink` | SIGTERM, then SIGKILL after 0.5 s | supervisor tests 60.0 s → 0.56 s |
| 11 | RUSTSEC-2026-0009 `time` 0.3.45 (DoS) | Medium | `rust/Cargo.lock` | `time` 0.3.55, MSRV 1.88 | `cargo audit` exit 0 |
| 12 | Renderer released `CVMetalTexture`s before the GPU read them | High | `MetalScreenView.swift` | kept alive until the command buffer completes | NOT RUN — needs Mac |
| 13 | Decoder's zero-copy block buffer could be read after reuse | High | `VideoDecoder.swift` | wait for frames after each decode | NOT RUN — needs Mac |
| 14 | `enqueue` main-actor isolated but called from the decode thread | High | `MetalScreenView.swift` | lock-protected `FrameSlot`, `nonisolated enqueue` | NOT RUN — needs Mac |
| 15 | Landscape frames stretched in a portrait window | Medium | `MetalScreenView.swift` | aspect-fit viewport | NOT RUN — needs Mac |
| 16 | Event stream never finished when `start()` failed (leaked task) | Low | `MirrorSession.swift` | finish the stream on every start failure | full suite |
| 17 | Build scripts failed when started outside the repo folder or pasted (`dirname: illegal option -- z`) | Low | `scripts/*.sh`, `tools/sectest/*.sh` | locate the repo via `BASH_SOURCE`/git | run from `/tmp` |
| 18 | adb server connected, in plaintext and without authenticating the device, to anything listening on `127.0.0.1:5555–5585` (emulator scan) and would sign its challenges with the adb key; adb also ran its own mDNS and could auto-connect to an address from an mDNS answer | **Medium** | `AdbEnvironment.swift` | `ADB_EMU=0`, `ADB_MDNS=0` | `tools/sectest/adb_local_exposure.sh`: before 8 connections, after 0; UDP sockets 2 → 0 |
| 19 | adb does not authenticate the phone to the Mac; the wireless pin was taken from whatever answered the mDNS name during pairing, so a LAN device could be pinned as the phone and receive typed input and the Mac clipboard | **Medium** | `MirrorSession.swift`, `SessionSetup.java`, `KeyManager.swift`, `PairingController.swift` | device key delivered over USB only; wireless endpoint must return HMAC-SHA-256(key, session pin) before any socket opens; pairing accepts only the address that completed the password-authenticated pairing | `usbProvisionsTheDeviceKeyAndWirelessMustProveIt`, `deviceKeyBelongsToOnePhoneAndGoesWithIt` pass; impostor and wrong-key phones end with `deviceNotProven`. Limit: a phone never connected by USB stays trust-on-first-use (SECURITY_NOTES §6) |
| 20 | Phone server: TLS handshake timeout applied per read (a peer trickling bytes could hold it), no timeout while waiting for the session secret | Low | `SecureChannel.java`, `SessionSetup.java` | one 10 s deadline for the handshake and for the secret | server builds; NOT RUN — needs real device |
| 21 | Rust core's C objects built for the build machine's macOS (26.5) instead of the deployment target 15.0 | Low | `.cargo/config.toml` | `MACOSX_DEPLOYMENT_TARGET=15.0` | macOS CI link |
| 22 | App crashed when Settings was opened (Swift exclusive-access trap: a closure passed to `actions.removeAll` read `actions`) | **High** | `SettingsWindow.swift` | read the kept element before mutating | macOS 26 CI: before `APP DIED after Settings`, after `APP ALIVE after Settings` + screenshot of the open Settings window |
| 23 | UI audit (one sub-agent + sweep): truncated two-line titles, clipped badge/status line, video jump on interrupted chrome animation, chrome off-screen near edges, stale Settings values, system accent colour, pills left-aligned, Settings rows pinned to the bottom, unusable window size on displays reporting a wrong physical size | Medium | `StatusView`, `ChromeView`, `PhoneWindowController`, `PhoneContentView`, `SettingsWindow`, `WindowSizer`, `main.swift`, companion `status.xml` | see commits `416b035`, `46aa4d0`, `a5e2676` and the next one | macOS 26 CI screenshots (status states, chrome, splash, Settings); companion NOT RUN — needs real device |
| 24 | App trapped at launch when no display was attached (`NSScreen.screens[0]`) | Medium | `PhoneWindowController.swift` | default frame when there is no screen | macOS 26 CI: build 0 warnings, `APP ALIVE after real launch`, Metal shader compiles (`METAL exit 0`) |
| 25 | Auto-connect: if the Mac locked or slept, or a USB session started, while the endpoint was being probed, `adb connect` still ran (result then discarded) | Medium | `SessionController.swift` (`link`) | conditions re-checked right before `adb connect` (`stillWanted`) | `AutoConnectTests` (10) + review; NOT RUN — needs Mac |
| 26 | Auto-connect refusal screen could cover a session that started meanwhile | Low | `SessionController.swift` | `showIfIdle` | review; NOT RUN — needs Mac |
| 27 | Companion read the **default** network; with Mullvad always on that is the VPN (`10.64.x.x/32`), so trusted Wi-Fi was never recognised | Medium | `ReadyService.java` | callback on a Wi-Fi `NetworkRequest` (NOT_VPN by default, INTERNET not required) | builds; NOT RUN — needs real device |
| 28 | Companion would re-enable Wireless debugging in a loop on a Wi-Fi Android doesn't trust yet (Android reverts to 0 and prompts each time) | Medium | `ReadyService.java` | one try per network join (`decide(…, triedHere)`) | `scripts/test-companion.sh` (19 checks) |
| 29 | Companion status notification visible on the lock screen | Low | `ReadyService.java` | `VISIBILITY_SECRET` | builds |
| 30 | Stale auto-connect results (an old probe finishing after the network changed) could mark the wrong endpoint ready | Medium | `AutoConnect.swift` | results carry their endpoint; ignored unless it is the one being verified | `AutoConnectTests.staleVerificationIsIgnored` |

No Critical findings. Every High finding is fixed; the macOS-only ones are fixed by inspection and stay NOT RUN until the first Mac build.

## Stage 1 — Static review & build hygiene

- `try!`/`fatalError`/force unwraps on untrusted data: none (one `as! SecKey` on a Keychain query result of class key). No `print`/`NSLog`; logs are compile-time messages + app-generated metadata only. No TODO/FIXME.
- Rust: `unsafe` only in `ffi` (113 blocks, 113 `SAFETY` notes); every other module `#![forbid(unsafe_code)]`; `unwrap`/`expect` only in tests. `cargo clippy --all-targets --release -- -D warnings` clean (host and `cargo ndk -t arm64-v8a`). `cargo audit` exit 0.
- Java: no unused imports. APK manifest: only `WRITE_SECURE_SETTINGS`, only the tile service exported (with `BIND_QUICK_SETTINGS_TILE`), no backup, no cleartext; apksigner v2 + v3, EC P-384.
- Swift (Linux part): 0 warnings. **macOS part: NOT RUN — needs Mac.**

## Stage 2 — Functional & regression

- `cargo test --release`: 43 passed (unit 24, fuzz 5, tls 9 incl. replay, tamper and burst, vectors 5). `swift test`: 68 tests in 10 suites passed (soak and virtual-LAN tests run only when their harness sets `CM_SOAK_SECONDS` / `CM_LAN_PHONE`).
- New edge test: phone dies mid-session → session ends in < 3 s, forward removed, phone files cleaned (`phoneDyingMidSessionEndsTheSessionCleanly`).
- Device edge cases (Wi-Fi drop, Mac sleep, two phones, non-English layout, Mullvad reconnect): `REAL_DEVICE_CHECKS.md`.

## Stage 3 — Security stress test & attack simulation

| # | Attack | Harness | Result |
|---|---|---|---|
| 3.1 | TLS 1.0/1.1/1.2, AES-128-only, P-256-only | `tools/sectest/tls_downgrade.sh` (OpenSSL 3.0.13) | 6/6 refused (`TlsHandshakeFailed` / `TlsPolicyViolation`) |
| 3.2 | Correct TLS 1.3 suite without the pinned Mac certificate (with and without ALPN); wrong phone pin; Mac cert from another identity | same + `rust/tests/tls.rs`, `SessionTests` | refused (`TlsPinMismatch`, identity changed) |
| 3.3 | Plaintext / leakage | `tools/sectest/capture_session.sh` (taps the Unix sockets) | encrypted: entropy 7.84–8.00, no markers, no start codes; plain control flagged (scanner works) |
| 3.4 | Plaintext `adb tcpip` on 5555 and another port | `tools/sectest/virtual_lan.sh` + `fake_adbd.py` | 5555 refused before connecting; other port → `plaintextRefused` |
| 3.5 | Exposure scan of the Mac from an attacker namespace during encrypted sessions | `virtual_lan.sh` + `port_scan.py` | Mac TCP listeners 0, UDP 0; 65 535 ports scanned → none open |
| 3.6 | Mullvad tunnel range, public IPv4/IPv6, fake `utun9` route | `virtual_lan.sh` | all refused; `utun9` TX packets 0 |
| 3.7 | Reused / expired pairing code, unknown second phone | `KeyTests` (single use, 120 s), `trustRequiresTheExactPin` | refused |
| 3.8 | Fuzzing ≥ 2 min per entry point | `tools/sectest/ffi_fuzz.sh 120` (Python hypothesis through the C ABI) + proptest | 13 entry points, 242k–332k examples each, no crash/abort, only documented statuses, memory flat |
| 3.9 | Replay of a whole recorded session; duplicate record; flipped bit; injection without the secret | `rust/tests/tls.rs`, `wrongSessionSecretIsRefusedByThePhone` | all refused / session ended |
| 3.10 | Create new key: old keys gone, new key untrusted until pairing; corrupted key file | `KeyTests` | pass |
| 3.11 | Logs contain no content/secrets; session-end triggers | code review; device check A5 | no content logged; triggers NOT RUN on Mac |
| 3.11a | Input while blurred; forged battery message | `InputTests`, `SessionTests` | dropped / session ended |
| 3.12 | Companion exported components | `aapt2 dump xmltree` | only the tile service, permission-protected |
| 3.13 | Server without secret; tampered jar | `SessionTests`, `deployerPushesOnlyVerifiedBytes` | refused |
| 3.14 | File/audio/unknown messages, clipboard > 1 MiB, non-UTF-8, adb injection strings | `SessionTests` (4 attacks), `injectedValuesAreRefusedBeforeAdbStarts`, vectors | dropped / refused |

## Stage 4 — Performance, soak & stability

`CM_SOAK_SECONDS=300 swift test --filter soak` — 5 minutes, sessions rebuilt every 15 s alternating USB 120 fps / Wi-Fi 60 fps (inner TLS on both), 500 input events/s, Mac identity replaced halfway:
```
SOAK cycle 2 USB 120 TLS: 111.6 fps delivered (1737/1737 frames), wire 239616/239616 B, 7500 events (481/s), fds 46, RSS 41.6 MiB
SOAK cycle 17 Wi-Fi 60 TLS: 56.1 fps delivered (874/874 frames), wire 239616/239616 B, 7500 events (481/s), fds 49, RSS 47.9 MiB
SOAK done: 23 sessions, 142900 events, key rotated: true, fds 40 → 44, RSS 36.2 → 48.7 MiB
✔ Test run with 1 test in 1 suite passed after 302.130 seconds.
```
Every event arrived in order, byte-exact; every frame sent was received; descriptors and memory plateau. Glass-to-glass latency, Mac CPU and idle memory (10.1) can only be measured on the Mac → `REAL_DEVICE_CHECKS.md` E. `tc netem` is not available in this environment, so packet loss/latency spikes were not simulated.

## Release gate (open)
1. First Mac build: fix compile errors in the macOS-only files, zero warnings.
2. `REAL_DEVICE_CHECKS.md` A–E on the Mac and the Pixel.
3. Bump version, CHANGELOG, signed DMG + APK, checksums, final evidence table.
