#!/usr/bin/env bash
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
# Phase 11 Stage 3.3: records every byte one virtual-phone session sends and receives on its private Unix
# sockets, then scans the recording for anything readable.
#   tools/sectest/capture_session.sh encryptedSessionStreamsVideoAndControl   (must be clean)
#   tools/sectest/capture_session.sh plainUSBSessionWorksWithoutTLS           (control: must be flagged)
# Needs the Python venv from setup-env.sh (dpkt).
set -uo pipefail

# Find the repository whether the script is run, sourced or started from another folder.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." 2>/dev/null && pwd)"
[ -f "$ROOT/Package.swift" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -f "$ROOT/Package.swift" ] || { echo "Open Terminal in the CarbonMirror folder and run: bash tools/sectest/capture_session.sh" >&2; exit 1; }
cd "$ROOT"
TEST="${1:?test name}"
CM_CAPTURE_DIR="$(mktemp -d)"
export CM_CAPTURE_DIR
swift test --filter "$TEST" 2>&1 | grep -E "✔ Test run|✘"
"$HOME/carbonmirror-deps/venv/bin/python" -I tools/sectest/capture_scan.py "$CM_CAPTURE_DIR" "Pixel 10 Pro XL" "hello"
status=$?
rm -rf "$CM_CAPTURE_DIR"
exit "$status"
