#!/usr/bin/env bash
# Builds the FFmpeg stack for iOS from source and packs it as two XCFrameworks:
#
#   Vendor/FFmpeg/FWFFmpeg.xcframework  dynamic framework: FFmpeg libraries + LAME + Opus + libvpx +
#                                       SVT-AV1 + libwebp + the in-process `ffmpeg` tool (fftools) behind
#                                       a tiny C API (scripts/ffmpeg/FWFFmpeg.h). LGPL-2.1-or-later.
#   Vendor/FFmpeg/WebP.xcframework      static libwebp (+ mux/demux/sharpyuv) for the app's own WebP
#                                       encoder (the macOS app's `cwebp`). BSD-3-Clause.
#
# Slices: iphoneos arm64, iphonesimulator arm64 + x86_64. Minimum iOS: $IOS_MIN.
# LGPL only: never pass --enable-gpl / --enable-nonfree; the script verifies the result.
#
# Usage: scripts/build-ffmpeg.sh [--clean] [--slices "iphoneos-arm64 iphonesimulator-arm64 ..."]
# Env:   WORK=<scratch dir> (default build/ffmpeg), JOBS=<n>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=ffmpeg-versions.env
source "$ROOT/scripts/ffmpeg-versions.env"
WORK="${WORK:-$ROOT/build/ffmpeg}"
OUT="$ROOT/Vendor/FFmpeg"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
SLICES="iphoneos-arm64 iphonesimulator-arm64 iphonesimulator-x86_64"

while [ $# -gt 0 ]; do
  case "$1" in
    --clean) rm -rf "$WORK"; shift ;;
    --slices) SLICES="$2"; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

for tool in cmake pkg-config xcrun lipo; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool (brew install cmake pkgconf)" >&2; exit 1; }
done

mkdir -p "$WORK/dl" "$WORK/src" "$OUT"
log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------------------------------
# Sources

fetch() { # name url
  local name="$1" url="$2" file="$WORK/dl/$1.tar.gz"
  [ -d "$WORK/src/$name" ] && return
  if [ ! -s "$file" ]; then
    log "Downloading $name"
    curl -fL --retry 5 --retry-delay 3 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  mkdir -p "$WORK/src/$name.tmp"
  tar -xf "$file" -C "$WORK/src/$name.tmp" --strip-components 1
  mv "$WORK/src/$name.tmp" "$WORK/src/$name"
}

fetch ffmpeg "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"
fetch lame "https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz"
fetch opus "https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz"
fetch libvpx "https://github.com/webmproject/libvpx/archive/refs/tags/v$LIBVPX_VERSION.tar.gz"
fetch libwebp "https://github.com/webmproject/libwebp/archive/refs/tags/v$LIBWEBP_VERSION.tar.gz"
fetch svtav1 "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$SVTAV1_VERSION/SVT-AV1-v$SVTAV1_VERSION.tar.gz"

# ---------------------------------------------------------------------------------------------------
# Per-slice toolchain

setup_slice() { # slice
  SLICE="$1"
  SDK="${SLICE%-*}"
  ARCH="${SLICE##*-}"
  SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
  CC="$(xcrun --sdk "$SDK" -f clang)"
  CXX="$(xcrun --sdk "$SDK" -f clang++)"
  if [ "$SDK" = iphoneos ]; then TRIPLE="$ARCH-apple-ios$IOS_MIN"; else TRIPLE="$ARCH-apple-ios$IOS_MIN-simulator"; fi
  HOST="$([ "$ARCH" = arm64 ] && echo aarch64 || echo x86_64)-apple-darwin"
  PREFIX="$WORK/install/$SLICE"
  BUILD="$WORK/build/$SLICE"
  CFLAGS="-target $TRIPLE -isysroot $SYSROOT -O2 -fPIC"
  LDFLAGS="-target $TRIPLE -isysroot $SYSROOT"
  export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"   # never pick up Homebrew's macOS libraries
  unset PKG_CONFIG_PATH
  mkdir -p "$PREFIX" "$BUILD"
}

cmake_build() { # name src extra-args...
  local name="$1" src="$2"; shift 2
  local dir="$BUILD/$name"
  [ -f "$dir/.done" ] && return
  log "$name ($SLICE)"
  rm -rf "$dir"
  cmake -S "$src" -B "$dir" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$SDK" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN" \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    "$@"
  cmake --build "$dir" --parallel "$JOBS"
  cmake --install "$dir"
  touch "$dir/.done"
}

