#!/usr/bin/env bash
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
# Attack: a local process listens where adb looks for emulators (127.0.0.1:5555–5585) and waits for the adb
# server to connect in plaintext. With CarbonMirror's adb environment the server must never connect, and
# must open no UDP (mDNS) socket. Uses the real adb from the Android SDK. Exit 0 = safe.
set -euo pipefail
ADB="${ANDROID_HOME:?set ANDROID_HOME}/platform-tools/adb"
DIR="$(mktemp -d)"
trap 'env -i HOME="$DIR" PATH=/usr/bin:/bin ADB_SERVER_SOCKET="localfilesystem:$DIR/cm-adb" "$ADB" kill-server >/dev/null 2>&1 || true; rm -rf "$DIR"' EXIT
run_adb() { env -i HOME="$DIR" ANDROID_USER_HOME="$DIR" TMPDIR="$DIR" PATH=/usr/bin:/bin ADB_SERVER_SOCKET="localfilesystem:$DIR/cm-adb" ADB_EMU=0 ADB_MDNS=0 "$ADB" "$@"; }

python3 - > "$DIR/hits" <<'PY' &
import socket, threading
hits = []
def serve(port):
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", port)); s.listen(4); s.settimeout(6)
    try:
        while True:
            c, _ = s.accept(); hits.append(port); c.close()
    except socket.timeout:
        pass
threads = [threading.Thread(target=serve, args=(p,)) for p in range(5555, 5586, 2)]
[t.start() for t in threads]; [t.join() for t in threads]
print(len(hits))
PY
sleep 1
run_adb start-server >/dev/null 2>&1
sleep 3
udp="$(ss -lunp 2>/dev/null | grep -c '"adb"' || true)"
devices="$(run_adb devices -l | grep -c 'emulator-' || true)"
wait %1
hits="$(cat "$DIR/hits")"
echo "emulator-port connections from adb: $hits (expected 0)"
echo "emulator devices listed: $devices (expected 0)"
echo "adb UDP sockets: $udp (expected 0)"
[ "$hits" = 0 ] && [ "$devices" = 0 ] && [ "$udp" = 0 ] && echo "PASS adb local exposure"
