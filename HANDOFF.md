# CarbonMirror — HANDOFF (v1.0.0 · auto-connect + companion service · release workflow · real Mac + phone checks NOT RUN)

> **Resume instruction:** Paste this file plus the latest source bundle (repo `ButcheCassidy/CarbonMirror`, branch `main`) into a new chat and say: *Continue CarbonMirror from the Next steps in HANDOFF.md.*
> Then: `source ~/carbonmirror-deps/env.sh` (Linux build env, §5) and start at **§12 Next steps, step 1**. The full spec is §14 (verbatim, with per-requirement status).

## 0b. Session 5 (2026-11-13) — read this first

- **Real-device pairing bug found and fixed (finding 43, High):** user recordings (Mac + phone, Mullvad LAN sharing on) showed `adb pair` succeeding on the phone, then the Mac at once showing "Untrusted device" → Pair → QR → loop. Cause: `TLSSession.capture()` (adbd key probe in `PairingController.finish` and `connectWireless`) used the PQ-only provider from finding 34; adbd (BoringSSL, classical groups) refuses it, so no key was captured. Fix: `tls::probe_provider()` (X25519MLKEM768, X25519, P-256, P-384) for the probe only; sessions stay PQ-only. Regression test `capture_reads_a_classical_only_adbd` (fails before, passes after).
- Pairing failures now log their step: `log show --predicate 'subsystem == "com.nomadicrebel.carbonmirror"' | grep "pairing failed"`.
- Settings: checkbox titles were black on the glass (glass content resolved to the light appearance) → explicit white `attributedTitle`; glass/blur/column get the dark appearance. AppKit code is not compiled on Linux: check on the Mac build.
- Tests: `cargo test` 46, clippy clean; `swift test` 81 (Linux). No macOS CI used. Version stays **1.0.1** (unpublished), so the 1.0.1 phone parts still match; the phone side is unchanged.
- **Signing finding (session 5):** the cloud environment's global git config sets `gpg.ssh.program=/tmp/code-sign` (environment manager), which signs every commit with the environment's own key `SHA256:32dP45eSMmVSt/G/CGvcxl/P+MO3Nwj9xeTh/GSA2wc` (`ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKy87HxSEheG8vEPhSs9u2KZCtVErAQfpmprtUJCZ2w7`), ignoring `user.signingkey`. All 62 commits up to `594f52d` carry that signature; the 2 GitHub web commits are PGP (web-flow). From now on the repo-local `gpg.ssh.program=ssh-keygen` makes commits use the user's registered key below. A new session must set it too (`git config gpg.ssh.program ssh-keygen`).
- Commits are SSH-signed with a new session-5 key (ed25519 `SHA256:g5Jso1MpxhGtp8rsRoFz0h1b3aWObBC6DcsdpXpJv0Y`, key only in the session-5 container); add its public key on GitHub as a Signing Key.
- Not changed (audited, by design): auto-connect needs the companion key proof (`autoConditions`); manual **Mirror** after pairing does not.
- Round 2 (user report: pairing + USB mirroring work, low latency; Wi-Fi blocked on enterprise Wi-Fi): findings 44–47 — keyboard created at session start and per session; CleanUp helper runs from a private copy (Android 17 crash); quality/adaptive profile on round trip, not fps (adaptive 1–120 Hz displays), display link 1–120 Hz; Settings checkbox titles as white labels. New `carbonmirror-server` built here (SHA-256 `1f6e1eed4dca225a186a25581055e9b5d776da95d41c365678e78f2df03ebd3f`) and sent in chat; `libcarbon_core.so` and the APK are unchanged from 1.0.1.
- Round 3: USB restart → "Connection lost"/black screen (finding 48): teardown race in `SessionController.end()` fixed; two Haiku audits (Mac + phone lifecycle) — rejected: CleanUp deleting the shared jar / leaving its copy (the child's `SERVER_PATH` is its own copy), killing the device server (it exits when its sockets close).
- Round 4: **light mode** at the user's request (deviates from spec 2.1/§13 "always dark"; monochrome kept, phone screen black, glass only Settings + status screens): `AppSettings.appearance` (default dark), Settings → General → Appearance, `Theme` adaptive tokens (`adaptive(dark:light:)`, `glassTint`, `panelFill`, `appearance(_:)`, `cg(_:for:)`), no forced `darkAqua`; pre-26 materials `.underWindowBackground`. Haiku audits (8 this session) — accepted: phone-mode stuck keys (49). Rejected/deferred: wireless proof without a stored device key (adb key pin already authenticates; failing closed breaks QR-only pairing), removeMacPin with an `ip:port` serial (valid adb serial), mDNS last-match/port cache (probe + prompt recover), companion trust needing an unplug event (Android change, next APK), horizontal scroll sign (needs a device test).
- Round 5: companion 1.0.1 rebuilt here (USB_STATE receiver → trust on unplug; one-time test key, signer SHA-256 `9feb3a67…97294`), Mac replaces a companion from another build (uninstall allowlisted), Wi-Fi probes all endpoint candidates, findings 51–54; strings: "Wi-Fi off", "your phone", "Wi-Fi only", title-case buttons. Final sweep (6 Haiku): rejected — CleanUp copy "never deleted" (the child's `SERVER_PATH` is its copy), predictable copy path (same shell uid, SELinux keeps apps out), "Shortcuts" → "Toolbar" rename (user's naming), font tokens, start/stop timeouts (MirrorSession has its own), Disconnect during the stop phase of a switch (edge case). Delivered: `CarbonMirror-1.0.1-source.zip` with phone parts in `Resources/` (marker 1.0.1).
- Round 6: findings 55–59 (switch/stop/queue in `SessionController`, reconnect-refused UI, Launch-at-login state, CleanUp copy O_EXCL/0600). New server SHA-256 `cfd2ffa1db354c9b94f5fab412ccb80216a214471dadb5bc865b318d00da4085`; zip re-sent.
- Round 7: 60 fps question. Research (Haiku): adb over USB on a Pixel 8 measured ~140–190 MiB/s in AOSP docs vs ~8 MB/s for a 64 Mbit/s stream, so the link is not the limit; Pixel USB generation per model unconfirmed (sources disagree, Google pages unreachable). Likely limits: the user's own "USB frame rate 60 fps" setting, Smooth Display off/apps at 60 Hz, encoder paced by KEY_FRAME_RATE 60 → server now sets frame and operating rate to max_fps above 60 (fallback without operating rate). Server SHA-256 `6d66dca2157c90b7fac4a5d0c281a9b2e8cb0a44c05440f3d90d89376857c342`. Routing video over the tether network rejected for now: no bandwidth gain, would need the Wi-Fi TLS path and a listening socket on the phone.
- **Proposed, waiting for the user (questions 1–2):** "Use phone's internet over USB" (USB tethering + mirroring on one cable). Research: shell-only tethering start reportedly blocked on Android 14+; Pixel keeps adb with tethering started from Settings (ncm,adb); macOS NCM native. Plan: try start from the shell-uid server (TetheringManager, untested), else open the phone's tethering screen in the mirror window for one click; badge "USB · Net"; sandbox can't change macOS service order → one-time guide. Integration points: `SessionController.startSession` pre-session hook, `AdbCommand` + `adb.rs check_shell`, new interface enumerator in `NetworkIdentity`.
- **Next:** user unzips, runs `bash scripts/build-mac.sh --install`, Settings → Connection → *Reinstall Over USB…* with the phone plugged in, then `REAL_DEVICE_CHECKS.md` A–F.
- Superseded: **Next:** user copies the new `carbonmirror-server` into `~/CarbonMirror/Resources/`, runs `git pull && bash scripts/build-mac.sh --install`, checks typing (Hardware keyboard; *Phone keyboard* mode injects Mac characters exactly), the crash notice, the quality word, then `REAL_DEVICE_CHECKS.md` A–F.

## 0a. Session 4 (2026-11-12 → 13) — read this first

### Latest (end of session 4)
- **v1.0.1 is not published.** Since 13:00 on 2026-11-12 GitHub starts **no macOS jobs** for this account (runs 8–11: the `mac` job stays queued and is cancelled after ~15 min, no log; `macos-26` and `macos-15` both). Linux jobs keep working. The user reports ~$4 credit left; suspected cause is an Actions budget/stop-usage setting or a missing payment method (github.com/settings/billing → Budgets, Payment information); unconfirmed.
- **Delivered instead:** `CarbonMirror-1.0.1-source.zip` (SHA-256 `9e84af7287f2d55fd3e35befd93689fc4133b8b506ed58e9a9ef6236c42638e1`, 3.0 MB) sent in chat: `git archive` of `ee0aabc` + the 1.0.1 phone parts from run 11's `phone` artifact (artifact digest `ebf0ae1f48ece01b257a480b47d8ca63ae09a7c676bb943f8af11317f06d78c3`, APK versionName 1.0.1, one-time key) + `Resources/phone-parts.version`. User builds offline on the Mac: `cd ~/CarbonMirror-1.0.1 && bash scripts/build-mac.sh --install` (signs with the user's existing **"CarbonMirror Dev"** certificate), then uninstalls the old companion on the phone and reinstalls it over USB (different APK key).
- **Release workflow** now has a `runner` input (`macos-15` default, selects Xcode 26 when present; `macos-26` optional) and release notes explaining how to open the self-signed DMG. No Developer ID (user has none; self-signed by choice).
- **Commit signing:** commits from `ee0aabc` on are SSH-signed (ed25519 `SHA256:X7rbPC4zCFhUw4lJwuixs0u2dCjlO4zYFTbvV6GlJPM`, key only in that cloud container). The user was asked to add the public key at github.com/settings/ssh/new as a **Signing Key**; older commits stay Unverified (no history rewrite on `main`).
- **INSTALL 4b** "Updating to a new version" (DMG or one-command source build, companion reinstall, keychain/re-pair notes). `build-mac.sh` takes phone parts from (in order) `~/Downloads/phone/Resources` (workflow artifact), the installed app, `~/Downloads/CarbonMirror-<version>.dmg`, or the GitHub release of that version; parts of another version are replaced (`Resources/phone-parts.version`).