build_lame() {
  local dir="$BUILD/lame"
  [ -f "$dir/.done" ] && return
  log "lame ($SLICE)"
  rm -rf "$dir"; cp -R "$WORK/src/lame" "$dir"
  (cd "$dir" &&
    ./configure --host="$HOST" --prefix="$PREFIX" --disable-shared --enable-static --disable-frontend \
      --disable-dependency-tracking CC="$CC" CFLAGS="$CFLAGS" CPPFLAGS="-target $TRIPLE -isysroot $SYSROOT" LDFLAGS="$LDFLAGS" >/dev/null &&
    make -j"$JOBS" >/dev/null && make install >/dev/null)
  # lame ships no pkg-config file; FFmpeg's configure only needs the library and header.
  touch "$dir/.done"
}

build_opus() {
  cmake_build opus "$WORK/src/opus" -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF -DOPUS_BUILD_SHARED_LIBRARY=OFF
}

build_libwebp() {
  cmake_build libwebp "$WORK/src/libwebp" \
    -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF \
    -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF \
    -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_LIBWEBPMUX=ON -DWEBP_ENABLE_SIMD=ON
}

build_svtav1() {
  local asm=OFF
  [ "$ARCH" = x86_64 ] && asm=ON   # simulator only: skip the x86 NASM kernels
  cmake_build svtav1 "$WORK/src/svtav1" -DBUILD_APPS=OFF -DBUILD_TESTING=OFF -DCOMPILE_C_ONLY="$asm" \
    -DENABLE_NASM=OFF -DSVT_AV1_LTO=OFF
}

build_libvpx() {
  local dir="$BUILD/libvpx"
  [ -f "$dir/.done" ] && return
  log "libvpx ($SLICE)"
  rm -rf "$dir"; mkdir -p "$dir"
  local target=generic-gnu vflags="$CFLAGS" vldflags="$LDFLAGS"
  if [ "$SLICE" = iphoneos-arm64 ]; then
    # libvpx's iOS target hard-codes -miphoneos-version-min=7.0, which clashes with -target; use the
    # older flag style and put ours last so it wins.
    target=arm64-darwin-gcc
    vflags="-arch arm64 -isysroot $SYSROOT -O2 -fPIC -miphoneos-version-min=$IOS_MIN"
    vldflags="-arch arm64 -isysroot $SYSROOT -miphoneos-version-min=$IOS_MIN"
  fi
  (cd "$dir" &&
    CC="$CC" CXX="$CXX" AR="$(xcrun -f ar)" LD="$CC" STRIP="$(xcrun -f strip)" LDFLAGS="$vldflags" \
    "$WORK/src/libvpx/configure" --target="$target" --prefix="$PREFIX" \
      --extra-cflags="$vflags" --extra-cxxflags="$vflags" \
      --disable-shared --enable-static --enable-pic --disable-examples --disable-tools --disable-docs \
      --disable-unit-tests --disable-install-bins --disable-install-docs --enable-vp8 --enable-vp9 \
      --enable-multithread >"$dir/configure.log" 2>&1 &&
    make -j"$JOBS" >"$dir/make.log" 2>&1 && make install >/dev/null) ||
    { tail -30 "$dir/configure.log"; tail -30 "$dir/make.log" 2>/dev/null; exit 1; }
  touch "$dir/.done"
}

