#!/usr/bin/env bash
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
# Phase 11 Stage 3.4–3.6 on a virtual LAN (Linux, root): namespaces "mac" 192.168.77.1, "phone" 192.168.77.2 and
# "attacker" 192.168.77.3 on one bridge, plus a fake Mullvad tunnel `utun9` (10.64.0.0/10) in "mac".
#  1. Legacy plaintext adb (5555 and another port) on the phone, Mullvad tunnel and public targets → refused.
#  2. While encrypted sessions run in "mac", the attacker scans all 65535 TCP ports of the Mac → none open,
#     and the Mac has no TCP or UDP listener at all (its sockets are private Unix sockets).
#  3. Nothing was ever sent into the fake tunnel.
set -uo pipefail

# Find the repository whether the script is run, sourced or started from another folder.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." 2>/dev/null && pwd)"
[ -f "$ROOT/Package.swift" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -f "$ROOT/Package.swift" ] || { echo "Open Terminal in the CarbonMirror folder and run: bash tools/sectest/virtual_lan.sh" >&2; exit 1; }
cd "$ROOT"
PY="$HOME/carbonmirror-deps/venv/bin/python"
NS="cm-mac cm-phone cm-attacker cm-lan"
cleanup() { for n in $NS; do ip netns del "$n" 2>/dev/null; done; }
trap cleanup EXIT
cleanup
for n in $NS; do ip netns add "$n"; ip -n "$n" link set lo up; done
ip -n cm-lan link add br0 type bridge && ip -n cm-lan link set br0 up
i=1
for n in cm-mac cm-phone cm-attacker; do
  ip link add "v$i" netns "$n" type veth peer name "p$i" netns cm-lan
  ip -n cm-lan link set "p$i" master br0 up
  ip -n "$n" addr add "192.168.77.$i/24" dev "v$i" && ip -n "$n" link set "v$i" up
  i=$((i + 1))
done
ip -n cm-mac link add utun9 type veth peer name utun9p && ip -n cm-mac addr add 10.64.0.5/10 dev utun9 && ip -n cm-mac link set utun9 up && ip -n cm-mac link set utun9p up

ip netns exec cm-phone "$PY" -I tools/sectest/fake_adbd.py 192.168.77.2 5555 37099 &
sleep 1
swift build --build-tests -q 2>/dev/null
status=0

echo "== 1. Plaintext adb, tunnel and public targets (from the Mac namespace)"
CM_LAN_PHONE=192.168.77.2 ip netns exec cm-mac swift test --skip-build --filter virtualLANRefusesPlaintextTunnelAndPublicTargets 2>&1 | grep -E "✔ Test run|✘" || status=1

echo "== 2. Attacker scans the Mac while encrypted sessions run"
( for _ in $(seq 40); do ip netns exec cm-mac swift test --skip-build --filter encryptedSessionStreamsVideoAndControl > /dev/null 2>&1; done ) &
SESSIONS=$!
for _ in $(seq 100); do ip netns exec cm-mac ss -Hxl | grep -q cm-f && break; sleep 0.2; done
echo "Mac TCP listeners: $(ip netns exec cm-mac ss -Htln | wc -l)   UDP: $(ip netns exec cm-mac ss -Huln | wc -l)   Unix (cm-f*): $(ip netns exec cm-mac ss -Hxl | grep -c cm-f)"
[ "$(ip netns exec cm-mac ss -Htln | wc -l)" -eq 0 ] || status=1
ip netns exec cm-attacker "$PY" -I tools/sectest/port_scan.py 192.168.77.1 4000 || status=1
kill "$SESSIONS" 2>/dev/null

echo "== 3. Fake tunnel untouched"
tx="$(ip -n cm-mac -s link show utun9 | awk '/TX:/{getline; print $2}')"
echo "utun9 TX packets: $tx"
[ "$tx" = "0" ] || status=1
kill %1 2>/dev/null
echo "RESULT: $([ $status -eq 0 ] && echo PASS || echo FAIL)"
exit "$status"
