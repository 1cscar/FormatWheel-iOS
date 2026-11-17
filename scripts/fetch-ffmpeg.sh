#!/usr/bin/env bash
# Downloads the prebuilt FWFFmpeg / WebP XCFrameworks from this repository's GitHub Release
# "$FFMPEG_TAG" (published by .github/workflows/ffmpeg.yml) into Vendor/FFmpeg/.
#
# Usage: scripts/fetch-ffmpeg.sh [--build-if-missing] [--force]
# Repo:  $FW_FFMPEG_REPO, else $GITHUB_REPOSITORY, else the `origin` remote.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=ffmpeg-versions.env
source "$ROOT/scripts/ffmpeg-versions.env"
OUT="$ROOT/Vendor/FFmpeg"
BUILD_IF_MISSING=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --build-if-missing) BUILD_IF_MISSING=1 ;;
    --force) FORCE=1 ;;
    *) echo "unknown option $arg" >&2; exit 2 ;;
  esac
done

if [ "$FORCE" = 0 ] && [ -d "$OUT/FWFFmpeg.xcframework" ] && [ -d "$OUT/WebP.xcframework" ] &&
   grep -qx "FFMPEG_VERSION=$FFMPEG_VERSION" "$OUT/VERSION" 2>/dev/null; then
  echo "Vendor/FFmpeg already has FFmpeg $FFMPEG_VERSION"
  exit 0
fi

REPO="${FW_FFMPEG_REPO:-${GITHUB_REPOSITORY:-}}"
if [ -z "$REPO" ]; then
  REPO="$(git -C "$ROOT" remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
fi
[ -n "$REPO" ] || { echo "cannot tell which GitHub repository to download from; set FW_FFMPEG_REPO=owner/name" >&2; exit 1; }

BASE="https://github.com/$REPO/releases/download/$FFMPEG_TAG"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

download() {
  curl -fsSL --retry 4 --retry-delay 3 -o "$TMP/$1" "$BASE/$1"
}

echo "Fetching $FFMPEG_TAG from $REPO"
if ! download SHA256SUMS; then
  if [ "$BUILD_IF_MISSING" = 1 ]; then
    echo "Release $FFMPEG_TAG not found; building from source (takes a while)"
    exec "$ROOT/scripts/build-ffmpeg.sh"
  fi
  echo "Release $FFMPEG_TAG not found in $REPO. Run the 'FFmpeg xcframeworks' workflow first," >&2
  echo "or build locally with scripts/build-ffmpeg.sh." >&2
  exit 1
fi
download FWFFmpeg.xcframework.zip
download WebP.xcframework.zip
(cd "$TMP" && shasum -a 256 -c SHA256SUMS)

rm -rf "$OUT/FWFFmpeg.xcframework" "$OUT/WebP.xcframework"
mkdir -p "$OUT"
ditto -x -k "$TMP/FWFFmpeg.xcframework.zip" "$OUT"
ditto -x -k "$TMP/WebP.xcframework.zip" "$OUT"
grep -E '^[A-Z0-9_]+=' "$ROOT/scripts/ffmpeg-versions.env" | grep -v FFMPEG_TAG > "$OUT/VERSION"
echo "Installed into $OUT"
