#!/usr/bin/env bash
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
RELEASE=/Applications/CarbonMirror.app/Contents/Resources
for part in carbonmirror-server libcarbon_core.so CarbonMirrorCompanion.apk; do
  [ -f "Resources/$part" ] && continue
  [ -f "$RELEASE/$part" ] || fail "missing Resources/$part: install the release DMG once (it contains the phone parts) or build them (INSTALL.md 8.4)."
  cp "$RELEASE/$part" "Resources/$part"
done

echo "==> 5/5 App, signature and DMG"
bash scripts/build.sh "$@"
