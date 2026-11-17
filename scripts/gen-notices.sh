#!/usr/bin/env bash
# Regenerates THIRD_PARTY_NOTICES.md with the full license texts of every bundled component.
# Needs the source trees that scripts/build-ffmpeg.sh downloads (build/ffmpeg/src).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=ffmpeg-versions.env
source "$ROOT/scripts/ffmpeg-versions.env"
SRC="${WORK:-$ROOT/build/ffmpeg}/src"
OUT="$ROOT/THIRD_PARTY_NOTICES.md"
[ -d "$SRC/ffmpeg" ] || { echo "run scripts/build-ffmpeg.sh first (needs $SRC)" >&2; exit 1; }

section() { # title file...
  local title="$1"; shift
  printf '\n### %s\n\n' "$title"
  for f in "$@"; do
    printf '<details><summary><code>%s</code></summary>\n\n```text\n' "$(basename "$f")"
    cat "$f"
    printf '\n```\n\n</details>\n'
  done
}

{
cat <<HEAD
# Third-party notices

FormatWheel iOS is MIT-licensed (see \`LICENSE\`). It bundles the components below. All of them are
compatible with distributing the app under MIT; none is GPL or non-free (x264, x265 and fdk-aac are
deliberately **not** included).

| Component | Version | License | How it is used |
|---|---|---|---|
| [FFmpeg](https://ffmpeg.org) | $FFMPEG_VERSION | LGPL-2.1-or-later | Inside \`FWFFmpeg.framework\`, **dynamically linked** |
| [LAME](https://lame.sourceforge.io) | $LAME_VERSION | LGPL-2.0-or-later | MP3 encoder, inside \`FWFFmpeg.framework\` (dynamic) |
| [Opus](https://opus-codec.org) | $OPUS_VERSION | BSD-3-Clause | inside \`FWFFmpeg.framework\` |
| [libvpx](https://chromium.googlesource.com/webm/libvpx) | $LIBVPX_VERSION | BSD-3-Clause + patent grant | VP8/VP9 (WebM), inside \`FWFFmpeg.framework\` |
| [SVT-AV1](https://gitlab.com/AOMediaCodec/SVT-AV1) | $SVTAV1_VERSION | BSD-3-Clause-Clear + AOMedia Patent License 1.0 | AV1 / AVIF encoder, inside \`FWFFmpeg.framework\` |
| [libwebp](https://chromium.googlesource.com/webm/libwebp) | $LIBWEBP_VERSION | BSD-3-Clause + patent grant | inside \`FWFFmpeg.framework\` and statically in the app (\`WebP.xcframework\`) |
| [FormatWheel (macOS)](https://github.com/Elise616/FormatWheel) | 1eb19a1 | MIT | the original app this project ports (see \`LICENSE\`) |

## FFmpeg and LGPL compliance

- FFmpeg is configured **without** \`--enable-gpl\` and \`--enable-nonfree\` (the build script refuses to
  continue otherwise, and a unit test checks \`avcodec_license()\` at runtime). It is built with
  \`--disable-network\`.
- FFmpeg, LAME and the other codec libraries live in the separate dynamic framework
  \`FormatWheel.app/Frameworks/FWFFmpeg.framework\`, so it can be replaced with a modified build.
- Corresponding source: the unmodified upstream tarballs listed in \`scripts/build-ffmpeg.sh\`
  (e.g. https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz). The only FormatWheel-specific code is the
  glue in \`scripts/ffmpeg/\` (in-process entry point, probe helper), compiled together with FFmpeg's
  \`fftools\` sources; FFmpeg itself is not patched.
- To rebuild or replace it: \`scripts/build-ffmpeg.sh\` produces \`Vendor/FFmpeg/FWFFmpeg.xcframework\`; build
  the app with it (\`xcodegen generate && scripts/build-unsigned.sh\`), or swap
  \`Frameworks/FWFFmpeg.framework\` inside an existing \`.ipa\` and re-sign.
- Prebuilt binaries are published as the GitHub Release \`$FFMPEG_TAG\` together with this notice.

## License texts
HEAD
section "FFmpeg — GNU Lesser General Public License v2.1" "$SRC/ffmpeg/LICENSE.md" "$SRC/ffmpeg/COPYING.LGPLv2.1"
section "LAME — GNU Library General Public License v2" "$SRC/lame/LICENSE" "$SRC/lame/COPYING"
section "Opus — BSD-3-Clause" "$SRC/opus/COPYING"
section "libvpx — BSD-3-Clause and patent grant" "$SRC/libvpx/LICENSE" "$SRC/libvpx/PATENTS"
section "SVT-AV1 — BSD-3-Clause-Clear and AOMedia Patent License 1.0" "$SRC/svtav1/LICENSE.md" "$SRC/svtav1/PATENTS.md"
section "libwebp — BSD-3-Clause and patent grant" "$SRC/libwebp/COPYING" "$SRC/libwebp/PATENTS"
section "FormatWheel (macOS original) — MIT" "$ROOT/upstream/LICENSE"
} > "$OUT"
echo "wrote $OUT ($(wc -l < "$OUT") lines)"
