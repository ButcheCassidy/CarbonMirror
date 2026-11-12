#!/usr/bin/env bash
# JVM tests of the companion's pure logic (subnet keys, Wireless debugging decisions) against android.jar.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd "$ROOT"
: "${ANDROID_HOME:?set ANDROID_HOME to the Android SDK}"
JAR="$ANDROID_HOME/platforms/${ANDROID_PLATFORM:-android-36}/android.jar"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
javac --release 17 -Xlint:all -Werror -encoding UTF-8 -classpath "$JAR" -d "$OUT" -implicit:none \
  companion/src/com/nomadicrebel/carbonmirror/companion/TrustedNetworks.java \
  companion/src/com/nomadicrebel/carbonmirror/companion/ReadyService.java \
  companion/src/com/nomadicrebel/carbonmirror/companion/WirelessDebugging.java \
  companion/src/com/nomadicrebel/carbonmirror/companion/StartReceiver.java \
  companion/src/com/nomadicrebel/carbonmirror/companion/MainActivity.java \
  companion/src/com/nomadicrebel/carbonmirror/companion/WirelessDebuggingTile.java \
  companion/test/CompanionTest.java -sourcepath companion/build/gen
java -ea -cp "$OUT:$JAR" com.nomadicrebel.carbonmirror.companion.CompanionTest
