#!/usr/bin/env bash
# Runs the unit tests on an available iPhone simulator (override with SIM_UDID=... or SIM_NAME=...).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -d FormatWheel.xcodeproj ] || xcodegen generate

UDID="${SIM_UDID:-$(xcrun simctl list devices available -j | python3 -c '
import json, os, sys
want = os.environ.get("SIM_NAME", "iPhone")
devs = [d for rt, ds in json.load(sys.stdin)["devices"].items() if "iOS" in rt for d in ds if d["name"].startswith(want)]
devs.sort(key=lambda d: (d["state"] != "Booted", d["name"]))
print(devs[0]["udid"] if devs else "")
')}"
[ -n "$UDID" ] || { echo "no available iOS simulator" >&2; xcrun simctl list devices available; exit 1; }
echo "Testing on simulator $UDID"

xcodebuild test \
  -project FormatWheel.xcodeproj -scheme FormatWheel \
  -destination "id=$UDID" \
  -derivedDataPath build/DerivedData \
  -resultBundlePath "build/TestResults-$(date +%s).xcresult" \
  CODE_SIGNING_ALLOWED=NO "$@"
