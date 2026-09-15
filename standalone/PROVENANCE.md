# Standalone provenance

What is in the standalone `scummvm` binary, where it came from, and how to get
the same bytes again. `standalone/standalone.lock.json` is the machine-readable
version of this file and is what the build enforces; this one explains it.

## Source

| | |
| --- | --- |
| Upstream | `https://github.com/scummvm/scummvm.git` |
| Tag | `v2026.3.0` |
| Commit | `fed42f2068dcafc6aafa1c28c77e4c88def74b66` |
| Licence | GPL-3.0-or-later (`COPYING` in that tree, copied to `LICENSES/STANDALONE-LICENSE.txt`) |

ScummVM is built **unmodified**. `build-standalone.sh` refuses to build if the
tracked files in the source tree differ from the commit.

## Codecs

The toolchain sysroot has no Ogg Vorbis, FLAC or MP3 libraries, so the build
compiles them from source and links them statically. Versions, archive hashes
and patches are the ones Buildroot 2024.02 uses, the release the toolchain image
is built from.

| Library | Version | Archive | Licence | Configure |
| --- | --- | --- | --- | --- |
| libogg | 1.3.5 | `libogg-1.3.5.tar.xz` (downloads.xiph.org) | BSD-3-Clause | defaults |
| libvorbis | 1.3.7 | `libvorbis-1.3.7.tar.xz` (downloads.xiph.org) | BSD-3-Clause | `--disable-oggtest --with-ogg=<deps>` |
| libFLAC | 1.4.3 | `flac-1.4.3.tar.xz` (downloads.xiph.org) | BSD-3-Clause (Xiph) | `--disable-cpplibs --disable-programs --disable-examples --disable-doxygen-docs --disable-xmms-plugin --disable-ogg --disable-stack-smash-protection` |
| libmad | 0.15.1b | `libmad-0.15.1b.tar.gz` (SourceForge) | GPL-2.0-or-later | `--disable-debugging --enable-fpm=64bit` |

Every library is built with `--disable-shared --enable-static` and
`CFLAGS=-O2 -fPIC -ffile-prefix-map=/work=/work`. `-fPIC` is needed because
ScummVM links a position-independent executable.

libmad is patched exactly as Buildroot patches it, in this order:

1. Debian's `libmad_0.15.1b-10.diff.gz` (snapshot.debian.org), which adds
   `debian/patches/`.
2. `patches/libmad/0001-mips-h-constraint-removal.patch` and
   `patches/libmad/0002-configure-ac-automake-foreign.patch`, copied from
   Buildroot's `package/libmad/`.
3. Every entry of `debian/patches/series`, in order. These include
   `md_size.diff` (CVE-2017-8372, CVE-2017-8373) and `length-check.patch`
   (CVE-2017-8374).
4. `autoreconf -fi`, so the configure script and libtool are current.

`--enable-fpm=64bit` is set because libmad's host table predates aarch64; the
64-bit fixed-point path is the exact portable one.

## Linkage

The binary links these shared libraries from the device and bundles none:
SDL2, ALSA, zlib, libpng, libjpeg, FreeType, and the C and C++ runtimes. The
MLP1 and the toolchain sysroot both ship glibc 2.38 and SDL 2.28.5.
`device-libs.txt` lists what the device provides; `verify-binary.sh` fails the
build if the binary needs anything else, carries an RPATH, or needs a newer
glibc than 2.38.

## Build

In the digest-pinned toolchain image, after the codecs:

```
./configure \
  --host=aarch64-buildroot-linux-gnu \
  --prefix=/usr \
  --backend=sdl \
  --with-sdl-prefix=<sysroot>/usr \
  --enable-release-mode --enable-optimizations --disable-debug \
  --enable-vkeybd \
  --disable-cloud --disable-libcurl --disable-sdlnet --disable-discord \
  --disable-tts --disable-updates --disable-fluidsynth \
  --enable-vorbis --disable-tremor \
  --with-ogg-prefix=<deps> --with-vorbis-prefix=<deps> \
  --enable-flac --with-flac-prefix=<deps> \
  --enable-mad --with-mad-prefix=<deps>
make VER_REV=
make VER_REV= install DESTDIR=<stage>
```

The binary is then stripped with the cross `strip --strip-unneeded`, and
`<stage>/usr/share/scummvm` (themes, engine data, virtual keyboard, shaders)
becomes the package's `share/scummvm`. The build copies licence notices for
ScummVM, the third-party code inside it, and each codec into `licenses/`.

Container facts `build-in-container.sh` handles:

- The image ships no host `strings` and no unprefixed `ranlib`, so `STRINGS` and
  `RANLIB` point at the cross tools.
- Cross pkg-config is pointed at the sysroot with `PKG_CONFIG_LIBDIR` and
  `PKG_CONFIG_SYSROOT_DIR`. The same wrapper would prefix the sysroot onto the
  private codec prefix, so the codec builds name that prefix directly with
  `CPPFLAGS`, `LDFLAGS`, `OGG_CFLAGS` and `OGG_LIBS`.

## Toolchain

| | |
| --- | --- |
| Image | `ghcr.io/utility-muffin-research-kitchen/mlp1-toolchain` |
| Digest | `sha256:66aac16fb8b07e663c9b4d66970f272df195a6eba98dfad8286eabbaa617faf9` |
| Compiler | `aarch64-buildroot-linux-gnu-gcc 12.3.0` (Buildroot 2024.02) |
| Target | aarch64 Cortex-A55, glibc 2.38 (Miniloong Pocket 1, RK3566) |

Pulled anonymously; no UMRK credentials and no local image build are required.
The build uses the digest, not the tag.

## Reproducibility

- `base/version.cpp` embeds `__DATE__` and `__TIME__`, so `SOURCE_DATE_EPOCH` is
  frozen to the pinned commit's committer timestamp.
- `VER_REV=` keeps a git revision out of the version string, so the binary does
  not depend on clone history.
- Codec objects are built with `-ffile-prefix-map` so build paths do not leak.

## Artifact

`35c65f35a7226a41bbaae12cebe64a3bdc333e19354cbfde9d493f2d1815591c`, 107,520,464
bytes stripped. Recorded 2026-09-15 from two clean `FORCE=1` builds, codecs
included, that agreed byte for byte.

`verify-binary.sh` on that binary: AArch64, stripped, no RPATH/RUNPATH, highest
glibc symbol `GLIBC_2.38`, and these `NEEDED` libraries, all provided by the
device:

```
libSDL2-2.0.so.0  libasound.so.2  libjpeg.so.8  libpng16.so.16  libz.so.1
libfreetype.so.6  libstdc++.so.6  libm.so.6  libgcc_s.so.1  libc.so.6
ld-linux-aarch64.so.1
```

No codec library appears: libogg, libvorbis, libFLAC and libmad are linked
statically.

## Package size

Record the packaged size of the standalone lane here once built, next to the
libretro core's, and keep it within the budget recorded in the plan.
