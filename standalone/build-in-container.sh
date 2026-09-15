#!/usr/bin/env bash
# Runs inside the pinned MLP1 toolchain image; started by build-standalone.sh,
# which has already checked every input against standalone.lock.json.
#
#   /src         ScummVM at the pinned commit, unmodified
#   /downloads   codec source archives and the libmad Debian diff (read-only)
#   /standalone  this directory: patches, verifier, device allowlist (read-only)
#   /work        cached codec build tree
#   /out         staged binary, data, licences and the verification report
set -euo pipefail

: "${CROSS:?}" "${SOURCE_DATE_EPOCH:?}" "${GLIBC_CEILING:?}" "${ARTIFACT:?}"
export SOURCE_DATE_EPOCH
export PATH="/opt/mlp1-toolchain/bin:$PATH"
SYS=/opt/mlp1-toolchain/aarch64-buildroot-linux-gnu/sysroot
JOBS="$(nproc)"
DEPS=/work/deps
CODEC_SRC=/work/src

log() { echo "build-in-container: $*"; }

# Run a quiet step; on failure show the tail of its log.
step() {
  local name=$1; shift
  if ! "$@" >"/work/$name.log" 2>&1; then
    echo "build-in-container: $name failed; last lines of /work/$name.log:" >&2
    tail -40 "/work/$name.log" >&2
    exit 1
  fi
}

# Static codec libraries. Each is built once per clean /work; -fPIC because
# ScummVM links a PIE executable, and the prefix map keeps build paths out of
# the objects.
CODEC_CFLAGS="-O2 -fPIC -ffile-prefix-map=/work=/work"

autotools_static() {
  local dir=$1; shift
  (
    cd "$dir"
    export CC="$CROSS-gcc" AR="$CROSS-ar" RANLIB="$CROSS-ranlib" CFLAGS="$CODEC_CFLAGS"
    # The toolchain's pkg-config wrapper prefixes the target sysroot onto every
    # path it reports, which is wrong for this private prefix. Name the prefix
    # directly instead of relying on .pc files.
    export CPPFLAGS="-I$DEPS/include" LDFLAGS="-L$DEPS/lib"
    export OGG_CFLAGS="-I$DEPS/include" OGG_LIBS="-L$DEPS/lib -logg"
    export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig" PKG_CONFIG_SYSROOT_DIR=""
    ./configure --host="$CROSS" --prefix="$DEPS" --disable-shared --enable-static "$@"
    make -j"$JOBS"
    make install
  )
}

