# CarbonMirror
**Not operation or yet, still working on this project!**
**Your Android phone, live on your Mac — and back again.**
A small native macOS app that mirrors and controls an Android phone with the feel of Apple's iPhone Mirroring. Tuned for the Google Pixel 10 Pro XL (stock Android or GrapheneOS); works with any Android 11+ phone.

> Status: 1.0.0. Built and tested on Linux and on a macOS 26 GitHub runner (build, signing, launch, screenshots); the checks on your Mac and phone are in [`REAL_DEVICE_CHECKS.md`](REAL_DEVICE_CHECKS.md).

By **ButcheCassidy - The Nomadic Rebel** · [PolyForm Shield 1.0.0](LICENSE)

---

## What it does

### The phone, in a window shaped like the phone
CarbonMirror opens a borderless window that is nothing but your phone's screen, with the same rounded corners your phone has. It opens at the phone's real physical size, and you can resize it from 0.75× to 2× without it ever stretching. Press **⌘0** to snap back to real size.

### Both ways at once
What you do on the Mac happens on the phone, and what you do on the phone shows on the Mac instantly. Click to tap, drag to swipe, hold to long-press, scroll with two fingers, pinch to zoom, right-click to go Back, and type with your Mac keyboard.

### Fast over USB, safe over Wi-Fi
Plug in a cable for up to 120 frames per second. Unplug and it carries on over Wi-Fi, switching automatically in about a second without closing the window. Wi-Fi uses Android's own encrypted *Wireless debugging* only — the old unencrypted `adb tcpip` mode is detected and refused.

### Auto-connect
After you pair once with the QR code (and plug in by USB once, so the phone holds its device key), CarbonMirror looks for your phone by itself when it starts. It only listens for your phone's own Wireless debugging announcement on a Wi-Fi network where you've mirrored before — no port scanning, never a public address — checks the phone's pinned key, opens the encrypted link and shows **Ready**. One click on **Mirror** starts the session, which runs the full handshake including the device-key proof. Nothing happens while your Mac is locked or asleep, and an identity mismatch stops auto-connect until you press Retry. Turn it off in Settings → Connection → *Auto-connect to my phone at launch*.

On the phone, the companion app keeps Wireless debugging on only while you're on one of those trusted Wi-Fi networks, and turns it off again when you leave. It runs as a small foreground service, starts again after a reboot, an OS update or an app update, and survives being killed. **Set the companion's battery usage to Unrestricted** (Settings → Apps → CarbonMirror Companion → App battery usage → Unrestricted, or the button in the companion) — otherwise Android may stop it. The first time it turns Wireless debugging on for a network, Android asks *Allow wireless debugging on this network?*: tick **Always allow on this network**.

### Encrypted twice, pinned to your phone
On top of Android's encryption, CarbonMirror wraps the video and controls in its own TLS 1.3 tunnel (AES-256-GCM with post-quantum key exchange), using keys pinned to your phone and your Mac. Over USB it's off by default — the cable is a physical link — and one switch (Settings → Security → *Encrypt over USB too*) turns it on. Pairing is a QR code you scan once; after that, any other phone — or anyone pretending to be yours — is refused.

### Works with Mullvad VPN always on
Turn on *Local network sharing* in Mullvad on both devices and CarbonMirror talks to your phone over the local network only, never through the VPN tunnel, and never to the internet.

### Hover for the toolbar
Move the pointer to the top of the window and a toolbar slides out around the screen (the picture itself never moves): Back, Home, Recents, App drawer, Notifications, Quick Settings, Screenshot, Clipboard sync, Privacy blur, Typing mode, Rotate, Volume, Mute, Lock, the connection badge, Pin on top and Settings. When the window is narrow, extra buttons fold into a **…** menu. A thin status line shows battery, charging and connection quality.

