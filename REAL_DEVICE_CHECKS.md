# Real-device checks

Everything here needs your Mac or your Pixel, so none of it has been run yet. Every item is **NOT RUN — needs my Mac / needs real device** until you report the result. Tick a box only after you saw the expected result yourself.

Before starting: build and install the app (`INSTALL.md`), connect the Pixel by USB, unlock it, and allow USB debugging.

## A. Mac app and sandbox (≈ 1 min)

1. [ ] **Launch.** Open CarbonMirror. *Expect:* a black phone-shaped window with continuous corners showing "Not paired" or your phone, and a two-phone icon in the menu bar.
2. [ ] **No network listeners at all.** While mirroring, run this in Terminal:
   ```bash
   lsof -nP -iTCP -sTCP:LISTEN | grep -i -e adb -e CarbonMi
   ```
   *Expect:* no output (adb and the session use private Unix sockets).
3. [ ] **UDP.** Run:
   ```bash
   lsof -nP -iUDP | grep -i -e adb -e CarbonMi
   ```
   *Expect:* no output, or only mDNS through the system (`mDNSResponder` is not listed here).
4. [ ] **Sandbox.** Run:
   ```bash
   codesign -d --entitlements - /Applications/CarbonMirror.app
   ```
   *Expect:* exactly `app-sandbox`, `network.client`, `network.server`, `device.usb`, `assets.pictures.read-write`.
5. [ ] **Logs hold no content.** While mirroring, type a word on the phone, copy text both ways, then run:
   ```bash
   log show --last 5m --predicate 'subsystem == "com.nomadicrebel.carbonmirror"' | grep -i -e "<the word you typed>" -e "<the copied text>"
   ```
   *Expect:* no output.

6a. [ ] **Unix sockets are private.** While mirroring, run:
   ```bash
   ls -la ~/Library/Containers/com.nomadicrebel.carbonmirror/Data/tmp/cm
   ```
   *Expect:* the folder is `drwx------`, containing `cm-adb` and one `cm-f…` socket per open session.
6b. [ ] **No Resume snapshots.** Quit CarbonMirror while mirroring, then run:
   ```bash
   ls ~/Library/Containers/com.nomadicrebel.carbonmirror/Data/Library/Saved\ Application\ State 2>&1
   ```
   *Expect:* "No such file or directory", or a folder with no window images.
6c. [ ] **Entitlement trim.** Re-sign a copy without `com.apple.security.network.server` (remove that key from `Resources/CarbonMirror.entitlements`, run `bash scripts/build.sh`). *Expect:* mirroring still works → keep it removed and report back; if adb fails to start, put it back.

A-S. **Startup animation (Mac).** Open CarbonMirror. Expected: the 3-second animation plays at once on pure black, exactly centred in the phone window, sharp, no stutter; then the status screen fades in. Resize the window to its smallest and largest size and reopen: still centred, never cut off. `NOT RUN — needs my Mac`

## B. USB mirroring (≈ 1.5 min)

6. [ ] **Server push and clean-up.** With the phone on USB, CarbonMirror connects by itself. *Expect:* the phone screen appears within ~2 s. Quit CarbonMirror, then:
   ```bash
   pgrep -fl adb
   ```
   *Expect:* no output (CarbonMirror stopped its private adb and every child process).
7. [ ] **120 fps.** Press ⌥⌘D (debug HUD) and scroll a long list on the phone. *Expect:* `fps` near 120, `TLS TLS_AES_256_GCM_SHA384 · X25519MLKEM768` (USB encryption is on by default).
8. [ ] **Colours and corners.** Open a photo with strong colours. *Expect:* the same colours as the phone; the window's rounded corners match the phone's.
9. [ ] **Use the phone by hand.** Open an app on the phone itself. *Expect:* the Mac shows every movement within a frame.
10. [ ] **Typing.** Tap a password field, type with the Mac keyboard in *Hardware keyboard* mode, then press ⌥⌘K and type in a chat field. *Write down* what autocorrect does in each mode on GrapheneOS Keyboard and on Gboard.
11. [ ] **Scroll direction.** Scroll vertically and horizontally with two fingers on the trackpad. *Expect:* content moves the same way as on a Mac (the horizontal sign is unverified).
12. [ ] **Screenshot.** Press ⌘S. *Expect:* `~/Pictures/CarbonMirror/CarbonMirror-YYYY-MM-DD-HHmmss.png` at 1344 × 2992.
13. [ ] **Capture protection.** Run:
    ```bash
    screencapture -x ~/Desktop/cm-test.png
    ```
    *Expect:* the phone window is missing or black in `cm-test.png`. Also try QuickTime screen recording and write down what it shows.
14. [ ] **Clipboard.** Copy text on the Mac, long-press Paste on the phone; copy on the phone, ⌘V on the Mac. Turn clipboard sync off (⇧⌘C) and repeat. *Expect:* works when on, nothing crosses when off. Also copy a password from your password manager on the Mac → it must **not** arrive on the phone; and phone text must not appear on your iPhone/iPad (no Universal Clipboard).
15. [ ] **Rotate.** Rotate the phone. *Expect:* the "Switch to landscape · Not now" pill; accepting rotates the window around its centre.

## C. Wireless, pairing and Mullvad (≈ 1.5 min)

