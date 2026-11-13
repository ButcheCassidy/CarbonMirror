#!/usr/bin/env bash
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
# One command on the Mac, from the source folder: certificate, Google's adb, Rust, phone parts, then
# scripts/build.sh (app + signed DMG). Safe to re-run: finished steps are skipped.
# Usage: bash scripts/build-mac.sh [--install]
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"
cd "$ROOT"
fail() { printf 'build-mac.sh: %s\n' "$*" >&2; exit 1; }
[ -f Package.swift ] || fail "run this from the CarbonMirror source folder."
[ "$(uname -s)" = "Darwin" ] || fail "run this on the Mac."
xcode-select -p > /dev/null 2>&1 || { xcode-select --install || true; fail "install Apple's Command Line Tools (a window opened), then run this again."; }

echo "==> 1/5 Signing certificate \"CarbonMirror Dev\""
bash scripts/make-cert.sh

echo "==> 2/5 Google's adb"
if [ ! -f Resources/adb ]; then
  mkdir -p deps
  curl -fL --retry 5 -o deps/platform-tools-latest-darwin.zip https://dl.google.com/android/repository/platform-tools-latest-darwin.zip
  shasum -a 256 deps/platform-tools-latest-darwin.zip >> deps.lock
  rm -rf deps/platform-tools
  ditto -x -k deps/platform-tools-latest-darwin.zip deps/
  cp deps/platform-tools/adb Resources/adb
fi

echo "==> 3/5 Rust"
[ -f "$HOME/.cargo/env" ] || curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
. "$HOME/.cargo/env"
rustup target add aarch64-apple-darwin
command -v cbindgen > /dev/null || cargo install cbindgen --locked

echo "==> 4/5 Phone parts (server, phone core library, companion APK)"
PARTS="carbonmirror-server libcarbon_core.so CarbonMirrorCompanion.apk"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
# Copies the parts from a release CarbonMirror.app of the same version (the phone server must match the app's version).
parts_from() {
  local app="$1" part
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null)" = "$VERSION" ] || return 1
  codesign --verify --deep --strict "$app" 2>/dev/null || return 1
  for part in $PARTS; do [ -f "$app/Contents/Resources/$part" ] || return 1; done
  for part in $PARTS; do cp "$app/Contents/Resources/$part" "Resources/$part" && xattr -c "Resources/$part"; done
}
# Same, from a release DMG: mounted read-only and hidden, then detached.
parts_from_dmg() {
  local mount ok=1
  mount="$(mktemp -d)"
  hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mount" "$1" > /dev/null || { rmdir "$mount"; return 1; }
  parts_from "$mount/CarbonMirror.app" && ok=0
  hdiutil detach -quiet "$mount" || true
  rmdir "$mount" 2> /dev/null || true
  return $ok
}
# Same, from a release source zip (the phone parts are inside it under Resources/).
parts_from_zip() {
  local zip="$1" part
  for part in $PARTS; do
    unzip -p "$zip" "CarbonMirror-$VERSION/Resources/$part" > "Resources/$part" 2> /dev/null && [ -s "Resources/$part" ] || return 1
  done
}
# Parts are reused only when they belong to this version (marker written below); otherwise fetched again.
missing=0
[ "$(cat Resources/phone-parts.version 2> /dev/null)" = "$VERSION" ] || missing=1
for part in $PARTS; do [ -f "Resources/$part" ] || missing=1; done
if [ "$missing" = 1 ]; then
  ZIP="$HOME/Downloads/CarbonMirror-$VERSION-source.zip"
  DMG="$HOME/Downloads/CarbonMirror-$VERSION.dmg"
  # The release workflow's "phone" artifact (Actions → Release run → Artifacts → phone), unpacked in Downloads.
  ARTIFACT="$HOME/Downloads/phone/Resources"
  if [ -f "$ARTIFACT/carbonmirror-server" ] && [ -f "$ARTIFACT/libcarbon_core.so" ] && [ -f "$ARTIFACT/CarbonMirrorCompanion.apk" ]; then
    for part in $PARTS; do cp "$ARTIFACT/$part" "Resources/$part" && xattr -c "Resources/$part"; done
  elif ! parts_from /Applications/CarbonMirror.app && ! { [ -f "$ZIP" ] && parts_from_zip "$ZIP"; } \
      && ! { [ -f "$DMG" ] && parts_from_dmg "$DMG"; }; then
    # From the GitHub release of this version: the source zip (1.0.1 on), else the DMG of older releases.
    mkdir -p deps
    RELEASE="https://github.com/ButcheCassidy/CarbonMirror/releases/download/v$VERSION"
    { curl -fsL --retry 5 -o "deps/CarbonMirror-$VERSION-source.zip" "$RELEASE/CarbonMirror-$VERSION-source.zip" \
        && parts_from_zip "deps/CarbonMirror-$VERSION-source.zip"; } \
      || { curl -fsL --retry 5 -o "deps/CarbonMirror-$VERSION.dmg" "$RELEASE/CarbonMirror-$VERSION.dmg" \
        && parts_from_dmg "deps/CarbonMirror-$VERSION.dmg"; } \
      || fail "no CarbonMirror $VERSION release found. Download CarbonMirror-$VERSION-source.zip from the GitHub releases page into Downloads, or build the phone parts (INSTALL.md 8.4)."
  fi
fi
for part in $PARTS; do [ -f "Resources/$part" ] || fail "missing Resources/$part"; done
echo "$VERSION" > Resources/phone-parts.version

echo "==> 5/5 App, signature and DMG"
bash scripts/build.sh "$@"