### Little things that iPhone Mirroring gets wrong
- **Never pauses** when you switch Spaces, minimise or cover the window.
- **Reconnects silently** after Wi-Fi blips or waking the Mac — no Connect button.
- **Two typing modes:** *Hardware keyboard* (exact keys, works in password fields) or *Phone keyboard* (keeps the phone's suggestions). Toggle it from the toolbar.
- **Privacy blur** from the toolbar, optional auto-blur when you look away, optional Touch ID to reveal.
- **Landscape** when you want it: rotate the phone and choose *Switch to landscape* or *Not now*.

### Walled off from your Mac
Only the screen comes out and only your input goes in — plus plain-text clipboard (both ways, can be switched off) and screenshots you take into `~/Pictures/CarbonMirror/`. No file transfer, no audio, no app installs by drag-and-drop, no phone storage browsing. Phone notifications stay on the phone. The app runs in the macOS sandbox and never listens on your network.

---

## Toolbar buttons

Hover over the top of the window to show the toolbar. By default it holds **Home** (plus the connection badge and Settings), so getting back is always one click. Add any of these in **Settings → Shortcuts**: Back, Recents, App drawer, Notifications, Quick Settings, Screenshot to Mac, Clipboard sync, Privacy blur, Typing mode, Rotate, Volume down/up, Mute, Lock, Pin on top. When the window is narrow, buttons that don't fit move into the **…** menu. Every action is also in the **Phone** menu.

There are no app keyboard shortcuts besides the standard macOS ones (⌘Q, ⌘H, ⌘M, ⌘W, ⌘,). Other ⌘ shortcuts (⌘C, ⌘V, ⌘A, ⌘Z …) go to the phone as Ctrl, so copy, paste and undo work the way you expect.

---

## Phone setup

### GrapheneOS and stock Android
1. Settings → About phone → tap **Build number** 7 times to enable Developer options (GrapheneOS: Developer options and adb exist only in the **Owner** profile).
2. Developer options → turn on **USB debugging** and, for Wi-Fi, **Wireless debugging**.
3. Add the **Wireless debugging** Quick Settings developer tile (Developer options → Quick settings developer tiles) — or the **CarbonMirror** tile from the companion — so you can turn it on only for a session.
4. In Mullvad on the phone **and** the Mac: Settings → VPN settings → **Local network sharing** on.
5. Keep USB and Wireless debugging **off when you're not mirroring**. With auto-connect off, CarbonMirror turns Wireless debugging off itself when you disconnect; with auto-connect on, the companion keeps it on for trusted Wi-Fi only.

GrapheneOS notes: its default *USB-C port: charging-only when locked* stops USB mirroring while the phone is locked (Wi-Fi keeps working). After an OS update ("Optimizing apps"), the companion tile works straight away; if the update reset its permission, the tile opens Developer options and the Mac re-grants it the next time you plug in USB.

### The companion app (optional)
*CarbonMirror Companion* is a tiny app with one Quick Settings tile that turns Wireless debugging on and shows **Off / Ready / Mirroring**. Opening it from the app drawer plays the startup animation and shows the same status with a **Turn on** button, **Add Quick Settings tile**, a battery button (until it's Unrestricted) and **Forget trusted Wi-Fi networks**. Its foreground service powers auto-connect (above). It has no internet permission and opens no socket; the only thing it stores is the SHA-256 of each trusted subnet (at most 8). Install it from CarbonMirror → Settings → Connection → *Install Over USB…*.

---

## Building

Everything is built from the command line — no Xcode, no Homebrew. The full step-by-step guide, including signing and the sizes of everything, is in [`INSTALL.md`](INSTALL.md). The scripts run the same commands as below: `scripts/make-cert.sh` (Step A), `scripts/build-server.sh`, `scripts/build-apk.sh`, `scripts/build.sh` (Steps B–F); `scripts/build-mac.sh` runs them all.

### Install or update: one command
Releases contain only the source code: `CarbonMirror-<version>-source.zip` on the [Releases page](https://github.com/ButcheCassidy/CarbonMirror/releases), with the phone parts (server, phone core library, companion app) already inside. You build and sign the app on your own Mac with one command; there is no DMG to drag and no "unverified developer" prompt for your own build.

1. Once: Apple's Command Line Tools (skip if installed).
```bash
xcode-select --install
```
2. Check the download against `SHA256SUMS.txt` on the release page (the line must match).
```bash
shasum -a 256 ~/Downloads/CarbonMirror-*-source.zip
```
3. Unzip it into your home folder.
```bash
ditto -x -k ~/Downloads/CarbonMirror-*-source.zip ~
```
4. Build, sign and install. Replace `<version>` with the version you downloaded.
```bash
cd ~/CarbonMirror-<version> && bash scripts/build-mac.sh --install
```
The first run installs Rust, fetches and checks Google's adb and creates a local "CarbonMirror Dev" signing certificate (macOS asks for your password once); later runs take about a minute. CarbonMirror opens when it is done.
5. Plug the phone in by USB, then CarbonMirror → Settings → Connection → **Install Over USB…** for the companion.

**Updating:** quit CarbonMirror and repeat steps 2–5 with the new zip. Settings, keys and pairing stay (same local certificate). If the app asks for Keychain access, click **Always Allow**. Choose **Reinstall Over USB…** after each update so the companion matches.

**From git instead of a zip:** `git clone https://github.com/ButcheCassidy/CarbonMirror.git ~/CarbonMirror`, then `cd ~/CarbonMirror && bash scripts/build-mac.sh --install`; update with `git pull` and the same command. The phone parts of that version are downloaded from its release automatically.

### Step 0. Every Terminal window: go to the project folder
Every command below runs **inside the project folder**; a new Terminal window starts in your home folder, so do this first each time.
Easiest: clone it (then `cd ~/CarbonMirror` instead of the two commands below).
```bash
git clone https://github.com/ButcheCassidy/CarbonMirror.git ~/CarbonMirror
```
Or download `CarbonMirror-<version>-source.zip` from the release page in Safari, then unpack it into your home folder (skip this if Safari already made a `CarbonMirror-<version>` folder in Downloads — move that folder to your home folder instead).
```bash
ditto -x -k ~/Downloads/CarbonMirror-1.0.0-source.zip ~/
```
Go into it.
```bash
cd ~/CarbonMirror-1.0.0
```
Check you are in the right place (it must print `Package.swift`).
```bash
ls Package.swift
```
In a new window, also reload Rust and the Android paths (after Steps A-3 and INSTALL §8.4 are done).
```bash
source "$HOME/.cargo/env"; export ANDROID_HOME="$HOME/Library/Android/sdk"; export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/30.0.16248370"
```

### Step A. One-time: create the local "CarbonMirror Dev" signing certificate
Strongest settings available without an Apple Developer account: an ECDSA P-384 key with SHA-384, for code signing only, valid 5 years, imported so it can't be exported and only `codesign` can use it.

Write the certificate settings to a temporary file.
```bash
printf '[req]\ndistinguished_name=dn\nprompt=no\n[dn]\nCN=CarbonMirror Dev\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' > cm-cert.cnf
```
Create the P-384 private key.
```bash
/usr/bin/openssl ecparam -name secp384r1 -genkey -noout -out cm-key.pem
```
Create the certificate, valid for 5 years.
```bash
/usr/bin/openssl req -x509 -new -key cm-key.pem -sha384 -days 1825 -config cm-cert.cnf -extensions ext -out cm-cert.pem
```
Make a random one-time password for the temporary bundle.
```bash
export CM_P12_PASS="$(/usr/bin/openssl rand -hex 32)"
```
Bundle the key and certificate.
```bash
/usr/bin/openssl pkcs12 -export -inkey cm-key.pem -in cm-cert.pem -name "CarbonMirror Dev" -passout env:CM_P12_PASS -out cm-cert.p12
```
Import it into your login Keychain as non-extractable, usable only by `codesign`.
```bash
security import cm-cert.p12 -k ~/Library/Keychains/login.keychain-db -P "$CM_P12_PASS" -x -T /usr/bin/codesign
```
Forget the password.
```bash
unset CM_P12_PASS
```
Delete the temporary files.
```bash
rm -f cm-key.pem cm-cert.pem cm-cert.p12 cm-cert.cnf
```
Check it is there (`CSSMERR_TP_NOT_TRUSTED` next to it is normal for a self-made certificate).
```bash
security find-identity -p codesigning
```
Copy a small program to test signing with.
```bash
cp /usr/bin/true /tmp/cm-sign-test
```
Sign it.
```bash
codesign --force --sign "CarbonMirror Dev" /tmp/cm-sign-test
```
Check the signature.
```bash
codesign --verify --verbose=2 /tmp/cm-sign-test
```
Remove the test file.
```bash
rm /tmp/cm-sign-test
```
If the test fails, delete the identity with `security delete-identity -c "CarbonMirror Dev"` and repeat Step A with the RSA fallback described in [`INSTALL.md`](INSTALL.md).

### Step A-2. One-time per adb update: Google's platform-tools
Make a folder for downloads.
```bash
mkdir -p deps
```
Download platform-tools for macOS.
```bash
curl -fL --retry 5 -o deps/platform-tools-latest-darwin.zip https://dl.google.com/android/repository/platform-tools-latest-darwin.zip
```
Record its checksum (Google doesn't publish one).
```bash
shasum -a 256 deps/platform-tools-latest-darwin.zip | tee -a deps.lock
```
Unpack it.
```bash
ditto -x -k deps/platform-tools-latest-darwin.zip deps/
```
Check it is signed by Google (the line should mention Google LLC).
```bash
codesign -dvv deps/platform-tools/adb 2>&1 | grep Authority
```
Put adb where the build expects it.
```bash
cp deps/platform-tools/adb Resources/adb
```

### Step A-3. One-time: Rust
Install Rust with the official installer.
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
```
Load it into this Terminal window.
```bash
source "$HOME/.cargo/env"
```
Add the Apple Silicon target.
```bash
rustup target add aarch64-apple-darwin
```
Install the header generator.
```bash
cargo install cbindgen --locked
```

### Phone parts: server, core library and companion
**Shortcut (no Android tools):** reuse the phone parts from the installed release app (built by the release workflow from the same source).
```bash
cp /Applications/CarbonMirror.app/Contents/Resources/carbonmirror-server Resources/
```
```bash
cp /Applications/CarbonMirror.app/Contents/Resources/libcarbon_core.so Resources/
```
```bash
cp /Applications/CarbonMirror.app/Contents/Resources/CarbonMirrorCompanion.apk Resources/
```
**Or build them yourself:** this needs a JDK and the Android SDK (INSTALL.md §8.4). Build the phone server and its core library.
```bash
bash scripts/build-server.sh
```
Build and sign the companion with your own key (it asks for the keystore password).
```bash
bash scripts/build-apk.sh
```

### Step B. Build the Rust core, then the app binary
Build the Rust core for Apple Silicon.
```bash
cargo build --release --target aarch64-apple-darwin --manifest-path rust/carbon-core/Cargo.toml
```
Regenerate the C header.
```bash
cbindgen --config rust/carbon-core/cbindgen.toml --crate carbon-core --output rust/include/carbon_core.h rust/carbon-core
```
Build the app.
```bash
swift build -c release --arch arm64 2>&1 | tee build.log
```
Show any errors (no output means none).
```bash
grep -E ": error:|^ld:|Undefined symbols" build.log | sort -u | head -60
```

### Step C. Assemble the .app bundle
Start clean.
```bash
rm -rf build/CarbonMirror.app
```
Create the bundle folders.
```bash
mkdir -p build/CarbonMirror.app/Contents/MacOS build/CarbonMirror.app/Contents/Resources build/CarbonMirror.app/Contents/Helpers
```
Copy the app binary.
```bash
cp .build/release/CarbonMirror build/CarbonMirror.app/Contents/MacOS/CarbonMirror
```
Copy the app's settings file.
```bash
cp Resources/Info.plist build/CarbonMirror.app/Contents/Info.plist
```
Copy adb.
```bash
cp Resources/adb build/CarbonMirror.app/Contents/Helpers/adb
```
Copy the phone server.
```bash
cp Resources/carbonmirror-server build/CarbonMirror.app/Contents/Resources/carbonmirror-server
```
Copy the phone core library.
```bash
cp Resources/libcarbon_core.so build/CarbonMirror.app/Contents/Resources/libcarbon_core.so
```
Copy the companion APK.
```bash
cp Resources/CarbonMirrorCompanion.apk build/CarbonMirror.app/Contents/Resources/CarbonMirrorCompanion.apk
```
Copy the startup animation.
```bash
cp Resources/CarbonMirror-startup.mp4 build/CarbonMirror.app/Contents/Resources/CarbonMirror-startup.mp4
```
Check the settings file is valid.
```bash
plutil -lint build/CarbonMirror.app/Contents/Info.plist
```
`scripts/build.sh` also writes the SHA-256 of the server and core library into the bundle's `Info.plist` here, so the app can verify them before every push to the phone.

### Step D. Make the app icon
Make a folder for the icon sizes.
```bash
mkdir -p build/CarbonMirror.iconset
```
Create each size (one command per size).
```bash
sips -z 16 16 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_16x16.png
```
```bash
sips -z 32 32 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_16x16@2x.png
```
```bash
sips -z 32 32 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_32x32.png
```
```bash
sips -z 64 64 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_32x32@2x.png
```
```bash
sips -z 128 128 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_128x128.png
```
```bash
sips -z 256 256 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_128x128@2x.png
```
```bash
sips -z 256 256 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_256x256.png
```
```bash
sips -z 512 512 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_256x256@2x.png
```
```bash
sips -z 512 512 Resources/CarbonMirror-icon-1024.png --out build/CarbonMirror.iconset/icon_512x512.png
```
```bash
cp Resources/CarbonMirror-icon-1024.png build/CarbonMirror.iconset/icon_512x512@2x.png
```
Turn them into the icon file.
```bash
iconutil -c icns build/CarbonMirror.iconset -o build/CarbonMirror.app/Contents/Resources/CarbonMirror.icns
```
Remove the temporary folder.
```bash
rm -rf build/CarbonMirror.iconset
```

### Step E. Sign inside-out and verify
Sign the bundled adb first.
```bash
codesign --force --options runtime --timestamp=none --entitlements Resources/adb-helper.entitlements --sign "CarbonMirror Dev" build/CarbonMirror.app/Contents/Helpers/adb
```
Then sign the app.
```bash
codesign --force --options runtime --timestamp=none --entitlements Resources/CarbonMirror.entitlements --sign "CarbonMirror Dev" build/CarbonMirror.app
```
Verify (should say "valid on disk" and "satisfies its Designated Requirement").
```bash
codesign --verify --deep --strict --verbose=2 build/CarbonMirror.app
```

### Step F. Make and sign the DMG
Make the output folders.
```bash
mkdir -p dist build/dmg
```
Copy the app into the DMG folder.
```bash
ditto build/CarbonMirror.app build/dmg/CarbonMirror.app
```
Add a shortcut to Applications.
```bash
ln -s /Applications build/dmg/Applications
```
Create the DMG (a deprecation warning on macOS 27 is normal).
```bash
hdiutil create -volname "CarbonMirror 1.0.0" -srcfolder build/dmg -ov -format UDZO dist/CarbonMirror-1.0.0.dmg
```
Remove the DMG folder.
```bash
rm -rf build/dmg
```
Sign the DMG.
```bash
codesign --force --timestamp=none --sign "CarbonMirror Dev" dist/CarbonMirror-1.0.0.dmg
```
Open it and drag CarbonMirror onto Applications (choose Replace when updating).
```bash
open dist/CarbonMirror-1.0.0.dmg
```

Or install straight away without the DMG. Quit the running copy.
```bash
osascript -e 'tell application id "com.nomadicrebel.carbonmirror" to quit'
```
Remove the old copy.
```bash
rm -rf /Applications/CarbonMirror.app
```
Copy the new one.
```bash
ditto build/CarbonMirror.app /Applications/CarbonMirror.app
```
Open it.
```bash
open /Applications/CarbonMirror.app
```

### Linux (development and tests)
The Rust core and the platform-independent Swift code build and test on Linux. Set up once with `scripts/setup-env.sh`, then:
```bash
source ~/carbonmirror-deps/env.sh
```
```bash
cargo test --release --manifest-path rust/Cargo.toml
```
```bash
cargo build --release --manifest-path rust/Cargo.toml && swift test
```

---

## Manual test checklist (spec 10.3)

1. First pair via QR.
2. Reconnect after Mac and phone reboot.
3. USB → Wi-Fi → USB handover mid-session.
4. Mullvad on, Local network sharing on (both devices).
5. Mullvad Local network sharing off → "LAN sharing blocked".
6. Phone hotspot mode.
7. 120 fps over USB (⌥⌘D shows fps).
8. Use the phone by hand while mirrored.
9. Rotate.
10. Resize 0.75× → max.
11. Lock the Mac → session ends.
12. Revoke authorisations on the phone → "Authentication failed" → Create new key → re-pair works.
13. A screen recording of the Mac doesn't show the phone window.
    - 13a. Clipboard both ways (text only); turning it off stops it.
    - 13b. Screenshot lands in `~/Pictures/CarbonMirror/`.
    - 13c. Phone notifications show only in the mirrored screen, never in macOS Notification Centre.
    - 13d. Switch Spaces and minimise for 2 minutes → still live on return.
    - 13e. Privacy blur (⇧⌘H, auto-blur, Touch ID reveal).
    - 13f. Status line shows the right battery, charging and connection quality.
    - 13g. Rotate the phone → landscape offer; each Landscape setting behaves as described.
    - 13h. Both typing modes; note what autocorrect does.
14. Companion tile turns Wireless debugging on; ending the session turns it off.
15. GrapheneOS update → "Optimizing apps" → tile still works.

---

## More
- [`INSTALL.md`](INSTALL.md) — install, sizes, signing, uninstall, troubleshooting.
- [`SECURITY_NOTES.md`](SECURITY_NOTES.md) — threat model, encryption, honest limits.
- [`REAL_DEVICE_CHECKS.md`](REAL_DEVICE_CHECKS.md) — the 5-minute hardware checklist.
- [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) · [`CHANGELOG.md`](CHANGELOG.md)