build_ffmpeg() {
  local dir="$BUILD/ffmpeg"
  [ -f "$dir/.done" ] && return
  log "FFmpeg $FFMPEG_VERSION ($SLICE)"
  rm -rf "$dir"; mkdir -p "$dir"
  local arch_flags=(--arch="$([ "$ARCH" = arm64 ] && echo aarch64 || echo x86_64)")
  [ "$ARCH" = x86_64 ] && arch_flags+=(--disable-x86asm)
  (cd "$dir" && "$WORK/src/ffmpeg/configure" \
    --prefix="$PREFIX" \
    --enable-cross-compile --target-os=darwin "${arch_flags[@]}" \
    --cc="$CC" --cxx="$CXX" --sysroot="$SYSROOT" \
    --extra-cflags="$CFLAGS -I$PREFIX/include" \
    --extra-ldflags="$LDFLAGS -L$PREFIX/lib" \
    --extra-libs="-liconv" \
    --pkg-config=pkg-config --pkg-config-flags=--static \
    --enable-static --disable-shared --enable-pic \
    --disable-autodetect --disable-debug --disable-doc --disable-htmlpages --disable-manpages \
    --disable-podpages --disable-txtpages \
    --disable-programs --enable-ffmpeg --disable-ffplay --disable-ffprobe \
    --disable-avdevice --disable-network \
    --enable-pthreads --enable-zlib --enable-bzlib --enable-iconv \
    --enable-videotoolbox --enable-audiotoolbox \
    --enable-libmp3lame --enable-libopus --enable-libvpx --enable-libwebp --enable-libsvtav1 \
    >"$dir/configure.log" 2>&1) || { tail -40 "$dir/configure.log"; tail -60 "$dir/ffbuild/config.log" 2>/dev/null; exit 1; }

  # License guard: this build must stay LGPL.
  for flag in CONFIG_GPL CONFIG_NONFREE CONFIG_GPLV3; do
    grep -q "#define $flag 0" "$dir/config.h" || { echo "license guard: $flag is enabled" >&2; exit 1; }
  done
  for enc in libmp3lame libopus libvpx_vp9 libwebp libsvtav1 h264_videotoolbox hevc_videotoolbox aac flac alac pcm_s16le; do
    grep -qE "^#define CONFIG_$(echo "$enc" | tr '[:lower:]' '[:upper:]')_ENCODER 1" "$dir/config_components.h" ||
      { echo "missing encoder: $enc" >&2; exit 1; }
  done
  for f in loudnorm palettegen paletteuse atempo setpts scale fps split pad format; do
    grep -qE "^#define CONFIG_$(echo "$f" | tr '[:lower:]' '[:upper:]')_FILTER 1" "$dir/config_components.h" ||
      { echo "missing filter: $f" >&2; exit 1; }
  done

  (cd "$dir" && make -j"$JOBS" >"$dir/make.log" 2>&1 && make install >/dev/null) ||
    { tail -60 "$dir/make.log"; exit 1; }
  touch "$dir/.done"
}

