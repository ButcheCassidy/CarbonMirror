#!/usr/bin/env bash
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
# CarbonMirror build & test environment (Linux: Debian/Ubuntu).
# Safe to re-run: anything already present is skipped, nothing is downloaded twice.
# Downloads are sequential, at least 1 s apart, with curl's exponential backoff (honours Retry-After).

set -euo pipefail

DEPS_DIR="${CARBONMIRROR_DEPS:-$HOME/carbonmirror-deps}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-36}"
BUILD_TOOLS="${BUILD_TOOLS:-36.0.0}"
SCRCPY_TAG="${SCRCPY_TAG:-v5.0}"
SWIFT_VERSION="${SWIFT_VERSION:-6.4.2}"
CMDLINE_TOOLS_URL="${CMDLINE_TOOLS_URL:-https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip}"

DL_DIR="$DEPS_DIR/downloads"
ANDROID_HOME="$DEPS_DIR/android-sdk"
LOCK="$DEPS_DIR/deps.lock"
VERSIONS="$DEPS_DIR/VERSIONS.txt"
mkdir -p "$DL_DIR" "$ANDROID_HOME"
touch "$LOCK"

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf '\n!!  %s\n' "$*" >&2; }

CAN_ROOT="yes"
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
elif command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  SUDO=""
  CAN_ROOT="no"
fi

fetch() {
  local url="$1" out="$2"
  if [ -s "$out" ]; then
    echo "cached: $(basename "$out")"
    return 0
  fi
  sleep 1
  if ! curl -fL --retry 5 --retry-max-time 300 --connect-timeout 20 -o "$out.part" "$url"; then
    rm -f "$out.part"
    warn "Download failed after retries: $url"
    warn "Run manually later: curl -fL -o '$out' '$url'"
    return 1
  fi
  mv "$out.part" "$out"
  sha256sum "$out" | tee -a "$LOCK"
}

apt_install() {
  local required="$1"; shift
  if ! command -v apt-get >/dev/null 2>&1 || [ "$CAN_ROOT" = "no" ]; then
    warn "Cannot install system packages here (no apt-get or no root/sudo). Install these yourself: $*"
    return 0
  fi
  if [ "$required" = "required" ]; then
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
  else
    for pkg in "$@"; do
      $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$pkg" >/dev/null 2>&1 \
        || warn "optional package not available: $pkg"
    done
  fi
}

log "System packages"
if command -v apt-get >/dev/null 2>&1 && [ "$CAN_ROOT" = "yes" ]; then
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -y
fi
apt_install required ca-certificates curl git unzip zip xz-utils tar gzip \
  python3 python3-venv python3-pip openssl lsof procps iproute2 tcpdump netcat-openbsd \
  ffmpeg jq file cmake clang libclang-dev build-essential pkg-config libssl-dev
apt_install optional binutils gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
  libncurses-dev libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libz3-dev \
  pkg-config tzdata zlib1g-dev librsvg2-bin shellcheck iperf3 iputils-ping kmod

log "Java (JDK 17+ needed by the Android SDK and the server build)"
if ! command -v javac >/dev/null 2>&1; then
  apt_install optional openjdk-21-jdk-headless
  command -v javac >/dev/null 2>&1 || apt_install required openjdk-17-jdk-headless
fi
if ! command -v javac >/dev/null 2>&1; then
  warn "No JDK found (javac missing). Install OpenJDK 17 or newer, then re-run."
  exit 1
fi
JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
export JAVA_HOME

log "Swift toolchain (swift.org release tarball; swiftly's API returned HTTP 403)"
SWIFT_DIR="$DEPS_DIR/swift-$SWIFT_VERSION"
if [ ! -x "$SWIFT_DIR/usr/bin/swift" ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  case "$(uname -m)" in aarch64|arm64) SFX="-aarch64" ;; *) SFX="" ;; esac
  SWIFT_FILE="swift-${SWIFT_VERSION}-RELEASE-ubuntu${VERSION_ID}${SFX}.tar.gz"
  fetch "https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu${VERSION_ID//./}${SFX}/swift-${SWIFT_VERSION}-RELEASE/${SWIFT_FILE}" "$DL_DIR/$SWIFT_FILE"
  mkdir -p "$SWIFT_DIR"
  tar -xzf "$DL_DIR/$SWIFT_FILE" -C "$SWIFT_DIR" --strip-components=1