### State in one paragraph
**v1.0.0 is published** (`680ab05`, https://github.com/ButcheCassidy/CarbonMirror/releases/tag/v1.0.0). `main` is ahead with the **1.0.1** work (version 1.0.1 in `Resources/Info.plist`, CHANGELOG `[1.0.1]`): the real-phone session deadlock fix, the Android 17 clean-up crash fix, the toolbar "Shortcuts" settings, the PolyForm Shield licence and build/doc fixes. Release run 9 (publish) was triggered for `f175e97`; its macOS job sat **queued** waiting for a `macos-26` runner (run 8 did the same and was cancelled for the licence change). If v1.0.1 is not on the releases page, re-run **Actions → Release → Run workflow (publish = true)**. The user built the app on their own Mac (M4 Pro) with `scripts/build-mac.sh`, installed it, and saw the phone server start ("Mirroring") but no picture on the Mac → root cause found and fixed in 1.0.1 (finding 36), **not yet re-tested by the user**.

### User rules added in session 4 (keep obeying, together with §3 and CLAUDE.md)
- Token-minimal: code, tests, fixes; no narration; replies only at milestones; task list kept for the user.
- Swift 6 / Rust strict, zero warnings; `unsafe` only in `ffi`; no TODO/stubs; every line has a purpose.
- Keep finished code; change it only for a requested feature, a bug, or a vulnerability (list it).
- Commit and push to `main` after each step, as ButcheCassidy, **no** AI attribution in commits/PRs/docs.
- Sub-agents: only when the user asks; Haiku preferred; audit every result yourself.
- macOS CI: manual, batched, ≤ 100 macOS runner-minutes in total (≈ 20 before session 4).
- Fix vulnerabilities of any severity as long as no feature breaks; bug-sweep what changed; then publish.

### User decisions (session 4)
| Topic | Decision |
|---|---|
| USB inner TLS | **Off by default**, Settings → Security → *Encrypt over USB too* |
| Auto-connect | Mac checkbox *Auto-connect to my phone at launch* (default on); mDNS + pinned-key checks; locked endpoint; one **Mirror** button |
| Companion | Foreground service + boot receiver + watchdog alarm allowed (deviates from spec 9.2/9.3); battery **Unrestricted** documented |
| Trusted Wi-Fi | **Subnet hash, no Location permission** |
| CI cap | 100 macOS runner-minutes total |
| DMG signing | Ephemeral self-signed "CarbonMirror Dev" in CI; Developer ID + notarisation automatically when its secrets exist |
| APK signing | `release` environment secrets — found **empty** → one-time P-384 key per run (warning in the log) |
| Version / publish | 1.0.0, published release; now 1.0.1 |
| Repo | Cleaned to the minimum (template workflows, Dependabot, `docs/RELEASING.md` removed; Dependabot PRs #2–#6 closed); branch `claude/release-workflows` merged into `main` **history only** (`f7ad105`, `-s ours`), branch kept |
| Toolbar | **No app keyboard shortcuts** for phone actions; Settings → **Shortcuts** chooses toolbar buttons; default **Home** only (+ connection badge + Settings, fixed) |
| Licence | **PolyForm Shield 1.0.0** (was Noncommercial); SPDX + Required Notice in every CarbonMirror source file; forked scrcpy files stay Apache-2.0 |
| Window | Standard 12 pt corners while the toolbar shows; phone shape at rest |

### Assumptions logged
- "Don't modify previously written code" = additive changes; existing lines changed only where a requested feature, bug or vulnerability needs it.
- With auto-connect on, the Mac does not turn Wireless debugging off after Disconnect/idle (the companion owns it per trusted Wi-Fi).
- Standard macOS menu keys (⌘Q ⌘H ⌘M ⌘W ⌘, and Edit ⌘C/⌘V/⌘X/⌘A) are kept; all phone-action shortcuts are gone.

### Session 4 log (commits, oldest first)
`95c5617` USB TLS off + auto-connect state machine + UI states Ready/Not connected · `abcfff7` auto-connect wired in (Settings, Ready/Mirror, Not connected/Connect) · `4f27d7e` companion `ReadyService`/`StartReceiver`/`TrustedNetworks` + `scripts/test-companion.sh` · `a491df2` uninstall note · `86fecdd` Android 11 app-drawer swipe + "Can't start safely" state · `3e1fcb3` auto-connect hardening, companion watches Wi-Fi (not the VPN) · `aa5c217` repo cleanup + Release workflow + 1.0.0 · `2cdcd61` companion one try per network; findings 25–30; checks F1–F8 · `cf257bb` one-time APK key fallback · `de3f213` receiver crash fix · `f73edf2`/`00e2f3d`/`c942e62` docs, `build.sh` `codesign -dvv` fix · `ebadb4d` actions pinned to SHAs, findings 31–33 · `1a60c2a` evidence table · `81ccd65` **PQ-only key exchange** · `680ab05` companion trusts only wireless sessions → **v1.0.0 published** · `f4d2369` checksums · `f7ad105` branch merge · `78c2b00`/`1ef47cc` build docs (Step 0, Android tools, licences) · `d2cafe5` `scripts/build-mac.sh` · `bde6522` Developer ID + notarisation · `f61abf0` 12 pt window corners · `e12107d` git clone instructions · `f016c65` build-mac phone parts from app/DMG/GitHub · `d0ebebe` cbindgen quiet · `01c8604` clean-up hard link + companion Pair button · `1514596` **1.0.1 deadlock fix** etc. · `0ac9428` PolyForm Shield · `f175e97` toolbar Shortcuts.

### GitHub state
- Releases: **v1.0.0** (DMG `a7b988b952cd68809fd9593fc4c1fb99d8b0d352a2c8b2b37f7a327639ffdd72`, APK `7cd9377c798e1270de853e195d4e64b7d0f4be10b3050b78dd8f301beefc9627`, source zip `d117b63bb03889afe7740e16c4fa12f5e1eab2919d0c2eeba095f15e48716955`, SHA256SUMS.txt). v1.0.1: see release run 9.
- Workflows: `ci.yml` (gitleaks on push), `release.yml` (manual; inputs `publish`, `runner`; jobs `phone` → `mac` → `publish`; actions pinned by commit SHA; jobs use environment `release`). Release runs: 1 failed (APK secrets empty), 2 failed (adb check `-dv`), 3 ✓ verify, 4 cancelled (security review first), 5 cancelled (extra fix), 6 ✓ **published v1.0.0**, 7 ✓ verify (Developer ID fallback path), 8 cancelled (licence), 9 + retry: mac never started (auto-cancelled), 10: mac never started (cancelled), 11 (`macos-15`): mac never started. Phone job ✓ in every run; run 11's `phone` artifact = the 1.0.1 phone parts. The Deployments page lists each run's `release` deployments (green = phone job, red = mac job that never got a runner).
- Secrets needed in environment `release` (none set): `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`; for warning-free DMGs `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD` (README "Public releases that open without warnings").
- PRs: Dependabot #2–#6 closed. Branches: `main`, `claude/release-workflows` (kept), Dependabot branches (auto).
- macOS CI minutes: ≈ 12 runner-minutes in session 4 (≈ 32 of 100 in total); none used since run 7.

### Security & bug findings 25–42 (details in RELEASE_CHECK.md)
25 connect after lock mid-probe (M) · 26 refusal over live session (L) · 27 companion read the VPN not Wi-Fi (M) · 28 companion prompt loop (M) · 29 lock-screen notification (L) · 30 stale probe results (M) · 31 actions by tag (M) · 32 `build.sh` adb check always failed (M) · 33 receiver crash (L) · 34 classical X25519 accepted → **PQ-only** (M) · 35 USB session trusted Wi-Fi (L) · **36 session deadlock: Mac read device meta before opening the control socket — no video on a real phone (H)** · **37 clean-up child ClassNotFoundException on Android 17 → private hard link; flag cleared by the server (H)** · **38 unknown screen state pressed POWER (H)** · 39 server errors invisible → `CM-ERROR server …` logged on the Mac (M) · 40 identity warning overwritten (M) · 41 H.265 fallback too narrow (M) · 42 file streams not closed (L). Two Haiku sweep agents (Mac / Android) were audited: one false positive rejected (clean-up child deletes its own link, not the shared jar). Not fixed (Low/by design): wireless TOFU without device key, adb start without retry, decoder/Metal failures only logged, hidden-API `AssertionError`s (now reported to the Mac log).

### Tests (Linux, end of session 4)
`cargo test` 45 (incl. PQ-only), clippy clean (host + Android), `cargo audit` clean · `swift test` **80** (incl. 10 auto-connect, toolbar settings; virtual phone now uses the real server socket order — the old Mac code hangs on it) · soak 300 s (and 60 s after the deadlock fix) · companion 19 · TLS downgrade 8/8 refused · capture "nothing readable" · virtual LAN PASS · adb exposure PASS · fuzz 14 × 120 s PASS. macOS CI (run 3/6/7): build 0 warnings, signatures valid, app alive, screenshots of every status screen and the splash.

### New/changed files (session 4)
`Sources/CMTransport/AutoConnect.swift` · `Tests/CMTests/AutoConnectTests.swift` · companion `ReadyService.java`, `StartReceiver.java`, `TrustedNetworks.java`, `companion/test/CompanionTest.java` · `scripts/test-companion.sh`, `scripts/build-mac.sh` · `.github/workflows/release.yml` (rewritten), `ci.yml` (gitleaks only) · server `CleanUp.privateClassPath`, `Server.reportError`, `Controller.swipeUpForAppDrawer`, `PowerManager` fail-safe · UI states `phoneReady` 12, `notConnected` 13, `launchCheckFailed` 14 · `AppSettings.autoConnect`, `toolbarItems`/`setToolbarItem` · Settings tab **Shortcuts** · `LICENSE` = PolyForm Shield 1.0.0.

### Commit signing
From session 4's end, commits are SSH-signed (ed25519, `SHA256:X7rbPC4zCFhUw4lJwuixs0u2dCjlO4zYFTbvV6GlJPM`). The private key exists only in that cloud session's container (`~/.ssh/carbonmirror_signing`), so a new session needs a new key: `ssh-keygen -t ed25519 -f ~/.ssh/carbonmirror_signing`, `git config gpg.format ssh`, `git config user.signingkey ~/.ssh/carbonmirror_signing.pub`, `git config commit.gpgsign true`, and the public key added at github.com/settings/ssh/new as a **Signing Key**. Remove old keys there when a session ends. Earlier commits stay Unverified (history is never rewritten on `main`).

### NOT RUN (needs the user's Mac + phone)
Everything in `REAL_DEVICE_CHECKS.md` A–F; the 1.0.1 deadlock fix on the real Pixel (Android 17, CP3A); companion service on device (battery, reboot, OS update, per-network prompt); Android 11 swipe; Developer ID/notarisation path; performance targets.

### Next steps
1. (superseded by *Latest* above) v1.0.1 is **not published yet**: run 9's macOS job never got a GitHub `macos-26` runner (queued, auto-cancelled after 15 min, re-run queued again; no logs, so likely runner capacity or the account's macOS minutes/billing — check github.com/settings/billing). Re-run **Actions → Release → Run workflow (publish = true)** later.
2. Until then the user builds 1.0.1 locally: download run 9's **phone** artifact (Actions → Release → run 9 → Artifacts → phone), unpack it in Downloads (`~/Downloads/phone/Resources/…`), then `cd ~/CarbonMirror && git pull && bash scripts/build-mac.sh --install` (the script now replaces phone parts of another version via `Resources/phone-parts.version`); reinstall the companion (Settings → Connection → Install over USB…); mirror over USB; if no picture, send `log show --last 15m --predicate 'subsystem == "com.nomadicrebel.carbonmirror"' | tail -40` (now includes the phone server's stop reason).
3. Run `REAL_DEVICE_CHECKS.md` A–F; record results in RELEASE_CHECK.md.
4. Add the `release` secrets (APK keystore; Developer ID + notarisation) before a public release.
5. Later: ML-DSA signatures when rcgen/webpki/Keychain support them.

