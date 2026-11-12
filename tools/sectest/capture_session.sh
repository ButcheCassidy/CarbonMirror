#!/usr/bin/env bash
# Phase 11 Stage 3.3: captures one virtual-phone session on loopback and scans it for plaintext.
#   tools/sectest/capture_session.sh encryptedSessionStreamsVideoAndControl   (must be clean)
#   tools/sectest/capture_session.sh plainUSBSessionWorksWithoutTLS           (control: must be flagged)
# Needs root for tcpdump and the Python venv from setup-env.sh (dpkt).
set -uo pipefail

# Find the repository whether the script is run, sourced or started from another folder.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." 2>/dev/null && pwd)"
[ -f "$ROOT/Package.swift" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -f "$ROOT/Package.swift" ] || { echo "Open Terminal in the CarbonMirror folder and run: bash tools/sectest/capture_session.sh" >&2; exit 1; }
cd "$ROOT"
TEST="${1:?test name}"
PCAP="$(mktemp --suffix .pcap)"
tcpdump -i lo -U -w "$PCAP" 'tcp portrange 27000-29999' 2>/dev/null &
DUMP=$!
sleep 1
swift test --filter "$TEST" 2>&1 | grep -E "✔ Test run|✘" 
sleep 1
kill "$DUMP"
wait "$DUMP" 2>/dev/null
"$HOME/carbonmirror-deps/venv/bin/python" -I tools/sectest/capture_scan.py "$PCAP" "Pixel 10 Pro XL" "hello"
status=$?
rm -f "$PCAP"
exit "$status"