fi
export PATH="$SWIFT_DIR/usr/bin:$PATH"
hash -r
command -v swift >/dev/null 2>&1 || { warn "swift missing after install"; exit 1; }

log "Rust toolchain (rustup, stable, minimal profile)"
CARGO_ENV="$HOME/.cargo/env"
if ! command -v cargo >/dev/null 2>&1 && [ ! -f "$CARGO_ENV" ]; then
  fetch "https://sh.rustup.rs" "$DL_DIR/rustup-init.sh"
  sh "$DL_DIR/rustup-init.sh" -y --profile minimal --default-toolchain stable
fi
# shellcheck disable=SC1090
[ -f "$CARGO_ENV" ] && . "$CARGO_ENV"
hash -r
sleep 1; rustup component add clippy rustfmt
sleep 1; rustup target add aarch64-linux-android
cargo_tool() {
  local crate="$1" bin="$2"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "cached: $crate"
    return 0
  fi
  sleep 1
  cargo install "$crate" --locked
}
cargo_tool cargo-ndk  cargo-ndk
cargo_tool cbindgen   cbindgen
cargo_tool cargo-audit cargo-audit

log "Android SDK command-line tools"
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMANAGER" ]; then
  fetch "$CMDLINE_TOOLS_URL" "$DL_DIR/cmdline-tools-linux.zip"
  rm -rf "$DL_DIR/cmdline-tools-unzip"
  unzip -q "$DL_DIR/cmdline-tools-linux.zip" -d "$DL_DIR/cmdline-tools-unzip"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  mv "$DL_DIR/cmdline-tools-unzip/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rm -rf "$DL_DIR/cmdline-tools-unzip"
fi
export ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME"

log "Android SDK licences"
yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1 || true

sdk_install() {
  local pkg="$1" dir="$2"
  if [ -d "$ANDROID_HOME/$dir" ]; then
    echo "cached: $pkg"
    return 0
  fi
  sleep 1
  "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --install "$pkg"
}
log "Android SDK packages (one at a time)"
sdk_install "platform-tools"                 "platform-tools"
sdk_install "platforms;${ANDROID_PLATFORM}"  "platforms/${ANDROID_PLATFORM}"
sdk_install "build-tools;${BUILD_TOOLS}"     "build-tools/${BUILD_TOOLS}"

log "Android NDK (newest stable, for the Rust core on the phone)"
if [ -z "${NDK_VERSION:-}" ]; then
  if [ -d "$ANDROID_HOME/ndk" ] && [ -n "$(ls -A "$ANDROID_HOME/ndk" 2>/dev/null)" ]; then
    NDK_VERSION="$(ls "$ANDROID_HOME/ndk" | sort -V | tail -n1)"
  else
    sleep 1
    NDK_VERSION="$("$SDKMANAGER" --sdk_root="$ANDROID_HOME" --list 2>/dev/null \
      | grep -oE 'ndk;[0-9]+\.[0-9]+\.[0-9]+ ' | sed 's/ndk;//; s/ //' | sort -V | tail -n1)"
  fi
fi
[ -n "$NDK_VERSION" ] || { warn "Could not find an NDK version; set NDK_VERSION and re-run."; exit 1; }
sdk_install "ndk;${NDK_VERSION}" "ndk/${NDK_VERSION}"
ANDROID_NDK_HOME="$ANDROID_HOME/ndk/$NDK_VERSION"

