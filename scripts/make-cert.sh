#!/usr/bin/env bash
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
# One-time: creates the local "CarbonMirror Dev" code-signing identity (spec 10.4 Step A).
# ECDSA P-384 / SHA-384, code signing only, 5 years, imported non-extractable and usable only by codesign.
# If codesign rejects the P-384 key, the identity is deleted and recreated with RSA-4096 / SHA-384.
set -euo pipefail

NAME="${CM_SIGN_IDENTITY:-CarbonMirror Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
[ "$(uname -s)" = "Darwin" ] || { echo "make-cert.sh: run this on the Mac." >&2; exit 1; }

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
  echo "\"$NAME\" already exists — nothing to do."
  security find-identity -p codesigning
  exit 0
fi

WORK="$(mktemp -d)"
chmod 700 "$WORK"
trap 'rm -rf "$WORK"; unset CM_P12_PASS' EXIT
cd "$WORK"

make_identity() {
  local algorithm="$1"
  printf '[req]\ndistinguished_name=dn\nprompt=no\n[dn]\nCN=%s\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' "$NAME" > cm-cert.cnf
  if [ "$algorithm" = "p384" ]; then
    /usr/bin/openssl ecparam -name secp384r1 -genkey -noout -out cm-key.pem
    /usr/bin/openssl req -x509 -new -key cm-key.pem -sha384 -days 1825 -config cm-cert.cnf -extensions ext -out cm-cert.pem
  else
    /usr/bin/openssl req -x509 -newkey rsa:4096 -nodes -keyout cm-key.pem -sha384 -days 1825 -config cm-cert.cnf -extensions ext -out cm-cert.pem
  fi
  CM_P12_PASS="$(/usr/bin/openssl rand -hex 32)"
  export CM_P12_PASS
  /usr/bin/openssl pkcs12 -export -inkey cm-key.pem -in cm-cert.pem -name "$NAME" -passout env:CM_P12_PASS -out cm-cert.p12
  security import cm-cert.p12 -k "$KEYCHAIN" -P "$CM_P12_PASS" -x -T /usr/bin/codesign
  unset CM_P12_PASS
  rm -f cm-key.pem cm-cert.pem cm-cert.p12 cm-cert.cnf
}

codesign_works() {
  cp /usr/bin/true cm-sign-test
  codesign --force --sign "$NAME" cm-sign-test && codesign --verify --verbose=2 cm-sign-test
  local ok=$?
  rm -f cm-sign-test
  return $ok
}

make_identity p384
if codesign_works; then
  echo "\"$NAME\" created with ECDSA P-384 / SHA-384."
else
  echo "codesign rejected the P-384 key; recreating with RSA-4096 / SHA-384." >&2
  security delete-identity -c "$NAME"
  make_identity rsa
  codesign_works
  echo "\"$NAME\" created with RSA-4096 / SHA-384 (fallback)."
fi
security find-identity -p codesigning
