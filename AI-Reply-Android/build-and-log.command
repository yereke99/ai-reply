#!/bin/bash
# Builds AI Reply and writes everything to build.log next to this script.
# Double-click it in Finder, or run ./build-and-log.command in Terminal.
cd "$(dirname "$0")" || exit 1

# Android Studio ships a JDK 17+; the system `java` on macOS is often older or
# absent, and AGP 8.7 requires 17.
for candidate in \
  "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
  "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
  "$(/usr/libexec/java_home -v 17 2>/dev/null)" \
  "$(/usr/libexec/java_home 2>/dev/null)"; do
  if [ -x "$candidate/bin/java" ]; then export JAVA_HOME="$candidate"; break; fi
done

# The SDK location, if Android Studio has not written local.properties yet.
if [ ! -f local.properties ] && [ -d "$HOME/Library/Android/sdk" ]; then
  echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties
fi

{
  echo "=== $(date) ==="
  echo "JAVA_HOME=$JAVA_HOME"
  "$JAVA_HOME/bin/java" -version 2>&1
  echo "ANDROID_SDK=$HOME/Library/Android/sdk"
  echo
  chmod +x gradlew
  ./gradlew --no-daemon assembleDebug testDebugUnitTest 2>&1
  echo "GRADLE_EXIT=$?"
} > build.log 2>&1

echo "Done. See build.log"