build_codec() {
  local name=$1
  [ -f "/work/.done-$name" ] && { log "$name: cached"; return; }
  log "$name: building"
  case "$name" in
    libogg)
      rm -rf "$CODEC_SRC/libogg-1.3.5"
      tar -xJf /downloads/libogg-1.3.5.tar.xz -C "$CODEC_SRC"
      step libogg autotools_static "$CODEC_SRC/libogg-1.3.5"
      ;;
    libvorbis)
      rm -rf "$CODEC_SRC/libvorbis-1.3.7"
      tar -xJf /downloads/libvorbis-1.3.7.tar.xz -C "$CODEC_SRC"
      step libvorbis autotools_static "$CODEC_SRC/libvorbis-1.3.7" \
        --disable-oggtest --with-ogg="$DEPS"
      ;;
    flac)
      rm -rf "$CODEC_SRC/flac-1.4.3"
      tar -xJf /downloads/flac-1.4.3.tar.xz -C "$CODEC_SRC"
      step flac autotools_static "$CODEC_SRC/flac-1.4.3" \
        --disable-cpplibs --disable-programs --disable-examples \
        --disable-doxygen-docs --disable-xmms-plugin --disable-ogg \
        --disable-stack-smash-protection
      ;;
    libmad)
      # Buildroot 2024.02's order: the Debian diff, the package patches, then
      # every debian/patches entry in series order; then autoreconf.
      rm -rf "$CODEC_SRC/libmad-0.15.1b"
      tar -xzf /downloads/libmad-0.15.1b.tar.gz -C "$CODEC_SRC"
      (
        cd "$CODEC_SRC/libmad-0.15.1b"
        gunzip -c /downloads/libmad_0.15.1b-10.diff.gz | patch -p1 -s
        for patch in /standalone/patches/libmad/*.patch; do
          patch -p1 -s <"$patch"
        done
        while read -r entry _; do
          case "$entry" in ''|\#*) continue ;; esac
          patch -p1 -s <"debian/patches/$entry"
        done <debian/patches/series
      ) >/work/libmad-patch.log 2>&1 || { tail -40 /work/libmad-patch.log >&2; exit 1; }
      step libmad-autoreconf bash -c "cd '$CODEC_SRC/libmad-0.15.1b' && autoreconf -fi"
      # aarch64 is not in libmad's host table; the 64-bit fixed-point path is
      # the portable exact one.
      step libmad autotools_static "$CODEC_SRC/libmad-0.15.1b" \
        --disable-debugging --enable-fpm=64bit
      ;;
  esac
  touch "/work/.done-$name"
}

mkdir -p "$CODEC_SRC" "$DEPS"
for codec in libogg libvorbis flac libmad; do
  build_codec "$codec"
done
for lib in libogg.a libvorbis.a libvorbisfile.a libFLAC.a libmad.a; do
  [ -f "$DEPS/lib/$lib" ] || { echo "build-in-container: missing $DEPS/lib/$lib" >&2; exit 1; }
done

log "ScummVM: configuring"
(
  cd /src
  # The image ships no host `strings` (endianness probe) and no unprefixed
  # ranlib; cross pkg-config must see only the target sysroot.
  export STRINGS="$CROSS-strings" RANLIB="$CROSS-ranlib"
  export PKG_CONFIG_LIBDIR="$SYS/usr/lib/pkgconfig:$SYS/usr/share/pkgconfig"
  export PKG_CONFIG_SYSROOT_DIR="$SYS"
  ./configure \
    --host="$CROSS" \
    --prefix=/usr \
    --backend=sdl \
    --with-sdl-prefix="$SYS/usr" \
    --enable-release-mode \
    --enable-optimizations \
    --disable-debug \
    --enable-vkeybd \
    --disable-cloud \
    --disable-libcurl \
    --disable-sdlnet \
    --disable-discord \
    --disable-tts \
    --disable-updates \
    --disable-fluidsynth \
    --enable-vorbis \
    --disable-tremor \
    --with-ogg-prefix="$DEPS" \
    --with-vorbis-prefix="$DEPS" \
    --enable-flac \
    --with-flac-prefix="$DEPS" \
    --enable-mad \
    --with-mad-prefix="$DEPS"
) >/work/scummvm-configure.log 2>&1 || { tail -60 /work/scummvm-configure.log >&2; exit 1; }

log "ScummVM: compiling (long)"
# VER_REV= keeps a git revision out of the version string, so the binary does
# not depend on clone history.
step scummvm-make make -C /src VER_REV= -j"$JOBS"

log "ScummVM: staging"
rm -rf /out/stage /out/share /out/licenses
step scummvm-install make -C /src VER_REV= install DESTDIR=/out/stage
"$CROSS-strip" --strip-unneeded -o "/out/$ARTIFACT" "/out/stage/usr/bin/scummvm"
mkdir -p /out/share /out/licenses
cp -R /out/stage/usr/share/scummvm /out/share/scummvm

cp /src/COPYING /out/licenses/scummvm-COPYING
cp /src/COPYRIGHT /out/licenses/scummvm-COPYRIGHT
cp -R /src/LICENSES /out/licenses/scummvm-LICENSES
cp "$CODEC_SRC/libogg-1.3.5/COPYING" /out/licenses/libogg-COPYING
cp "$CODEC_SRC/libvorbis-1.3.7/COPYING" /out/licenses/libvorbis-COPYING
cp "$CODEC_SRC/flac-1.4.3/COPYING.Xiph" /out/licenses/flac-COPYING.Xiph
cp "$CODEC_SRC/libmad-0.15.1b/COPYING" /out/licenses/libmad-COPYING
rm -rf /out/stage

log "verifying the binary"
bash /standalone/verify-binary.sh "/out/$ARTIFACT" /standalone/device-libs.txt "$GLIBC_CEILING" \
  | tee /out/verify-binary.txt
