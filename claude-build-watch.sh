#!/bin/bash
# Build/test watcher for the Claude session (v4).
# Leave this running in Terminal. Ctrl-C to stop.
# Nothing is committed, pushed or installed.

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJ="$ROOT/AI-Reply"
cd "$PROJ" || exit 1

date '+v4 started %H:%M:%S' > "$ROOT/.watcher-v4"

pick_sim() {
  xcrun simctl list devices available \
    | sed -n 's/^ *\(iPhone [^(]*\) (\([0-9A-Fa-f-]\{36\}\)).*/\2/p' \
    | head -1
}

echo "Watching $PROJ   (v4)"
echo "  build -> $ROOT/ios-build.log"
echo "  test  -> $ROOT/ios-test.log"
echo "If another copy of this script is still running in a different Terminal"
echo "window, close that one — two watchers fight over the same request files."
echo

while true; do
  if [ -f "$ROOT/.build-request" ]; then
    rm -f "$ROOT/.build-request" "$ROOT/.build-done"
    echo "$(date '+%H:%M:%S')  building..."
    xcodebuild -project AIReply.xcodeproj -scheme AIReply \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath build/SimDerivedData \
      CODE_SIGNING_ALLOWED=NO build > "$ROOT/ios-build.log" 2>&1
    grep -c "error:" "$ROOT/ios-build.log" > "$ROOT/.build-done"
    echo "$(date '+%H:%M:%S')  build done — $(cat "$ROOT/.build-done") error line(s)"
  fi

  # Deliberately a name the older versions of this script do not know, so a
  # stale watcher cannot swallow the request.
  if [ -f "$ROOT/.claude-test" ]; then
    rm -f "$ROOT/.claude-test" "$ROOT/.claude-test-done"
    SIM="$(pick_sim)"
    echo "$(date '+%H:%M:%S')  testing on simulator id $SIM ..."
    xcodebuild -project AIReply.xcodeproj -scheme AIReply \
      -destination "id=$SIM" \
      -derivedDataPath build/SimDerivedData \
      CODE_SIGNING_ALLOWED=NO test > "$ROOT/ios-test.log" 2>&1
    echo "xcodebuild exit=$?" >> "$ROOT/ios-test.log"
    date '+%H:%M:%S' > "$ROOT/.claude-test-done"
    echo "$(date '+%H:%M:%S')  test done"
  fi

  sleep 2
done
