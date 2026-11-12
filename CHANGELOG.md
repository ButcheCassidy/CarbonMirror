# Changelog

All notable changes to CarbonMirror. Versions follow `CFBundleShortVersionString`.

## 0.1.0 — unreleased

First build, not yet released (Phase 11 release check pending).

### Added
- Native macOS app (Swift 6, AppKit, Metal, VideoToolbox) mirroring and controlling an Android phone, tuned for the Pixel 10 Pro XL.
- Phone-shaped borderless window with continuous corners from the phone's real corner radius, real-size sizing (0.75×–2.0×), locked aspect ratio and hover chrome with overflow menu.
- USB "Performance" profile (120 fps, H.264, 32 Mbit/s) with adaptive fallback; wireless "Secure" profile (60 fps, H.265, 12 Mbit/s) over Android Wireless debugging only.
- Inner TLS 1.3 (AES-256-GCM, X25519MLKEM768) from one Rust core on both ends, pinned keys, session secret; on for USB too by default.
- QR pairing with single-use 120 s codes, 6-digit fallback, key pinning, "Create new key" recovery and rotation reminder.
- Auto transport switching, silent reconnect, privacy blur with Touch ID reveal, status line, landscape offer, two typing modes, plain-text clipboard sync, screenshots to `~/Pictures/CarbonMirror/`, debug HUD.
- Forked scrcpy 5.0 server (video + control only) and a stateless Quick Settings companion APK for GrapheneOS.
