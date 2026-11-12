# CarbonMirror — Security notes

What CarbonMirror protects, how, and where the limits are. Everything here describes the code as built; items marked **NOT RUN** have not yet been checked on real hardware (see `REAL_DEVICE_CHECKS.md`).

## 1. Threat model (spec 7.1)

| Threat | Defence |
|---|---|
| Hostile devices on the LAN or phone hotspot | The Mac has **no TCP or UDP listener at all**: adb's server and every `adb forward` are Unix-domain sockets in a 0700 folder inside the sandbox container. Connections go only to private-range addresses (allowlist in Rust). |
| Passive sniffing | Wireless traffic is double-encrypted: adb's own TLS (Wireless debugging) and CarbonMirror's inner TLS 1.3 with AES-256-GCM. Plain `adb tcpip` is detected and refused. |
| Active man-in-the-middle | Pairing uses Android's SPAKE2 QR flow; afterwards the phone's adb TLS key (SHA-256 of its public key) and serial are pinned. Inner TLS uses pinning-only verifiers on both ends — no CA trust, no hostnames. |
| A different phone trying to pair or connect | Unknown serial or key → "Untrusted device"; a known serial with a different key → "This phone's identity changed" (possible MITM). Nothing is trusted automatically. |
| Malware on the Mac capturing the window | Window `sharingType = .none` by default (see §6 for limits). Privacy blur, auto-blur and Touch ID reveal. |
| Other processes or users on the Mac reaching adb or the session sockets | adb's server protocol has no authentication, so it must not be reachable: it and the forwards live on Unix sockets in the app's sandbox container (other users can't traverse `~/Library`; other sandboxed apps can't enter the container; macOS asks before an unsandboxed app reads another app's container). On top, every session socket must present a random 256-bit secret after the inner TLS handshake, checked in constant time on the phone. |
| A stolen Mac | The identity key is non-extractable in the login Keychain; sessions end on lock, sleep, user switch and idle. Clipboard and frames are never written to disk. |
| Stale or corrupted keys | adb key fingerprint mirrored in the Keychain and checked at launch; "Create new key" securely replaces everything and forces a new QR pairing. |
| A compromised phone or link | Only video and an allowlist of small device messages are parsed — in Rust, with every length bounds-checked; malformed data ends the session. No files, audio, shell or app-data paths exist in the forked server. |

## 2. Encryption in use

| Path | Protection |
|---|---|
| Wireless (always) | adb TLS (Android Wireless debugging) **plus** inner TLS 1.3 from `carbon-core::tls`: suites `TLS_AES_256_GCM_SHA384` then `TLS_CHACHA20_POLY1305_SHA256` only; key exchange `X25519MLKEM768` (hybrid post-quantum) **only** — a classical-only peer is refused; mutual authentication with pinned certificates; ALPN `carbonmirror/1` required; no resumption, no 0-RTT; KeyUpdate every 15 min or 4 GiB; handshake timeout 10 s; any alert or decrypt error ends the session. |
| USB | Inner TLS **off by default** (spec 7.3; owner decision). Toggle: Settings → Security → *Encrypt over USB too*. The session secret and device-key provisioning still run on every USB session. |
| Session keys | Mac: fresh Ed25519 client certificate per session, signed by the long-term identity. Phone: fresh Ed25519 certificate per server start; its pin travels over the authenticated adb channel (`CM-PIN` on stdout). Secrets in Rust are `zeroize`d on drop. |
| Long-term identity | ECDSA P-384, created with `SecKeyCreateRandomKey` in the login Keychain, `kSecAttrIsExtractable = false`. rustls signs through a Swift callback (`ecdsaSignatureMessageX962SHA384`); the private key never enters Rust or app memory. |
| Session setup | One line on the adb shell's **stdin** (`CM1 <tls|plain> <secret> <mac-ca>`), never in argv or files on the phone. |
| Pushed binaries | Server jar and `libcarbon_core.so` are SHA-256-verified against hashes sealed into the signed `Info.plist`, copied to a private 0600 file, and that copy is pushed (no check/push race). |
| adb helper | Runtime code-signature check (`SecStaticCodeCheckValidity`) against the app's own leaf certificate before adb ever runs. Mismatch → adb is not started. |
| Signing | Mac: local ECDSA P-384/SHA-384 "CarbonMirror Dev" certificate, non-extractable, usable only by `codesign`; hardened runtime. APK: your own P-384 key, apksigner v2 + v3. |

**Why Rust (honest):** not for memory savings — the video pipeline decides the footprint. Rust gives memory-safe parsing of untrusted bytes, one identical TLS implementation and policy on the Mac and the phone (rustls + aws-lc-rs), and code that is built, tested and fuzzed on Linux. `unsafe` exists only in `ffi`; panics never cross the C ABI.

## 3. Pairing and trust (spec 7.2, 7.5)

- QR codes `WIFI:T:ADB;S:carbonmirror-<10 base62>;P:<22 base62 ≥ 130 bit>;;` from the system CSPRNG, single use, 120 s lifetime. The phone advertises `_adb-tls-pairing._tcp` under the code's name; the Mac resolves it **without connecting** (dns_sd), checks the address against the allowlist, consumes the code, then runs `adb pair`.
- After pairing the Mac probes the phone's Wireless-debugging port itself: it speaks only `CNXN`/`STLS`, reads the phone's TLS public key, and aborts. A plaintext `CNXN` answer means `adb tcpip` → refused.
- The phone pins the Mac's identity CA on first use in `/data/local/tmp/carbonmirror-mac.pin` (0600). **Limit:** anyone with adb shell access to the phone can delete that file; adb's SPAKE2 pairing remains the root of trust. "Create new key" removes it with an allowlisted command before the first new session.
- **USB without pairing:** if no phone is paired yet, an authorised USB phone may mirror (Android's own USB authorisation dialog is the trust root). Once a phone is paired, any other USB phone is "Untrusted device".
- Create new key: deletes Keychain items, overwrites then deletes the adb key files, clears pins and endpoints, makes a new identity, restarts adb (new adb key), and starts QR pairing. Never trusts a new key without a completed pairing. Logged as metadata only ("key rotated", timestamp).

**Device key (who the phone is).** adb authenticates the Mac to the phone, not the phone to the Mac. So the first time the phone is connected by USB — the one channel that is physically yours — CarbonMirror hands it a random 256-bit device key (kept in the Mac Keychain, bound to the phone's serial; on the phone in `/data/local/tmp/carbonmirror-device.key`, shell-only). On every wireless session the phone must return HMAC-SHA-256(device key, its session key pin) before the Mac opens any socket. The key is never sent over Wi-Fi. A device on the network that answers as your phone cannot produce the proof and gets no video socket, no input and no clipboard. Forget device and Create new key delete it; the next USB connection sets a new one.

**adb is kept on a short lead.** The bundled adb runs with `ADB_EMU=0` (it never connects to "emulators" on localhost ports, which is plaintext and unauthenticated) and `ADB_MDNS=0` (it never discovers or auto-connects by itself; discovery is CarbonMirror's own, allowlist first).

## 4. Network rules (spec 6.2)

- Allowed destinations: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`, `fe80::/10`, `fc00::/7`. Refused: public addresses, Mullvad's tunnel ranges (`10.64.0.0/10`, `fc00:bbbb:bbbb:bb01::/64`), IPv4-mapped IPv6, link-local without zone, hostnames, port 5555.
- The probe binds to `.wifi` / `.wiredEthernet` and prohibits `.other` and `.cellular`; a route through `utun*` → "LAN sharing blocked".
- **Limit:** adb itself opens the phone↔Mac TCP connection for Wireless debugging; its socket follows system routing and cannot be bound from outside. CarbonMirror's own session sockets are private Unix sockets created by `adb forward`. The pre-connect probe is what verifies the physical route.
- **Network identity without the SSID:** reading the Wi-Fi name needs Location Services permission, which CarbonMirror never requests. "This network" is the IPv4 subnet of the Wi-Fi interface, stored only as a SHA-256 key. A change of subnet during a wireless session counts as "change to an unknown network" and ends it.
- No port scanning, ever. When mDNS replies are blocked, the user types the IP and port shown on the phone.

## 5. Session hygiene (spec 7.6)

- A session ends and its keys are freed on: Mac lock, sleep (lid close without an external display sleeps the Mac), fast user switch, Wi-Fi network change, idle timeout (default 10 min). Display sleep and screensaver blur the screen instead.
- After a **final** end (Disconnect, quit, idle) of a wireless session the Mac turns Wireless debugging off (`settings put global adb_wifi_enabled 0`) — unless auto-connect is on, in which case the companion keeps it on for trusted Wi-Fi only (§7). After lock or sleep it is left on so the silent reconnect can work; the phone's tile or settings turn it off.
- Silent reconnect only ever targets the pinned phone, with the full handshake, never while the Mac is locked or asleep, and gives up after 10 minutes.
- Clipboard: plain text only, ≤ 1 MiB, UTF-8 checked in Rust, never logged or written to disk; read from `NSPasteboard` only while sync is on and the window is key; phone text is dropped while sync is off.
- Nothing is written to disk except screenshots you take (`~/Pictures/CarbonMirror/`). Frames are dropped on disconnect. Windows are not restorable, so macOS never saves a "Resume" snapshot of the phone screen. adb's key folder is excluded from Time Machine; Keychain items are never synchronizable.
- Clipboard privacy: Mac items marked concealed/transient by password managers (nspasteboard.org types) are never sent; Android clips marked sensitive (Android 13+) never leave the phone; phone text is written with `currentHostOnly`, so it never travels to other Apple devices through Universal Clipboard.
- Lock state: the "screen unlocked" distributed notification can be posted by any process, so it is trusted only when the window server (`CGSessionCopyCurrentDictionary`) agrees.
- Logs: `os.Logger` subsystem `com.nomadicrebel.carbonmirror`, compile-time messages plus app-generated metadata only. The app writes no log files; unified logging rotates itself (this is how "rotate at 1 MB" is met).

## 7. Auto-connect (owner addition)

**Mac.** At launch, unlock, wake and network change, if *Auto-connect to my phone at launch* is on:
1. Runs only when the phone is pinned (adb TLS key from QR pairing) **and** holds a device key from a USB session, the Mac is unlocked and awake, Wi-Fi is up, the current subnet is one the phone was seen on, and no USB or user session is running.
2. Finds the phone only through its own mDNS `_adb-tls-connect` announcement for the pinned serial — no port scan, no guessed ports, no stored public address. Every answer must be a private address (the Rust allowlist: no public, tunnel/Mullvad, link-local-without-zone or port 5555) **inside the Mac's current subnet**.
3. Probes the endpoint (route not via `utun`, plaintext adb refused), checks the pinned adb TLS key, then `adb connect` (adb's own mutually authenticated TLS). The checks are repeated right before connecting: if the Mac locked, slept, a session started or the network changed during the probe, nothing connects.
4. The verified endpoint is **locked** until it fails or the network changes; other answers are ignored while the lock holds. Searches back off 5 → 10 → 20 → 30 s.
5. The window shows **Ready**; one click on **Mirror** starts the session with the full inner TLS 1.3 handshake and the device-key HMAC proof. Nothing streams before that click.
6. A wrong key or a plaintext endpoint shows the identity/insecure warning and **halts** auto-connect until you press Retry — an impostor cannot make it retry in a loop. Lock, sleep, USB or turning the setting off drops the idle link.

**Phone (companion).** A foreground service (`connectedDevice`) keeps Wireless debugging on while the phone's **Wi-Fi network** (not the default network — with Mullvad that is the VPN) has a trusted subnet, and turns it off again when the phone leaves one — only if the service turned it on, never during a session. A subnet becomes trusted when a CarbonMirror session runs while the phone is on that Wi-Fi with Wireless debugging on. Stored: SHA-256 of `carbonmirror-companion-subnet-v1:<a.b.c.d/n>`, at most 8, app-private, not backed up; *Forget trusted Wi-Fi networks* clears them. It tries once per network join: Android itself refuses Wireless debugging on a Wi-Fi it hasn't been told to *Always allow* (per BSSID) and asks the user — the companion never asks twice. The service, its start receiver (boot, OS update, app update, 15-minute watchdog alarm) are not exported; it opens no socket and has no internet permission.

**Residual risks.** (a) A different Wi-Fi with the same subnet (e.g. `192.168.1.0/24` at a café) counts as known: the Mac may browse there and the companion may try to turn Wireless debugging on. Android's per-BSSID *Allow wireless debugging on this network?* prompt still stands in the way on the phone, and on the Mac an impostor fails the pinned-key check (warning + halt). No Location permission is used, by owner decision, so the SSID/BSSID cannot be checked by the apps themselves. (b) A USB session while the phone sits on an untrusted Wi-Fi with Wireless debugging switched on by hand also marks that subnet trusted (the companion cannot tell USB from Wi-Fi sessions). Both Low.

## 6. Known limits and deviations (honest list)

0. **Post-quantum scope:** key exchange is post-quantum (hybrid `X25519MLKEM768`, enforced, tested: `only_post_quantum_hybrid_key_exchange_is_offered`, negotiated group `0x11EC` asserted in Rust and Swift tests), so recorded traffic stays safe against a future quantum computer. **Signatures are classical**: Mac identity ECDSA P-384, session certificates Ed25519, adb's own keys RSA/EC. Forging them needs a quantum computer *during* the handshake (no harvest-now-decrypt-later risk). ML-DSA certificates need rcgen/webpki/Keychain support that is not stable yet.

1. **Window capture:** `sharingType = .none` keeps the window out of `CGWindowListCreateImage`-style capture and most screen-sharing; newer ScreenCaptureKit-based recorders on recent macOS versions may still capture it. **NOT RUN** — test 13 in `REAL_DEVICE_CHECKS.md` records what it blocks.
2. **Data-protection Keychain / Secure Enclave** need an Apple Developer Team ID; a self-signed certificate has none. The identity lives in the login Keychain instead. Future upgrade.
3. **rustls decrypts into its own buffer** (its unbuffered API does not yet decrypt in place); plaintext is copied once into the caller's buffer. Protocol parsing is offset-based and zero-copy.
4. **Signal inheritance:** the app ignores SIGTERM to handle it on a dispatch source; children inherit that, so every child is stopped with SIGTERM then SIGKILL after 0.5 s.
5. **Companion "Mirroring" state:** the server sets the global setting `carbonmirror_session` to 1 while it runs (and its clean-up process sets 0). Any app on the phone can read this one bit, just as it can read `adb_enabled`/`adb_wifi_enabled`.
6. **GrapheneOS USB-C port control:** GrapheneOS defaults to "Charging-only when locked", which disables USB data (and adb) while the phone is locked. USB mirroring stops when the phone locks; wireless keeps working.
7. **Lid close** is detected as system sleep; in clamshell mode with an external display the Mac does not sleep and the session continues (it still ends on lock).
8. **App drawer:** `KEYCODE_ALL_APPS` on Android 12+; on Android 11 the phone server swipes up from 92 % to 35 % of the display height instead (the version decides, not a failure signal). **NOT RUN** on an Android 11 device.
9. **Adaptive USB profile:** Android sends no frames for a still screen, so only seconds with ≥ 30 fps count; legitimately slower content (e.g. 60 fps video) can still trigger a step down. **NOT RUN** on the device.
10. **Sandbox:** adb runs inside the app sandbox (inherited). If a macOS version refuses that, the fallback is a sandboxed XPC helper — not built yet. **NOT RUN.**
11. **`network.server` entitlement:** with Unix sockets nothing listens on TCP any more; the entitlement is kept until the Mac confirms adb can bind its Unix socket without it (REAL_DEVICE_CHECKS A6), then it is removed.
12. **Phone side:** the server's abstract socket `scrcpy_<random 31-bit id>` can be reached by other processes on the phone. Without the 256-bit session secret (checked in constant time, first bytes on every socket) nothing flows; with the inner TLS (always on Wi-Fi, optional on USB) they also cannot complete the handshake without a certificate signed by the pinned Mac identity. At worst they can disturb a session start (denial of service).
- **A phone that has never been connected by USB is trusted on first use over Wi-Fi.** Without the device key the wireless pin comes from the endpoint that completed QR pairing (same address as the password-authenticated pairing). Plug the phone in once and the gap closes for good.
- **USB identity is the serial number.** adb over USB does not authenticate the device; someone with physical access and a device that fakes your phone's serial could be mirrored. Physical access to an unlocked Mac is outside the threat model.
- **Phone → Mac clipboard** sets the Mac clipboard whenever the phone copies text while sync is on (by design, spec A7). Turn sync off in the toolbar if you paste into terminals.
