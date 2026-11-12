#!/usr/bin/env bash
# Phase 11 Stage 3.8: runs ffi_fuzz.py for every C ABI entry point, SECONDS each (default 120), 4 at a time.
set -uo pipefail

# Find the repository whether the script is run, sourced or started from another folder.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." 2>/dev/null && pwd)"
[ -f "$ROOT/Package.swift" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -f "$ROOT/Package.swift" ] || { echo "Open Terminal in the CarbonMirror folder and run: bash tools/sectest/ffi_fuzz.sh" >&2; exit 1; }
cd "$ROOT"
SECONDS_EACH="${1:-120}"
cargo build -q --release --manifest-path rust/Cargo.toml || exit 1
PY="$HOME/carbonmirror-deps/venv/bin/python"
LIB="rust/target/release/libcarbon_core.so"
ENTRIES="video_header device_message device_name adb_parse_devices adb_track_frame net_check_ip net_check_endpoint adb_validate annexb corner_radius clipboard probe_classify tls_client_parser"
status=0
echo "$ENTRIES" | tr ' ' '\n' | xargs -P 4 -I{} "$PY" -I tools/sectest/ffi_fuzz.py "$LIB" {} "$SECONDS_EACH" || status=1
exit "$status"
