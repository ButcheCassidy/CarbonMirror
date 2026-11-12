"""Phase 11 Stage 3.3: scans a packet capture of a mirroring session for anything readable.

Usage: python -I capture_scan.py <capture.pcap | tap directory> <marker> [<marker> ...]
A pcap is reassembled per TCP flow; a directory holds one raw file per socket direction (the session's
Unix sockets, recorded by the tests' TapStream). Reports per flow: bytes, Shannon entropy (bits/byte),
H.264/H.265 Annex B start codes, and any marker string (device name, clipboard text, typed text).
Exit 0 = nothing readable: no marker anywhere, no start codes, every flow ≥ 4 KiB above 7.5 bits/byte.
"""
import collections
import math
import os
import socket
import sys

import dpkt

MIN_ENTROPY = 7.5
MIN_FLOW = 4096


def entropy(data: bytes) -> float:
    counts = collections.Counter(data)
    return -sum(c / len(data) * math.log2(c / len(data)) for c in counts.values()) if data else 0.0


def flows(path: str) -> dict:
    if os.path.isdir(path):
        return {name: bytearray(open(os.path.join(path, name), "rb").read()) for name in os.listdir(path)}
    out = collections.defaultdict(bytearray)
    with open(path, "rb") as f:
        for _, raw in dpkt.pcap.Reader(f):
            try:
                ip = dpkt.ethernet.Ethernet(raw).data
            except dpkt.UnpackError:
                continue
            if isinstance(ip, (dpkt.ip.IP, dpkt.ip6.IP6)) and isinstance(ip.data, dpkt.tcp.TCP) and ip.data.data:
                family = socket.AF_INET6 if isinstance(ip, dpkt.ip6.IP6) else socket.AF_INET
                key = f"{socket.inet_ntop(family, ip.src)}:{ip.data.sport} -> {socket.inet_ntop(family, ip.dst)}:{ip.data.dport}"
                out[key] += ip.data.data
    return out


def main() -> int:
    path, markers = sys.argv[1], [m.encode() for m in sys.argv[2:]]
    readable = False
    for key, data in sorted(flows(path).items()):
        data = bytes(data)
        found = [m.decode() for m in markers if m in data]
        start_codes = data.count(b"\x00\x00\x00\x01")
        e = entropy(data)
        low = len(data) >= MIN_FLOW and e < MIN_ENTROPY
        bad = bool(found) or start_codes > 0 or low
        readable |= bad
        print(f"{'READABLE' if bad else 'ok      '} {key:52} {len(data):9d} B  entropy {e:4.2f}  start codes {start_codes:4d}  markers {found}")
    print("RESULT:", "plaintext found" if readable else "nothing readable")
    return 1 if readable else 0


if __name__ == "__main__":
    sys.exit(main())
