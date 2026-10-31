#!/bin/bash
# App Store ekran görüntüleri.
#   tool/take_screenshots.sh <simulator-udid> <çıktı-klasörü> [portrait|landscape]
# Simülatörü açar, durum çubuğunu 9:41/tam şarj olarak sabitler, entegrasyon
# testini sürer ve testin istediği anlarda `simctl io screenshot` ile çeker.
set -u
UDID="$1"; OUT="$2"; ORIENT="${3:-portrait}"
mkdir -p "$OUT"
rm -f /tmp/shot_req /tmp/shot_done
xcrun simctl boot "$UDID" 2>/dev/null
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged \
  --batteryLevel 100 --cellularMode active --cellularBars 4 --wifiBars 3 >/dev/null 2>&1
(
  while true; do
    if [ -f /tmp/shot_req ]; then
      name=$(cat /tmp/shot_req); rm -f /tmp/shot_req
      if [ "$name" = "__bitti__" ]; then exit 0; fi
      sleep 0.4
      xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
      touch /tmp/shot_done
    fi
    sleep 0.2
  done
) &
WATCH=$!
flutter test integration_test/screenshots_test.dart -d "$UDID" --dart-define=ORIENTATION="$ORIENT" 2>&1 | tail -25
kill $WATCH 2>/dev/null
ls -la "$OUT"
