#!/usr/bin/env bash
# Builds, signs and packages CarbonMirror on the Mac (README / spec 10.4 steps B–F).
# Usage: scripts/build.sh [--install]
# Needs: Apple Command Line Tools, Rust (Step A-3), the "CarbonMirror Dev" certificate (scripts/make-cert.sh),
# Resources/adb (Step A-2), and Resources/carbonmirror-server, Resources/libcarbon_core.so,
# Resources/CarbonMirrorCompanion.apk (scripts/build-server.sh, scripts/build-apk.sh).
set -euo pipefail

# Find the repository whether the script is run, sourced or started from another folder.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"
[ -f "$ROOT/Package.swift" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -f "$ROOT/Package.swift" ] || { echo "Open Terminal in the CarbonMirror folder and run: bash scripts/build.sh" >&2; exit 1; }
cd "$ROOT"
IDENTITY="${CM_SIGN_IDENTITY:-CarbonMirror Dev}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
APP=build/CarbonMirror.app

fail() { printf 'build.sh: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "run this on the Mac (Linux builds use swift build / cargo test only)."
for input in Resources/adb Resources/carbonmirror-server Resources/libcarbon_core.so Resources/CarbonMirrorCompanion.apk Resources/CarbonMirror-icon-1024.png Resources/CarbonMirror-startup.mp4; do
  [ -f "$input" ] || fail "missing $input — see README (Step A-2, scripts/build-server.sh, scripts/build-apk.sh)."
done

echo "==> Checking the bundled adb is Google's original and matches deps.lock"
codesign -dv Resources/adb 2>&1 | grep -q "Authority=.*Google LLC" || fail "Resources/adb is not signed by Google LLC."
if [ -f deps/platform-tools-latest-darwin.zip ] && [ -f deps.lock ]; then
  recorded="$(grep 'platform-tools-latest-darwin.zip' deps.lock | tail -1 | cut -d' ' -f1)"
  actual="$(shasum -a 256 deps/platform-tools-latest-darwin.zip | cut -d' ' -f1)"
  [ "$recorded" = "$actual" ] || fail "platform-tools zip does not match deps.lock ($actual vs $recorded)."
fi

echo "==> Step B: Rust core and app binary"
cargo build --release --target aarch64-apple-darwin --manifest-path rust/carbon-core/Cargo.toml
cbindgen --config rust/carbon-core/cbindgen.toml --crate carbon-core --output rust/include/carbon_core.h rust/carbon-core
rm -f .build/release/CarbonMirror
swift build -c release --arch arm64 2>&1 | tee build.log
if grep -E ": error:|^ld:|Undefined symbols" build.log | sort -u | head -60 | grep -q .; then
  fail "swift build reported errors (see build.log)."
fi

echo "==> Step C: assemble the .app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp .build/release/CarbonMirror "$APP/Contents/MacOS/CarbonMirror"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/adb "$APP/Contents/Helpers/adb"
cp Resources/carbonmirror-server "$APP/Contents/Resources/carbonmirror-server"
cp Resources/libcarbon_core.so "$APP/Contents/Resources/libcarbon_core.so"
cp Resources/CarbonMirrorCompanion.apk "$APP/Contents/Resources/CarbonMirrorCompanion.apk"
cp Resources/CarbonMirror-startup.mp4 "$APP/Contents/Resources/CarbonMirror-startup.mp4"
plutil -replace CMServerSHA256 -string "$(shasum -a 256 Resources/carbonmirror-server | cut -d' ' -f1)" "$APP/Contents/Info.plist"
plutil -replace CMCoreLibSHA256 -string "$(shasum -a 256 Resources/libcarbon_core.so | cut -d' ' -f1)" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

echo "==> Step D: app icon"
ICONSET=build/CarbonMirror.iconset
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/CarbonMirror-icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  if [ "$double" -eq 1024 ]; then
    cp Resources/CarbonMirror-icon-1024.png "$ICONSET/icon_${size}x${size}@2x.png"
  else
    sips -z "$double" "$double" Resources/CarbonMirror-icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  fi
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/CarbonMirror.icns"
rm -rf "$ICONSET"

echo "==> Step E: sign inside-out and verify"
codesign --force --options runtime --timestamp=none --entitlements Resources/adb-helper.entitlements --sign "$IDENTITY" "$APP/Contents/Helpers/adb"
codesign --force --options runtime --timestamp=none --entitlements Resources/CarbonMirror.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Step F: DMG"
DMG="dist/CarbonMirror-$VERSION.dmg"
mkdir -p dist build/dmg
ditto "$APP" build/dmg/CarbonMirror.app
ln -s /Applications build/dmg/Applications
hdiutil create -volname "CarbonMirror $VERSION" -srcfolder build/dmg -ov -format UDZO "$DMG"
rm -rf build/dmg
codesign --force --timestamp=none --sign "$IDENTITY" "$DMG"
codesign --verify --verbose=2 "$DMG"
shasum -a 256 "$DMG"

if [ "${1:-}" = "--install" ]; then
  echo "==> Installing to /Applications"
  osascript -e 'tell application id "com.nomadicrebel.carbonmirror" to quit' || true
  rm -rf /Applications/CarbonMirror.app
  ditto "$APP" /Applications/CarbonMirror.app
  open /Applications/CarbonMirror.app
fi
