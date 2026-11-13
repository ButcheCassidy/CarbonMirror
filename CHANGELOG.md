# Changelog

All notable changes to CarbonMirror. Versions follow `CFBundleShortVersionString`.

## [1.0.2] — 2026-11-13

### Fixed
- **Phone server crashed at start (`ClassNotFoundException: com.genymobile.scrcpy.Server`):** a rebuild in an existing folder kept the phone parts of the same version number, so the older 1.0.1 server stayed in use; its clean-up helper deleted the shared server file, and the next session's server could vanish before Android loaded it. 1.0.2 ships fresh phone parts (server, phone library, companion) that `build-mac.sh` picks up automatically, and the clean-up helper only ever deletes its own private copy.

## [1.0.1] — 2026-11-13

### Fixed
- **Pairing looped back to the QR code ("Untrusted device") on a real phone:** after `adb pair` succeeded, the Mac read the phone's adb TLS key with a post-quantum-only handshake that adbd (classical key exchange) refuses. The key probe now also offers X25519/P-256/P-384; it carries no data, and CarbonMirror's own sessions stay `X25519MLKEM768`-only. Each pairing failure now logs the step where it stopped.
- Settings: checkbox labels were black on the dark glass (even with a white title); each checkbox title is now a plain white label (click toggles), and the Settings content uses the dark appearance.
- **Mac keyboard did not type on the phone:** the hardware keyboard was created on the first key (Android reconfigured and closed an open app drawer, and the key was lost), and after the first session it was never created again. It is now created at every session start.
- **Quality "Poor" and silent downgrades on USB:** both screens are adaptive (phone 1–120 Hz, ProMotion), so a quiet screen sends few frames. Quality now comes from the round trip only, and the adaptive USB profile steps down on a round trip above 50 ms for 3 s instead of on frame rate (it used to restart the session at lower size/fps, e.g. "USB · 90"). The Mac's display link runs 1–120 Hz.
- Phone keyboard mode: keys held when the window lost focus stayed pressed (and repeated) on the phone; they are now released.
- Companion: a Wi-Fi network is trusted as soon as the cable comes out during a Wi-Fi session (it used to wait for the 15-minute watchdog).
- Wi-Fi: every mDNS answer and the cached endpoint are probed in turn; a stale port after a phone restart no longer hides the live one.
- Session switching: Disconnect during a switch is honoured, restarts never overlap (queued instead), and a reconnect refused while the Mac is locked no longer leaves the "retrying" screen up. "Launch at login" shows the real state when macOS refuses.
- **Restarting over USB failed ("Connection lost", black screen):** Disconnect cleared the session before its teardown finished, so a new session could start meanwhile, and the old teardown then deleted the server just pushed for it. New sessions now wait for the teardown; a start requested meanwhile runs right after. Failed sessions log their reason.
- Phone: the clean-up helper crashed at session start (`app_process` ClassNotFoundException `CleanUp`): SELinux denies the hard link, and the fallback path was already gone. It now runs from its own copy of the server; without one it is not started.
- **Mirroring never started on a real phone:** the Mac waited for the phone's device info before opening the control connection, while the phone sends it only after both connections are open (deadlock; the phone showed "Mirroring", the Mac nothing). The Mac now opens both first, and gives up after 15 s instead of waiting forever. The virtual test phone now follows the real order.
- Phone (Android 17 crash): the clean-up helper loads from its own link to the server file, so it can't vanish underneath it; the companion's "Mirroring" flag is also cleared when the server exits.
- Phone: an unknown screen state no longer makes the session press POWER (which could turn the screen off).
- Fatal phone-server errors are reported to the Mac log (`log show --predicate 'subsystem == "com.nomadicrebel.carbonmirror"'`).
- The "identity changed" warning can no longer be replaced by a generic error; H.265 falls back to H.264 on any failure before the first frame; file handles closed on the phone.

