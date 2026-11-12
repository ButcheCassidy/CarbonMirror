# Installing CarbonMirror

Numbered steps for a Mac with Apple Command Line Tools (no Xcode, no Homebrew). Paste one command at a time. After each command, "You should see" tells you what to expect.

---

## 1. What adb is and where it lives

adb is Google's tool for talking to Android phones. CarbonMirror carries its own copy **inside the app** (`CarbonMirror.app/Contents/Helpers/adb`) and runs it only while it needs it, on a private socket file inside the app's own sandbox folder — nothing on your network or other user accounts can reach it. You do **not** install adb system-wide, change your PATH, or keep another copy.

What stays on your Mac after quitting: the app's private folder `~/Library/Containers/com.nomadicrebel.carbonmirror/` (settings, and `Data/Library/Application Support/CarbonMirror/adb/` with adb's key pair — the phone recognises your Mac by it), and four Keychain items named "CarbonMirror …". No adb process keeps running.

## 2. Sizes (measured on your Mac)

See how big the installed app is.
```bash
du -sh /Applications/CarbonMirror.app
```
See how big the bundled adb is.
```bash
du -sh /Applications/CarbonMirror.app/Contents/Helpers/adb
```
See the platform-tools download (Step A-2).
```bash
du -sh deps
```
See the Rust toolchain.
```bash
du -sh ~/.rustup ~/.cargo
```
See the build folders.
```bash
du -sh build .build rust/target server/build companion/build
```
See the app's data folder.
```bash
du -sh ~/Library/Containers/com.nomadicrebel.carbonmirror
```

| Item | Keep? |
|---|---|
| `/Applications/CarbonMirror.app`, the app's data folder | Keep (needed to run) |
| `deps/`, `~/.rustup`, `~/.cargo`, JDK, Android SDK | Keep only if you will rebuild |
| `build/`, `.build/`, `rust/target/`, `server/build/`, `companion/build/` | Delete any time (rebuilt automatically) |
| `dist/` | Keep the DMG/APK you install from; delete old versions |

## 3. Cleanup