## 0. Where things stand (end of session 3, 2026-11-12)

**Stopped by the user (usage limit). Nothing is mid-edit; `main` is clean and pushed (last code commit `7cbfccb`).**

### Done and proven (evidence in `RELEASE_CHECK.md`)
- Mac app: `swift build -c release` on macOS 26 (GitHub runner, Xcode 26.6) — 0 errors, 0 warnings. Launches in `--demo` and in the normal path, survives opening Settings, Metal shader compiles. Screenshots checked: splash, all status screens, hover toolbar + overflow, Settings (Connection tab).
- Linux: `cargo test` 44 passed, clippy clean (host + Android), `cargo audit` clean, `swift test` 70 passed, server jar + `libcarbon_core.so` + companion APK build (test key).
- Security re-run: TLS downgrade 8/8, capture scan clean, virtual LAN PASS, soak 300 s, fuzz 14 entry points × 120 s, `adb_local_exposure.sh` PASS. Findings 18–24 fixed (adb emulator scan + adb mDNS off; device key proof for wireless; pairing IP binding; phone-side deadlines; Settings crash; no-display launch crash; 13 UI bugs).
- Startup animation on both apps; companion launcher screen; docs (README, INSTALL, SECURITY_NOTES, CHANGELOG, REAL_DEVICE_CHECKS, RELEASE_CHECK).

### Half done (code written, not proven on real hardware or not fully checked)
1. **Companion launcher screen + Android splash** — builds and verifies; never run on a phone (no emulator here). Check `REAL_DEVICE_CHECKS.md` D-S.
2. **Device key proof** — Swift/Rust side tested against the virtual phone; the Java side (`SessionSetup.java`: key file, HMAC, 5-field setup line) and the phone-side deadlines have never run on a device. Check D-K.
3. **Settings window** — only the Connection tab was seen on screen; Display, Experience, Security, Screenshots, General, About are unverified visually. Glass look verified only over a black desktop.
4. **Mirroring UI with a live session** — status line, connection badge, landscape pill, blur, HUD: compiled, never seen with real video.
5. **Signing and packaging** — `scripts/make-cert.sh` and `scripts/build.sh` have never run on a Mac; no DMG exists; sandbox + entitlements + bundled adb signature check untested.
6. **Launch-check failure message** — when adb is missing or its signature is rejected the window says "Disconnected / Connection lost" (seen on CI with the unsigned test bundle). Works, but the wording is misleading; give it its own state.
7. **INSTALL.md §7 (uninstall)** does not yet mention deleting `/data/local/tmp/carbonmirror-device.key` on the phone.
8. **`swift test` on macOS** — never run (tests use Glibc-only sockets); Mac coverage is build + launch + screenshots only.
9. **CI** — the `macos` job contains screenshot/liveness scaffolding (fine to keep, manual only). Dependabot PR #6 (upload-artifact bump) is obsolete: close it.

