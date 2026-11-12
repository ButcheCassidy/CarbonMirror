"""Phase 11 Stage 3.8: property-based fuzzing of the Rust core's C ABI — the exact boundary the Mac app and
the phone server call — with Python `hypothesis` through ctypes on the Linux build of `libcarbon_core.so`.

Usage: python -I ffi_fuzz.py <libcarbon_core.so> <entry> <seconds>      (entries: see ENTRIES)
Each entry runs random, truncated, oversized (length fields up to 2^32-1) and structured inputs until the time
budget is spent. The release build aborts on any panic, so a panic ends the process with a signal (= FAIL).
Also fails on a status outside the documented codes, a call slower than 1 s, or memory growth > 64 MiB.
Prints: entry, examples run, distinct status codes seen, RSS growth.
"""
import ctypes as C
import resource
import struct
import sys
import time

from hypothesis import HealthCheck, given, settings, strategies as st

LIB = C.CDLL(sys.argv[1])
ENTRY, BUDGET = sys.argv[2], float(sys.argv[3])
KNOWN = {0, 1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 14, 15, 16, 17, 30, 31, 32, 33, 34, 50, 60, 61, 70,
         80, 81, 82, 83, 84, 85, 90, 91, 92, 93, 94, 100}
seen = set()
U8P, SZ, SZP, U32P = C.c_char_p, C.c_size_t, C.POINTER(C.c_size_t), C.POINTER(C.c_uint32)


def call(fn, *args):
    start = time.monotonic()
    code = fn(*args)
    if time.monotonic() - start > 1.0:
        raise AssertionError(f"{ENTRY}: call took over 1 s")
    if code not in KNOWN:
        raise AssertionError(f"{ENTRY}: undocumented status {code}")
    seen.add(code)


def out_buf(n=1 << 16):
    return C.create_string_buffer(n)


def video_header(b):
    call(LIB.cm_proto_video_header, b, len(b), out_buf(256))


def device_message(b):
    call(LIB.cm_proto_device_message, b, len(b), out_buf(256))


def device_name(b):
    call(LIB.cm_proto_device_name, b, len(b), C.byref(C.c_size_t()))


def adb_parse_devices(b):
    call(LIB.cm_adb_parse_devices, b, len(b), out_buf(), 1 << 16, C.byref(C.c_size_t()))


def adb_track_frame(b):
    call(LIB.cm_adb_track_frame, b, len(b), C.byref(C.c_size_t()), C.byref(C.c_size_t()))


def net_check_ip(b):
    call(LIB.cm_net_check_ip, b, len(b))


def net_check_endpoint(b):
    port = int.from_bytes(b[:4].ljust(4, b"\0"), "little")
    call(LIB.cm_net_check_endpoint, b[4:], len(b) - min(4, len(b)), C.c_uint32(port))


def adb_validate(b):
    call(LIB.cm_adb_validate, b, len(b), C.c_uint32(b[0] & 3 if b else 0))


def annexb(b):
    call(LIB.cm_annexb_to_avcc, b, len(b), out_buf(len(b) * 2 + 64), len(b) * 2 + 64, C.byref(C.c_size_t()))


def corner_radius(b):
    call(LIB.cm_display_corner_radius, b, len(b), C.byref(C.c_uint32()))


def clipboard(b):
    call(LIB.cm_clipboard_check, b, len(b))


def probe_classify(b):
    call(LIB.cm_adb_probe_classify, b, len(b), C.byref(C.c_uint32()))


def tls_client_parser(b):
    """Hostile 'phone' bytes into the TLS client the probe uses (rustls record + handshake parsing)."""
    session = C.c_void_p()
    call(LIB.cm_tls_capture_new, C.byref(session))
    try:
        sink = out_buf()
        call(LIB.cm_tls_write_tls, session, sink, 1 << 16, C.byref(C.c_size_t()))
        call(LIB.cm_tls_read_tls, session, b, len(b))
    finally:
        LIB.cm_tls_session_free(session)


ENTRIES = {f.__name__: f for f in [video_header, device_message, device_name, adb_parse_devices, adb_track_frame,
                                    net_check_ip, net_check_endpoint, adb_validate, annexb, corner_radius,
                                    clipboard, probe_classify, tls_client_parser]}

# Raw bytes, plus inputs shaped like real messages with hostile length fields (up to 2^32-1).
lengths = st.sampled_from([0, 1, 255, 256, 65535, 1 << 20, (1 << 20) + 1, 1 << 23, (1 << 31) - 1, (1 << 32) - 1]) | st.integers(0, (1 << 32) - 1)
structured = st.one_of(
    st.builds(lambda t, n, tail: bytes([t]) + struct.pack(">I", n) + tail, st.integers(0, 255), lengths, st.binary(max_size=64)),
    st.builds(lambda pts, n, tail: struct.pack(">QI", pts, n) + tail, st.integers(0, (1 << 64) - 1), lengths, st.binary(max_size=64)),
    st.builds(lambda t, v, n, tail: bytes([t, 3, v]) + struct.pack(">H", n & 0xFFFF) + tail, st.sampled_from([20, 21, 22, 23, 24]),
              st.integers(0, 4), lengths, st.binary(max_size=128)),
    st.text(max_size=300).map(lambda s: s.encode("utf-8", "surrogatepass")),
)
inputs = st.binary(max_size=8192) | structured


@settings(max_examples=2000, deadline=None, database=None, suppress_health_check=list(HealthCheck))
@given(inputs)
def fuzz_once(b):
    ENTRIES[ENTRY](b)


def rss_mib():
    with open("/proc/self/statm") as f:
        return int(f.read().split()[1]) * resource.getpagesize() / (1 << 20)


def main():
    end = time.monotonic() + BUDGET
    runs, baseline = 0, None
    while time.monotonic() < end:
        fuzz_once()
        runs += 2000
        if baseline is None:
            baseline = rss_mib()
    growth = rss_mib() - (baseline or rss_mib())
    print(f"PASS  {ENTRY:20} {runs:8d} examples  statuses {sorted(seen)}  RSS growth {growth:+.1f} MiB")
    if growth > 64:
        print(f"FAIL  {ENTRY}: memory grew {growth:.1f} MiB")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