### Added
- **Trackpad scrolling like a finger:** two-finger scrolls drive a finger drag on the phone, so lists and home-screen pages move smoothly and fling on release (mouse wheels still scroll in steps).
- **Compatibility mode** (Settings → General, off): a last resort if an OS update breaks mirroring — H.264, up to 60 fps, scroll-wheel scrolling and text typing; encryption unchanged. Offered automatically after three failed starts in a row.
- **Share the phone's internet over USB** (Settings → Connection, off): when USB tethering is off, the phone's tethering screen opens in the mirror window to switch it on; mirroring reconnects by itself after the phone's USB re-enumerates.
- While mirroring, macOS is asked not to nap or coalesce timers (latency-critical activity).
- Phone encoder: above 60 fps the frame rate is also set as the encoder's operating rate (falls back to the encoder's default if refused), so 90/120 fps sessions are not paced at 60.
- **Companion install from the Mac:** Settings → Connection → *Install / Reinstall over USB…* now replaces a companion signed by another build automatically (uninstall is allowlisted for the companion package only, over USB, after confirmation) and says exactly what happened.
- **Light mode:** Settings → General → **Appearance**: Automatic (follows macOS), Light or Dark (default Dark). Every text, pill, hairline, toolbar and glass tint follows it; the phone screen stays on black. Nothing forces dark any more (that also removes the cause of black Settings text on a dark background).
- Companion: *Pair with your Mac (QR code)* button.
- **Settings → Shortcuts:** choose which buttons the toolbar shows. By default only **Home** (plus the connection badge and Settings); add Back, Recents, App drawer, Notifications, Quick Settings, Screenshot, Clipboard sync, Privacy blur, Typing mode, Rotate, Volume, Mute, Lock and Pin on top as you like.

### Removed
- **Release DMG and APK.** Releases are source-only: `CarbonMirror-<version>-source.zip` with the phone parts inside; build and update with `bash scripts/build-mac.sh --install` (README → Install or update). The release workflow no longer uses a macOS runner.
- App keyboard shortcuts for phone actions (⌘1, ⌘[, ⇧⌘H …); every action is a toolbar button and in the Phone menu. Standard macOS keys (⌘Q, ⌘H, ⌘M, ⌘W, ⌘,) stay; other ⌘ keys go to the phone as Ctrl.

### Licence
- CarbonMirror is now licensed under the **PolyForm Shield License 1.0.0** (was PolyForm Noncommercial 1.0.0); every source file carries the SPDX identifier and the Required Notice. The forked scrcpy server files stay under Apache-2.0.

### Changed
- Toolbar buttons show the standard macOS hover highlight.
- Window corners: a standard macOS window radius (12 pt) while the toolbar shows, so the traffic lights and toolbar ends are no longer clipped; the resting window keeps the phone's shape.
- Releases sign with your Developer ID certificate and are notarised when its secrets are in the `release` environment; `scripts/build.sh` does the same locally (`CM_SIGN_IDENTITY`, `CM_NOTARY_PROFILE`).
- `scripts/build-mac.sh`: one command from the source folder to a signed app and DMG.

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
- Inner TLS key exchange is post-quantum only (X25519MLKEM768); classical-only peers are refused.
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
- Inner TLS 1.3 (AES-256-GCM, X25519MLKEM768 only) from one Rust core on both ends, pinned keys, session secret; on for USB too by default.
- QR pairing with single-use 120 s codes, 6-digit fallback, key pinning, "Create new key" recovery and rotation reminder.
- Auto transport switching, silent reconnect, privacy blur with Touch ID reveal, status line, landscape offer, two typing modes, plain-text clipboard sync, screenshots to `~/Pictures/CarbonMirror/`, debug HUD.
- Forked scrcpy 5.0 server (video + control only) and a stateless Quick Settings companion APK for GrapheneOS.

### Security
- adb no longer scans localhost for emulators or runs its own mDNS.
- Pairing pins only the address that completed the password-authenticated pairing.
- Phone server: one deadline for the TLS handshake and the session secret.
