#!/usr/bin/env bash
# Puts real sample photos on an iPhone simulator, then walks the app (UI test) while recording the screen.
set -euo pipefail
UDID="$1"
OUT="${2:-build/shots}"
BUNDLE=com.stproperties.photofolders
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
mkdir -p "$OUT_ABS" build/sample

# Sample photos (Unsplash via picsum, fixed ids): dogs, cats, food, landscapes, sea, city, people...
IDS="237 1025 1062 659 169 40 219 1074 1084 1003 1024 1069 1080 292 429 1060 425 488 312 30 29 1018 1036 1015 1039 1043 1044 1050 1051 10 11 12 13 14 15 16 17 18 19 20 22 24 26 28 1016 1019 1020 1029 1031 1033 1035 1040 1047 1048 1055 1059 1067 1068 1070 1076"
for id in $IDS; do
  curl -sfL --retry 3 -o "build/sample/p$id.jpg" "https://picsum.photos/id/$id/1200/900" || echo "skip $id"
done
echo "sample photos: $(ls build/sample | wc -l)"

# Real labels from Apple's classifier on this Mac (the simulator's own classifier is a stand-in).
swift scripts/mac_classify.swift build/sample > "$OUT_ABS/sim-labels.json" 2> "$OUT_ABS/mac-labels.txt" || echo "mac classify failed"
head -20 "$OUT_ABS/mac-labels.txt" || true

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl addmedia "$UDID" build/sample/*.jpg
xcrun simctl install "$UDID" build/dd/Build/Products/Debug-iphonesimulator/PhotoFolders.app
DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
mkdir -p "$DATA/Documents" && cp "$OUT_ABS/sim-labels.json" "$DATA/Documents/sim-labels.json" && echo "real labels placed"
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 || true

xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT_ABS/walk.mp4" &
REC=$!
sleep 2
# If the app ever stalls, these show exactly where every thread is.
for at in 110 220; do
  ( sleep $at; PID=$(pgrep -f "PhotoFolders.app/PhotoFolders" | head -1)
    [ -n "$PID" ] && sample "$PID" 4 -file "$OUT_ABS/sample-${at}s.txt" >/dev/null 2>&1 ) &
done
set +e
TEST_RUNNER_SHOTS_DIR="$OUT_ABS" xcodebuild test-without-building -project PhotoFolders.xcodeproj -scheme PhotoFolders \
  -destination "id=$UDID" -derivedDataPath build/dd -only-testing:PhotoFoldersUITests \
  -resultBundlePath build/walk.xcresult CODE_SIGNING_ALLOWED=NO > build/walk.log 2>&1
RESULT=$?
set -e
kill -INT $REC || true
wait $REC || true
grep -E "Test Case|error|XCTAssert|failed" build/walk.log | tail -20 || true

xcrun simctl spawn "$UDID" log show --info --style compact --last 20m --predicate 'subsystem == "com.stproperties.photofolders"' > "$OUT_ABS/app.log" 2>&1 || true
DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)
[ -n "$DATA" ] && cp "$DATA/Library/Application Support/PhotoFolders/index.json" "$OUT_ABS/index.json" 2>/dev/null || echo "no index file"
ls -la "$OUT_ABS"
exit $RESULT