# Links FFmpeg + codecs + fftools into FWFFmpeg.framework for one slice.
link_framework() {
  local fw="$WORK/frameworks/$SLICE/FWFFmpeg.framework"
  log "FWFFmpeg.framework ($SLICE)"
  rm -rf "$fw"; mkdir -p "$fw/Headers" "$fw/Modules"
  local ff="$BUILD/ffmpeg" obj="$BUILD/fw-obj"
  rm -rf "$obj"; mkdir -p "$obj"
  local inc=(-I"$ff" -I"$WORK/src/ffmpeg" -I"$PREFIX/include" -I"$ROOT/scripts/ffmpeg")
  "$CC" $CFLAGS -std=c17 -w "${inc[@]}" -c "$ROOT/scripts/ffmpeg/fw_ffmpeg.c" -o "$obj/fw_ffmpeg.o"
  "$CC" $CFLAGS -std=c17 "${inc[@]}" -c "$ROOT/scripts/ffmpeg/fw_exit.c" -o "$obj/fw_exit.o"
  "$CC" $CFLAGS -std=c17 "${inc[@]}" -c "$ROOT/scripts/ffmpeg/fw_probe.c" -o "$obj/fw_probe.o"
  "$CC" $CFLAGS -std=c17 "${inc[@]}" -c "$ROOT/scripts/ffmpeg/fw_versions.c" -o "$obj/fw_versions.o"

  # Every fftools object FFmpeg's own Makefile built for the ffmpeg program, except its main().
  local tools=()
  while IFS= read -r o; do tools+=("$o"); done < <(
    cd "$ff" && find fftools -name '*.o' ! -name 'ffmpeg.o' ! -name 'ffprobe.o' ! -name 'ffplay*.o' | sort | sed "s|^|$ff/|")
  [ "${#tools[@]}" -gt 5 ] || { echo "fftools objects not found" >&2; exit 1; }

  local libs
  libs="$(pkg-config --static --libs libavfilter libavformat libavcodec libswresample libswscale libavutil)"
  # shellcheck disable=SC2086
  "$CC" -dynamiclib $LDFLAGS -o "$fw/FWFFmpeg" "$obj"/*.o "${tools[@]}" \
    -L"$PREFIX/lib" $libs -lmp3lame -lwebpmux -lwebp -lsharpyuv \
    -framework VideoToolbox -framework AudioToolbox -framework CoreMedia -framework CoreVideo \
    -framework CoreFoundation -framework CoreServices -framework QuartzCore -framework Foundation \
    -lz -lbz2 -liconv -lc++ \
    -install_name @rpath/FWFFmpeg.framework/FWFFmpeg \
    -compatibility_version 1 -current_version 1 \
    -Wl,-exported_symbols_list,"$ROOT/scripts/ffmpeg/exports.txt" -Wl,-dead_strip
  xcrun strip -x "$fw/FWFFmpeg"

  cp "$ROOT/scripts/ffmpeg/FWFFmpeg.h" "$fw/Headers/"
  cp "$ROOT/scripts/ffmpeg/module.modulemap" "$fw/Modules/"
  local platform; platform="$([ "$SDK" = iphoneos ] && echo iPhoneOS || echo iPhoneSimulator)"
  cat >"$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>FWFFmpeg</string>
  <key>CFBundleIdentifier</key><string>io.github.formatwheel.FWFFmpeg</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>FWFFmpeg</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$FFMPEG_VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>
  <key>MinimumOSVersion</key><string>$IOS_MIN</string>
  <key>NSHumanReadableCopyright</key><string>FFmpeg $FFMPEG_VERSION (LGPL-2.1-or-later) with LAME, Opus, libvpx, SVT-AV1, libwebp</string>
</dict>
</plist>
PLIST
}

pack_webp() {
  local dir="$WORK/webp/$SLICE"
  rm -rf "$dir"; mkdir -p "$dir/Headers/webp"
  libtool -static -o "$dir/libWebP.a" "$PREFIX/lib/libwebp.a" "$PREFIX/lib/libwebpmux.a" \
    "$PREFIX/lib/libwebpdemux.a" "$PREFIX/lib/libsharpyuv.a" 2>/dev/null
  cp "$PREFIX"/include/webp/*.h "$dir/Headers/webp/"
  cat >"$dir/Headers/module.modulemap" <<'MAP'
module WebP {
    header "webp/encode.h"
    header "webp/decode.h"
    header "webp/mux.h"
    header "webp/demux.h"
    link "WebP"
    export *
}
MAP
}

# ---------------------------------------------------------------------------------------------------

for s in $SLICES; do
  setup_slice "$s"
  build_lame
  build_opus
  build_libwebp
  build_svtav1
  build_libvpx
  build_ffmpeg
  link_framework
  pack_webp
done

log "Creating XCFrameworks"
mkdir -p "$WORK/frameworks/iphonesimulator" "$WORK/webp/iphonesimulator"
sim=()
dev=()
for s in $SLICES; do case "$s" in iphonesimulator-*) sim+=("$s") ;; iphoneos-*) dev+=("$s") ;; esac; done

fw_args=()
webp_args=()
if [ "${#dev[@]}" -gt 0 ]; then
  fw_args+=(-framework "$WORK/frameworks/${dev[0]}/FWFFmpeg.framework")
  webp_args+=(-library "$WORK/webp/${dev[0]}/libWebP.a" -headers "$WORK/webp/${dev[0]}/Headers")
fi
if [ "${#sim[@]}" -gt 0 ]; then
  simfw="$WORK/frameworks/iphonesimulator/FWFFmpeg.framework"
  rm -rf "$simfw"; cp -R "$WORK/frameworks/${sim[0]}/FWFFmpeg.framework" "$simfw"
  lipo -create $(for s in "${sim[@]}"; do echo "$WORK/frameworks/$s/FWFFmpeg.framework/FWFFmpeg"; done) -output "$simfw/FWFFmpeg"
  fw_args+=(-framework "$simfw")
  simwebp="$WORK/webp/iphonesimulator"
  rm -rf "$simwebp"; mkdir -p "$simwebp"; cp -R "$WORK/webp/${sim[0]}/Headers" "$simwebp/"
  lipo -create $(for s in "${sim[@]}"; do echo "$WORK/webp/$s/libWebP.a"; done) -output "$simwebp/libWebP.a"
  webp_args+=(-library "$simwebp/libWebP.a" -headers "$simwebp/Headers")
fi

rm -rf "$OUT/FWFFmpeg.xcframework" "$OUT/WebP.xcframework"
xcodebuild -create-xcframework "${fw_args[@]}" -output "$OUT/FWFFmpeg.xcframework" >/dev/null
xcodebuild -create-xcframework "${webp_args[@]}" -output "$OUT/WebP.xcframework" >/dev/null
cat >"$OUT/VERSION" <<EOF
FFMPEG_VERSION=$FFMPEG_VERSION
LAME_VERSION=$LAME_VERSION
OPUS_VERSION=$OPUS_VERSION
LIBVPX_VERSION=$LIBVPX_VERSION
LIBWEBP_VERSION=$LIBWEBP_VERSION
SVTAV1_VERSION=$SVTAV1_VERSION
IOS_MIN=$IOS_MIN
EOF
log "Done: $OUT"
du -sh "$OUT"/*.xcframework