log "scrcpy source (pinned)"
SCRCPY_SRC="$DEPS_DIR/scrcpy"
if [ ! -d "$SCRCPY_SRC/.git" ]; then
  sleep 1
  if ! git clone --depth 1 --branch "$SCRCPY_TAG" https://github.com/Genymobile/scrcpy.git "$SCRCPY_SRC"; then
    warn "Tag $SCRCPY_TAG not found; using the newest release tag instead."
    sleep 1
    LATEST_TAG="$(git ls-remote --tags --refs --sort=-v:refname https://github.com/Genymobile/scrcpy.git 'v*' | head -n1 | sed 's#.*refs/tags/##')"
    [ -n "$LATEST_TAG" ] || { warn "Could not list scrcpy tags."; exit 1; }
    SCRCPY_TAG="$LATEST_TAG"
    sleep 1
    git clone --depth 1 --branch "$SCRCPY_TAG" https://github.com/Genymobile/scrcpy.git "$SCRCPY_SRC"
  fi
fi
SCRCPY_COMMIT="$(git -C "$SCRCPY_SRC" rev-parse HEAD)"
SCRCPY_TAG_ACTUAL="$(git -C "$SCRCPY_SRC" describe --tags --exact-match 2>/dev/null || echo "$SCRCPY_TAG")"

log "Python test environment"
VENV="$DEPS_DIR/venv"
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/python" -m pip install --quiet --upgrade pip
for pkg in cryptography pytest hypothesis dpkt; do
  "$VENV/bin/python" -m pip install --quiet "$pkg"
  sleep 1
done

log "Synthetic test video streams (for the virtual phone)"
VID_DIR="$DEPS_DIR/test-video"
mkdir -p "$VID_DIR"
make_stream() {
  local out="$1" rate="$2" codec="$3" fmt="$4"
  [ -s "$out" ] && { echo "cached: $(basename "$out")"; return 0; }
  ffmpeg -hide_banner -loglevel error -f lavfi -i "testsrc2=size=1344x2992:rate=${rate}" -t 5 \
    -c:v "$codec" -preset ultrafast -tune zerolatency -g "$rate" -pix_fmt yuv420p -f "$fmt" "$out" \
    || warn "ffmpeg could not make $(basename "$out") with $codec"
}
make_stream "$VID_DIR/pixel10proxl-120fps.h264" 120 libx264 h264
make_stream "$VID_DIR/pixel10proxl-60fps.h264"   60 libx264 h264
make_stream "$VID_DIR/pixel10proxl-60fps.h265"   60 libx265 hevc

log "Swift <-> Rust static-link smoke test"
SMOKE="$DEPS_DIR/smoke-swift-rust"
SMOKE_RESULT="not run"
NATIVE_LIBS=""
rm -rf "$SMOKE"
mkdir -p "$SMOKE/rs/src" "$SMOKE/include"
cat > "$SMOKE/rs/Cargo.toml" <<'TOML'
[package]
name = "cm_smoke"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["staticlib"]

[profile.release]
panic = "abort"
TOML
cat > "$SMOKE/rs/src/lib.rs" <<'RS'
#[no_mangle]
pub extern "C" fn cm_smoke_add(a: u32, b: u32) -> u32 {
    a.wrapping_add(b)
}
RS
cat > "$SMOKE/include/cm_smoke.h" <<'H'
#include <stdint.h>
uint32_t cm_smoke_add(uint32_t a, uint32_t b);
H
cat > "$SMOKE/include/module.modulemap" <<'MM'
module CMSmoke {
    header "cm_smoke.h"
    export *
}
MM
cat > "$SMOKE/main.swift" <<'SW'
import CMSmoke
let r = cm_smoke_add(40, 2)
print(r == 42 ? "swift-rust-ok" : "swift-rust-wrong-result")
SW
NATIVE_LIBS="$(cd "$SMOKE/rs" && cargo rustc --release --quiet -- --print native-static-libs 2>&1 | grep -o 'native-static-libs: .*' | sed 's/native-static-libs: //' || true)"
LINK_FLAGS=()
for flag in $NATIVE_LIBS; do LINK_FLAGS+=("$flag"); done
if swiftc -O -I "$SMOKE/include" "$SMOKE/main.swift" -L "$SMOKE/rs/target/release" -lcm_smoke "${LINK_FLAGS[@]}" -o "$SMOKE/smoke" >/dev/null 2>&1 \
   && [ "$("$SMOKE/smoke")" = "swift-rust-ok" ]; then
  SMOKE_RESULT="passed (extra link libs: ${NATIVE_LIBS:-none})"
