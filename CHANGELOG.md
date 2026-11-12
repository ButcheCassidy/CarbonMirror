# Changelog

All notable changes to CarbonMirror. Versions follow `CFBundleShortVersionString`.

## [1.0.0] — 2026-11-12

First release.

### Added
- **Auto-connect:** after QR pairing and one USB connection, the Mac finds the paired phone at launch (mDNS only, known subnet, private addresses), verifies its pinned key, locks the endpoint and shows **Ready** — one click on **Mirror** starts the encrypted session. Settings → Connection → *Auto-connect to my phone at launch*.
- **Companion service:** keeps Wireless debugging on for trusted Wi-Fi only, off elsewhere; starts after boot, OS and app updates and after being killed; battery Unrestricted and *Forget trusted Wi-Fi networks* buttons.
- App drawer swipe-up fallback on Android 11.
- "Can't start safely" screen when the bundled adb is missing or fails its signature check; "Ready" and "Not connected" screens.
- Release workflow: companion APK signed with the release key, app and DMG signed on macOS, checksums, source zip.

### Changed
- Inner TLS over USB is **off by default** (Settings → Security → *Encrypt over USB too*); always on over Wi-Fi.

### Security
- Auto-connect never connects while the Mac is locked or asleep, re-checks conditions before connecting, ignores stale results and halts on an identity mismatch.
- Companion watches the Wi-Fi network itself (Mullvad's VPN is the default network) and asks Android at most once per network.

## 0.1.0 — not released

Development builds.

### Added
- Startup animation on both apps (1024 px clip, shown at most 512 pt, OLED black, centred); `tools/startup/render_carbonmirror.py` renders it.
- Companion app screen: Off / Ready / Mirroring, Turn on, Add Quick Settings tile.
- Device key: a wireless session needs proof of a secret the phone received over USB.
- macOS build in CI (started by hand only).
- Native macOS app (Swift 6, AppKit, Metal, VideoToolbox) mirroring and controlling an Android phone, tuned for the Pixel 10 Pro XL.
- Phone-shaped borderless window with continuous corners from the phone's real corner radius, real-size sizing (0.75×–2.0×), locked aspect ratio and hover chrome with overflow menu.
- USB "Performance" profile (120 fps, H.264, 32 Mbit/s) with adaptive fallback; wireless "Secure" profile (60 fps, H.265, 12 Mbit/s) over Android Wireless debugging only.
- Inner TLS 1.3 (AES-256-GCM, X25519MLKEM768) from one Rust core on both ends, pinned keys, session secret; on for USB too by default.
- QR pairing with single-use 120 s codes, 6-digit fallback, key pinning, "Create new key" recovery and rotation reminder.
- Auto transport switching, silent reconnect, privacy blur with Touch ID reveal, status line, landscape offer, two typing modes, plain-text clipboard sync, screenshots to `~/Pictures/CarbonMirror/`, debug HUD.
- Forked scrcpy 5.0 server (video + control only) and a stateless Quick Settings companion APK for GrapheneOS.

### Security
- adb no longer scans localhost for emulators or runs its own mDNS.
- Pairing pins only the address that completed the password-authenticated pairing.
- Phone server: one deadline for the TLS handshake and the session secret.
