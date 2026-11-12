#!/usr/bin/env bash
# Phase 11 Stage 3.1/3.2: attacks the phone-side inner TLS policy with a foreign TLS stack (OpenSSL).
# Every attempt must be refused: old protocol versions, weak or non-allowed suites, non-allowed groups, and
# a correct TLS 1.3 client without the pinned Mac certificate (mutual authentication). Exit 0 = all refused.
set -uo pipefail

# Find the repository whether the script is run, sourced or started from another folder.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." 2>/dev/null && pwd)"
[ -f "$ROOT/Package.swift" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -f "$ROOT/Package.swift" ] || { echo "Open Terminal in the CarbonMirror folder and run: bash tools/sectest/tls_downgrade.sh" >&2; exit 1; }
cd "$ROOT"
PORT="${1:-47311}"
cargo build -q --release --example tls_endpoint --manifest-path rust/Cargo.toml || exit 1
LOG="$(mktemp)"
rust/target/release/examples/tls_endpoint "$PORT" > "$LOG" &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null; rm -f "$LOG"' EXIT
for _ in $(seq 50); do grep -q LISTENING "$LOG" && break; sleep 0.1; done

attacks=(
  "TLS 1.0|-tls1"
  "TLS 1.1|-tls1_1"
  "TLS 1.2 strong suite|-tls1_2 -cipher ECDHE-ECDSA-AES256-GCM-SHA384"
  "TLS 1.2 any suite|-tls1_2"
  "TLS 1.3 AES-128-GCM only|-tls1_3 -ciphersuites TLS_AES_128_GCM_SHA256"
  "TLS 1.3 P-256 group only|-tls1_3 -groups P-256"
  "TLS 1.3 allowed suite, no ALPN, no client cert|-tls1_3 -ciphersuites TLS_AES_256_GCM_SHA384 -groups X25519"
  "TLS 1.3 allowed suite + ALPN, no client cert|-tls1_3 -ciphersuites TLS_AES_256_GCM_SHA384 -groups X25519 -alpn carbonmirror/1"
)

failed=0
for attack in "${attacks[@]}"; do
  name="${attack%%|*}"
  flags="${attack#*|}"
  before=$(wc -l < "$LOG")
  # shellcheck disable=SC2086
  echo | timeout 10 openssl s_client -connect "127.0.0.1:$PORT" $flags -servername phone > /dev/null 2>&1
  for _ in $(seq 30); do [ "$(wc -l < "$LOG")" -gt "$before" ] && break; sleep 0.1; done
  verdict="$(sed -n "$((before + 1))p" "$LOG")"
  if [[ "$verdict" == REFUSED* ]]; then
    printf 'PASS  %-50s server: %s\n' "$name" "$verdict"
  else
    printf 'FAIL  %-50s server: %s\n' "$name" "${verdict:-no verdict}"
    failed=1
  fi
done
openssl version
exit "$failed"