### Not started / still open
- All of `REAL_DEVICE_CHECKS.md` (A–E, plus A-S, D-S, D-K) on the user's Mac and Pixel; performance targets (10.1) unmeasured.
- Older open issues: horizontal scroll sign unverified; `ALL_APPS` swipe-up fallback not implemented (spec 5.4); `network.server` entitlement possibly removable; no `tc netem` (no loss/latency simulation); landscape pill width at smallest size.
- Open security limits (documented, need the user's decision to go further): wireless trust-on-first-use for a phone never connected by USB; USB identity = serial; phone → Mac clipboard injection by design.
- Release gate: version bump, CHANGELOG date, signed DMG + APK with the user's keys, SHA-256 checksums, evidence table, INSTALL final pass.

### Next action
User runs on the Mac, from the repo folder: `bash scripts/make-cert.sh` → Step A-2 (adb) → `bash scripts/build-server.sh` → `bash scripts/build-apk.sh` → `bash scripts/build.sh`, and sends the tail of `build.log`. Then `REAL_DEVICE_CHECKS.md`. Details in §12.

## 1. Header

| Item | Value |
|---|---|
| Project | CarbonMirror — native macOS ⇄ Google Pixel 10 Pro XL mirroring & control (any Android 11+ phone; GrapheneOS-compatible) |
| Version | 0.1.0 (`CFBundleShortVersionString`; server `VERSION_NAME` and APK versionName/versionCode 100 derive from it) |
| Milestone | Past Milestone 2 (user waived milestone stops). Phase 11 release check: Linux stages 1–4 done; release gate open |
| Date | 2026-11-12 |
| Author credit | **ButcheCassidy - The Nomadic Rebel** |
| Repo / branch | `ButcheCassidy/CarbonMirror`, `main` only (see `git log`; session 3 starts at `7321add`) |
| Phase 1 Base project & packaging | ✅ code + scripts · `swift build -c release` passes on macOS 26 CI (0 warnings) · sign/DMG NOT RUN |
| Phase 2 Window & UI | ✅ compiles; `--demo` screenshots taken on macOS CI; UI audit (12 findings) fixed |
| Phase 3 Infrastructure | ✅ (adb on private Unix sockets since Phase 11) |
| Phase 4 Mirroring pipeline | ✅ code · decoder/renderer uncompiled |
| Phase 5 Input & control | ✅ Linux-tested engine · AppKit glue uncompiled |
| Phase 6 Wireless & Mullvad | ✅ code · virtual LAN tests pass · real Wi-Fi NOT RUN |
| Phase 7 Security | ✅ code + Linux attack tests · Keychain/QR NOT RUN |
| Phase 8 Settings, menu bar, icon, extras | ✅ code · uncompiled |
| Phase 9 Companion APK | ✅ builds + verifies on Linux (test key) · device NOT RUN |
| Phase 10 Docs & delivery | ✅ docs · DMG NOT RUN · performance targets unmeasured |
| Phase 11 Release check | 🟡 Stages 1–4 on Linux ✅ re-run in session 3 (23 findings, all High/Medium fixed) · release gate ⬜ |
| Startup animation | ✅ both apps (session 3) |

**One-line state:** every spec feature has code; all Linux tests and attack harnesses pass; the Mac app **compiles with zero warnings and launches (`--demo`) on a macOS 26 GitHub runner**; nothing has run on the user's Mac or the Pixel yet (signing, sandbox, adb, Keychain, Metal with a real phone).

## 2. Session log (everything that happened, in order)

**Session 1 (2026-11-11)**
1. Linux env: `scripts/setup-env.sh` (swiftly hit HTTP 403 → Swift 6.4.2 from the swift.org tarball). Commits `e876933`…`c33b7fa`.
2. Milestone 1 partial: Rust core (policies, adb parser, crypto, C ABI v1), Swift bridge, adb transport, shared vectors.
3. Phase 1 `46964c3` (Info.plist, entitlements, icon PNG, build.sh, make-cert.sh) · Phase 2 `c05fff1` (window, status screens, hover chrome + overflow, sizing, menu bar, `--demo`) · Phase 3 `4b6ebd1` (forked scrcpy 5.0 server, `build-server.sh`, phone core lib).
4. `6f772e9` C ABI 16 MiB buffer cap (lengths up to `isize::MAX` reached `from_raw_parts` = UB).
5. `f111449` Rust: scrcpy framing, control encoding, input/key mapping, adb probe, pairing/trust, TLS 1.3 (rustls) + JNI, ABI 2 · `e77ff87` server stdin setup, inner TLS via JNI, session secret, battery/ping, text-only clipboard · `b3615a7` transport, SecureStream, MirrorSession, virtual phone · `57149ba` input engine · `bab88c6` 8.2 policies · `1ec3eac` key manager, wireless probe · `7eb64a8` Annex B + WIP decoder/renderer + full HANDOFF at pause.

**Session 2 (2026-11-12, this one)** — user decisions at start: push to `main` (not the session branch), **inner TLS on USB by default**, **companion icon as vector from the SVG**; all commits in the user's name; lean code; one-line progress notes.
6. `ecf733d` reviewed + fixed the uncompiled media files (CVMetalTexture lifetime, decoder block-buffer lifetime, `enqueue` actor isolation, letterbox, BT.601, dim) · USB TLS default on · SVG added.
7. `6190096` SessionController (whole session lifecycle), MirrorView, PairingController (QR + 6-digit + IP/port prompt), Settings window (Liquid Glass), menu bar, NetworkIdentity, Bonjour (dns_sd), OwnerCheck.
8. `bfbc43c` Phase 9 companion APK + `build-apk.sh`; server publishes `carbonmirror_session` for the tile's "Mirroring" state.
9. `e015871` children inherit `SIG_IGN` for SIGTERM → stop hung up to 60 s; fixed (TERM → KILL).
10. `f8bd9dc` docs + LICENSE · `2339dfc` OpenSSL downgrade harness, RUSTSEC-2026-0009 fix · `a7e5e9e` capture/entropy scan · `019f354` INSTALL.md · `0262b8d` HANDOFF.
11. **User ran `scripts/build.sh` on the Mac:** it failed before compiling — `dirname: illegal option -- z` and `Print: Entry, ":CFBundleShortVersionString", Does Not Exist` (script started with `$0 = -zsh`, so it `cd`'d to `/`). Fixed `502ad5e`.
12. Phase 11 with self-attack (user: "try and hack your own app… I want it to be pretty private"):
    - `ac0287d` **High:** adb server reachable on localhost TCP without authentication → moved adb server + forwards to private Unix sockets.
    - `63b04b2` clipboard privacy (password managers, Android sensitive clips), forged unlock notification, `adb pair` guid check.
    - `e9c5648` TLS replay/tamper tests · `d338ff9` virtual LAN (netns) + hypothesis C-ABI fuzzing.
    - `a690723` **High (found by the soak):** inner TLS died on > 16 KiB plaintext bursts → fixed; soak test added.
    - `6f895ef` no Resume snapshots, no Universal Clipboard, non-synchronizable Keychain items, adb keys out of backups.
    - `f66e3d3` RELEASE_CHECK.md, docs, edge test; then this HANDOFF.

**Session 3 (2026-11-12)** — user answers: animation = **slide & settle**; Android gets a **minimal launcher Activity**; Mac splash **fits inside the phone window**; **macOS CI allowed**, budget ≤ 100 runner-minutes total (used ≈ 20 over 13 runs; billed ×10 against the included quota on a private repo), job is manual-only.
13. `7321add`…`d6c33b7` macOS job in CI (`macos-26`, Xcode 26.6); first Mac compile: 8 errors fixed (`Theme`/`EndpointPrompt.Fields` isolation, slider value, deprecated `String(cString:)`); job made manual (`workflow_dispatch`) after the user's budget note.
14. `1a59ac5` startup animation: `tools/startup/render_carbonmirror.py` (user's script + multiprocessing; both variants 2 min 24 s), `Resources/CarbonMirror-startup.mp4`, `SplashView`. `8895797` companion launcher screen.
15. Security re-run (all harnesses pass) + self-attack: `9de3a7c` finding 18 (adb emulator scan / adb mDNS), `621c3b2` finding 19 (device key proof), 20, 21.
16. `416b035` UI audit by one sub-agent (12 findings) + sweep, all fixed; from the CI screenshots: window-size floor, centred pills (`46aa4d0`), **Settings crash** (`a5e2676`), Settings rows top-aligned (`8c0e0a7`). Final CI run: build 0 warnings, `APP ALIVE after Settings`.
17. Whole-app sweep (no sub-agent): pattern scan clean (no `try!`, no force unwraps on untrusted data, no exclusive-access closures left); fixed launch trap with no display attached (`cf02cca`, `7cbfccb`). CI now also checks the real launch path and the Metal shader: `APP ALIVE after real launch`, `METAL exit 0`.

## 3. User rules (mandatory — keep obeying)
- **Token economy:** one-line progress notes, shortest possible replies, no long tool output.
- **macOS CI minutes:** job `macos` in `ci.yml` runs only via Actions → CI → Run workflow (or the `run_workflow` API); never on push; batch fixes; hard cap 100 runner-minutes in total.
- **USB must stay plug-and-play:** no extra tools or steps for wired mirroring.
- Sub-agents only when the user asks (session 3: one small UI-audit agent, done).
- Work and push **directly on `main`**. No branches, no PRs (the cloud harness proposes a branch; the user overrode it twice). Before any commit: `git config user.name "ButcheCassidy"` and `git config user.email "354005634+ButcheCassidy@users.noreply.github.com"`. **No** `Co-Authored-By`, "Generated with Claude", session IDs or links in commits, code, docs or comments. Everything committed in the user's name.
- Responses: structured, concise, **no conversational filler**; while working, one-line notes of what is being done.
- No sub-agents unless asked. No research tangents.
- **Every line of code has a purpose — no bloat.**
- Build everything; bug hunts in Phase 11 (now running); fix earlier only when strictly necessary.
- Do not stop at milestones. Write the full-spec HANDOFF at the end or when asked, and also paste it in chat when asked.
- UI rule: test the UI at every stage; every element exactly where the spec puts it; no overflow/clipping at any size 0.75×–max; toolbar collapses into an overflow (…) menu when narrow.
- Liquid Glass (`NSGlassEffectView` macOS 26+; `NSVisualEffectView` .hudWindow on 15–25) **only** for Settings and not-connected status screens; mirroring UI fully opaque.
- README GitHub-friendly, natural feature explanations.
- Icon: Mac `.icns` from `Resources/CarbonMirror-icon-1024.png` (sha256 `0252738b…01cf03`); companion adaptive icon = VectorDrawable converted from `Resources/CarbonMirror-icon.svg` (sha256 `3a223258…5bbb83e`; gradients kept, SVG blur shadows dropped).
- Licence: **PolyForm Shield 1.0.0** (`LICENSE`, required notice "Copyright 2026 ButcheCassidy - The Nomadic Rebel").
- Device scope: Pixel 10 Pro XL defaults, spec fallbacks kept; other Android 11+ phones work. **Must be GrapheneOS-compatible.**
- **Encryption & privacy first:** everything the spec says deserves encryption is encrypted; inner TLS on for USB too (owner decision); no plaintext transport on LAN; privacy-preserving defaults everywhere.
- Next phase of work (user): after the Mac build, the user attaches the full prompt again and we go requirement by requirement adding all detail.

## 4. Security architecture (what protects what)
- **Transport:** wireless = Android Wireless debugging (adb TLS) **plus** inner TLS 1.3 from the Rust core on both ends; USB = inner TLS too (default on). Plain `adb tcpip` detected and refused. Suites `TLS_AES_256_GCM_SHA384` → `TLS_CHACHA20_POLY1305_SHA256` only; groups `X25519MLKEM768` → `X25519`; rustls built without TLS 1.2 code; mutual auth, pinning-only verifiers; ALPN `carbonmirror/1`; no resumption, no 0-RTT; KeyUpdate 15 min / 4 GiB; 10 s handshake timeout; any alert/decrypt error ends the session; decrypted data in a bounded buffer zeroed on drop.
- **Identity:** Mac = non-extractable ECDSA P-384 in the login Keychain, signs a self-made CA once (via Swift callback; key never in Rust/app memory); fresh Ed25519 session certs on both sides; phone pins the Mac CA (TOFU file 0600); Mac pins the phone's adb TLS key (SHA-256 of SPKI) + serial after QR pairing.
- **Local exposure:** **no TCP or UDP listener on the Mac.** adb server (`ADB_SERVER_SOCKET=localfilesystem:…/cm/cm-adb`) and every forward (`localfilesystem:…/cm/cm-f<16 hex>`) are Unix sockets in a 0700 folder in the sandbox container; plus a 256-bit session secret on every session socket (constant-time check on the phone).
- **adb wrapper:** fixed command templates only, Rust allowlist (private IPs, no `tcp:` forwards, strict server options, install only over USB after confirmation); no user strings in shell commands.
- **Binaries:** adb helper code signature checked at launch against the app's own leaf cert (refuse to start adb on mismatch); server jar + core lib SHA-256 sealed in the signed Info.plist, verified, staged 0600, then pushed.
- **Segregation (A7):** sandbox with minimal entitlements; only video + allowlisted device messages parsed (Rust, bounds-checked, fuzzed); clipboard plain text ≤ 1 MiB both ways, toggle, never logged; screenshots only to `~/Pictures/CarbonMirror/`; no files/audio/shell/recording.
- **Privacy:** password-manager clipboard items never sent; Android sensitive clips never read; phone text `currentHostOnly` (no Universal Clipboard); no Resume snapshots; Keychain items non-synchronizable; adb keys excluded from backups; SSID never read (needs Location) — network identity = hashed subnet; logs metadata only, no log files.
- **Session hygiene:** ends on lock (verified with the window server), sleep, user switch, network change, idle (10 min default); blur on display sleep/screensaver; Wireless debugging turned off after final ends; reconnect only to the pinned phone, never while locked/asleep.
- **Phone side:** server runs as `shell` via `app_process` (GrapheneOS app restrictions don't apply), core lib deleted after `System.load`, jar unlinks itself, no key files, strict option allowlist, audio/camera/files removed.

- **Device key (session 3):** adb never authenticates the phone to the Mac. USB sessions deliver a random 256-bit key (Mac Keychain item `CarbonMirror device key` = key ‖ serial; phone `/data/local/tmp/carbonmirror-device.key`, shell-only). Wireless: the phone must print `CM-PIN <pin> <HMAC-SHA-256(key, pin)>`; missing/wrong proof → `SessionEnd.deviceNotProven` → "Untrusted device" before any socket opens. Never sent over Wi-Fi. A phone never connected by USB stays TOFU.
- **adb environment:** `ADB_EMU=0` (no localhost emulator scan), `ADB_MDNS=0` (no adb-side mDNS/auto-connect).

## 5. Environment (Linux build box)
- **macOS CI:** trigger `ci.yml` by hand; artifact `mac-build-log` = `build.log` + `shots/*.jpg` (demo screenshots, 1024×768 runner display). Download via the artifact URL, never paste the log (hundreds of lines).
- `source ~/carbonmirror-deps/env.sh` sets `JAVA_HOME` (OpenJDK 21), `ANDROID_HOME=/root/carbonmirror-deps/android-sdk`, `ANDROID_NDK_HOME=…/ndk/30.0.16248370`, `CM_TEST_VIDEO_DIR`, PATH (Swift 6.4.2, build-tools 36.0.0, platform-tools, cargo). Unset `JAVA_TOOL_OPTIONS` to silence proxy noise from Java tools.
- Versions: Swift 6.4.2, Rust 1.97.0 (crate MSRV 1.88), cargo-ndk 4.1.2, cbindgen 0.29.4, cargo-audit 0.23.0, NDK 30.0.16248370, platform android-36, build-tools 36.0.0, platform-tools 37.0.1, scrcpy v5.0 (`19871982cefb9de4c981c2314dfda2ac81564b48`), Python 3.13 venv (hypothesis 6.170.15, dpkt, cryptography), ffmpeg 6.1.1, OpenSSL 3.0.13. netns **yes** (as root), `tc netem` **no**, `dummy` kernel module **no** (use veth).
- Test streams `~/carbonmirror-deps/test-video/pixel10proxl-{60fps,120fps}.h264`, `…60fps.h265`.
- Fresh container: `scripts/setup-env.sh` (sequential, cached, sha-recorded in `~/carbonmirror-deps/deps.lock`).
- Gotchas: SwiftPM doesn't relink after Rust changes → `touch Sources/CMCoreBridge/*.swift`. `swift test` output buffers when redirected → `--filter` + `timeout`. Run scripts as `bash scripts/x.sh`.

## 6. Decisions and deviations from the spec (with reasons)
1. Layout per spec (root `Package.swift`, `rust/`, `Resources/`, `scripts/`, `server/`, `companion/`, `tools/`), not CLAUDE.md's `android/`/`macos/`; the template CI/release workflows (`.github/`, `docs/RELEASING.md`) expect that layout and stay skipped/unused.
2. Cargo workspace `rust/`; outputs `rust/target/…`.
3. `CarbonCoreC` = `.systemLibrary(path: "rust/include")`.
4. Static archive linked by full path (with `-l` the linker picks the cdylib).
5. **adb server + forwards on Unix sockets** (replaces the old random 127.0.0.1 port): socket folder = sandbox `tmp/cm` (0700), path ≤ 103 bytes or launch fails closed; stale cleanup = if `cm-adb` exists → `kill-server` + remove. Rust allowlist accepts only `localfilesystem:<abs path>/cm-f<16 hex>` forwards.
6. Helper adb signature: `identifier "adb" and certificate leaf = H"<SHA-1 of the app's own leaf cert>"`, checked in `SessionController.launch()`.
7. Pushed artifacts hash-verified, staged 0600, staged copy pushed; hashes in Info.plist `CMServerSHA256`/`CMCoreLibSHA256` (written by `build.sh`, sealed by codesign).
8. IP policy also refuses Mullvad `10.64.0.0/10`, `fc00:bbbb:bbbb:bb01::/64`, IPv4-mapped IPv6, link-local without zone, hostnames, port 5555.
9. Extra UI states: `IdentityChanged`, `InsecureConnectionRefused`, `RetryingSilently`.
10. C ABI buffer cap 16 MiB.
11. rustls buffered API (no in-place decrypt in 0.23); plaintext copied once.
12. Pin = SHA-256 of SubjectPublicKeyInfo.
13. Identity design: Keychain P-384 (tag `com.nomadicrebel.carbonmirror.identity`, label `CarbonMirror identity`) → CA `CN=CarbonMirror Mac identity` → per-session Ed25519 `CN=CarbonMirror Mac session` (now−1 h…+24 h); phone per-start Ed25519 `CN=CarbonMirror phone session`; `WebPkiClientVerifier` mandatory client auth.
14. Phone pins Mac CA TOFU in `/data/local/tmp/carbonmirror-mac.pin`; mismatch → `CM-ERROR identity-changed`; after Create new key the Mac runs `rm -f` on it before the first session (`macPinResetPending`).
15. Session setup over adb shell stdin: `CM1 <plain|tls> <secret 64 hex> <mac-ca base64 | ->`; `CM-PIN <64 hex>` on stdout.
16. Session secret 32 bytes, first on each socket (after TLS), `MessageDigest.isEqual`.
17. Connect retry 60 × 100 ms on `StreamError.closed` (adb forward accepts before the server listens); TLS/pin errors not retried.
18. Wireless: adb makes the phone↔Mac TCP connection; CarbonMirror's own pre-connect probe (Network.framework, `.wifi`/`.wiredEthernet`, prohibits `.other`/`.cellular`) checks route (`utun` → LAN sharing blocked), refuses plaintext and captures the phone's adb TLS key.
19. QR flow: the phone advertises `_adb-tls-pairing._tcp`; the Mac browses (NWBrowser) and resolves without connecting (dns_sd), then `adb pair`.
20. Server fork: audio, camera, virtual/new display, `list_*`, media scan, torch/zoom, resize, reverse tunnel removed; strict `Options` allowlist.
21. Device messages `0x40` battery, `0x41` pong; control `0x41` ping every 2 s.
22. Clipboard: 1 MiB both ways, `text/plain|html` only, **sensitive clips skipped** (Android 13+), UTF-8/no NUL check in Rust; phone→Mac dropped when sync off; Mac concealed/transient items skipped; `currentHostOnly`.
23. ⌘ → Ctrl to the phone; non-app ⌘ combos via `performKeyEquivalent` + immediate key-up; `AppShortcuts` list.
24. Pointer ids −2/−3; pinch 400 px; scroll ÷24 pt clamp ±16; horizontal sign unverified.
25. App drawer `KEYCODE_ALL_APPS` (284); swipe-up fallback not implemented.
26. Linux test signer = `/usr/bin/openssl` P-384.
27. Keychain generic passwords (service `com.nomadicrebel.carbonmirror`, accounts `CarbonMirror identity certificate`, `… adb key fingerprint`, `… paired device`), `kSecAttrSynchronizable false`. Data-protection keychain / Secure Enclave need a Team ID (future).
28. Logging `os.Logger` subsystem `com.nomadicrebel.carbonmirror`, metadata only, no log files.
29. Network identity = SHA-256 of `subnet:<a.b.c.d/n>` of the Wi-Fi interface (SSID needs Location permission); subnet change ends a wireless session.
30. USB without pairing allowed while nothing is paired; once paired, other serials → Untrusted device.
31. Companion "Mirroring" = Global setting `carbonmirror_session` written by server `CleanUp` (verified in AOSP: unknown Global keys aren't `@Readable`-gated; `adb_wifi_enabled` is `@Readable`). 1-bit leak documented.
32. Children inherit `SIG_IGN` (SIGTERM) → `ChildProcesses.stop`: TERM, 0.5 s, KILL.
33. Wireless debugging turned off after final ends only (Disconnect, quit, idle); lock/sleep keep it for silent reconnect.
34. Display sleep/screensaver → blur; sleep/lock/user switch/network change/idle → end. Lid close = system sleep. Unlock notification trusted only if `CGSessionCopyCurrentDictionary` agrees; lock state read at launch.
35. Adaptive USB: only seconds with ≥ 30 fps judged; `requestedMaxSize` decides if a frame is native size.
36. Wireless H.265 fails before first connect → retry H.264.
37. Companion: no launcher activity; fallback `ACTION_APPLICATION_DEVELOPMENT_SETTINGS` (PendingIntent on API 34+).
38. `adb pair` guid `[guid=adb-<serial>-<suffix>]` → serial + connect-service name; only `[A-Za-z0-9._-]`, ≤ 128.
39. Inner TLS keeps decrypted data in its own buffer (`PLAIN_LIMIT` 16 MiB, zeroed) — rustls caps unread plaintext at 16 KiB.
40. Windows `isRestorable = false`; adb folders `isExcludedFromBackup`.
41. Scripts find the repo via `BASH_SOURCE`/git; run as `bash scripts/…`.
42. Rust crate licence `PolyForm-Shield-1.0.0`; MSRV 1.88 (`time` 0.3.55).
43. `network.server` entitlement kept until the Mac confirms adb's Unix socket works without it (REAL_DEVICE_CHECKS 6c).
44. Test-only code stays in `Tests/` (TCP loopback connect for the fake adbd, `TapStream`, soak, LAN test) — production has no test hooks.
45. Virtual LAN must be outside `10.64.0.0/10` (Mullvad range, refused by design) → `192.168.77.0/24`.

46. Setup line is now `CM1 <plain|tls> <secret> <mac-ca | -> <device-key hex | ->` (5 fields); pin line `CM-PIN <pin hex> [<proof hex>]`. Device key provisioned on every USB session, stored on the Mac only after that session reaches `.connected`.
47. Pairing: the `_adb-tls-connect` answer is used only if its IP equals the IP that completed `adb pair`; otherwise the IP/port prompt.
48. Companion has a launcher Activity (user decision; deviates from spec 9.1/9.2 "tile only / no other exported component"): `MainActivity` exported for LAUNCHER only, ignores its Intent, no new permission. `WirelessDebugging` holds the logic shared with the tile.
49. Startup clip: slide & settle, 1024×1024, 120 fps, 3.0 s, H.264 High, ≈ 236 KB, committed (`Resources/CarbonMirror-startup.mp4`); Mac shows it at min(512 pt, window) on black for 3.0 s then fades 0.25 s; Android at min(512 dp, 1024 px, window). Hover chrome is suppressed while it plays.
50. Points per inch clamped to 96–254 (TVs/virtual displays report unusable sizes).
51. Mac controls use the Graphite accent (`AppleAccentColor = -1` in the app's own defaults) — no asset catalog needed.
52. `.cargo/config.toml` sets `MACOSX_DEPLOYMENT_TARGET=15.0` for the Rust core.
53. CI: template `macos` job replaced; `android` template job still skipped (no `android/gradlew`).

## 7. Security log (Phase 11 findings and attack results)

### Findings
| # | Finding | Severity | Fix (commit) | Re-test |
|---|---|---|---|---|
| 1 | adb server reachable on `127.0.0.1:<port>` without authentication by any local user / sandboxed app with network access (could run adb shell/pull on the phone); same for forward ports | **High** | Unix sockets in 0700 sandbox folder; `tcp:` forwards refused (`ac0287d`) | 6 new vectors; 0 TCP/UDP listeners; full port scan none open |
| 2 | Inner TLS failed on > 16 KiB plaintext per socket read (large key frames) → sessions died (Mac + phone) | **High** | bounded, zeroed session buffer (`a690723`) | regression test fails on old code, passes; 5-min soak |
| 3 | Password-manager clipboard items sent to the phone | Medium | skip concealed/transient types (`63b04b2`) | NOT RUN (Mac) |
| 4 | Android sensitive clips sent to the Mac | Medium | `EXTRA_IS_SENSITIVE` skipped (`63b04b2`) | NOT RUN (device) |
| 5 | Phone text synced to other Apple devices (Universal Clipboard) | Medium | `currentHostOnly` (`6f895ef`) | NOT RUN (Mac) |
| 6 | macOS Resume snapshot of the phone window on disk | Medium | `isRestorable = false` (`6f895ef`) | NOT RUN (Mac) |
| 7 | Forged "screen unlocked" notification could trigger reconnect while locked | Medium | verified with window server (`63b04b2`) | NOT RUN (Mac) |
| 8 | adb private key in Time Machine backups | Low | excluded from backup (`6f895ef`) | NOT RUN (Mac) |
| 9 | Phone-controlled `adb pair` guid unchecked | Low | charset/length check (`63b04b2`) | build |
| 10 | Stop/quit hung up to 60 s (SIGTERM ignored by children) | Medium | TERM → KILL (`e015871`) | 60.0 s → 0.56 s |
| 11 | RUSTSEC-2026-0009 `time` 0.3.45 | Medium | 0.3.55 (`2339dfc`) | `cargo audit` exit 0 |
| 12 | Renderer freed textures before GPU use | High | retain until completion (`ecf733d`) | NOT RUN (Mac) |
| 13 | Decoder block buffer reused too early | High | wait for frames (`ecf733d`) | NOT RUN (Mac) |
| 14 | `enqueue` actor isolation (Swift 6 error / race) | High | `FrameSlot` (`ecf733d`) | NOT RUN (Mac) |
| 15 | Landscape frames stretched | Medium | aspect-fit viewport (`ecf733d`) | NOT RUN (Mac) |
| 16 | Event stream not finished on start failure | Low | finish on failure (`6190096`) | suite |
| 17 | Scripts failed when not started from the repo (`dirname: illegal option -- z`) | Low | locate repo (`502ad5e`) | run from `/tmp` |

| 18 | adb server connected in plaintext, without device authentication, to localhost 5555–5585 and ran its own mDNS | **Medium** | `ADB_EMU=0`, `ADB_MDNS=0` (`9de3a7c`) | `adb_local_exposure.sh`: 8 → 0 connections, UDP 2 → 0 |
| 19 | Wireless pin taken from an unauthenticated mDNS answer; a LAN device could be pinned as the phone | **Medium** | device key + proof, pairing IP binding (`621c3b2`) | 2 new tests; impostor refused |
| 20 | Phone: per-read handshake timeout, none for the secret | Low | one 10 s deadline (`621c3b2`) | builds; NOT RUN (device) |
| 21 | Rust C objects built for macOS 26.5, linked for 15.0 | Low | `.cargo/config.toml` (`9de3a7c`) | macOS CI: 0 linker notes |
| 22 | App crashed on opening Settings (exclusive-access trap in `SettingsWindow.show`) | **High** | `a5e2676` | macOS CI: `APP ALIVE after Settings` + screenshot |
| 23 | UI audit + sweep (13 layout/appearance bugs) | Medium | `416b035`, `46aa4d0`, `a5e2676`, Settings top-align | macOS CI screenshots |

Open, documented (SECURITY_NOTES §6): wireless TOFU for a phone never connected by USB; USB identity = serial; phone → Mac clipboard injection by design.

### Attack results (Linux, with evidence in `RELEASE_CHECK.md`)
- **Session 3 re-run:** tls_downgrade 8/8, capture clean, virtual LAN PASS, cargo audit 0, clippy clean (host + Android), soak 300 s (23 sessions, 142 600 events, fds 44 → 48, RSS 36.3 → 49.3 MiB), fuzz 14 entry points × 120 s (220k–276k examples each, incl. `hmac_verify`), `adb_local_exposure.sh` PASS.
- **macOS 26 CI:** window absent from `screencapture` with *Hide from capture* on (default).
- **TLS downgrade/impersonation** (`tools/sectest/tls_downgrade.sh`, OpenSSL 3.0.13): TLS 1.0, 1.1, 1.2 (strong and any suite), TLS 1.3 AES-128-only, P-256-only → refused (`TlsHandshakeFailed`/`TlsPolicyViolation`); TLS 1.3 allowed suite without the pinned Mac cert (with/without ALPN) → `TlsPinMismatch`. 8/8. Success case: suite `0x1302`, group `0x11EC`.
- **Plaintext/leakage** (`capture_session.sh`): encrypted session entropy 7.84–8.00, no device name, clipboard text or H.264 start codes; plain control flagged.
- **Virtual LAN** (`virtual_lan.sh`): plaintext adb (5555 + other port) refused; Mullvad tunnel, public IPv4/IPv6 refused; Mac TCP listeners 0, UDP 0; attacker scan of 65 535 ports → none open; fake `utun9` TX 0.
- **Fuzzing** (`ffi_fuzz.sh 120`): 13 C-ABI entry points × 120 s, 242k–332k examples each, no crash/abort, only documented statuses, memory flat; plus proptest 4096 cases × 5 in `cargo test`.
- **Replay/tamper** (`rust/tests/tls.rs`): replayed whole session, duplicate record, flipped bit → refused/ended.
- **Pairing**: reused/expired codes, unknown phone, wrong pins → refused (`KeyTests`, `SessionTests`).
- **Segregation**: unknown/file message, 2 MiB clipboard, non-UTF-8 clipboard, forged battery → session ended; adb injection strings refused.
- **Soak** (`CM_SOAK_SECONDS=300`): 23 sessions (USB 120 / Wi-Fi 60, TLS), 142 900 events byte-exact in order, 111.4–111.8 / 56.0–56.4 fps delivered, every frame received, key rotated halfway, fds 40 → 44 (plateau 49 while running), RSS 36 → 48.7 MiB (plateau).
- **Static review**: no `try!`/force unwraps on untrusted data, 113 `unsafe` blocks only in `ffi` each with `SAFETY`, logs metadata-only, no unused Java imports, clippy clean, `cargo audit` clean.

## 8. Exact values in use
- Bundle ids `com.nomadicrebel.carbonmirror` / `com.nomadicrebel.carbonmirror.companion`; cert "CarbonMirror Dev" (P-384/SHA-384, 5 y, non-extractable, codesign-only; RSA-4096 fallback).
- Phone paths `/data/local/tmp/carbonmirror-server.jar`, `/data/local/tmp/libcarbon_core.so`, `/data/local/tmp/carbonmirror-mac.pin`; class `com.genymobile.scrcpy.Server`; abstract socket `scrcpy_<scid 8 hex, 31-bit>`; Global setting `carbonmirror_session`.
- Mac sockets: `<container>/Data/tmp/cm/cm-adb` (server), `…/cm-f<16 hex>` (forwards); adb HOME `<container>/Data/Library/Application Support/CarbonMirror/adb/` (0700/0600).
- Artifact SHA-256 (Linux build of `621c3b2`, gitignored): server jar `38b313b98d0c585143e09866b0e2501aa86e5ef5be0fab852a1d4ffc22a70b0b`, `libcarbon_core.so` arm64 `d6984aeb7c837fd6aec377b757ccffcccb3994ca490a6fa68cc8c17e14ec1a01`; startup clip `96523ac717d30103edc47be434a4514dd7dd95b2f8c8bf207a3a69631df30bb3`. Rebuild on the Mac; `build.sh` writes the hashes into the bundle.
- USB profile H.264, 2992, 120 fps, 32 Mbps; adaptive 2992→2560→2240→1920 then 120→90→60 when < 110 fps over 3 s. Wireless "Secure" 60 fps, H.265 (→ H.264), 12 Mbps; 90/120 experimental.
- Size 0.75×–2.0×, fallback 127 pt/inch, corner fallback 9.5 % width, fine-tune ±15 %; Pixel 10 Pro XL 1344×2992 @ 486 ppi.
- Chrome: toolbar 44 pt + status line 14 pt, margins 10, hover zone 28, reveal 0.2 s ease-out, hide 1.2 s; buttons 22 pt; traffic lights x 8/28/48; landscape pill 28 pt high, 12 pt from top.
- Fonts/colours: title 17 bold, subtitle 13, pill 13 semibold, status line SF Pro 11 tabular; secondary white 60 %; hairline white 10 %; pill fill 16 %/28 %; chrome grey 0.08.
- TLS: ALPN `carbonmirror/1`; handshake 10 s; KeyUpdate 15 min/4 GiB; no resumption/0-RTT; send buffer 4 MiB; plaintext buffer 16 MiB; IANA 0x1302/0x1303, 0x11EC/0x001D.
- Pairing QR `WIFI:T:ADB;S:carbonmirror-<10 base62>;P:<22 base62>;;`, 120 s, single use; 6-digit fallback.
- Reconnect 0.5/1/2/4/8 s then 30 s, give up 600 s. Quality: Excellent ≥95 % & ≤20 ms; Good ≥80 % & ≤50; Fair ≥50 % & ≤120; else Poor. Idle 10 min (1–120). Rotation reminder 180 days. Auto-blur 0/5/10/30/60 s. Clipboard poll 0.5 s. Status line 1 Hz. Occlusion decode pause 5 s.
- Limits: video packet ≤ 8 MiB, frame dim ≤ 8192, clipboard ≤ 1 MiB, UHID ≤ 64 B, inject text ≤ 300 B, adb output ≤ 1 MiB, dumpsys ≤ 4 MiB, adb line ≤ 4096 B, setup line ≤ 8192 B, socket path ≤ 103 B.
- UHID keyboard id 1 "CarbonMirror Keyboard" 0x18D1/0x4EE7. Android keys HOME 3, BACK 4, VOL 24/25, POWER 26, SYSRQ 120, MUTE 164, APP_SWITCH 187, ALL_APPS 284.
- Crates: rustls 0.23.46 (aws_lc_rs, prefer-post-quantum, std; no tls12), aws-lc-rs 1.19.0, rustls-webpki 0.103.16, rcgen 0.14.7, time 0.3.55, zeroize 1.9.1, jni 0.21.1 (Android); dev: serde, serde_json, proptest. `Cargo.lock` committed.
- C ABI version **3**, 67 functions (+ `cm_hmac_sha256`, `cm_hmac_sha256_verify`) (list in `rust/include/carbon_core.h`). Status codes: Ok 0, NullPointer 1, InvalidUtf8 2, InvalidArgument 3, BufferTooSmall 4, Panic 5, NeedMoreData 6, Ip* 10–14, InterfaceTunnelRefused 15, PortInvalid 16, PortLegacyTcpipRefused 17, Adb* 30–34, DigestMismatch 50, ParseMalformed 60, ParseTooLarge 61, InputOutside 70, Tls* 80–85, Pairing/Trust 90–94, AdbProbeMalformed 100.
- Defaults keys (non-secret): all 8.3 settings + `macPinResetPending`, `companionInstalled`. Keychain: §6.13/6.27.

## 9. File tree (one-line purpose each)
- **Root:** `Package.swift` · `CLAUDE.md` rules · `HANDOFF.md` this file · `README.md` overview + 10.4 commands + 10.3 checklist · `INSTALL.md` 10.5 guide · `SECURITY_NOTES.md` threat model + limits · `REAL_DEVICE_CHECKS.md` hardware checklist · `RELEASE_CHECK.md` Phase 11 record · `THIRD_PARTY_NOTICES.md` · `CHANGELOG.md` · `LICENSE` · `.gitignore` · `.github/` + `docs/RELEASING.md` (template CI, unused layout).
- **Resources/:** `Info.plist`, `CarbonMirror.entitlements`, `adb-helper.entitlements`, `CarbonMirror-icon-1024.png`, `CarbonMirror-icon.svg`; build outputs (gitignored) `adb`, `carbonmirror-server`, `libcarbon_core.so`, `CarbonMirrorCompanion.apk`.
- **scripts/:** `setup-env.sh` Linux env · `make-cert.sh` Step A · `build-server.sh` server jar + phone core lib · `build-apk.sh` companion (`--test-key` on Linux) · `build.sh` Steps B–F (+ `--install`).
- **rust/carbon-core/src/:** `lib.rs` · `status.rs` · `crypto.rs` · `tls.rs` inner TLS · `ffi/mod.rs` C ABI · `ffi/jni.rs` JNI · `policy/{adb,net,size,failure,clipboard,pairing}.rs` · `protocol/{adb_devices,adb_wire,annexb,control,display_info,input,keymap,scrcpy}.rs`. **tests/** `vectors.rs`, `fuzz.rs`, `tls.rs` (incl. replay/tamper/burst). **examples/** `tls_endpoint.rs` (attack target). `cbindgen.toml`. **rust/include/** `carbon_core.h`, `module.modulemap`.
- **tests/vectors/:** `adb.json net.json size.json failure.json adb_devices.json`.
- **Sources/CMCoreBridge/:** CoreStatus, Crypto (`hex`), Policy, SizeMath, AdbDeviceList, Protocol, Input, Security.
- **Sources/CMCore/:** Log, PhoneProfile, Device, StatusContent, AppSettings, ChromeLayout, Policies, VideoSink, Encryption.
- **Sources/CMTransport/:** AdbCommand, AdbEnvironment (Unix sockets), AdbRunner, AdbSupervisor, ChildProcesses, ServerDeployer, ByteStream (`POSIXStream` + Unix connect), NWByteStream (LAN probe only), SecureStream, PhoneLink, MirrorSession, WirelessProbe, NetworkIdentity, Bonjour (macOS).
- **Sources/CMSecurity/:** HelperSignature, KeyManager, KeychainKeyStore, OwnerCheck.
- **Sources/CMInput/:** InputEngine. **Sources/CMMedia/:** Screenshot, VideoDecoder, MetalScreenView.
- **Sources/CMUI/ (macOS):** Theme, PhoneWindow, PhoneContentView (+ overlay, landscape pill), StatusView (+ LandscapeOfferView), ChromeView, WindowSizer, PhoneWindowController, MenuBarController, DemoDriver, AppDelegate, MirrorView (+ HUD, AppShortcuts), SessionController, PairingController (+ PairingView, EndpointPrompt), SettingsWindow. **Sources/CarbonMirrorApp/main.swift.**
- **Tests/CMTests/:** VectorTests, BridgeTests, TransportTests (+ `Fixtures/fake-adb.sh`), UILayoutTests, SessionTests (+ phone-dies edge test), VirtualPhone (+ `loopFPS`, `TapStream`), InputTests, PolicyTests, KeyTests, ProbeTests (+ LAN test), SoakTests.
- **server/:** forked scrcpy 5.0 (`LICENSE-scrcpy`), `carbon/{CarbonCore,SessionSetup,SecureChannel,BatteryMonitor}.java`; `CleanUp.java` writes `carbonmirror_session`; `ClipboardManager.java` skips sensitive clips.
- **companion/:** `AndroidManifest.xml`, `src/com/nomadicrebel/carbonmirror/companion/WirelessDebuggingTile.java`, `res/{drawable/ic_foreground,ic_monochrome,ic_tile, mipmap-anydpi/ic_launcher, values/strings,colors}.xml`.
- **tools/sectest/:** `tls_downgrade.sh`, `capture_session.sh` + `capture_scan.py`, `virtual_lan.sh` + `fake_adbd.py` + `port_scan.py`, `ffi_fuzz.sh` + `ffi_fuzz.py`.

- **Session 3 files:** `Sources/CMUI/SplashView.swift` · `Resources/CarbonMirror-startup.mp4` · `tools/startup/render_carbonmirror.py` · `tools/sectest/adb_local_exposure.sh` · `.cargo/config.toml` · `companion/src/…/{MainActivity,WirelessDebugging}.java` · `companion/res/{layout/status,drawable/pill,values/styles}.xml` · `.github/workflows/ci.yml` (manual `macos` job).

## 10. Build, sign, package & install commands
**Startup clip:** `python3 tools/startup/render_carbonmirror.py Resources/CarbonMirror-icon.svg <out> slide 120` → copy to `Resources/CarbonMirror-startup.mp4` (needs Pillow, numpy, ffmpeg). **Attack:** `bash tools/sectest/adb_local_exposure.sh`.
**Linux (verified):** `source ~/carbonmirror-deps/env.sh` · `cargo test --release --manifest-path rust/Cargo.toml` · `cargo clippy --release --all-targets --manifest-path rust/Cargo.toml -- -D warnings` · `(cd rust/carbon-core && cargo ndk -t arm64-v8a -P 30 clippy --release -- -D warnings)` · `(cd rust && cargo audit)` · `cargo build --release --manifest-path rust/Cargo.toml && touch Sources/CMCoreBridge/*.swift && swift build --build-tests && swift test` · `bash scripts/build-server.sh` · `bash scripts/build-apk.sh --test-key` · `bash tools/sectest/tls_downgrade.sh` · `bash tools/sectest/capture_session.sh encryptedSessionStreamsVideoAndControl` · `bash tools/sectest/virtual_lan.sh` (root) · `bash tools/sectest/ffi_fuzz.sh 120` · `CM_SOAK_SECONDS=300 swift test --filter soak`.
**Mac (NOT RUN):** order = Step A `bash scripts/make-cert.sh` (or README) → Step A-2 platform-tools → `Resources/adb` → Step A-3 Rust → JDK + Android SDK/NDK (INSTALL §8.4) → `bash scripts/build-server.sh` → release keystore (INSTALL §8.4) → `bash scripts/build-apk.sh` → `bash scripts/build.sh` (`--install` to copy to /Applications). Every 10.4 command is written out one per line in README.

## 11. Test status
- `cargo test --release`: **44 passed**; clippy clean (host + Android); `cargo audit` exit 0.
- `swift build --build-tests`: 0 warnings (Linux). `swift test`: **70 tests in 10 suites passed** (soak and LAN tests run via their harnesses).
- Phase 11 harnesses: all PASS (§7).
- **NOT RUN — needs my Mac:** every macOS-only Swift file (never compiled), `build.sh`, `make-cert.sh`, codesign/DMG, Keychain, sandbox, Liquid Glass, Metal/VideoToolbox, UI layout on screen. **NOT RUN — needs real device:** all of `REAL_DEVICE_CHECKS.md` (A1–A5, 6a–6c, B6–B15, C16–C24, D25–D29, E30).
- **macOS 26 CI:** release build 0 errors / 0 warnings; `--demo` launches, splash plays, status states render (screenshots).
- **Known open issues:** (1) first build + sign on the user's Mac pending (`scripts/build.sh`); (2) horizontal scroll sign unverified; (3) `ALL_APPS` swipe fallback not implemented; (4) companion permission-fallback only checked on device; (5) no `tc netem` → no loss/latency simulation; (6) `network.server` entitlement possibly removable; (7) landscape pill width at 0.75× (~239 pt) to verify on screen; (8) performance targets (latency, CPU, idle memory) only measurable on the Mac.

## 12. Next steps (ordered; start at 1)
0. Session 3 leftovers: none half-finished. Android screen and both splashes are NOT RUN on real hardware → `REAL_DEVICE_CHECKS.md` A/D.
1. **Mac first build.** (Compile errors are already cleared on CI.) User runs (from the repo folder): Step A-2 adb → `bash scripts/build-server.sh` → `bash scripts/build-apk.sh` → `bash scripts/build.sh`, and sends the tail of `build.log`. Fix compile errors in the macOS-only files (Swift 6 strict concurrency, zero warnings). Expect issues in: SessionController (`@MainActor` closures in notifications/timers), Bonjour (`dnssd` C callbacks), MetalScreenView, SettingsWindow (`NSGlassEffectView.contentView`), PairingController.
2. `REAL_DEVICE_CHECKS.md` A–E on the Mac and Pixel; record results in `RELEASE_CHECK.md`; fix findings and re-run the affected Phase 11 stage. Try removing `network.server` (6c).
3. Second pass (user attaches the full prompt): go requirement by requirement through §14, adding all remaining detail.
4. Release gate: version bump, CHANGELOG, signed DMG + APK, SHA-256 checksums, evidence table, INSTALL final pass. Commit + push to `main` after every step.

## 13. Rules to keep obeying
- **A3 rules 1–10**, especially **rule 9 (honesty & evidence):** exact command + real output for every "done/tested"; otherwise `NOT RUN — <reason>` + `REAL_DEVICE_CHECKS.md`; never weaken/skip/hard-code tests or special-case test inputs; every fix shows its diff + re-run.
- A7 scope: display out, input in, plain-text clipboard ≤ 1 MB both ways, screenshots only to `~/Pictures/CarbonMirror/`; no files, drag-and-drop, audio, recording, APK drops, storage browsing, free-form shell; notifications never reach macOS.
- Monochrome UI (icon is the only colour), always dark.
- No Xcode-only tools, no Homebrew; command-line build; Swift 6 strict concurrency, zero warnings.
- Network etiquette (A3.8): download once, sequential, ≤ 1 req/s, cache + SHA-256, backoff 2→4→8→16→32 s, max 5, then print the manual command.
- Author credit "ButcheCassidy - The Nomadic Rebel".
- Terminal instructions for the user: one command per line, plain sentence before each, no comment lines; tell the user to run scripts as `bash scripts/…` from the repo folder.
- §3 user rules (main only, user's name, no AI attribution, lean code, no filler, encryption/privacy first, GrapheneOS).

## 14. The full spec (verbatim; PART A + all phases), with requirement status
Legend: ✅ done · 🟡 partial · ⬜ not started. Status for each numbered requirement is given in the table directly after this legend; the spec text follows unchanged.

| Req | Status | Evidence / note |
|---|---|---|
| A3.1 native only | ✅ | Swift/AppKit/Metal + Rust; no web views |
| A3.2 no Apple binaries/assets | ✅ | original code; system SF Symbols only |
| A3.3 CLT-only build | ✅ | scripts use swift/sips/iconutil/plutil/codesign/hdiutil; Metal shader compiled at runtime |
| A3.4 signed .app in .dmg | 🟡 | scripts/build.sh written; first Mac run stopped on a script bug (fixed `502ad5e`); NOT RUN |
| A3.5 monochrome | ✅ | Theme tokens; traffic lights are system buttons |
| A3.6 security rules | ✅ code | Phase 7 + Phase 11 self-attack (§7) |
| A3.7 files complete, README/terminal style | ✅ | README, INSTALL written; no TODO/stubs |
| A3.8 network etiquette | ✅ | only crates, the PolyForm text, the RustSec DB and two AOSP source files fetched, once each |
| A3.9 evidence | ✅ | §9 |
| A3.10 Linux vs Mac | ✅ | macOS parts guarded; NOT RUN list §9 |
| A9 Rust core split/C ABI/no Tokio/no unsafe outside ffi/release profile/zeroize/cbindgen/vectors twice/JNI | ✅ (in-place decrypt deviation §6.11) | cargo audit clean; fuzzed |
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
| 3.2 private adb env (spec: 127.0.0.1) | ✅ stronger | Unix sockets in the sandbox container, no TCP (§6.5) |
| 3.3 forked server (no Gradle), hash verify, libcarbon_core.so | ✅ | build-server.sh output §9 |
| 3.4 supervisor | ✅ | stop hang fixed (TERM→KILL) |
| 3.5 device model | ✅ | Device.swift |
| Checkpoint 3 | ✅ Linux | REAL_DEVICE_CHECKS.md written |
| 4.1 protocol client + allowlist + battery | ✅ | SessionTests |
| 4.2 corner radius | ✅ | read + window wiring |
| 4.3 decode | 🟡 | reviewed + fixed; uncompiled (needs Mac) |
| 4.4 render | 🟡 | reviewed + fixed (texture lifetime, letterbox, BT.601); uncompiled |
| 4.5 USB profile + adaptive fallback | ✅ code | wiring in SessionController; device check |
| 4.6 debug HUD | ✅ code | ⌥⌘D, MirrorView |
| Checkpoint 4 | 🟡 | framing/config/key frames ✅; soak 120/60 fps ✅; real 120 fps/colours NOT RUN |
| 5.1 main display, screen-off toggle | ✅ code | toggle live |
| 5.2 mapping | ✅ | InputTests |
| 5.3 typing modes | ✅ | InputTests |
| 5.4 shortcuts | ✅ engine+menu / Mac screenshot 🟡 | |
| 5.5 dedicated queue, rotation/scale mapping | ✅ | ordered non-blocking send |
| 5.6 clipboard | ✅ code | Mac→phone polling 0.5 s while key + sync on |
| Checkpoint 5 | ✅ Linux | InputTests incl. flood |
| 6.1 Wireless debugging only, tcpip refused, Secure profile | ✅ | H.265→H.264 fallback |
| 6.2 allowlist, interface binding, IP only, discovery, hotspot, self-check, README tile | ✅ code | virtual LAN ✅ |
| 6.3 auto switching + mode setting | ✅ code | switchSession handover |
| Checkpoint 6 | ✅ Linux | virtual LAN: allowlist, tunnel, plaintext refusal, no listeners, capture clean |
| 7.1 threat model doc | ✅ | SECURITY_NOTES.md |
| 7.2 QR pairing, 120 s single use, pins, 6-digit fallback | ✅ code | PairingController; NOT RUN |
| 7.3 inner TLS (all bullets) | ✅ | rust tests/tls.rs, SessionTests |
| 7.4 identity key + adb key fingerprint | ✅ code / Keychain NOT RUN | |
| 7.5 key regeneration & recovery | ✅ code | dialogs, retry, reminder |
| 7.6 hardening | ✅ code | + Unix sockets, unlock check, no Resume, clipboard privacy |
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
