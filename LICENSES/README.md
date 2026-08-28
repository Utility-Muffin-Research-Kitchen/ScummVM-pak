# Licensing

Three different things ship in this repository and they are not under one
licence. Read this before redistributing the built pak.

| What | Licence | Where |
| --- | --- | --- |
| The ScummVM libretro core (`scummvm_libretro.so`) | **GPL-3.0-or-later** | `CORE-LICENSE.txt` |
| This repository's build system, manifests, scripts | MIT (see `REPO-LICENSE.txt`) | — |
| `pak/art/SCUMMVM.png` | CC0 1.0 | `../pak/art/LICENSE-ASSETS.md` |

## The GPLv3 obligation, concretely

The core is GPLv3. Distributing the built `.so` — which is what installing
this pak does — obliges you to offer the **corresponding source** for that
exact binary.

This repository discharges that by construction rather than by promise:

- `core/core.lock.json` pins the exact upstream commit
  (`libretro/scummvm`) and the exact commits of its two build dependencies,
  so the corresponding source is identified precisely, not "whatever master
  was".
- `core/build-core.sh` rebuilds that exact source with a digest-pinned
  toolchain image and refuses to package an artifact whose sha256 does not
  match the lock.
- `make dist-source` produces the corresponding-source archive to publish
  **alongside** the binary.

A written offer alone is weaker than shipping the archive, so publish the
archive. If you fork this repository and change the pin, republish the source
for your pin: the obligation follows the binary you distributed, not the one
upstream currently builds.

Leaf's separate constraints on which cores may ship in a release image are a
different question and do not discharge this one.
