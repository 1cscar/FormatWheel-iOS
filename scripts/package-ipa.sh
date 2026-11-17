#!/usr/bin/env bash
# Packs an unsigned Release-iphoneos build into sideloadable archives:
#   <out>/<name>.ipa   for AltStore / SideStore / manual signing (they re-sign it)
#   <out>/<name>.tipa  for TrollStore (same payload, pseudo-signed with ldid + entitlements)
#
# Usage: scripts/package-ipa.sh <path/to/FormatWheel.app> [out-dir] [name]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?usage: package-ipa.sh <App.app> [out-dir] [name]}"
OUTDIR="${2:-$ROOT/dist}"
NAME="${3:-FormatWheel}"
ENTITLEMENTS="${ENTITLEMENTS:-$ROOT/App/FormatWheel.entitlements}"
command -v ldid >/dev/null || { echo "ldid not found (brew install ldid)" >&2; exit 1; }
[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload" "$OUTDIR"
cp -R "$APP" "$STAGE/Payload/"
BUNDLE="$STAGE/Payload/$(basename "$APP")"
EXEC="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$BUNDLE/Info.plist")"

# Frameworks and app extensions first (inside-out), then the main executable with entitlements.
if [ -d "$BUNDLE/Frameworks" ]; then
  find "$BUNDLE/Frameworks" -maxdepth 1 -name '*.framework' | while read -r fw; do
    bin="$fw/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$fw/Info.plist")"
    ldid -S "$bin"
  done
  find "$BUNDLE/Frameworks" -maxdepth 1 -name '*.dylib' -exec ldid -S {} \;
fi
if [ -d "$BUNDLE/PlugIns" ]; then
  find "$BUNDLE/PlugIns" -maxdepth 1 -name '*.appex' | while read -r ext; do
    ent="$ROOT/App/ShareExtension/ShareExtension.entitlements"
    bin="$ext/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$ext/Info.plist")"
    if [ -f "$ent" ]; then ldid -S"$ent" "$bin"; else ldid -S "$bin"; fi
  done
fi
ldid -S"$ENTITLEMENTS" "$BUNDLE/$EXEC"
rm -rf "$BUNDLE/_CodeSignature" 2>/dev/null || true
ldid -S"$ENTITLEMENTS" "$BUNDLE/$EXEC"

(cd "$STAGE" && zip -qry -X "$OUTDIR/$NAME.ipa" Payload)
cp "$OUTDIR/$NAME.ipa" "$OUTDIR/$NAME.tipa"
ls -lh "$OUTDIR/$NAME.ipa" "$OUTDIR/$NAME.tipa"
