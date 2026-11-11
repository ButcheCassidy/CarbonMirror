# Releasing CarbonMirror

## Expected layout
- `android/` — Gradle project with `gradlew` and an `app` module.
- `macos/` — Xcode project (`*.xcodeproj`). Set repo variable `MACOS_SCHEME`.

Jobs for a platform are skipped until its folder exists.

## Cut a release
- **GitHub UI:** Actions → Release → Run workflow → version `1.2.0`.
- **CLI:** `git tag -a v1.2.0 -m "v1.2.0" && git push origin v1.2.0`

Output: GitHub Release with signed APK/AAB, notarized macOS zip, `SHA256SUMS.txt`,
and a build-provenance attestation (verify: `gh attestation verify <file> -R ButcheCassidy/CarbonMirror`).
Tags containing `-` (e.g. `v1.2.0-beta.1`) are marked pre-release.

## Secrets
Add under **Settings → Environments → New environment → `release`** → *Environment secrets*.
Environment-scoped secrets are only exposed to the release jobs, not to CI or PR builds.

| Secret | What | How to get it |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | Upload/release keystore | `base64 -i release.jks \| pbcopy` |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password | Set when creating keystore |
| `ANDROID_KEY_ALIAS` | Key alias | Set when creating keystore |
| `ANDROID_KEY_PASSWORD` | Key password | Set when creating keystore |
| `MACOS_CERT_P12_BASE64` | Developer ID Application cert + private key | Keychain Access → export `.p12` → `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | `.p12` export password | Set on export |
| `APPLE_ID` | Apple ID email for notarization | Apple Developer account |
| `APPLE_APP_SPECIFIC_PASSWORD` | Notarization password | appleid.apple.com → Sign-In and Security → App-Specific Passwords |
| `APPLE_TEAM_ID` | 10-char team ID | developer.apple.com → Membership |

Repository **variable** (not secret): `MACOS_SCHEME` — Xcode scheme name.

Create an Android keystore (keep an offline backup; losing it blocks updates):
```bash
keytool -genkeypair -v -keystore release.jks -alias carbonmirror -keyalg RSA -keysize 4096 -validity 10000
```

## Android signing config (`android/app/build.gradle.kts`)
```kotlin
android {
    defaultConfig {
        versionName = System.getenv("VERSION_NAME") ?: "0.0.0-dev"
        versionCode = System.getenv("VERSION_CODE")?.toInt() ?: 1
    }
    signingConfigs {
        create("release") {
            System.getenv("ANDROID_KEYSTORE_PATH")?.let { storeFile = file(it) }
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

## Security notes
- Keystore and `.p12` are decoded to the runner temp dir with `umask 077` and deleted after use.
- macOS uses a throwaway keychain with a random password, deleted in an `always()` step.
- Workflows default to `contents: read`; only tag creation and publishing get `contents: write`.
- `gitleaks` scans every push/PR for committed secrets.
- Never commit `*.jks`, `*.keystore`, `*.p12`, `.env`, `local.properties`.
