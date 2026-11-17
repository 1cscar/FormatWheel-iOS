#!/usr/bin/env bash
# Compiles upstream/Sources/Catalog.swift (unmodified) with a tiny shim on macOS and writes its behaviour
# for every parity scenario to build/parity/upstream-catalog.json. Tests/CoreTests/CatalogParityTests
# replays the same scenarios on FormatWheelCore and fails on any difference.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/parity"
mkdir -p "$OUT"
SHA="$(grep -oE '[0-9a-f]{40}' "$ROOT/upstream/UPSTREAM.md" | head -1)"
xcrun --sdk macosx swiftc -O -swift-version 5 -module-name UpstreamCatalog \
  -o "$OUT/dump-upstream-catalog" \
  "$ROOT/upstream/Sources/Catalog.swift" "$ROOT/scripts/catalog-parity/Shim.swift" "$ROOT/scripts/catalog-parity/main.swift" \
  2> >(grep -v 'warning:' >&2 || true)
"$OUT/dump-upstream-catalog" "$SHA" > "$OUT/upstream-catalog.json"
echo "wrote $OUT/upstream-catalog.json"