Delete the build folders.
```bash
rm -rf build .build rust/target server/build companion/build
```
Delete the platform-tools download (you'll need Step A-2 again for the next build).
```bash
rm -rf deps
```
Remove Rust completely if you stop rebuilding.
```bash
rustup self uninstall
```

## 4. Installing the Mac app

1. Open `CarbonMirror-1.0.0.dmg` (from the GitHub release, or `dist/` when you build it yourself) and drag **CarbonMirror** onto **Applications**.
   - Check the download first: `shasum -a 256 ~/Downloads/CarbonMirror-1.0.0.dmg` must print the DMG line of `SHA256SUMS.txt` from the release.
   - The release DMG is signed in GitHub Actions with a one-time "CarbonMirror Dev" certificate that was deleted after the build. It runs the same, but when you later switch to your own build (section 8), macOS asks once more for Keychain access and you pair the phone again (the identity key is tied to the app's signature).
2. The first time, macOS says it can't verify the developer (the app is self-signed, not notarised). Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to CarbonMirror. Don't turn Gatekeeper off.
3. Allow **Local Network** when asked (needed to find your phone on Wi-Fi). If macOS asks about the USB accessory, allow it.

You should see: the startup animation (3 seconds, on black, centred in the phone-shaped window), then the window saying "Not paired" (or your phone if it is plugged in), and a two-phone icon in the menu bar.

### 4a. Or build it yourself from GitHub (one folder, one command)
Install Apple's Command Line Tools (includes `git`; skip if already installed).
```bash
xcode-select --install
```
Download the source into a folder in your home folder.
```bash
git clone https://github.com/ButcheCassidy/CarbonMirror.git ~/CarbonMirror
```
Go into it (do this first in every new Terminal window).
```bash
cd ~/CarbonMirror
```
Get the latest changes later on.
```bash
git pull
```
Build, sign, make the DMG and install (the phone parts come from the matching release: installed app, the DMG in Downloads, or GitHub).
```bash
bash scripts/build-mac.sh --install
```
You should see `valid on disk`, `satisfies its Designated Requirement` and a SHA-256 line for `dist/CarbonMirror-<version>.dmg`; CarbonMirror opens. If the repository is private, `git clone` asks for your GitHub username and a personal access token (GitHub → Settings → Developer settings → Personal access tokens) instead of your password.

## 5. Phone setup (GrapheneOS and stock Android)

1. **Developer options:** Settings → About phone → tap **Build number** 7 times. (GrapheneOS: only in the Owner profile.)
2. **USB debugging:** Settings → System → Developer options → **USB debugging** on.
3. **Wireless debugging:** in the same screen, **Wireless debugging** on when you want Wi-Fi mirroring.
4. **Quick Settings tile:** Developer options → **Quick settings developer tiles** → Wireless debugging. Now you can switch it per session from the pull-down.
5. **Mullvad:** in the Mullvad app on the phone **and** on the Mac: Settings → VPN settings → **Local network sharing** on.
6. **Companion:** plug the phone in by USB, unlock it, then in CarbonMirror: Settings → Connection → **Install over USB…** → Install. You should see "Companion installed". (Or install `CarbonMirrorCompanion-1.0.0.apk` from the release. If the release environment had no keystore, that APK is signed with a one-time key: before installing a later build signed with your own key, uninstall the companion — the Mac re-grants its permission on the next USB connection.)
7. **CarbonMirror tile:** pull down Quick Settings twice → edit (pencil) → drag **CarbonMirror** into place. It shows Off / Ready / Mirroring.
8. **Battery: Unrestricted** (needed for auto-connect): Settings → Apps → **CarbonMirror Companion** → App battery usage → **Unrestricted** (or tap the battery button in the companion). Also allow its notification — it is the small "Ready for auto-connect" service that keeps working after reboots, OS updates and app updates.
9. **Auto-connect:** on by default on the Mac (Settings → Connection → *Auto-connect to my phone at launch*). It starts after the first USB connection and QR pairing. The first time the companion turns Wireless debugging on for your Wi-Fi, Android asks *Allow wireless debugging on this network?* — tick **Always allow on this network** → Allow.
10. GrapheneOS: the default *USB-C port: charging-only when locked* stops USB data while the phone is locked — keep it unlocked for USB, or use Wi-Fi.

## 6. First connection

1. **USB first:** plug the phone in and unlock it. Tap **Allow** on the phone's "Allow USB debugging?" dialog (tick *Always allow from this computer*). You should see the phone's screen in the window within a few seconds.
2. **Pair for Wi-Fi:** menu-bar icon → **Pair New Device…**. The window shows a QR code with a 2-minute countdown. On the phone: Wireless debugging → **Pair device with QR code** → scan. You should see the phone's screen again, and a lock next to "Wi-Fi" in the toolbar.
3. If the phone isn't found (Mullvad can block the replies that help find it), CarbonMirror asks for the **IP address & Port** shown on the phone's Wireless debugging screen. Type them in.

## 7. Full uninstall

Quit CarbonMirror (this also turns Wireless debugging off on the phone).
```bash
osascript -e 'tell application id "com.nomadicrebel.carbonmirror" to quit'
```
Delete the app.
```bash
rm -rf /Applications/CarbonMirror.app
```
Delete its data.
```bash
rm -rf ~/Library/Containers/com.nomadicrebel.carbonmirror
```
Delete its Keychain items (run each until it says the item could not be found).
```bash
security delete-generic-password -s com.nomadicrebel.carbonmirror
```
Delete its identity key: open **Keychain Access**, search for `CarbonMirror identity`, select the key and press Delete (there is no Terminal command for deleting a single key).
Delete the signing certificate.
```bash
security delete-identity -c "CarbonMirror Dev"
```
On the phone: uninstall **CarbonMirror Companion** (this also deletes its trusted-network list); delete the device key and the Mac pin while the phone is plugged in (run before deleting the app: `/Applications/CarbonMirror.app/Contents/Helpers/adb shell rm -f /data/local/tmp/carbonmirror-device.key /data/local/tmp/carbonmirror-mac.pin`); Developer options → **Revoke USB debugging authorizations**; Wireless debugging → **Paired devices** → remove your Mac; then turn **Developer options** off.

## 8. Signing everything on your Mac (strongest settings)

### 8.1 The "CarbonMirror Dev" certificate
Run Step A from the README (or `bash scripts/make-cert.sh` from the project folder): an ECDSA P-384 key with SHA-384, code-signing only, 5 years, imported non-extractable and usable only by `codesign`, with the temporary file protected by a random password and deleted immediately.

If the signing test fails, delete the identity.
```bash
security delete-identity -c "CarbonMirror Dev"
```
Then repeat Step A, replacing its two P-384 commands (`ecparam` and `req -x509 -new -key …`) with this single RSA-4096 command.
```bash
/usr/bin/openssl req -x509 -newkey rsa:4096 -nodes -sha384 -keyout cm-key.pem -days 1825 -config cm-cert.cnf -extensions ext -out cm-cert.pem
```

### 8.2 Signing order
Sign the bundled adb first, then the app, then the DMG (README Steps E and F, or `scripts/build.sh`).

### 8.3 Checking the signatures
Show the app's signature.
```bash
codesign -dvvv /Applications/CarbonMirror.app
```
You should see `Authority=CarbonMirror Dev`, a `Runtime Version=` line (hardened runtime on) and `CandidateCDHashFull sha256=`. `codesign` always hashes code with SHA-256; the P-384/SHA-384 strength is in your certificate's signature.

Show the entitlements.
```bash
codesign -d --entitlements - /Applications/CarbonMirror.app
```
You should see exactly: `com.apple.security.app-sandbox`, `com.apple.security.network.client`, `com.apple.security.network.server`, `com.apple.security.device.usb`, `com.apple.security.assets.pictures.read-write`.

Verify the app.
```bash
codesign --verify --deep --strict --verbose=2 /Applications/CarbonMirror.app
```
You should see "valid on disk" and "satisfies its Designated Requirement".

Verify the DMG.
```bash
codesign --verify --verbose=2 dist/CarbonMirror-1.0.0.dmg
```
You should see "valid on disk".

macOS will still warn the first time (self-signed, not notarised) — use **Open Anyway** as in step 4.

### 8.4 Signing the companion APK with your own key
The phone parts need a JDK and Android's build tools, installed from official downloads (no Homebrew):

1. Download a JDK 21 `.pkg` for macOS (aarch64) from **adoptium.net** and install it.
2. Download **Command line tools only** for Mac from **developer.android.com/studio** (bottom of the page). Safari saves `commandlinetools-mac-…_latest.zip` in Downloads.

Check Java works (it must print version 21).
```bash
java -version
```
Make the SDK folder.
```bash
mkdir -p ~/Library/Android/sdk/cmdline-tools
```
Unpack the tools into it.
```bash
ditto -x -k ~/Downloads/commandlinetools-mac-*_latest.zip ~/Library/Android/sdk/cmdline-tools/
```
Rename the unpacked folder to `latest` (Android requires that name).
```bash
mv ~/Library/Android/sdk/cmdline-tools/cmdline-tools ~/Library/Android/sdk/cmdline-tools/latest
```

Tell the tools where the SDK lives.
```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"
```
Accept the SDK licences (type `y` when asked).
```bash
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses
```
Install the Android 16 platform, build tools and NDK (each downloaded once).
```bash
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "platforms;android-36" "build-tools;36.0.0" "ndk;30.0.16248370"
```
Tell cargo where the NDK is.
```bash
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/30.0.16248370"
```
Add the phone target to Rust.
```bash
rustup target add aarch64-linux-android
```
Install the NDK helper for cargo.
```bash
cargo install cargo-ndk --locked
```
Make a private folder for your release key.
```bash
mkdir -p ~/Library/Application\ Support/CarbonMirror/signing && chmod 700 ~/Library/Application\ Support/CarbonMirror/signing
```
Create your P-384 release key (type a strong password when asked; it is never stored).
```bash
keytool -genkeypair -keyalg EC -groupname secp384r1 -sigalg SHA384withECDSA -validity 10000 -alias carbonmirror -storetype PKCS12 -keystore ~/Library/Application\ Support/CarbonMirror/signing/carbonmirror-release.p12 -dname "CN=CarbonMirror Companion"
```
Go to the project folder (README Step 0), then build the phone server and core library.
```bash
bash scripts/build-server.sh
```
Build and sign the APK (asks for the password; signs with APK Signature Scheme v2 and v3).
```bash
bash scripts/build-apk.sh
```
You should see `Verified using v2 scheme (APK Signature Scheme v2): true`, `Verified using v3 scheme …: true`, `Signer #1 key algorithm: EC`, `key size (bits): 384`, and exactly these permissions: `WRITE_SECURE_SETTINGS`, `ACCESS_NETWORK_STATE`, `CHANGE_NETWORK_STATE`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `RECEIVE_BOOT_COMPLETED`, `POST_NOTIFICATIONS`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.

**Back up `carbonmirror-release.p12` and its password somewhere safe and offline.** Android only accepts updates signed with the same key.

### 8.5 Re-signing and expiry
Every rebuild re-signs with the same certificate (`scripts/build.sh`), so macOS keeps the app's permissions. When the certificate expires after 5 years, make a new one with Step A; macOS will ask for Local Network and Keychain access once more.

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| "CarbonMirror can't be opened" | System Settings → Privacy & Security → **Open Anyway**. |
| Window stays on "Searching" | Unlock the phone; check Wireless debugging is on and both are on the same Wi-Fi. Enter the IP & port when asked. |
| "LAN sharing blocked" | Turn on Mullvad **Local network sharing** on both devices (and reconnect Mullvad). |
| "Wireless debugging off" | Turn it on with the Quick Settings tile. |
| "Authentication failed" | Click **Retry**; if it stays, **Create new key**, then on the phone revoke USB debugging authorisations and remove the old Mac under Paired devices. |
| "This phone's identity changed" | Someone may be intercepting. Only if you reset/reinstalled the phone: **Create new key** and pair again. |
| "Insecure connection refused" | The phone offered `adb tcpip` (unencrypted). Restart the phone and use Wireless debugging. |
| USB mirroring stops when the phone locks (GrapheneOS) | That's GrapheneOS's USB protection; keep the phone unlocked or use Wi-Fi. |
| The companion tile opens Developer options | Its permission was reset by an update; plug in USB once — CarbonMirror re-grants it. |
| Build says `missing Resources/…` | Run Step A-2 (adb), `scripts/build-server.sh` and `scripts/build-apk.sh` first. |
