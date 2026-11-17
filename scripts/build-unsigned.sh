#!/usr/bin/env bash
# Unsigned Release build for real devices, then packs FormatWheel.ipa / .tipa into dist/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -d FormatWheel.xcodeproj ] || xcodegen generate
SCHEME="${SCHEME:-FormatWheel}"
xcodebuild build \
  -project FormatWheel.xcodeproj -scheme "$SCHEME" -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  -quiet
"$ROOT/scripts/package-ipa.sh" "build/DerivedData/Build/Products/Release-iphoneos/FormatWheel.app" "$ROOT/dist" "${IPA_NAME:-FormatWheel}"