16. [ ] **QR pairing.** Menu bar → Pair New Device…, then on the phone Wireless debugging → *Pair device with QR code*. *Expect:* paired, then mirroring over Wi-Fi with a lock in the connection badge.
17. [ ] **Plaintext refusal.** On the phone over USB run `adb tcpip 5555` (from any adb), then try to connect. *Expect:* "Insecure connection refused". Restart the phone afterwards.
18. [ ] **Mullvad on both, Local network sharing on.** *Expect:* wireless mirroring works.
19. [ ] **Mullvad Local network sharing off.** *Expect:* "LAN sharing blocked".
20. [ ] **Phone hotspot.** Join the Pixel's hotspot from the Mac. *Expect:* connects (enter IP and port from the phone's Wireless debugging screen if asked).
21. [ ] **Handover.** While on Wi-Fi, plug in USB. *Expect:* switches to USB within ~1 s without closing the window; unplug → back to Wi-Fi.
22. [ ] **Lock the Mac** (⌃⌘Q). *Expect:* session ends; after unlocking it reconnects silently.
23. [ ] **Keychain.** Run:
    ```bash
    security find-generic-password -s com.nomadicrebel.carbonmirror -a "CarbonMirror identity certificate"
    ```
    *Expect:* one item. Then Settings → Security → Create New Key…, run it again and compare the date. Revoke authorisations on the phone and check "Authentication failed" → Create new key → QR works.
24. [ ] **Brute force.** Use the 6-digit pairing code option and enter a wrong code three times. *Expect:* the phone rejects each; CarbonMirror never offers anything weaker.

## D. Companion and GrapheneOS (≈ 1 min)

25. [ ] **Install.** Settings → Connection → Install over USB… *Expect:* "Companion installed".
26. [ ] **Exported components.** Run:
    On the phone: Settings → Apps → CarbonMirror Companion → Permissions, and Developer options → Running services. *Expect:* only `WRITE_SECURE_SETTINGS: granted=true` and the tile service with `BIND_QUICK_SETTINGS_TILE`.
27. [ ] **Tile.** Add the CarbonMirror tile in Quick Settings, tap it. *Expect:* Wireless debugging on, tile says Ready; during mirroring it says Mirroring; with auto-connect off, Disconnect on the Mac turns it Off.
28. [ ] **GrapheneOS update.** After an OS update and "Optimizing apps", tap the tile without opening anything. *Expect:* still works; if the permission was reset, the tile opens Developer options and the Mac re-grants it next USB connect ("Companion permission re-granted").
29. [ ] **USB while locked (GrapheneOS).** Lock the phone during USB mirroring. *Expect:* USB stops (GrapheneOS charging-only-when-locked); wireless still works.

D-S. **Companion screen.** Open *CarbonMirror Companion* from the app drawer. Expected: black screen, the animation plays at once in the exact centre (no white flash, no icon first), then "Off / Ready / Mirroring" with **Turn on** and **Add Quick Settings tile**; all dark. Rotate, split-screen and largest font size: nothing cut off. `NOT RUN — needs real device`
D-K. **Device key.** After one USB session, start a wireless session: it connects. Then run `adb shell rm /data/local/tmp/carbonmirror-device.key` from another computer and start wireless again. Expected: "Untrusted device"; plugging in USB once repairs it. `NOT RUN — needs real device`

## F. Auto-connect and companion service (≈ 2 min)

F1. [ ] **Battery.** Companion → tap *Set Battery to Unrestricted* → Allow. *Expect:* the button disappears; a silent "CarbonMirror — Waiting for a trusted Wi-Fi network" notification exists.
F2. [ ] **Trust.** Mirror once over Wi-Fi on your home network. *Expect:* the notification says "Trusted Wi-Fi…".
F3. [ ] **Launch.** Quit CarbonMirror, turn Wireless debugging off on the phone, wait 30 s, open CarbonMirror. *Expect:* phone turns Wireless debugging on by itself (first time on this Wi-Fi: Android asks *Allow wireless debugging on this network?* → tick *Always allow* → Allow); the Mac shows **Searching** then **Ready**; click **Mirror** → the phone appears with the lock in the badge.
F4. [ ] **Lock.** Lock the Mac while on **Ready**. *Expect:* nothing connects while locked (`adb devices` from the app's helper shows no Wi-Fi device after 10 s); unlock → **Ready** again.
F5. [ ] **Leave Wi-Fi.** Switch the phone to mobile data or another Wi-Fi. *Expect:* Wireless debugging goes off on the phone within seconds; the Mac shows **Not connected** or **Searching**.
F6. [ ] **Survives.** Swipe the companion away in Recents, then reboot the phone, then install an OS update. *Expect:* after each, the notification is back without opening the app, and F3 works.
F7. [ ] **Setting off.** Mac Settings → Connection → untick *Auto-connect…*. *Expect:* **Not connected** with **Connect**; nothing searches until you click it.
F8. [ ] **Impostor.** (optional) Another Android phone paired with nothing advertises on the same Wi-Fi. *Expect:* never shown as Ready.

## E. 5-minute soak (USB, then Wi-Fi)

30. [ ] Mirror for 5 minutes while scrolling, typing fast and rotating, then switch to Wi-Fi and repeat. Watch Activity Monitor. *Expect:* CPU < 8 % (USB) / < 10 % (Wi-Fi), memory flat, no hangs, all input arrives.
