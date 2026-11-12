#!/usr/bin/env bash
# Builds the forked scrcpy-server without Gradle (javac → d8, like scrcpy's build_without_gradle.sh) and
# libcarbon_core.so for the phone (cargo ndk, arm64-v8a, API 30). Outputs:
#   Resources/carbonmirror-server   (jar with classes.dex)
#   Resources/libcarbon_core.so
# Needs: JDK 17+, ANDROID_HOME with platforms/android-36 + build-tools/36.0.0, ANDROID_NDK_HOME, cargo-ndk.
# Nothing is downloaded here; SDK pieces are installed once by scripts/setup-env.sh (Linux) or by hand (Mac).
set -euo pipefail

# Find the repository whether the script is run, sourced or started from another folder.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"
[ -f "$ROOT/Package.swift" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -f "$ROOT/Package.swift" ] || { echo "Open Terminal in the CarbonMirror folder and run: bash scripts/build-server.sh" >&2; exit 1; }
cd "$ROOT"

SERVER_VERSION="$(grep -A1 '<key>CFBundleShortVersionString</key>' Resources/Info.plist | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')"
PLATFORM="${ANDROID_PLATFORM:-android-36}"
BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-36.0.0}"
: "${ANDROID_HOME:?set ANDROID_HOME to the Android SDK}"
ANDROID_JAR="$ANDROID_HOME/platforms/$PLATFORM/android.jar"
ANDROID_AIDL="$ANDROID_HOME/platforms/$PLATFORM/framework.aidl"
BT="$ANDROID_HOME/build-tools/$BUILD_TOOLS"
LAMBDA_JAR="$BT/core-lambda-stubs.jar"
for f in "$ANDROID_JAR" "$ANDROID_AIDL" "$BT/d8" "$BT/aidl" "$LAMBDA_JAR"; do
  [ -e "$f" ] || { echo "build-server.sh: missing $f" >&2; exit 1; }
done

BUILD="$ROOT/server/build"
CLASSES="$BUILD/classes"
GEN="$BUILD/gen"
rm -rf "$BUILD"
mkdir -p "$CLASSES" "$GEN/com/genymobile/scrcpy" Resources

echo "==> Server version $SERVER_VERSION ($PLATFORM, build-tools $BUILD_TOOLS)"
cat > "$GEN/com/genymobile/scrcpy/BuildConfig.java" <<EOF
package com.genymobile.scrcpy;

public final class BuildConfig {
  public static final boolean DEBUG = false;
  public static final String VERSION_NAME = "$SERVER_VERSION";
}
EOF

echo "==> AIDL"
(cd server/src/main/aidl &&
  "$BT/aidl" -o"$GEN" -I. android/content/IOnPrimaryClipChangedListener.aidl &&
  "$BT/aidl" -o"$GEN" -I. -p "$ANDROID_AIDL" android/view/IDisplayWindowListener.aidl)

echo "==> javac"
(cd server/src/main/java &&
  find . -name '*.java' > "$BUILD/sources.txt" &&
  javac -encoding UTF-8 -Xlint:-options -bootclasspath "$ANDROID_JAR" -cp "$LAMBDA_JAR:$GEN" \
    -d "$CLASSES" -source 1.8 -target 1.8 @"$BUILD/sources.txt")

echo "==> d8"
(cd "$CLASSES" &&
  find . -name '*.class' > "$BUILD/classes.txt" &&
  "$BT/d8" --release --min-api 30 --classpath "$ANDROID_JAR" --output "$BUILD/classes.zip" @"$BUILD/classes.txt")
cp "$BUILD/classes.zip" Resources/carbonmirror-server

echo "==> libcarbon_core.so (arm64-v8a, API 30)"
(cd rust/carbon-core && cargo ndk -t arm64-v8a -P 30 -o "$BUILD/jniLibs" build --release)
cp "$BUILD/jniLibs/arm64-v8a/libcarbon_core.so" Resources/libcarbon_core.so

rm -rf "$GEN" "$CLASSES"
echo "==> SHA-256"
if command -v sha256sum >/dev/null; then
  sha256sum Resources/carbonmirror-server Resources/libcarbon_core.so
else
  shasum -a 256 Resources/carbonmirror-server Resources/libcarbon_core.so
fi
