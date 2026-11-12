"""Rate-limited TCP connect scan of every port on one host (the attacker's view of the Mac).
Usage: python -I port_scan.py <ip> [rate per second]   Exit 0 = no port open."""
import asyncio
import sys

HOST, RATE = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 4000


async def probe(port: int, open_ports: list) -> None:
    try:
        _, writer = await asyncio.wait_for(asyncio.open_connection(HOST, port), 0.5)
        open_ports.append(port)
        writer.close()
    except (OSError, asyncio.TimeoutError):
        pass


async def main() -> int:
    open_ports: list = []
    tasks = []
    for port in range(1, 65536):
        tasks.append(asyncio.create_task(probe(port, open_ports)))
        if port % RATE == 0:
            await asyncio.sleep(1)
    await asyncio.gather(*tasks)
    print(f"scanned 65535 TCP ports on {HOST}: open {sorted(open_ports) or 'none'}")
    return 1 if open_ports else 0


sys.exit(asyncio.run(main()))
