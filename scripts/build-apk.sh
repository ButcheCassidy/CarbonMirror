#!/usr/bin/env bash
# Builds CarbonMirror Companion without Gradle (spec 9.4): aapt2 compile/link → javac --release 17 → d8 →
# zipalign -p 4 → apksigner (v2 + v3). Nothing is downloaded. Outputs dist/CarbonMirrorCompanion-<version>.apk
# and Resources/CarbonMirrorCompanion.apk (bundled into the Mac app).
#   scripts/build-apk.sh              sign with the release key (password typed in, never stored)
#   scripts/build-apk.sh --test-key   sign with a throwaway P-384 key (Linux checks only, never released)
# Release keystore: CM_KEYSTORE, default ~/Library/Application Support/CarbonMirror/signing/carbonmirror-release.p12;
# alias CM_KEY_ALIAS (default carbonmirror).
set -euo pipefail

# Find the repository whether the script is run, sourced or started from another folder.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"
[ -f "$ROOT/Package.swift" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -f "$ROOT/Package.swift" ] || { echo "Open Terminal in the CarbonMirror folder and run: bash scripts/build-apk.sh" >&2; exit 1; }
cd "$ROOT"
VERSION="$(grep -A1 '<key>CFBundleShortVersionString</key>' Resources/Info.plist | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')"
IFS=. read -r MAJOR MINOR PATCH <<< "$VERSION"
VERSION_CODE=$((MAJOR * 10000 + MINOR * 100 + PATCH))
PLATFORM="${ANDROID_PLATFORM:-android-36}"
BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-36.0.0}"
: "${ANDROID_HOME:?set ANDROID_HOME to the Android SDK}"
ANDROID_JAR="$ANDROID_HOME/platforms/$PLATFORM/android.jar"
BT="$ANDROID_HOME/build-tools/$BUILD_TOOLS"
for f in "$ANDROID_JAR" "$BT/aapt2" "$BT/d8" "$BT/zipalign" "$BT/apksigner"; do
  [ -e "$f" ] || { echo "build-apk.sh: missing $f" >&2; exit 1; }
done

BUILD="companion/build"
OUT="dist/CarbonMirrorCompanion-$VERSION.apk"
rm -rf "$BUILD"
mkdir -p "$BUILD/gen" "$BUILD/classes" "$BUILD/dex" dist Resources

echo "==> aapt2 ($VERSION, code $VERSION_CODE)"
cp -R companion/res "$BUILD/res"
mkdir -p "$BUILD/res/raw"
cp Resources/CarbonMirror-startup.mp4 "$BUILD/res/raw/startup.mp4"
"$BT/aapt2" compile --dir "$BUILD/res" -o "$BUILD/res.zip"
"$BT/aapt2" link -I "$ANDROID_JAR" --manifest companion/AndroidManifest.xml --min-sdk-version 30 --target-sdk-version 36 \
  --version-code "$VERSION_CODE" --version-name "$VERSION" --java "$BUILD/gen" -o "$BUILD/unaligned.apk" "$BUILD/res.zip"

echo "==> javac + d8"
find companion/src "$BUILD/gen" -name '*.java' > "$BUILD/sources.txt"
javac --release 17 -encoding UTF-8 -classpath "$ANDROID_JAR" -d "$BUILD/classes" @"$BUILD/sources.txt"
find "$BUILD/classes" -name '*.class' > "$BUILD/classes.txt"
"$BT/d8" --release --min-api 30 --lib "$ANDROID_JAR" --output "$BUILD/dex" @"$BUILD/classes.txt"
(cd "$BUILD/dex" && zip -q -X ../unaligned.apk classes.dex)

echo "==> zipalign"
"$BT/zipalign" -p -f 4 "$BUILD/unaligned.apk" "$BUILD/aligned.apk"

echo "==> apksigner"
if [ "${1:-}" = "--test-key" ]; then
  CM_TEST_PASS="$(openssl rand -hex 32)"
  export CM_TEST_PASS
  keytool -genkeypair -keyalg EC -groupname secp384r1 -sigalg SHA384withECDSA -validity 1 -dname "CN=CarbonMirror Test Key" \
    -alias carbonmirror -storetype PKCS12 -keystore "$BUILD/test.p12" -storepass:env CM_TEST_PASS >/dev/null
  "$BT/apksigner" sign --ks "$BUILD/test.p12" --ks-key-alias carbonmirror --ks-pass env:CM_TEST_PASS \
    --v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled true --out "$OUT" "$BUILD/aligned.apk"
  rm -f "$BUILD/test.p12"
  unset CM_TEST_PASS
else
  KEYSTORE="${CM_KEYSTORE:-$HOME/Library/Application Support/CarbonMirror/signing/carbonmirror-release.p12}"
  [ -f "$KEYSTORE" ] || { echo "build-apk.sh: no keystore at $KEYSTORE (create it with keytool, see INSTALL.md)" >&2; exit 1; }
  # Passwords are typed in; CI passes them as environment variables only (CM_KEYSTORE_PASS, CM_KEY_PASS).
  PASSWORDS=()
  [ -n "${CM_KEYSTORE_PASS:-}" ] && PASSWORDS=(--ks-pass env:CM_KEYSTORE_PASS --key-pass env:CM_KEY_PASS)
  "$BT/apksigner" sign --ks "$KEYSTORE" --ks-key-alias "${CM_KEY_ALIAS:-carbonmirror}" ${PASSWORDS[@]+"${PASSWORDS[@]}"} \
    --v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled true --out "$OUT" "$BUILD/aligned.apk"
fi
cp "$OUT" Resources/CarbonMirrorCompanion.apk

echo "==> verify"
"$BT/apksigner" verify --verbose --print-certs --min-sdk-version 24 "$OUT"
"$BT/aapt2" dump permissions "$OUT"
shasum -a 256 "$OUT" 2>/dev/null || sha256sum "$OUT"
