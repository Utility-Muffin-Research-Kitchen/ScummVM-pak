# Licensing

The components in this repository are not under one licence. Read this before
redistributing the built pak.

| What | Licence | Where |
| --- | --- | --- |
| The ScummVM libretro core (`scummvm_libretro.so`) | **GPL-3.0-or-later** | `CORE-LICENSE.txt` |
| The standalone ScummVM executable (`emulators/scummvm-standalone/bin/scummvm`) | **GPL-3.0-or-later** | `STANDALONE-LICENSE.txt`; in the package also `emulators/scummvm-standalone/licenses/scummvm-COPYING` |
| Third-party code inside ScummVM | Various (Apache, BSD, ISC, LGPL, MIT, MPL, OFL, ...) | `emulators/scummvm-standalone/licenses/scummvm-LICENSES/` in the package |
| libmad, statically linked into the standalone | GPL-2.0-or-later | `emulators/scummvm-standalone/licenses/libmad-COPYING` |
| libogg and libvorbis, statically linked into the standalone | BSD-3-Clause | `licenses/libogg-COPYING`, `licenses/libvorbis-COPYING` |
| libFLAC, statically linked into the standalone | BSD-3-Clause (Xiph) | `licenses/flac-COPYING.Xiph` |
| This repository's build system, manifests, scripts | MIT (see `REPO-LICENSE.txt`) | - |
| `pak/art/SCUMMVM.png` | CC BY-SA 4.0 | `../pak/art/LICENSE-ASSETS.md` |
| `pak/art/SCUMMVM-photo.png` | AI-generated render; no copyright claimed | `../pak/art/LICENSE-ASSETS.md` |

libmad's GPL-2.0-or-later terms are compatible with the standalone executable's
GPL-3.0-or-later, and the BSD libraries only require their notices, which ship
in the package.

The standalone links the device's own shared libraries (SDL2, ALSA, zlib,
libpng, libjpeg, FreeType, the C and C++ runtimes) and bundles none of them.

## The GPL obligation, concretely

Both ScummVM binaries are GPLv3. Distributing them, which is what installing
this pak does, obliges you to offer the **corresponding source** for those exact
binaries.

This repository discharges that by construction rather than by promise:

- `core/core.lock.json` pins the exact libretro ScummVM commit and the exact
  commits of its two build dependencies.
- `standalone/standalone.lock.json` pins the exact upstream ScummVM commit and
  the sha256 of every codec source archive and patch linked into the
  standalone.
- Each build script rebuilds that exact source with a digest-pinned toolchain
  image and refuses to package an artifact whose sha256 does not match its
  lock.
- `make dist-source` produces two archives to publish **alongside** the pak:
  the libretro core's source, and the standalone's ScummVM tree, codec archives,
  patches and build scripts.

A written offer alone is weaker than shipping the archives, so publish them. If
you fork this repository and change a pin, republish the source for your pin:
the obligation follows the binary you distributed, not the one upstream
currently builds.

Leaf's separate constraints on which cores may ship in a release image are a
different question and do not discharge this one.