else
  SMOKE_RESULT="FAILED - check swiftc/cargo installs"
  warn "Swift <-> Rust smoke test failed."
fi

log "Checking whether network namespaces work (for the virtual LAN)"
NETNS="no"
NETEM="no"
if [ "$CAN_ROOT" = "yes" ] && $SUDO ip netns add cm_probe >/dev/null 2>&1; then
  NETNS="yes"
  $SUDO ip -n cm_probe link set lo up >/dev/null 2>&1 || true
  if $SUDO ip netns exec cm_probe tc qdisc add dev lo root netem delay 5ms loss 1% >/dev/null 2>&1; then
    NETEM="yes"
  fi
  $SUDO ip netns del cm_probe >/dev/null 2>&1 || true
fi

log "Writing env.sh and VERSIONS.txt"
cat > "$DEPS_DIR/env.sh" <<EOF
export CARBONMIRROR_DEPS="$DEPS_DIR"
export JAVA_HOME="$JAVA_HOME"
export ANDROID_HOME="$ANDROID_HOME"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_PLATFORM="$ANDROID_PLATFORM"
export ANDROID_BUILD_TOOLS="$BUILD_TOOLS"
export ANDROID_NDK_HOME="$ANDROID_NDK_HOME"
export ANDROID_JAR="$ANDROID_HOME/platforms/$ANDROID_PLATFORM/android.jar"
export SCRCPY_SRC="$SCRCPY_SRC"
export CM_TEST_VIDEO_DIR="$VID_DIR"
export CM_NETNS_AVAILABLE="$NETNS"
export CM_NETEM_AVAILABLE="$NETEM"
export CM_RUST_NATIVE_STATIC_LIBS="${NATIVE_LIBS:-}"
export PATH="$SWIFT_DIR/usr/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/$BUILD_TOOLS:$JAVA_HOME/bin:\$PATH"
[ -f "$CARGO_ENV" ] && . "$CARGO_ENV"
[ -f "$VENV/bin/activate" ] && . "$VENV/bin/activate"
EOF

{
  echo "CarbonMirror environment — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "deps dir:        $DEPS_DIR"
  echo "swift:           $(swift --version 2>/dev/null | head -n1 || echo 'not on PATH')"
  echo "java:            $(java -version 2>&1 | head -n1)"
  echo "rust:            $(rustc --version 2>/dev/null) / $(cargo --version 2>/dev/null)"
  echo "rust tools:      $(cargo ndk --version 2>/dev/null | head -n1); $(cbindgen --version 2>/dev/null); $(cargo audit --version 2>/dev/null)"
  echo "android ndk:     $NDK_VERSION"
  echo "android platform: $ANDROID_PLATFORM"
  echo "build-tools:     $BUILD_TOOLS"
  echo "platform-tools:  $(grep -m1 Pkg.Revision "$ANDROID_HOME/platform-tools/source.properties" 2>/dev/null | cut -d= -f2)"
  echo "scrcpy:          $SCRCPY_TAG_ACTUAL ($SCRCPY_COMMIT)"
  echo "python:          $("$VENV/bin/python" --version 2>&1)"
  echo "ffmpeg:          $(ffmpeg -version 2>/dev/null | head -n1)"
  echo "network namespaces available: $NETNS"
  echo "netem (latency/packet-loss simulation) available: $NETEM"
  echo "swift<->rust smoke test: $SMOKE_RESULT"
  echo
  echo "test streams:"
  ls -l "$VID_DIR" 2>/dev/null | tail -n +2
  echo
  echo "checksums (deps.lock):"
  cat "$LOCK"
} > "$VERSIONS"

log "Done"
cat "$VERSIONS"
echo
echo "Load it in any shell with:  source $DEPS_DIR/env.sh"
