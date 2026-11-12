# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
"""Plaintext `adb tcpip`-style endpoint for the virtual LAN: answers any CNXN with a CNXN (no STLS).
Usage: python -I fake_adbd.py <ip> <port> [<port> ...]"""
import socket
import struct
import sys
import threading

CNXN = 0x4E584E43


def serve(ip: str, port: int) -> None:
    listener = socket.create_server((ip, port))
    while True:
        conn, _ = listener.accept()
        with conn:
            conn.recv(4096)
            banner = b"device::ro.product.name=virtual;\0"
            header = struct.pack("<6I", CNXN, 0x01000001, 256 * 1024, len(banner), sum(banner) & 0xFFFFFFFF, CNXN ^ 0xFFFFFFFF)
            conn.sendall(header + banner)


for p in sys.argv[2:]:
    threading.Thread(target=serve, args=(sys.argv[1], int(p)), daemon=True).start()
threading.Event().wait()
